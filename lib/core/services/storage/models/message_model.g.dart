// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_model.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetMessageModelCollection on Isar {
  IsarCollection<MessageModel> get messageModels => this.collection();
}

int _messageModelJsSafeInt(String value) => int.parse(value);

final MessageModelSchema = CollectionSchema(
  name: r'MessageModel',
  id: _messageModelJsSafeInt('-902762555029995869'),
  properties: {
    r'burnAfterRead': PropertySchema(
      id: 0,
      name: r'burnAfterRead',
      type: IsarType.bool,
    ),
    r'burnAfterSeconds': PropertySchema(
      id: 1,
      name: r'burnAfterSeconds',
      type: IsarType.long,
    ),
    r'chatId': PropertySchema(
      id: 2,
      name: r'chatId',
      type: IsarType.string,
    ),
    r'contactAvatar': PropertySchema(
      id: 3,
      name: r'contactAvatar',
      type: IsarType.string,
    ),
    r'contactName': PropertySchema(
      id: 4,
      name: r'contactName',
      type: IsarType.string,
    ),
    r'contactUserId': PropertySchema(
      id: 5,
      name: r'contactUserId',
      type: IsarType.string,
    ),
    r'contactUsername': PropertySchema(
      id: 6,
      name: r'contactUsername',
      type: IsarType.string,
    ),
    r'content': PropertySchema(
      id: 7,
      name: r'content',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 8,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'editedAt': PropertySchema(
      id: 9,
      name: r'editedAt',
      type: IsarType.dateTime,
    ),
    r'fileName': PropertySchema(
      id: 10,
      name: r'fileName',
      type: IsarType.string,
    ),
    r'forwardFrom': PropertySchema(
      id: 11,
      name: r'forwardFrom',
      type: IsarType.string,
    ),
    r'id': PropertySchema(
      id: 12,
      name: r'id',
      type: IsarType.string,
    ),
    r'isDeleted': PropertySchema(
      id: 13,
      name: r'isDeleted',
      type: IsarType.bool,
    ),
    r'isOutgoing': PropertySchema(
      id: 14,
      name: r'isOutgoing',
      type: IsarType.bool,
    ),
    r'isRead': PropertySchema(
      id: 15,
      name: r'isRead',
      type: IsarType.bool,
    ),
    r'localPath': PropertySchema(
      id: 16,
      name: r'localPath',
      type: IsarType.string,
    ),
    r'mediaDuration': PropertySchema(
      id: 17,
      name: r'mediaDuration',
      type: IsarType.long,
    ),
    r'mediaHeight': PropertySchema(
      id: 18,
      name: r'mediaHeight',
      type: IsarType.long,
    ),
    r'mediaSize': PropertySchema(
      id: 19,
      name: r'mediaSize',
      type: IsarType.long,
    ),
    r'mediaWidth': PropertySchema(
      id: 20,
      name: r'mediaWidth',
      type: IsarType.long,
    ),
    r'reactions': PropertySchema(
      id: 21,
      name: r'reactions',
      type: IsarType.string,
    ),
    r'remoteUrl': PropertySchema(
      id: 22,
      name: r'remoteUrl',
      type: IsarType.string,
    ),
    r'replyToId': PropertySchema(
      id: 23,
      name: r'replyToId',
      type: IsarType.string,
    ),
    r'replyToPreview': PropertySchema(
      id: 24,
      name: r'replyToPreview',
      type: IsarType.string,
    ),
    r'senderAvatar': PropertySchema(
      id: 25,
      name: r'senderAvatar',
      type: IsarType.string,
    ),
    r'senderEmojiAvatar': PropertySchema(
      id: 26,
      name: r'senderEmojiAvatar',
      type: IsarType.string,
    ),
    r'senderId': PropertySchema(
      id: 27,
      name: r'senderId',
      type: IsarType.string,
    ),
    r'senderName': PropertySchema(
      id: 28,
      name: r'senderName',
      type: IsarType.string,
    ),
    r'senderNicknameColor': PropertySchema(
      id: 29,
      name: r'senderNicknameColor',
      type: IsarType.string,
    ),
    r'seq': PropertySchema(
      id: 30,
      name: r'seq',
      type: IsarType.long,
    ),
    r'status': PropertySchema(
      id: 31,
      name: r'status',
      type: IsarType.byte,
      enumMap: _MessageModelstatusEnumValueMap,
    ),
    r'thumbnail': PropertySchema(
      id: 32,
      name: r'thumbnail',
      type: IsarType.string,
    ),
    r'type': PropertySchema(
      id: 33,
      name: r'type',
      type: IsarType.byte,
      enumMap: _MessageModeltypeEnumValueMap,
    )
  },
  estimateSize: _messageModelEstimateSize,
  serialize: _messageModelSerialize,
  deserialize: _messageModelDeserialize,
  deserializeProp: _messageModelDeserializeProp,
  idName: r'isarId',
  indexes: {
    r'id': IndexSchema(
      id: _messageModelJsSafeInt('-3268401673993471357'),
      name: r'id',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'id',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'chatId_createdAt': IndexSchema(
      id: _messageModelJsSafeInt('-8009080684031631222'),
      name: r'chatId_createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'chatId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'senderId': IndexSchema(
      id: _messageModelJsSafeInt('-1619654757968658561'),
      name: r'senderId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'senderId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'createdAt': IndexSchema(
      id: _messageModelJsSafeInt('-3433535483987302584'),
      name: r'createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _messageModelGetId,
  getLinks: _messageModelGetLinks,
  attach: _messageModelAttach,
  version: '3.1.0+1',
);

int _messageModelEstimateSize(
  MessageModel object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.chatId.length * 3;
  {
    final value = object.contactAvatar;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.contactName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.contactUserId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.contactUsername;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.content.length * 3;
  {
    final value = object.fileName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.forwardFrom;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.id.length * 3;
  {
    final value = object.localPath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.reactions;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.remoteUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.replyToId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.replyToPreview;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.senderAvatar;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.senderEmojiAvatar;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.senderId.length * 3;
  bytesCount += 3 + object.senderName.length * 3;
  {
    final value = object.senderNicknameColor;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.thumbnail;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _messageModelSerialize(
  MessageModel object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.burnAfterRead);
  writer.writeLong(offsets[1], object.burnAfterSeconds);
  writer.writeString(offsets[2], object.chatId);
  writer.writeString(offsets[3], object.contactAvatar);
  writer.writeString(offsets[4], object.contactName);
  writer.writeString(offsets[5], object.contactUserId);
  writer.writeString(offsets[6], object.contactUsername);
  writer.writeString(offsets[7], object.content);
  writer.writeDateTime(offsets[8], object.createdAt);
  writer.writeDateTime(offsets[9], object.editedAt);
  writer.writeString(offsets[10], object.fileName);
  writer.writeString(offsets[11], object.forwardFrom);
  writer.writeString(offsets[12], object.id);
  writer.writeBool(offsets[13], object.isDeleted);
  writer.writeBool(offsets[14], object.isOutgoing);
  writer.writeBool(offsets[15], object.isRead);
  writer.writeString(offsets[16], object.localPath);
  writer.writeLong(offsets[17], object.mediaDuration);
  writer.writeLong(offsets[18], object.mediaHeight);
  writer.writeLong(offsets[19], object.mediaSize);
  writer.writeLong(offsets[20], object.mediaWidth);
  writer.writeString(offsets[21], object.reactions);
  writer.writeString(offsets[22], object.remoteUrl);
  writer.writeString(offsets[23], object.replyToId);
  writer.writeString(offsets[24], object.replyToPreview);
  writer.writeString(offsets[25], object.senderAvatar);
  writer.writeString(offsets[26], object.senderEmojiAvatar);
  writer.writeString(offsets[27], object.senderId);
  writer.writeString(offsets[28], object.senderName);
  writer.writeString(offsets[29], object.senderNicknameColor);
  writer.writeLong(offsets[30], object.seq);
  writer.writeByte(offsets[31], object.status.index);
  writer.writeString(offsets[32], object.thumbnail);
  writer.writeByte(offsets[33], object.type.index);
}

MessageModel _messageModelDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = MessageModel();
  object.burnAfterRead = reader.readBool(offsets[0]);
  object.burnAfterSeconds = reader.readLong(offsets[1]);
  object.chatId = reader.readString(offsets[2]);
  object.contactAvatar = reader.readStringOrNull(offsets[3]);
  object.contactName = reader.readStringOrNull(offsets[4]);
  object.contactUserId = reader.readStringOrNull(offsets[5]);
  object.contactUsername = reader.readStringOrNull(offsets[6]);
  object.content = reader.readString(offsets[7]);
  object.createdAt = reader.readDateTime(offsets[8]);
  object.editedAt = reader.readDateTimeOrNull(offsets[9]);
  object.fileName = reader.readStringOrNull(offsets[10]);
  object.forwardFrom = reader.readStringOrNull(offsets[11]);
  object.id = reader.readString(offsets[12]);
  object.isDeleted = reader.readBool(offsets[13]);
  object.isOutgoing = reader.readBool(offsets[14]);
  object.isRead = reader.readBool(offsets[15]);
  object.localPath = reader.readStringOrNull(offsets[16]);
  object.mediaDuration = reader.readLongOrNull(offsets[17]);
  object.mediaHeight = reader.readLongOrNull(offsets[18]);
  object.mediaSize = reader.readLongOrNull(offsets[19]);
  object.mediaWidth = reader.readLongOrNull(offsets[20]);
  object.reactions = reader.readStringOrNull(offsets[21]);
  object.remoteUrl = reader.readStringOrNull(offsets[22]);
  object.replyToId = reader.readStringOrNull(offsets[23]);
  object.replyToPreview = reader.readStringOrNull(offsets[24]);
  object.senderAvatar = reader.readStringOrNull(offsets[25]);
  object.senderEmojiAvatar = reader.readStringOrNull(offsets[26]);
  object.senderId = reader.readString(offsets[27]);
  object.senderName = reader.readString(offsets[28]);
  object.senderNicknameColor = reader.readStringOrNull(offsets[29]);
  object.seq = reader.readLong(offsets[30]);
  object.status =
      _MessageModelstatusValueEnumMap[reader.readByteOrNull(offsets[31])] ??
          MsgStatus.sending;
  object.thumbnail = reader.readStringOrNull(offsets[32]);
  object.type =
      _MessageModeltypeValueEnumMap[reader.readByteOrNull(offsets[33])] ??
          MsgType.text;
  return object;
}

P _messageModelDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readDateTime(offset)) as P;
    case 9:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    case 13:
      return (reader.readBool(offset)) as P;
    case 14:
      return (reader.readBool(offset)) as P;
    case 15:
      return (reader.readBool(offset)) as P;
    case 16:
      return (reader.readStringOrNull(offset)) as P;
    case 17:
      return (reader.readLongOrNull(offset)) as P;
    case 18:
      return (reader.readLongOrNull(offset)) as P;
    case 19:
      return (reader.readLongOrNull(offset)) as P;
    case 20:
      return (reader.readLongOrNull(offset)) as P;
    case 21:
      return (reader.readStringOrNull(offset)) as P;
    case 22:
      return (reader.readStringOrNull(offset)) as P;
    case 23:
      return (reader.readStringOrNull(offset)) as P;
    case 24:
      return (reader.readStringOrNull(offset)) as P;
    case 25:
      return (reader.readStringOrNull(offset)) as P;
    case 26:
      return (reader.readStringOrNull(offset)) as P;
    case 27:
      return (reader.readString(offset)) as P;
    case 28:
      return (reader.readString(offset)) as P;
    case 29:
      return (reader.readStringOrNull(offset)) as P;
    case 30:
      return (reader.readLong(offset)) as P;
    case 31:
      return (_MessageModelstatusValueEnumMap[reader.readByteOrNull(offset)] ??
          MsgStatus.sending) as P;
    case 32:
      return (reader.readStringOrNull(offset)) as P;
    case 33:
      return (_MessageModeltypeValueEnumMap[reader.readByteOrNull(offset)] ??
          MsgType.text) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _MessageModelstatusEnumValueMap = {
  'sending': 0,
  'sent': 1,
  'delivered': 2,
  'read': 3,
  'failed': 4,
};
const _MessageModelstatusValueEnumMap = {
  0: MsgStatus.sending,
  1: MsgStatus.sent,
  2: MsgStatus.delivered,
  3: MsgStatus.read,
  4: MsgStatus.failed,
};
const _MessageModeltypeEnumValueMap = {
  'text': 0,
  'image': 1,
  'video': 2,
  'audio': 3,
  'voice': 4,
  'file': 5,
  'sticker': 6,
  'gif': 7,
  'location': 8,
  'contact': 9,
  'poll': 10,
  'system': 11,
  'call': 12,
  'redPacket': 13,
  'transfer': 14,
};
const _MessageModeltypeValueEnumMap = {
  0: MsgType.text,
  1: MsgType.image,
  2: MsgType.video,
  3: MsgType.audio,
  4: MsgType.voice,
  5: MsgType.file,
  6: MsgType.sticker,
  7: MsgType.gif,
  8: MsgType.location,
  9: MsgType.contact,
  10: MsgType.poll,
  11: MsgType.system,
  12: MsgType.call,
  13: MsgType.redPacket,
  14: MsgType.transfer,
};

Id _messageModelGetId(MessageModel object) {
  return object.isarId;
}

List<IsarLinkBase<dynamic>> _messageModelGetLinks(MessageModel object) {
  return [];
}

void _messageModelAttach(
    IsarCollection<dynamic> col, Id id, MessageModel object) {}

extension MessageModelByIndex on IsarCollection<MessageModel> {
  Future<MessageModel?> getById(String id) {
    return getByIndex(r'id', [id]);
  }

  MessageModel? getByIdSync(String id) {
    return getByIndexSync(r'id', [id]);
  }

  Future<bool> deleteById(String id) {
    return deleteByIndex(r'id', [id]);
  }

  bool deleteByIdSync(String id) {
    return deleteByIndexSync(r'id', [id]);
  }

  Future<List<MessageModel?>> getAllById(List<String> idValues) {
    final values = idValues.map((e) => [e]).toList();
    return getAllByIndex(r'id', values);
  }

  List<MessageModel?> getAllByIdSync(List<String> idValues) {
    final values = idValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'id', values);
  }

  Future<int> deleteAllById(List<String> idValues) {
    final values = idValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'id', values);
  }

  int deleteAllByIdSync(List<String> idValues) {
    final values = idValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'id', values);
  }

  Future<Id> putById(MessageModel object) {
    return putByIndex(r'id', object);
  }

  Id putByIdSync(MessageModel object, {bool saveLinks = true}) {
    return putByIndexSync(r'id', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllById(List<MessageModel> objects) {
    return putAllByIndex(r'id', objects);
  }

  List<Id> putAllByIdSync(List<MessageModel> objects, {bool saveLinks = true}) {
    return putAllByIndexSync(r'id', objects, saveLinks: saveLinks);
  }
}

extension MessageModelQueryWhereSort
    on QueryBuilder<MessageModel, MessageModel, QWhere> {
  QueryBuilder<MessageModel, MessageModel, QAfterWhere> anyIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhere> anyCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAt'),
      );
    });
  }
}

extension MessageModelQueryWhere
    on QueryBuilder<MessageModel, MessageModel, QWhereClause> {
  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> isarIdEqualTo(
      Id isarId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: isarId,
        upper: isarId,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> isarIdNotEqualTo(
      Id isarId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: isarId, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: isarId, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: isarId, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: isarId, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> isarIdGreaterThan(
      Id isarId,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: isarId, includeLower: include),
      );
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> isarIdLessThan(
      Id isarId,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: isarId, includeUpper: include),
      );
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> isarIdBetween(
    Id lowerIsarId,
    Id upperIsarId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerIsarId,
        includeLower: includeLower,
        upper: upperIsarId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> idEqualTo(
      String id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'id',
        value: [id],
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> idNotEqualTo(
      String id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'id',
              lower: [],
              upper: [id],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'id',
              lower: [id],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'id',
              lower: [id],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'id',
              lower: [],
              upper: [id],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      chatIdEqualToAnyCreatedAt(String chatId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'chatId_createdAt',
        value: [chatId],
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      chatIdNotEqualToAnyCreatedAt(String chatId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'chatId_createdAt',
              lower: [],
              upper: [chatId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'chatId_createdAt',
              lower: [chatId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'chatId_createdAt',
              lower: [chatId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'chatId_createdAt',
              lower: [],
              upper: [chatId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      chatIdCreatedAtEqualTo(String chatId, DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'chatId_createdAt',
        value: [chatId, createdAt],
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      chatIdEqualToCreatedAtNotEqualTo(String chatId, DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'chatId_createdAt',
              lower: [chatId],
              upper: [chatId, createdAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'chatId_createdAt',
              lower: [chatId, createdAt],
              includeLower: false,
              upper: [chatId],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'chatId_createdAt',
              lower: [chatId, createdAt],
              includeLower: false,
              upper: [chatId],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'chatId_createdAt',
              lower: [chatId],
              upper: [chatId, createdAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      chatIdEqualToCreatedAtGreaterThan(
    String chatId,
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'chatId_createdAt',
        lower: [chatId, createdAt],
        includeLower: include,
        upper: [chatId],
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      chatIdEqualToCreatedAtLessThan(
    String chatId,
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'chatId_createdAt',
        lower: [chatId],
        upper: [chatId, createdAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      chatIdEqualToCreatedAtBetween(
    String chatId,
    DateTime lowerCreatedAt,
    DateTime upperCreatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'chatId_createdAt',
        lower: [chatId, lowerCreatedAt],
        includeLower: includeLower,
        upper: [chatId, upperCreatedAt],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> senderIdEqualTo(
      String senderId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'senderId',
        value: [senderId],
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      senderIdNotEqualTo(String senderId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'senderId',
              lower: [],
              upper: [senderId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'senderId',
              lower: [senderId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'senderId',
              lower: [senderId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'senderId',
              lower: [],
              upper: [senderId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> createdAtEqualTo(
      DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [createdAt],
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      createdAtNotEqualTo(DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause>
      createdAtGreaterThan(
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [createdAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> createdAtLessThan(
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [],
        upper: [createdAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterWhereClause> createdAtBetween(
    DateTime lowerCreatedAt,
    DateTime upperCreatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [lowerCreatedAt],
        includeLower: includeLower,
        upper: [upperCreatedAt],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension MessageModelQueryFilter
    on QueryBuilder<MessageModel, MessageModel, QFilterCondition> {
  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      burnAfterReadEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'burnAfterRead',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      burnAfterSecondsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'burnAfterSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      burnAfterSecondsGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'burnAfterSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      burnAfterSecondsLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'burnAfterSeconds',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      burnAfterSecondsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'burnAfterSeconds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> chatIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      chatIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      chatIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> chatIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'chatId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      chatIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      chatIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      chatIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> chatIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'chatId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      chatIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'chatId',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      chatIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'chatId',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'contactAvatar',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'contactAvatar',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contactAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contactAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contactAvatar',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'contactAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'contactAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'contactAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'contactAvatar',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactAvatar',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactAvatarIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'contactAvatar',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'contactName',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'contactName',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contactName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contactName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contactName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'contactName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'contactName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'contactName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'contactName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactName',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'contactName',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'contactUserId',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'contactUserId',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contactUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contactUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contactUserId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'contactUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'contactUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'contactUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'contactUserId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactUserId',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUserIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'contactUserId',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'contactUsername',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'contactUsername',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactUsername',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contactUsername',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contactUsername',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contactUsername',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'contactUsername',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'contactUsername',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'contactUsername',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'contactUsername',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contactUsername',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contactUsernameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'contactUsername',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'content',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'content',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'content',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      contentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'content',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      editedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'editedAt',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      editedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'editedAt',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      editedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'editedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      editedAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'editedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      editedAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'editedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      editedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'editedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'fileName',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'fileName',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'fileName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'fileName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'fileName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'fileName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'fileName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'fileName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'fileName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'fileName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'fileName',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      fileNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'fileName',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'forwardFrom',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'forwardFrom',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'forwardFrom',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'forwardFrom',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'forwardFrom',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'forwardFrom',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'forwardFrom',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'forwardFrom',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'forwardFrom',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'forwardFrom',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'forwardFrom',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      forwardFromIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'forwardFrom',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'id',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      isDeletedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isDeleted',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      isOutgoingEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isOutgoing',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> isReadEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isRead',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> isarIdEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      isarIdGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      isarIdLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> isarIdBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'isarId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'localPath',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'localPath',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'localPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'localPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'localPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localPath',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      localPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'localPath',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaDurationIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'mediaDuration',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaDurationIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'mediaDuration',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaDurationEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mediaDuration',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaDurationGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mediaDuration',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaDurationLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mediaDuration',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaDurationBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mediaDuration',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaHeightIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'mediaHeight',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaHeightIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'mediaHeight',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaHeightEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mediaHeight',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaHeightGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mediaHeight',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaHeightLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mediaHeight',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaHeightBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mediaHeight',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaSizeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'mediaSize',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaSizeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'mediaSize',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaSizeEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mediaSize',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaSizeGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mediaSize',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaSizeLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mediaSize',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaSizeBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mediaSize',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaWidthIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'mediaWidth',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaWidthIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'mediaWidth',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaWidthEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mediaWidth',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaWidthGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mediaWidth',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaWidthLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mediaWidth',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      mediaWidthBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mediaWidth',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'reactions',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'reactions',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reactions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'reactions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'reactions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'reactions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'reactions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'reactions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'reactions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'reactions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reactions',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      reactionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'reactions',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'remoteUrl',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'remoteUrl',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'remoteUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'remoteUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'remoteUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'remoteUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'remoteUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'remoteUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'remoteUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'remoteUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'remoteUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      remoteUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'remoteUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'replyToId',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'replyToId',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'replyToId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'replyToId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'replyToId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'replyToId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'replyToId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'replyToId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'replyToId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'replyToId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'replyToId',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'replyToId',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'replyToPreview',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'replyToPreview',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'replyToPreview',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'replyToPreview',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'replyToPreview',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'replyToPreview',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'replyToPreview',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'replyToPreview',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'replyToPreview',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'replyToPreview',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'replyToPreview',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      replyToPreviewIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'replyToPreview',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'senderAvatar',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'senderAvatar',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'senderAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'senderAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'senderAvatar',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'senderAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'senderAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'senderAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'senderAvatar',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderAvatar',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderAvatarIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'senderAvatar',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'senderEmojiAvatar',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'senderEmojiAvatar',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderEmojiAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'senderEmojiAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'senderEmojiAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'senderEmojiAvatar',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'senderEmojiAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'senderEmojiAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'senderEmojiAvatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'senderEmojiAvatar',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderEmojiAvatar',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderEmojiAvatarIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'senderEmojiAvatar',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'senderId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'senderId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'senderId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderId',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'senderId',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'senderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'senderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'senderName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'senderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'senderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'senderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'senderName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderName',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'senderName',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'senderNicknameColor',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'senderNicknameColor',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderNicknameColor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'senderNicknameColor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'senderNicknameColor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'senderNicknameColor',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'senderNicknameColor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'senderNicknameColor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'senderNicknameColor',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'senderNicknameColor',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'senderNicknameColor',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      senderNicknameColorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'senderNicknameColor',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> seqEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'seq',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      seqGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'seq',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> seqLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'seq',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> seqBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'seq',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> statusEqualTo(
      MsgStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      statusGreaterThan(
    MsgStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'status',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      statusLessThan(
    MsgStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'status',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> statusBetween(
    MsgStatus lower,
    MsgStatus upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'status',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'thumbnail',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'thumbnail',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'thumbnail',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'thumbnail',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'thumbnail',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'thumbnail',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'thumbnail',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'thumbnail',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'thumbnail',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'thumbnail',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'thumbnail',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      thumbnailIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'thumbnail',
        value: '',
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> typeEqualTo(
      MsgType value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition>
      typeGreaterThan(
    MsgType value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> typeLessThan(
    MsgType value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterFilterCondition> typeBetween(
    MsgType lower,
    MsgType upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'type',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension MessageModelQueryObject
    on QueryBuilder<MessageModel, MessageModel, QFilterCondition> {}

extension MessageModelQueryLinks
    on QueryBuilder<MessageModel, MessageModel, QFilterCondition> {}

extension MessageModelQuerySortBy
    on QueryBuilder<MessageModel, MessageModel, QSortBy> {
  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByBurnAfterRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'burnAfterRead', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByBurnAfterReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'burnAfterRead', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByBurnAfterSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'burnAfterSeconds', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByBurnAfterSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'burnAfterSeconds', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByChatId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByChatIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByContactAvatar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactAvatar', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByContactAvatarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactAvatar', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByContactName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactName', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByContactNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactName', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByContactUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactUserId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByContactUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactUserId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByContactUsername() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactUsername', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByContactUsernameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactUsername', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByEditedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'editedAt', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByEditedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'editedAt', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByFileName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fileName', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByFileNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fileName', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByForwardFrom() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'forwardFrom', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByForwardFromDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'forwardFrom', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByIsDeletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByIsOutgoing() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isOutgoing', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByIsOutgoingDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isOutgoing', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByIsRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRead', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByIsReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRead', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByLocalPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localPath', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByLocalPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localPath', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByMediaDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaDuration', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByMediaDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaDuration', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByMediaHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaHeight', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByMediaHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaHeight', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByMediaSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaSize', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByMediaSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaSize', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByMediaWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaWidth', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByMediaWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaWidth', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByReactions() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reactions', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByReactionsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reactions', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByRemoteUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteUrl', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByRemoteUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteUrl', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByReplyToId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyToId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByReplyToIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyToId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByReplyToPreview() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyToPreview', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortByReplyToPreviewDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyToPreview', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortBySenderAvatar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderAvatar', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortBySenderAvatarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderAvatar', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortBySenderEmojiAvatar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderEmojiAvatar', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortBySenderEmojiAvatarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderEmojiAvatar', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortBySenderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortBySenderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortBySenderName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderName', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortBySenderNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderName', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortBySenderNicknameColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderNicknameColor', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      sortBySenderNicknameColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderNicknameColor', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortBySeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'seq', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortBySeqDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'seq', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByThumbnail() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thumbnail', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByThumbnailDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thumbnail', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension MessageModelQuerySortThenBy
    on QueryBuilder<MessageModel, MessageModel, QSortThenBy> {
  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByBurnAfterRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'burnAfterRead', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByBurnAfterReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'burnAfterRead', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByBurnAfterSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'burnAfterSeconds', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByBurnAfterSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'burnAfterSeconds', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByChatId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByChatIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByContactAvatar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactAvatar', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByContactAvatarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactAvatar', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByContactName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactName', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByContactNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactName', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByContactUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactUserId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByContactUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactUserId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByContactUsername() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactUsername', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByContactUsernameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contactUsername', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByEditedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'editedAt', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByEditedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'editedAt', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByFileName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fileName', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByFileNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fileName', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByForwardFrom() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'forwardFrom', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByForwardFromDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'forwardFrom', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByIsDeletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByIsOutgoing() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isOutgoing', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByIsOutgoingDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isOutgoing', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByIsRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRead', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByIsReadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isRead', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByIsarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByLocalPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localPath', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByLocalPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localPath', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByMediaDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaDuration', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByMediaDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaDuration', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByMediaHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaHeight', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByMediaHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaHeight', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByMediaSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaSize', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByMediaSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaSize', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByMediaWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaWidth', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByMediaWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mediaWidth', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByReactions() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reactions', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByReactionsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reactions', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByRemoteUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteUrl', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByRemoteUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'remoteUrl', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByReplyToId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyToId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByReplyToIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyToId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByReplyToPreview() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyToPreview', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenByReplyToPreviewDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'replyToPreview', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenBySenderAvatar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderAvatar', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenBySenderAvatarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderAvatar', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenBySenderEmojiAvatar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderEmojiAvatar', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenBySenderEmojiAvatarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderEmojiAvatar', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenBySenderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderId', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenBySenderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderId', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenBySenderName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderName', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenBySenderNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderName', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenBySenderNicknameColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderNicknameColor', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy>
      thenBySenderNicknameColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'senderNicknameColor', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenBySeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'seq', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenBySeqDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'seq', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByThumbnail() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thumbnail', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByThumbnailDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thumbnail', Sort.desc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QAfterSortBy> thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }
}

extension MessageModelQueryWhereDistinct
    on QueryBuilder<MessageModel, MessageModel, QDistinct> {
  QueryBuilder<MessageModel, MessageModel, QDistinct>
      distinctByBurnAfterRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'burnAfterRead');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct>
      distinctByBurnAfterSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'burnAfterSeconds');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByChatId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'chatId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByContactAvatar(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contactAvatar',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByContactName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contactName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByContactUserId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contactUserId',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByContactUsername(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contactUsername',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'content', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByEditedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'editedAt');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByFileName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'fileName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByForwardFrom(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'forwardFrom', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctById(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'id', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isDeleted');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByIsOutgoing() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isOutgoing');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByIsRead() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isRead');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByLocalPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'localPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct>
      distinctByMediaDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaDuration');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByMediaHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaHeight');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByMediaSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaSize');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByMediaWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mediaWidth');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByReactions(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'reactions', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByRemoteUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'remoteUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByReplyToId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'replyToId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByReplyToPreview(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'replyToPreview',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctBySenderAvatar(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'senderAvatar', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct>
      distinctBySenderEmojiAvatar({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'senderEmojiAvatar',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctBySenderId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'senderId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctBySenderName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'senderName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct>
      distinctBySenderNicknameColor({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'senderNicknameColor',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctBySeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'seq');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status');
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByThumbnail(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'thumbnail', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MessageModel, MessageModel, QDistinct> distinctByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type');
    });
  }
}

extension MessageModelQueryProperty
    on QueryBuilder<MessageModel, MessageModel, QQueryProperty> {
  QueryBuilder<MessageModel, int, QQueryOperations> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isarId');
    });
  }

  QueryBuilder<MessageModel, bool, QQueryOperations> burnAfterReadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'burnAfterRead');
    });
  }

  QueryBuilder<MessageModel, int, QQueryOperations> burnAfterSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'burnAfterSeconds');
    });
  }

  QueryBuilder<MessageModel, String, QQueryOperations> chatIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'chatId');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations>
      contactAvatarProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contactAvatar');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> contactNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contactName');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations>
      contactUserIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contactUserId');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations>
      contactUsernameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contactUsername');
    });
  }

  QueryBuilder<MessageModel, String, QQueryOperations> contentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'content');
    });
  }

  QueryBuilder<MessageModel, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<MessageModel, DateTime?, QQueryOperations> editedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'editedAt');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> fileNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'fileName');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> forwardFromProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'forwardFrom');
    });
  }

  QueryBuilder<MessageModel, String, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<MessageModel, bool, QQueryOperations> isDeletedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isDeleted');
    });
  }

  QueryBuilder<MessageModel, bool, QQueryOperations> isOutgoingProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isOutgoing');
    });
  }

  QueryBuilder<MessageModel, bool, QQueryOperations> isReadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isRead');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> localPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localPath');
    });
  }

  QueryBuilder<MessageModel, int?, QQueryOperations> mediaDurationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaDuration');
    });
  }

  QueryBuilder<MessageModel, int?, QQueryOperations> mediaHeightProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaHeight');
    });
  }

  QueryBuilder<MessageModel, int?, QQueryOperations> mediaSizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaSize');
    });
  }

  QueryBuilder<MessageModel, int?, QQueryOperations> mediaWidthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mediaWidth');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> reactionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'reactions');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> remoteUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'remoteUrl');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> replyToIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'replyToId');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations>
      replyToPreviewProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'replyToPreview');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> senderAvatarProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'senderAvatar');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations>
      senderEmojiAvatarProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'senderEmojiAvatar');
    });
  }

  QueryBuilder<MessageModel, String, QQueryOperations> senderIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'senderId');
    });
  }

  QueryBuilder<MessageModel, String, QQueryOperations> senderNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'senderName');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations>
      senderNicknameColorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'senderNicknameColor');
    });
  }

  QueryBuilder<MessageModel, int, QQueryOperations> seqProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'seq');
    });
  }

  QueryBuilder<MessageModel, MsgStatus, QQueryOperations> statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<MessageModel, String?, QQueryOperations> thumbnailProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'thumbnail');
    });
  }

  QueryBuilder<MessageModel, MsgType, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }
}
