// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"log"
	"time"
	"genericim/internal/models"
)

const (
	messageIdempotencyCollectionName = "message_idempotency"
	messageIdempotencyIndexKey       = "__message_idempotency_indexes__"
	messageIdempotencyPending        = "pending"
	messageIdempotencyCompleted      = "completed"
	messageIdempotencyLease          = 30 * time.Second
)

var ErrMessageSendInProgress = errors.New("message with this client id is still being processed")

type messageIdempotencyRecord struct {
	ID                primitive.ObjectID `bson:"_id,omitempty"`
	ChatID            string             `bson:"chat_id"`
	SenderID          string             `bson:"sender_id"`
	MsgID             string             `bson:"msg_id"`
	Status            string             `bson:"status"`
	Owner             string             `bson:"owner"`
	MessageCollection string             `bson:"message_collection,omitempty"`
	MessageObjectID   primitive.ObjectID `bson:"message_object_id,omitempty"`
	MessageSeq        uint64             `bson:"message_seq,omitempty"`
	LeaseUntil        time.Time          `bson:"lease_until"`
	ExpiresAt         time.Time          `bson:"expires_at"`
	CreatedAt         time.Time          `bson:"created_at"`
	UpdatedAt         time.Time          `bson:"updated_at"`
}

type messageIdempotencyReservation struct {
	Owner    string
	ChatID   string
	SenderID string
	MsgID    string
}

func messageIdempotencyExpiry(now time.Time, months int) time.Time {
	months = normalizeMessageRetentionMonths(months)
	return now.AddDate(0, months, 0)
}

func (s *MessageService) ensureMessageIdempotencyIndexes(ctx context.Context) error {
	if s == nil || s.mongoDB == nil {
		return errors.New("message idempotency storage is unavailable")
	}
	if _, loaded := s.indexes.Load(messageIdempotencyIndexKey); loaded {
		return nil
	}

	indexCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	_, err := s.mongoDB.Collection(messageIdempotencyCollectionName).Indexes().CreateMany(indexCtx, []mongo.IndexModel{
		{
			Keys: bson.D{
				{Key: "chat_id", Value: 1},
				{Key: "sender_id", Value: 1},
				{Key: "msg_id", Value: 1},
			},
			Options: options.Index().SetName("uniq_chat_sender_client_msg").SetUnique(true),
		},
		{
			Keys:    bson.D{{Key: "expires_at", Value: 1}},
			Options: options.Index().SetName("ttl_message_idempotency").SetExpireAfterSeconds(0),
		},
	})
	if err != nil {
		return fmt.Errorf("ensure message idempotency indexes: %w", err)
	}
	s.indexes.Store(messageIdempotencyIndexKey, struct{}{})
	return nil
}

func (s *MessageService) reserveMessageIdempotency(
	ctx context.Context,
	chatID string,
	senderID string,
	msgID string,
) (*messageIdempotencyReservation, *models.Message, error) {
	if err := s.ensureMessageIdempotencyIndexes(ctx); err != nil {
		return nil, nil, err
	}
	now := time.Now()
	owner := uuid.NewString()
	record := messageIdempotencyRecord{
		ChatID:     chatID,
		SenderID:   senderID,
		MsgID:      msgID,
		Status:     messageIdempotencyPending,
		Owner:      owner,
		LeaseUntil: now.Add(messageIdempotencyLease),
		ExpiresAt:  messageIdempotencyExpiry(now, s.idempotencyMonths),
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	collection := s.mongoDB.Collection(messageIdempotencyCollectionName)
	_, err := collection.InsertOne(ctx, record)
	if err == nil {
		return &messageIdempotencyReservation{
			Owner: owner, ChatID: chatID, SenderID: senderID, MsgID: msgID,
		}, nil, nil
	}
	if !isMongoDuplicateKeyError(err) {
		return nil, nil, err
	}
	key := bson.M{"chat_id": chatID, "sender_id": senderID, "msg_id": msgID}
	for attempt := 0; attempt < 12; attempt++ {
		var existing messageIdempotencyRecord
		if err := collection.FindOne(ctx, key).Decode(&existing); err != nil {
			return nil, nil, err
		}
		if existing.Status == messageIdempotencyCompleted {
			message, loadErr := s.loadIdempotentMessage(ctx, &existing)
			return nil, message, loadErr
		}

		// A process may have stored the message immediately before crashing while
		// completing the ledger. Recover that state before considering takeover.
		if message, found, findErr := s.findMessageByClientIDInCollections(
			ctx,
			chatID,
			senderID,
			msgID,
			s.recentMessageCollections(chatID, time.Now(), 2),
		); findErr != nil {
			return nil, nil, findErr
		} else if found {
			collectionName := models.GetMessageCollection(chatID, message.CreatedAt)
			if err := s.completeMessageIdempotency(ctx, nil, message, collectionName); err != nil {
				log.Printf("[MessageIdempotency] recover completion failed chatId=%s msgId=%s err=%v", chatID, msgID, err)
			}
			return nil, message, nil
		}

		now = time.Now()
		if !existing.LeaseUntil.After(now) {
			filter := bson.M{
				"chat_id": chatID, "sender_id": senderID, "msg_id": msgID,
				"status":      messageIdempotencyPending,
				"lease_until": bson.M{"$lte": now},
			}
			update := bson.M{"$set": bson.M{
				"owner": owner, "lease_until": now.Add(messageIdempotencyLease),
				"updated_at": now, "expires_at": messageIdempotencyExpiry(now, s.idempotencyMonths),
			}}
			result, updateErr := collection.UpdateOne(ctx, filter, update)
			if updateErr != nil {
				return nil, nil, updateErr
			}
			if result.ModifiedCount == 1 {
				return &messageIdempotencyReservation{
					Owner: owner, ChatID: chatID, SenderID: senderID, MsgID: msgID,
				}, nil, nil
			}
		}

		select {
		case <-ctx.Done():
			return nil, nil, ctx.Err()
		case <-time.After(50 * time.Millisecond):
		}
	}
	return nil, nil, ErrMessageSendInProgress
}

func (s *MessageService) loadIdempotentMessage(ctx context.Context, record *messageIdempotencyRecord) (*models.Message, error) {
	if record == nil {
		return nil, errors.New("message idempotency record is missing")
	}
	if record.MessageCollection != "" {
		filter := bson.M{"chat_id": record.ChatID, "sender_id": record.SenderID, "msg_id": record.MsgID}
		var message models.Message
		if err := s.mongoDB.Collection(record.MessageCollection).FindOne(ctx, filter).Decode(&message); err == nil {
			return &message, nil
		} else if err != mongo.ErrNoDocuments {
			return nil, err
		}
	}
	if message, found, err := s.FindMessageByClientID(ctx, record.ChatID, record.SenderID, record.MsgID); err != nil {
		return nil, err
	} else if found {
		return message, nil
	}
	return nil, errors.New("idempotent message no longer exists inside the retention window")
}

func (s *MessageService) completeMessageIdempotency(
	ctx context.Context,
	reservation *messageIdempotencyReservation,
	message *models.Message,
	collectionName string,
) error {
	if message == nil {
		return errors.New("cannot complete idempotency without a message")
	}
	if err := s.ensureMessageIdempotencyIndexes(ctx); err != nil {
		return err
	}
	filter := bson.M{
		"chat_id": message.ChatID, "sender_id": message.SenderID, "msg_id": message.MsgID,
	}
	if reservation != nil {
		filter["owner"] = reservation.Owner
	}
	now := time.Now()
	update := bson.M{"$set": bson.M{
		"status": messageIdempotencyCompleted, "message_collection": collectionName,
		"message_object_id": message.ID, "message_seq": message.Seq,
		"lease_until": now, "updated_at": now,
		"expires_at": messageIdempotencyExpiry(message.CreatedAt, s.idempotencyMonths),
	}}
	opts := options.Update().SetUpsert(reservation == nil)
	_, err := s.mongoDB.Collection(messageIdempotencyCollectionName).UpdateOne(ctx, filter, update, opts)
	return err
}

func (s *MessageService) releaseMessageIdempotency(ctx context.Context, reservation *messageIdempotencyReservation) {
	if reservation == nil || s == nil || s.mongoDB == nil {
		return
	}
	filter := bson.M{
		"chat_id": reservation.ChatID, "sender_id": reservation.SenderID,
		"msg_id": reservation.MsgID, "owner": reservation.Owner,
		"status": messageIdempotencyPending,
	}
	if _, err := s.mongoDB.Collection(messageIdempotencyCollectionName).DeleteOne(ctx, filter); err != nil {
		log.Printf("[MessageIdempotency] release failed chatId=%s msgId=%s err=%v", reservation.ChatID, reservation.MsgID, err)
	}
}
