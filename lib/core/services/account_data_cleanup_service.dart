// 文件用途：封装 AccountPurgeStage 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AccountPurgeStage 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';

import 'api/api_client.dart';
import 'media_cache_manager.dart';
import 'offline_message_queue.dart';
import 'storage/isar_service.dart';
import 'storage/models/chat_model.dart'
    if (dart.library.js_interop) 'storage/models/chat_model_web.dart';
import 'storage/models/message_model.dart'
    if (dart.library.js_interop) 'storage/models/message_model_web.dart';
import 'storage/models/user_model.dart'
    if (dart.library.js_interop) 'storage/models/user_model_web.dart';

// 流程逻辑：`accountStoragePrefix` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
String accountStoragePrefix(String accountId) {
  final normalized = accountId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
  }
  return 'acct_v1_${sha256.convert(utf8.encode(normalized))}_';
}

/// 仅删除当前账号命名空间及明确登记的旧键，未归属账号的全局设置不在清理范围内。
Set<String> accountPreferenceDeletionSet(
  Iterable<String> availableKeys,
  String accountId,
) {
  final normalized = accountId.trim();
  if (normalized.isEmpty) return <String>{};
  final prefix = accountStoragePrefix(normalized);
  final legacyKeys = <String>{
    'favorite_messages_v1_$normalized',
  };
  return availableKeys
      .where((key) => key.startsWith(prefix) || legacyKeys.contains(key))
      .toSet();
}

// 关键声明：account data cleanup service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
enum AccountPurgeStage {
  scheduled,
  referencedMediaDeleted,
  isarDeleted,
  preferencesDeleted,
  offlineQueueDeleted,
  mediaDeleted,
}

/// 持久化清理进度，使进程在任意步骤退出后都能从最后成功阶段继续，而不是重新猜测状态。
class AccountPurgeJournal {
  const AccountPurgeJournal({
    required this.accountId,
    required this.stage,
    required this.createdAt,
  });

  final String accountId;
  final AccountPurgeStage stage;
  final DateTime createdAt;

  AccountPurgeJournal copyWith({AccountPurgeStage? stage}) {
    return AccountPurgeJournal(
      accountId: accountId,
      stage: stage ?? this.stage,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'account_id': accountId,
        'stage': stage.name,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory AccountPurgeJournal.fromJson(Map<String, dynamic> json) {
    final stageName = json['stage']?.toString() ?? '';
    return AccountPurgeJournal(
      accountId: json['account_id']?.toString().trim() ?? '',
      stage: AccountPurgeStage.values.firstWhere(
        (item) => item.name == stageName,
        orElse: () => AccountPurgeStage.scheduled,
      ),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class AccountDataSnapshot {
  const AccountDataSnapshot({
    required this.accountId,
    required this.chatCount,
    required this.messageCount,
    required this.contactCount,
    required this.draftCount,
    required this.offlineMessageCount,
    required this.preferenceCount,
    required this.privateMediaFileCount,
    required this.privateMediaBytes,
  });

  final String accountId;
  final int chatCount;
  final int messageCount;
  final int contactCount;
  final int draftCount;
  final int offlineMessageCount;
  final int preferenceCount;
  final int privateMediaFileCount;
  final int privateMediaBytes;

  int get localUniqueItemCount =>
      draftCount + offlineMessageCount + privateMediaFileCount;
}

class AccountPurgeResult {
  const AccountPurgeResult({
    required this.accountId,
    required this.success,
    this.errors = const <String>[],
  });

  final String accountId;
  final bool success;
  final List<String> errors;
}

class AccountDataCleanupService {
  static const String journalPreferenceKey = 'account_data_purge_journal_v1';

  Future<AccountPurgeJournal?> pendingJournal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(journalPreferenceKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final journal = AccountPurgeJournal.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return journal.accountId.isEmpty ? null : journal;
    } catch (_) {
      return null;
    }
  }

  Future<AccountDataSnapshot> inspectAccount(String accountId) async {
    // 这里只盘点账号私有数据，不修改任何缓存，供删除确认页展示不可恢复内容的规模。
    final normalized = accountId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }

    var chatCount = 0;
    var messageCount = 0;
    var contactCount = 0;
    var draftCount = 0;
    if (!kIsWeb && IsarService.instance.isAvailable) {
      final isar = IsarService.instance.isar;
      final chats =
          await isar.chatModels.filter().accountIdEqualTo(normalized).findAll();
      final messages = await isar.messageModels
          .filter()
          .accountIdEqualTo(normalized)
          .findAll();
      final users =
          await isar.userModels.filter().accountIdEqualTo(normalized).findAll();
      chatCount = chats.length;
      messageCount = messages.length;
      contactCount = users.length;
      draftCount =
          chats.where((chat) => (chat.draft ?? '').trim().isNotEmpty).length;
    }

    final prefs = await SharedPreferences.getInstance();
    final deletionKeys = accountPreferenceDeletionSet(
      prefs.getKeys(),
      normalized,
    );
    final offlineRaw = prefs.getStringList(
          '${accountStoragePrefix(normalized)}offline_message_queue',
        ) ??
        const <String>[];
    final media = await ChatMediaCacheManager.inspectAccountPrivateData(
      normalized,
    );

    return AccountDataSnapshot(
      accountId: normalized,
      chatCount: chatCount,
      messageCount: messageCount,
      contactCount: contactCount,
      draftCount: draftCount,
      offlineMessageCount: offlineRaw.length,
      preferenceCount: deletionKeys.length,
      privateMediaFileCount: media.files,
      privateMediaBytes: media.bytes,
    );
  }

  Future<void> scheduleAccountPurge(String accountId) async {
    final normalized = accountId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'must not be empty');
    }
    final pending = await pendingJournal();
    // 同一时刻只允许一个账号存在清理日志，避免错误地把 A 账号阶段应用到 B 账号。
    if (pending != null && pending.accountId != normalized) {
      throw StateError('Another account purge is still pending');
    }
    await _saveJournal(
      pending ??
          AccountPurgeJournal(
            accountId: normalized,
            stage: AccountPurgeStage.scheduled,
            createdAt: DateTime.now().toUtc(),
          ),
    );
  }

  /// Runs before cached authentication is restored. A purge targeting the
  /// stored account must win over automatic sign-in after an interrupted run.
  Future<bool> resumePendingPurgeBeforeAuth() async {
    final journal = await pendingJournal();
    if (journal == null) return false;
    final storedAccountId = (await TokenStorage.getUserId())?.trim() ?? '';
    final blocksStoredAccount = storedAccountId == journal.accountId;
    if (blocksStoredAccount) {
      await TokenStorage.clear();
    }
    await resumePendingPurge();
    return blocksStoredAccount;
  }

  Future<AccountPurgeResult> resumePendingPurge() async {
    var journal = await pendingJournal();
    if (journal == null) {
      return const AccountPurgeResult(accountId: '', success: true);
    }
    final purgeAccountId = journal.accountId;

    try {
      // 每完成一个幂等阶段就落盘；崩溃恢复时只执行尚未确认完成的后续阶段。
      if (journal.stage.index <
          AccountPurgeStage.referencedMediaDeleted.index) {
        await _deleteReferencedLocalFiles(journal.accountId);
        journal = journal.copyWith(
          stage: AccountPurgeStage.referencedMediaDeleted,
        );
        await _saveJournal(journal);
      }
      if (journal.stage.index < AccountPurgeStage.isarDeleted.index) {
        await _deleteIsarData(journal.accountId);
        journal = journal.copyWith(stage: AccountPurgeStage.isarDeleted);
        await _saveJournal(journal);
      }
      if (journal.stage.index < AccountPurgeStage.preferencesDeleted.index) {
        await _deletePreferences(journal.accountId);
        journal = journal.copyWith(stage: AccountPurgeStage.preferencesDeleted);
        await _saveJournal(journal);
      }
      if (journal.stage.index < AccountPurgeStage.offlineQueueDeleted.index) {
        await OfflineMessageQueue().clearAccount(journal.accountId);
        journal =
            journal.copyWith(stage: AccountPurgeStage.offlineQueueDeleted);
        await _saveJournal(journal);
      }
      if (journal.stage.index < AccountPurgeStage.mediaDeleted.index) {
        await ChatMediaCacheManager.deleteAccountPrivateData(
          journal.accountId,
        );
        journal = journal.copyWith(stage: AccountPurgeStage.mediaDeleted);
        await _saveJournal(journal);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(journalPreferenceKey);
      return AccountPurgeResult(accountId: journal.accountId, success: true);
    } catch (error, stackTrace) {
      debugPrint('[AccountCleanup] Purge failed: $error\n$stackTrace');
      return AccountPurgeResult(
        accountId: purgeAccountId,
        success: false,
        errors: <String>[error.toString()],
      );
    }
  }

  Future<int> clearRedownloadableCache(String accountId) {
    return ChatMediaCacheManager.clearRedownloadableCache(accountId);
  }

  Future<void> _deleteIsarData(String accountId) async {
    if (kIsWeb || !IsarService.instance.isAvailable) return;
    final isar = IsarService.instance.isar;
    final chats =
        await isar.chatModels.filter().accountIdEqualTo(accountId).findAll();
    final messages =
        await isar.messageModels.filter().accountIdEqualTo(accountId).findAll();
    final users =
        await isar.userModels.filter().accountIdEqualTo(accountId).findAll();
    await isar.writeTxn(() async {
      await isar.messageModels.deleteAll(
        messages.map((item) => item.isarId).toList(growable: false),
      );
      await isar.chatModels.deleteAll(
        chats.map((item) => item.isarId).toList(growable: false),
      );
      await isar.userModels.deleteAll(
        users.map((item) => item.isarId).toList(growable: false),
      );
    });
  }

  Future<void> _deleteReferencedLocalFiles(String accountId) async {
    if (kIsWeb) return;
    final targetPaths = <String>{};
    final otherPaths = <String>{};

    if (IsarService.instance.isAvailable) {
      final messages =
          await IsarService.instance.isar.messageModels.where().findAll();
      for (final message in messages) {
        final destination =
            message.accountId == accountId ? targetPaths : otherPaths;
        final localPath = message.localPath?.trim() ?? '';
        final thumbnail = message.thumbnail?.trim() ?? '';
        if (localPath.isNotEmpty) destination.add(localPath);
        if (thumbnail.isNotEmpty && !thumbnail.startsWith('http')) {
          destination.add(thumbnail);
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final targetPrefix = accountStoragePrefix(accountId);
    for (final key in prefs.getKeys()) {
      final destination =
          key.startsWith(targetPrefix) ? targetPaths : otherPaths;
      if (key.endsWith('_offline_message_queue')) {
        for (final raw in prefs.getStringList(key) ?? const <String>[]) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              final path = decoded['localPath']?.toString().trim() ?? '';
              if (path.isNotEmpty) destination.add(path);
            }
          } catch (_) {}
        }
      } else if (key.endsWith('_custom_emoji_items')) {
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final path = item['path']?.toString().trim() ?? '';
                if (path.isNotEmpty) destination.add(path);
              }
            }
          }
        } catch (_) {}
      }
    }

    final temporary = (await getTemporaryDirectory()).absolute.path;
    final documents = (await getApplicationDocumentsDirectory()).absolute.path;
    final legacyCustomEmojiRoot =
        '$documents${Platform.pathSeparator}custom_emojis';
    final accountRoot = (await ChatMediaCacheManager.accountPrivateDirectory(
      accountId,
      '_root_probe',
      create: false,
    ))
        .parent
        .absolute
        .path;
    final safeRoots = <String>{temporary, legacyCustomEmojiRoot, accountRoot};

    // 仅删除目标账号独占且位于受控目录内的文件，其他账号仍引用的媒体必须保留。
    for (final rawPath in targetPaths.difference(otherPaths)) {
      final file = File(rawPath).absolute;
      final path = file.path;
      final isWithinSafeRoot = safeRoots.any(
        (root) =>
            path == root || path.startsWith('$root${Platform.pathSeparator}'),
      );
      if (!isWithinSafeRoot) continue;
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _deletePreferences(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = accountPreferenceDeletionSet(prefs.getKeys(), accountId);
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  Future<void> _saveJournal(AccountPurgeJournal journal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(journalPreferenceKey, jsonEncode(journal.toJson()));
  }
}

final accountDataCleanupServiceProvider = Provider<AccountDataCleanupService>(
  (ref) => AccountDataCleanupService(),
);
