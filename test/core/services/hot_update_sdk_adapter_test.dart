import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart' as shorebird;
import 'package:generic_im/core/services/hot_update_sdk_adapter.dart';

void main() {
  group('HotUpdateSdkAdapter.downloadLatestShorebirdPatch', () {
    test('reports unavailable when Shorebird is not integrated', () async {
      final adapter = HotUpdateSdkAdapter(
        shorebirdUpdater: _FakeShorebirdUpdater(isAvailable: false),
        platformSupportsShorebird: true,
      );

      final result = await adapter.downloadLatestShorebirdPatch();

      expect(result.success, isFalse);
      expect(result.requiresRestart, isFalse);
      expect(result.message, 'hot_update_sdk_not_integrated');
    });

    test('downloads an available patch without overriding its track', () async {
      final updater = _FakeShorebirdUpdater(
        statuses: <shorebird.UpdateStatus>[shorebird.UpdateStatus.outdated],
      );
      final adapter = HotUpdateSdkAdapter(
        shorebirdUpdater: updater,
        platformSupportsShorebird: true,
      );

      final result = await adapter.downloadLatestShorebirdPatch();

      expect(result.success, isTrue);
      expect(result.requiresRestart, isTrue);
      expect(result.message, 'shorebird_update_downloaded');
      expect(updater.checkedTracks, <shorebird.UpdateTrack?>[null]);
      expect(updater.updatedTracks, <shorebird.UpdateTrack?>[null]);
    });

    test('reports an already downloaded patch as restart required', () async {
      final updater = _FakeShorebirdUpdater(
        statuses: <shorebird.UpdateStatus>[
          shorebird.UpdateStatus.restartRequired,
        ],
      );
      final adapter = HotUpdateSdkAdapter(
        shorebirdUpdater: updater,
        platformSupportsShorebird: true,
      );

      final result = await adapter.downloadLatestShorebirdPatch();

      expect(result.success, isTrue);
      expect(result.requiresRestart, isTrue);
      expect(result.message, 'shorebird_restart_required');
      expect(updater.updatedTracks, isEmpty);
    });
  });
}

class _FakeShorebirdUpdater implements shorebird.ShorebirdUpdater {
  _FakeShorebirdUpdater({
    this.isAvailable = true,
    List<shorebird.UpdateStatus>? statuses,
  }) : _statuses = statuses ?? <shorebird.UpdateStatus>[];

  @override
  final bool isAvailable;

  final List<shorebird.UpdateStatus> _statuses;
  final List<shorebird.UpdateTrack?> checkedTracks = <shorebird.UpdateTrack?>[];
  final List<shorebird.UpdateTrack?> updatedTracks = <shorebird.UpdateTrack?>[];

  @override
  Future<shorebird.UpdateStatus> checkForUpdate({
    shorebird.UpdateTrack? track,
  }) async {
    checkedTracks.add(track);
    return _statuses.removeAt(0);
  }

  @override
  Future<shorebird.Patch?> readCurrentPatch() async => null;

  @override
  Future<shorebird.Patch?> readNextPatch() async => null;

  @override
  Future<void> update({shorebird.UpdateTrack? track}) async {
    updatedTracks.add(track);
  }
}
