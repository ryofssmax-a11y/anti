import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'database.dart';
import 'settings.dart';

/// バックアップファイルの中身（記録のすべてと主な設定）を JSON にする。
Future<String> buildBackupJson(AppDatabase db, AppSettings settings) async {
  final tables = await db.exportTables();
  return jsonEncode({
    'app': 'baken-app',
    'format': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'tables': tables,
    'settings': settings.exportForBackup(),
  });
}

/// バックアップの件数（確認ダイアログ用）
class BackupSummary {
  BackupSummary(this.tickets, this.exportedAt);
  final int tickets;
  final DateTime? exportedAt;
}

/// バックアップファイルを読み、中身を確かめる。形式が違えば FormatException。
({Map<String, Object?> data, BackupSummary summary}) parseBackupJson(
  String text,
) {
  final decoded = jsonDecode(text);
  if (decoded is! Map ||
      decoded['app'] != 'baken-app' ||
      decoded['tables'] is! Map) {
    throw const FormatException('このアプリのバックアップファイルではありません');
  }
  final data = decoded.cast<String, Object?>();
  final tables = (data['tables'] as Map).cast<String, Object?>();
  return (
    data: data,
    summary: BackupSummary(
      (tables['tickets'] as List? ?? const []).length,
      DateTime.tryParse('${data['exportedAt']}'),
    ),
  );
}

/// バックアップで記録と設定を置き換える。
Future<void> restoreBackup(
  AppDatabase db,
  AppSettings settings,
  Map<String, Object?> data,
) async {
  await db.importTables((data['tables'] as Map).cast<String, Object?>());
  final s = data['settings'];
  if (s is Map) await settings.importFromBackup(s.cast<String, Object?>());
}

/// バックアップの保存先
abstract class BackupTarget {
  Future<void> write(String name, String content);
  Future<List<String>> list();
  Future<void> delete(String name);
}

/// Android のフォルダ選択（Storage Access Framework）で選んだフォルダ。
/// Google ドライブのフォルダも選べるので、アプリを消してもバックアップが残る。
class SafBackupTarget implements BackupTarget {
  SafBackupTarget(this.treeUri);

  final String treeUri;

  static const channel = MethodChannel('baken/backup');

  /// フォルダを選ぶ。キャンセルなら null。
  static Future<({String uri, String name})?> pickFolder() async {
    final r = await channel.invokeMapMethod<String, Object?>('pickFolder');
    if (r == null) return null;
    return (uri: r['uri'] as String, name: (r['name'] as String?) ?? 'フォルダ');
  }

  @override
  Future<void> write(String name, String content) => channel.invokeMethod(
    'writeFile',
    {'tree': treeUri, 'name': name, 'content': content},
  );

  @override
  Future<List<String>> list() async =>
      (await channel.invokeListMethod<String>('listFiles', {
        'tree': treeUri,
      })) ??
      const [];

  @override
  Future<void> delete(String name) =>
      channel.invokeMethod('deleteFile', {'tree': treeUri, 'name': name});
}

const latestBackupName = 'baken_backup_latest.json';
const _dailyPrefix = 'baken_backup_';
final _dailyPattern = RegExp(r'^baken_backup_(\d{4}-\d{2}-\d{2})\.json$');

/// 何日分の日付つきバックアップを残すか
const keepDailyBackups = 30;

String dailyBackupName(DateTime d) =>
    '$_dailyPrefix${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json';

/// 記録が変わるたびに（少し待ってから）バックアップを書く。
///
/// 書くファイルは「最新」1つと「日付つき」1日1つ。日付つきは [keepDailyBackups] 日より古いものを消す。
class BackupService {
  BackupService({
    required this.db,
    required this.settings,
    BackupTarget? Function(String uri)? targetFor,
    this.delay = const Duration(seconds: 3),
    DateTime Function()? now,
  }) : _targetFor = targetFor ?? ((uri) => SafBackupTarget(uri)),
       _now = now ?? DateTime.now;

  final AppDatabase db;
  final AppSettings settings;
  final BackupTarget? Function(String uri) _targetFor;
  final Duration delay;
  final DateTime Function() _now;
  Timer? _timer;
  bool _running = false;

  bool get enabled => settings.autoBackup && settings.backupFolderUri != null;

  void start() {
    db.addListener(_schedule);
    // 起動時にも1回（その日の日付つきファイルを作るため）
    _schedule();
  }

  void dispose() {
    db.removeListener(_schedule);
    _timer?.cancel();
  }

  void _schedule() {
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer(delay, () => backupNow());
  }

  /// すぐにバックアップする。失敗したらエラー文を返す。
  Future<String?> backupNow() async {
    final uri = settings.backupFolderUri;
    if (uri == null) return '保存先のフォルダが選ばれていません';
    final target = _targetFor(uri);
    if (target == null || _running) return null;
    _running = true;
    try {
      final json = await buildBackupJson(db, settings);
      await target.write(latestBackupName, json);
      final today = _now();
      await target.write(dailyBackupName(today), json);
      await _prune(target, today);
      await settings.recordBackupResult();
      return null;
    } catch (e) {
      final msg = e is PlatformException ? (e.message ?? e.code) : '$e';
      await settings.recordBackupResult(error: msg);
      debugPrint('backup failed: $msg');
      return msg;
    } finally {
      _running = false;
    }
  }

  Future<void> _prune(BackupTarget target, DateTime today) async {
    final limit = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: keepDailyBackups));
    for (final name in await target.list()) {
      final m = _dailyPattern.firstMatch(name);
      if (m == null) continue;
      final d = DateTime.tryParse(m.group(1)!);
      if (d != null && d.isBefore(limit)) await target.delete(name);
    }
  }
}
