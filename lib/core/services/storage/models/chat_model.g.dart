// 文件用途：由代码生成器生成 chat model 的序列化或数据库适配代码，请勿手工修改。
// GENERATED CODE - DO NOT MODIFY BY HAND
// 核心逻辑：仅承载代码生成器输出的序列化、数据库适配或字段映射代码，业务逻辑位于对应源文件。

part of 'chat_model.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetChatModelCollection on Isar {
  IsarCollection<ChatModel> get chatModels => this.collection();
}

const ChatModelSchema = CollectionSchema(
  name: r'ChatModel',
  id: 3590324851517520026,
  properties: {
    r'accountId': PropertySchema(
      id: 0,
      name: r'accountId',
      type: IsarType.string,
    ),
    r'avatar': PropertySchema(
      id: 1,
      name: r'avatar',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 2,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'draft': PropertySchema(
      id: 3,
      name: r'draft',
      type: IsarType.string,
    ),
    r'hasMention': PropertySchema(
      id: 4,
      name: r'hasMention',
      type: IsarType.bool,
    ),
    r'hasMessageGap': PropertySchema(
      id: 5,
      name: r'hasMessageGap',
      type: IsarType.bool,
    ),
    r'id': PropertySchema(
      id: 6,
      name: r'id',
      type: IsarType.string,
    ),
    r'isArchived': PropertySchema(
      id: 7,
      name: r'isArchived',
      type: IsarType.bool,
    ),
    r'isMuted': PropertySchema(
      id: 8,
      name: r'isMuted',
      type: IsarType.bool,
    ),
    r'isPinned': PropertySchema(
      id: 9,
      name: r'isPinned',
      type: IsarType.bool,
    ),
    r'lastMessage': PropertySchema(
      id: 10,
      name: r'lastMessage',
      type: IsarType.string,
    ),
    r'lastMessageFailed': PropertySchema(
      id: 11,
      name: r'lastMessageFailed',
      type: IsarType.bool,
    ),
    r'lastMessageMediaUrl': PropertySchema(
      id: 12,
      name: r'lastMessageMediaUrl',
      type: IsarType.string,
    ),
    r'lastMessageSender': PropertySchema(
      id: 13,
      name: r'lastMessageSender',
      type: IsarType.string,
    ),
    r'lastMessageSeq': PropertySchema(
      id: 14,
      name: r'lastMessageSeq',
      type: IsarType.long,
    ),
    r'lastMessageTime': PropertySchema(
      id: 15,
      name: r'lastMessageTime',
      type: IsarType.dateTime,
    ),
    r'lastMessageType': PropertySchema(
      id: 16,
      name: r'lastMessageType',
      type: IsarType.byte,
      enumMap: _ChatModellastMessageTypeEnumValueMap,
    ),
    r'lastSyncedAt': PropertySchema(
      id: 17,
      name: r'lastSyncedAt',
      type: IsarType.dateTime,
    ),
    r'lastSyncedSeq': PropertySchema(
      id: 18,
      name: r'lastSyncedSeq',
      type: IsarType.long,
    ),
    r'memberCount': PropertySchema(
      id: 19,
      name: r'memberCount',
      type: IsarType.long,
    ),
    r'name': PropertySchema(
      id: 20,
      name: r'name',
      type: IsarType.string,
    ),
    r'peerUserId': PropertySchema(
      id: 21,
      name: r'peerUserId',
      type: IsarType.string,
    ),
    r'type': PropertySchema(
      id: 22,
      name: r'type',
      type: IsarType.byte,
      enumMap: _ChatModeltypeEnumValueMap,
    ),
    r'unreadCount': PropertySchema(
      id: 23,
      name: r'unreadCount',
      type: IsarType.long,
    ),
    r'updatedAt': PropertySchema(
      id: 24,
      name: r'updatedAt',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _chatModelEstimateSize,
  serialize: _chatModelSerialize,
  deserialize: _chatModelDeserialize,
  deserializeProp: _chatModelDeserializeProp,
  idName: r'isarId',
  indexes: {
    r'accountId_id': IndexSchema(
      id: 5095769145217530892,
      name: r'accountId_id',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'accountId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'id',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'id': IndexSchema(
      id: -3268401673993471357,
      name: r'id',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'id',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'lastMessageTime': IndexSchema(
      id: -209683041052770976,
      name: r'lastMessageTime',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'lastMessageTime',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'isPinned': IndexSchema(
      id: 7607338673446676027,
      name: r'isPinned',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'isPinned',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'updatedAt': IndexSchema(
      id: -6238191080293565125,
      name: r'updatedAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'updatedAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _chatModelGetId,
  getLinks: _chatModelGetLinks,
  attach: _chatModelAttach,
  version: '3.1.0+1',
);

int _chatModelEstimateSize(
  ChatModel object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.accountId.length * 3;
  {
    final value = object.avatar;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.draft;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.id.length * 3;
  {
    final value = object.lastMessage;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.lastMessageMediaUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.lastMessageSender;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  {
    final value = object.peerUserId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _chatModelSerialize(
  ChatModel object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.accountId);
  writer.writeString(offsets[1], object.avatar);
  writer.writeDateTime(offsets[2], object.createdAt);
  writer.writeString(offsets[3], object.draft);
  writer.writeBool(offsets[4], object.hasMention);
  writer.writeBool(offsets[5], object.hasMessageGap);
  writer.writeString(offsets[6], object.id);
  writer.writeBool(offsets[7], object.isArchived);
  writer.writeBool(offsets[8], object.isMuted);
  writer.writeBool(offsets[9], object.isPinned);
  writer.writeString(offsets[10], object.lastMessage);
  writer.writeBool(offsets[11], object.lastMessageFailed);
  writer.writeString(offsets[12], object.lastMessageMediaUrl);
  writer.writeString(offsets[13], object.lastMessageSender);
  writer.writeLong(offsets[14], object.lastMessageSeq);
  writer.writeDateTime(offsets[15], object.lastMessageTime);
  writer.writeByte(offsets[16], object.lastMessageType.index);
  writer.writeDateTime(offsets[17], object.lastSyncedAt);
  writer.writeLong(offsets[18], object.lastSyncedSeq);
  writer.writeLong(offsets[19], object.memberCount);
  writer.writeString(offsets[20], object.name);
  writer.writeString(offsets[21], object.peerUserId);
  writer.writeByte(offsets[22], object.type.index);
  writer.writeLong(offsets[23], object.unreadCount);
  writer.writeDateTime(offsets[24], object.updatedAt);
}

ChatModel _chatModelDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ChatModel();
  object.accountId = reader.readString(offsets[0]);
  object.avatar = reader.readStringOrNull(offsets[1]);
  object.createdAt = reader.readDateTime(offsets[2]);
  object.draft = reader.readStringOrNull(offsets[3]);
  object.hasMention = reader.readBool(offsets[4]);
  object.hasMessageGap = reader.readBool(offsets[5]);
  object.id = reader.readString(offsets[6]);
  object.isArchived = reader.readBool(offsets[7]);
  object.isMuted = reader.readBool(offsets[8]);
  object.isPinned = reader.readBool(offsets[9]);
  object.lastMessage = reader.readStringOrNull(offsets[10]);
  object.lastMessageFailed = reader.readBool(offsets[11]);
  object.lastMessageMediaUrl = reader.readStringOrNull(offsets[12]);
  object.lastMessageSender = reader.readStringOrNull(offsets[13]);
  object.lastMessageSeq = reader.readLong(offsets[14]);
  object.lastMessageTime = reader.readDateTimeOrNull(offsets[15]);
  object.lastMessageType = _ChatModellastMessageTypeValueEnumMap[
          reader.readByteOrNull(offsets[16])] ??
      MessageType.text;
  object.lastSyncedAt = reader.readDateTimeOrNull(offsets[17]);
  object.lastSyncedSeq = reader.readLong(offsets[18]);
  object.memberCount = reader.readLongOrNull(offsets[19]);
  object.name = reader.readString(offsets[20]);
  object.peerUserId = reader.readStringOrNull(offsets[21]);
  object.type =
      _ChatModeltypeValueEnumMap[reader.readByteOrNull(offsets[22])] ??
          ChatType.private;
  object.unreadCount = reader.readLong(offsets[23]);
  object.updatedAt = reader.readDateTime(offsets[24]);
  return object;
}

P _chatModelDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readDateTime(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readBool(offset)) as P;
    case 8:
      return (reader.readBool(offset)) as P;
    case 9:
      return (reader.readBool(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readBool(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readLong(offset)) as P;
    case 15:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 16:
      return (_ChatModellastMessageTypeValueEnumMap[
              reader.readByteOrNull(offset)] ??
          MessageType.text) as P;
    case 17:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 18:
      return (reader.readLong(offset)) as P;
    case 19:
      return (reader.readLongOrNull(offset)) as P;
    case 20:
      return (reader.readString(offset)) as P;
    case 21:
      return (reader.readStringOrNull(offset)) as P;
    case 22:
      return (_ChatModeltypeValueEnumMap[reader.readByteOrNull(offset)] ??
          ChatType.private) as P;
    case 23:
      return (reader.readLong(offset)) as P;
    case 24:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _ChatModellastMessageTypeEnumValueMap = {
  'text': 0,
  'image': 1,
  'video': 2,
  'audio': 3,
  'voice': 4,
  'file': 5,
  'sticker': 6,
  'location': 7,
  'contact': 8,
  'system': 9,
  'call': 10,
};
const _ChatModellastMessageTypeValueEnumMap = {
  0: MessageType.text,
  1: MessageType.image,
  2: MessageType.video,
  3: MessageType.audio,
  4: MessageType.voice,
  5: MessageType.file,
  6: MessageType.sticker,
  7: MessageType.location,
  8: MessageType.contact,
  9: MessageType.system,
  10: MessageType.call,
};
const _ChatModeltypeEnumValueMap = {
  'private': 0,
  'group': 1,
  'channel': 2,
};
const _ChatModeltypeValueEnumMap = {
  0: ChatType.private,
  1: ChatType.group,
  2: ChatType.channel,
};

Id _chatModelGetId(ChatModel object) {
  return object.isarId;
}

List<IsarLinkBase<dynamic>> _chatModelGetLinks(ChatModel object) {
  return [];
}

void _chatModelAttach(IsarCollection<dynamic> col, Id id, ChatModel object) {}

extension ChatModelByIndex on IsarCollection<ChatModel> {
  Future<ChatModel?> getByAccountIdId(String accountId, String id) {
    return getByIndex(r'accountId_id', [accountId, id]);
  }

  ChatModel? getByAccountIdIdSync(String accountId, String id) {
    return getByIndexSync(r'accountId_id', [accountId, id]);
  }

  Future<bool> deleteByAccountIdId(String accountId, String id) {
    return deleteByIndex(r'accountId_id', [accountId, id]);
  }

  bool deleteByAccountIdIdSync(String accountId, String id) {
    return deleteByIndexSync(r'accountId_id', [accountId, id]);
  }

  Future<List<ChatModel?>> getAllByAccountIdId(
      List<String> accountIdValues, List<String> idValues) {
    final len = accountIdValues.length;
    assert(
        idValues.length == len, 'All index values must have the same length');
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([accountIdValues[i], idValues[i]]);
    }

    return getAllByIndex(r'accountId_id', values);
  }

  List<ChatModel?> getAllByAccountIdIdSync(
      List<String> accountIdValues, List<String> idValues) {
    final len = accountIdValues.length;
    assert(
        idValues.length == len, 'All index values must have the same length');
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([accountIdValues[i], idValues[i]]);
    }

    return getAllByIndexSync(r'accountId_id', values);
  }

  Future<int> deleteAllByAccountIdId(
      List<String> accountIdValues, List<String> idValues) {
    final len = accountIdValues.length;
    assert(
        idValues.length == len, 'All index values must have the same length');
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([accountIdValues[i], idValues[i]]);
    }

    return deleteAllByIndex(r'accountId_id', values);
  }

  int deleteAllByAccountIdIdSync(
      List<String> accountIdValues, List<String> idValues) {
    final len = accountIdValues.length;
    assert(
        idValues.length == len, 'All index values must have the same length');
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([accountIdValues[i], idValues[i]]);
    }

    return deleteAllByIndexSync(r'accountId_id', values);
  }

  Future<Id> putByAccountIdId(ChatModel object) {
    return putByIndex(r'accountId_id', object);
  }

  Id putByAccountIdIdSync(ChatModel object, {bool saveLinks = true}) {
    return putByIndexSync(r'accountId_id', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByAccountIdId(List<ChatModel> objects) {
    return putAllByIndex(r'accountId_id', objects);
  }

  List<Id> putAllByAccountIdIdSync(List<ChatModel> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'accountId_id', objects, saveLinks: saveLinks);
  }
}

extension ChatModelQueryWhereSort
    on QueryBuilder<ChatModel, ChatModel, QWhere> {
  QueryBuilder<ChatModel, ChatModel, QAfterWhere> anyIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhere> anyLastMessageTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'lastMessageTime'),
      );
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhere> anyIsPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isPinned'),
      );
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhere> anyUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'updatedAt'),
      );
    });
  }
}

extension ChatModelQueryWhere
    on QueryBuilder<ChatModel, ChatModel, QWhereClause> {
  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> isarIdEqualTo(
      Id isarId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: isarId,
        upper: isarId,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> isarIdNotEqualTo(
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

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> isarIdGreaterThan(
      Id isarId,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: isarId, includeLower: include),
      );
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> isarIdLessThan(
      Id isarId,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: isarId, includeUpper: include),
      );
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> isarIdBetween(
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

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> accountIdEqualToAnyId(
      String accountId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'accountId_id',
        value: [accountId],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause>
      accountIdNotEqualToAnyId(String accountId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'accountId_id',
              lower: [],
              upper: [accountId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'accountId_id',
              lower: [accountId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'accountId_id',
              lower: [accountId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'accountId_id',
              lower: [],
              upper: [accountId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> accountIdIdEqualTo(
      String accountId, String id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'accountId_id',
        value: [accountId, id],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause>
      accountIdEqualToIdNotEqualTo(String accountId, String id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'accountId_id',
              lower: [accountId],
              upper: [accountId, id],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'accountId_id',
              lower: [accountId, id],
              includeLower: false,
              upper: [accountId],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'accountId_id',
              lower: [accountId, id],
              includeLower: false,
              upper: [accountId],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'accountId_id',
              lower: [accountId],
              upper: [accountId, id],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> idEqualTo(String id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'id',
        value: [id],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause>
      lastMessageTimeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'lastMessageTime',
        value: [null],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause>
      lastMessageTimeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'lastMessageTime',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> lastMessageTimeEqualTo(
      DateTime? lastMessageTime) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'lastMessageTime',
        value: [lastMessageTime],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause>
      lastMessageTimeNotEqualTo(DateTime? lastMessageTime) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'lastMessageTime',
              lower: [],
              upper: [lastMessageTime],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'lastMessageTime',
              lower: [lastMessageTime],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'lastMessageTime',
              lower: [lastMessageTime],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'lastMessageTime',
              lower: [],
              upper: [lastMessageTime],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause>
      lastMessageTimeGreaterThan(
    DateTime? lastMessageTime, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'lastMessageTime',
        lower: [lastMessageTime],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> lastMessageTimeLessThan(
    DateTime? lastMessageTime, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'lastMessageTime',
        lower: [],
        upper: [lastMessageTime],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> lastMessageTimeBetween(
    DateTime? lowerLastMessageTime,
    DateTime? upperLastMessageTime, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'lastMessageTime',
        lower: [lowerLastMessageTime],
        includeLower: includeLower,
        upper: [upperLastMessageTime],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> isPinnedEqualTo(
      bool isPinned) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'isPinned',
        value: [isPinned],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> isPinnedNotEqualTo(
      bool isPinned) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isPinned',
              lower: [],
              upper: [isPinned],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isPinned',
              lower: [isPinned],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isPinned',
              lower: [isPinned],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isPinned',
              lower: [],
              upper: [isPinned],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> updatedAtEqualTo(
      DateTime updatedAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'updatedAt',
        value: [updatedAt],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> updatedAtNotEqualTo(
      DateTime updatedAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'updatedAt',
              lower: [],
              upper: [updatedAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'updatedAt',
              lower: [updatedAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'updatedAt',
              lower: [updatedAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'updatedAt',
              lower: [],
              upper: [updatedAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> updatedAtGreaterThan(
    DateTime updatedAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'updatedAt',
        lower: [updatedAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> updatedAtLessThan(
    DateTime updatedAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'updatedAt',
        lower: [],
        upper: [updatedAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterWhereClause> updatedAtBetween(
    DateTime lowerUpdatedAt,
    DateTime upperUpdatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'updatedAt',
        lower: [lowerUpdatedAt],
        includeLower: includeLower,
        upper: [upperUpdatedAt],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ChatModelQueryFilter
    on QueryBuilder<ChatModel, ChatModel, QFilterCondition> {
  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> accountIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      accountIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> accountIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> accountIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'accountId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> accountIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> accountIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> accountIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'accountId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> accountIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'accountId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> accountIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'accountId',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      accountIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'accountId',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'avatar',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'avatar',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'avatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'avatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'avatar',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'avatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'avatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'avatar',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'avatar',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avatar',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> avatarIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'avatar',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> createdAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> createdAtLessThan(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> createdAtBetween(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'draft',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'draft',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'draft',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'draft',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'draft',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'draft',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'draft',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'draft',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'draft',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'draft',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'draft',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> draftIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'draft',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> hasMentionEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hasMention',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      hasMessageGapEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hasMessageGap',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idEqualTo(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idBetween(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idStartsWith(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idEndsWith(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idContains(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idMatches(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> isArchivedEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isArchived',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> isMutedEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isMuted',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> isPinnedEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isPinned',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> isarIdEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> isarIdGreaterThan(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> isarIdLessThan(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> isarIdBetween(
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastMessage',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastMessage',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> lastMessageEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> lastMessageLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> lastMessageBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastMessage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'lastMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> lastMessageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'lastMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> lastMessageContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'lastMessage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> lastMessageMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'lastMessage',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessage',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'lastMessage',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageFailedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessageFailed',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastMessageMediaUrl',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastMessageMediaUrl',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessageMediaUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastMessageMediaUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastMessageMediaUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastMessageMediaUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'lastMessageMediaUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'lastMessageMediaUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'lastMessageMediaUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'lastMessageMediaUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessageMediaUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageMediaUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'lastMessageMediaUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastMessageSender',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastMessageSender',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessageSender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastMessageSender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastMessageSender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastMessageSender',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'lastMessageSender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'lastMessageSender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'lastMessageSender',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'lastMessageSender',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessageSender',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSenderIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'lastMessageSender',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSeqEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessageSeq',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSeqGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastMessageSeq',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSeqLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastMessageSeq',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageSeqBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastMessageSeq',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTimeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastMessageTime',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTimeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastMessageTime',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTimeEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessageTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTimeGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastMessageTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTimeLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastMessageTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTimeBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastMessageTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTypeEqualTo(MessageType value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastMessageType',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTypeGreaterThan(
    MessageType value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastMessageType',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTypeLessThan(
    MessageType value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastMessageType',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastMessageTypeBetween(
    MessageType lower,
    MessageType upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastMessageType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastSyncedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastSyncedAt',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastSyncedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastSyncedAt',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> lastSyncedAtEqualTo(
      DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSyncedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastSyncedAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastSyncedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastSyncedAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastSyncedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> lastSyncedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastSyncedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastSyncedSeqEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSyncedSeq',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastSyncedSeqGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastSyncedSeq',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastSyncedSeqLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastSyncedSeq',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      lastSyncedSeqBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastSyncedSeq',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      memberCountIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'memberCount',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      memberCountIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'memberCount',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> memberCountEqualTo(
      int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'memberCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      memberCountGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'memberCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> memberCountLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'memberCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> memberCountBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'memberCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> peerUserIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'peerUserId',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      peerUserIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'peerUserId',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> peerUserIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'peerUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      peerUserIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'peerUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> peerUserIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'peerUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> peerUserIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'peerUserId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      peerUserIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'peerUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> peerUserIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'peerUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> peerUserIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'peerUserId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> peerUserIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'peerUserId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      peerUserIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'peerUserId',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      peerUserIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'peerUserId',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> typeEqualTo(
      ChatType value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> typeGreaterThan(
    ChatType value, {
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> typeLessThan(
    ChatType value, {
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> typeBetween(
    ChatType lower,
    ChatType upper, {
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

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> unreadCountEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'unreadCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      unreadCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'unreadCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> unreadCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'unreadCount',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> unreadCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'unreadCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> updatedAtEqualTo(
      DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition>
      updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterFilterCondition> updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ChatModelQueryObject
    on QueryBuilder<ChatModel, ChatModel, QFilterCondition> {}

extension ChatModelQueryLinks
    on QueryBuilder<ChatModel, ChatModel, QFilterCondition> {}

extension ChatModelQuerySortBy on QueryBuilder<ChatModel, ChatModel, QSortBy> {
  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByAvatar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatar', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByAvatarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatar', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByDraft() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draft', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByDraftDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draft', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByHasMention() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasMention', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByHasMentionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasMention', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByHasMessageGap() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasMessageGap', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByHasMessageGapDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasMessageGap', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByIsArchivedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByIsMuted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMuted', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByIsMutedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMuted', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByIsPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPinned', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByIsPinnedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPinned', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessage', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessage', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageFailed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageFailed', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy>
      sortByLastMessageFailedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageFailed', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageMediaUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageMediaUrl', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy>
      sortByLastMessageMediaUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageMediaUrl', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageSender() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageSender', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy>
      sortByLastMessageSenderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageSender', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageSeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageSeq', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageSeqDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageSeq', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageTime', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageTime', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageType', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastMessageTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageType', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastSyncedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncedAt', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastSyncedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncedAt', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastSyncedSeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncedSeq', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByLastSyncedSeqDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncedSeq', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByMemberCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memberCount', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByMemberCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memberCount', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByPeerUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerUserId', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByPeerUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerUserId', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByUnreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unreadCount', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByUnreadCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unreadCount', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension ChatModelQuerySortThenBy
    on QueryBuilder<ChatModel, ChatModel, QSortThenBy> {
  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByAccountId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByAccountIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'accountId', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByAvatar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatar', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByAvatarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatar', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByDraft() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draft', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByDraftDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'draft', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByHasMention() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasMention', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByHasMentionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasMention', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByHasMessageGap() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasMessageGap', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByHasMessageGapDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasMessageGap', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIsArchivedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIsMuted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMuted', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIsMutedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMuted', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIsPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPinned', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIsPinnedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPinned', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByIsarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessage', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessage', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageFailed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageFailed', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy>
      thenByLastMessageFailedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageFailed', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageMediaUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageMediaUrl', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy>
      thenByLastMessageMediaUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageMediaUrl', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageSender() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageSender', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy>
      thenByLastMessageSenderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageSender', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageSeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageSeq', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageSeqDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageSeq', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageTime', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageTime', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageType', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastMessageTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastMessageType', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastSyncedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncedAt', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastSyncedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncedAt', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastSyncedSeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncedSeq', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByLastSyncedSeqDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncedSeq', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByMemberCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memberCount', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByMemberCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memberCount', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByPeerUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerUserId', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByPeerUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'peerUserId', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByUnreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unreadCount', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByUnreadCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unreadCount', Sort.desc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension ChatModelQueryWhereDistinct
    on QueryBuilder<ChatModel, ChatModel, QDistinct> {
  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByAccountId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'accountId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByAvatar(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'avatar', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByDraft(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'draft', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByHasMention() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hasMention');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByHasMessageGap() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hasMessageGap');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctById(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'id', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isArchived');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByIsMuted() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isMuted');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByIsPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isPinned');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastMessage(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastMessage', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastMessageFailed() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastMessageFailed');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastMessageMediaUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastMessageMediaUrl',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastMessageSender(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastMessageSender',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastMessageSeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastMessageSeq');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastMessageTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastMessageTime');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastMessageType() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastMessageType');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastSyncedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncedAt');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByLastSyncedSeq() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncedSeq');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByMemberCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'memberCount');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByPeerUserId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'peerUserId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByUnreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'unreadCount');
    });
  }

  QueryBuilder<ChatModel, ChatModel, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension ChatModelQueryProperty
    on QueryBuilder<ChatModel, ChatModel, QQueryProperty> {
  QueryBuilder<ChatModel, int, QQueryOperations> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isarId');
    });
  }

  QueryBuilder<ChatModel, String, QQueryOperations> accountIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'accountId');
    });
  }

  QueryBuilder<ChatModel, String?, QQueryOperations> avatarProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'avatar');
    });
  }

  QueryBuilder<ChatModel, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<ChatModel, String?, QQueryOperations> draftProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'draft');
    });
  }

  QueryBuilder<ChatModel, bool, QQueryOperations> hasMentionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hasMention');
    });
  }

  QueryBuilder<ChatModel, bool, QQueryOperations> hasMessageGapProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hasMessageGap');
    });
  }

  QueryBuilder<ChatModel, String, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ChatModel, bool, QQueryOperations> isArchivedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isArchived');
    });
  }

  QueryBuilder<ChatModel, bool, QQueryOperations> isMutedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isMuted');
    });
  }

  QueryBuilder<ChatModel, bool, QQueryOperations> isPinnedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isPinned');
    });
  }

  QueryBuilder<ChatModel, String?, QQueryOperations> lastMessageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessage');
    });
  }

  QueryBuilder<ChatModel, bool, QQueryOperations> lastMessageFailedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessageFailed');
    });
  }

  QueryBuilder<ChatModel, String?, QQueryOperations>
      lastMessageMediaUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessageMediaUrl');
    });
  }

  QueryBuilder<ChatModel, String?, QQueryOperations>
      lastMessageSenderProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessageSender');
    });
  }

  QueryBuilder<ChatModel, int, QQueryOperations> lastMessageSeqProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessageSeq');
    });
  }

  QueryBuilder<ChatModel, DateTime?, QQueryOperations>
      lastMessageTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessageTime');
    });
  }

  QueryBuilder<ChatModel, MessageType, QQueryOperations>
      lastMessageTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastMessageType');
    });
  }

  QueryBuilder<ChatModel, DateTime?, QQueryOperations> lastSyncedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncedAt');
    });
  }

  QueryBuilder<ChatModel, int, QQueryOperations> lastSyncedSeqProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncedSeq');
    });
  }

  QueryBuilder<ChatModel, int?, QQueryOperations> memberCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'memberCount');
    });
  }

  QueryBuilder<ChatModel, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<ChatModel, String?, QQueryOperations> peerUserIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'peerUserId');
    });
  }

  QueryBuilder<ChatModel, ChatType, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }

  QueryBuilder<ChatModel, int, QQueryOperations> unreadCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'unreadCount');
    });
  }

  QueryBuilder<ChatModel, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
