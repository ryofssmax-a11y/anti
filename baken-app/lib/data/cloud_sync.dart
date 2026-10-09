import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/cloud.dart';
import 'backup.dart';
import 'database.dart';
import 'settings.dart';

/// ブラウザ版の記録を、アーティファクトのデータ保存に自動で置く。
///
/// 開いたときにブラウザの中の記録が空なら、保存してある記録を戻す。
/// 記録が変わると、少し待ってから全体を保存する。
class CloudSyncService extends ChangeNotifier {
  CloudSyncService({
    required this.db,
    required this.settings,
    required this.store,
    this.delay = const Duration(seconds: 2),
  });

  final AppDatabase db;
  final AppSettings settings;
  final CloudStore store;
  final Duration delay;

  bool? _available;
  DateTime? lastSavedAt;
  String? lastError;
  bool restored = false;
  Timer? _timer;
  bool _saving = false;
  bool _pending = false;

  /// null = まだ確認中
  bool? get available => _available;

  Future<void> start() async {
    try {
      _available = await store.available();
    } catch (_) {
      _available = false;
    }
    notifyListeners();
    if (_available != true) return;
    await _restoreIfEmpty();
    db.addListener(_schedule);
  }

  @override
  void dispose() {
    db.removeListener(_schedule);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _restoreIfEmpty() async {
    try {
      if ((await db.tickets()).isNotEmpty) return;
      final json = await store.load();
      if (json == null || json.isEmpty) return;
      final parsed = parseBackupJson(json);
      await restoreBackup(db, settings, parsed.data);
      restored = true;
      lastSavedAt = parsed.summary.exportedAt;
      notifyListeners();
    } catch (e) {
      lastError = '保存した記録を読み込めませんでした';
      debugPrint('cloud restore failed: $e');
      notifyListeners();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(delay, saveNow);
  }

  /// すぐに保存する。
  Future<void> saveNow() async {
    if (_saving) {
      _pending = true;
      return;
    }
    _saving = true;
    try {
      final ok = await store.save(await buildBackupJson(db, settings));
      if (ok) {
        lastSavedAt = DateTime.now();
        lastError = null;
      } else {
        lastError = '保存できませんでした';
      }
    } catch (e) {
      lastError = '保存できませんでした';
      debugPrint('cloud save failed: $e');
    } finally {
      _saving = false;
      notifyListeners();
    }
    if (_pending) {
      _pending = false;
      await saveNow();
    }
  }
}
