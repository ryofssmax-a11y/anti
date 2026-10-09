import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../platform/cloud.dart';
import 'common.dart';

/// 設定画面のバックアップ欄
class BackupSection extends StatelessWidget {
  const BackupSection({super.key});

  Future<void> _pickFolder(BuildContext context) async {
    final scope = AppScope.of(context);
    try {
      final folder = await SafBackupTarget.pickFolder();
      if (folder == null) return;
      await scope.settings.setBackupFolder(folder.uri, folder.name);
      final err = await scope.backup?.backupNow();
      if (context.mounted) {
        toast(
          context,
          err == null ? '「${folder.name}」にバックアップしました' : 'バックアップできませんでした: $err',
        );
      }
    } on PlatformException catch (e) {
      if (context.mounted) toast(context, 'フォルダを選べませんでした: ${e.message}');
    }
  }

  Future<void> _backupNow(BuildContext context) async {
    final err = await AppScope.of(context).backup?.backupNow();
    if (context.mounted) {
      toast(context, err == null ? 'バックアップしました' : 'バックアップできませんでした: $err');
    }
  }

  Future<void> _share(BuildContext context) async {
    final scope = AppScope.of(context);
    final json = await buildBackupJson(scope.db, scope.settings);
    final name = dailyBackupName(today());
    if (kIsWeb) {
      final ok = await saveTextFile(name, json);
      if (context.mounted && !ok) toast(context, 'ファイルを保存できませんでした');
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsString(json, encoding: utf8);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: '馬券収支電卓のバックアップ'),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final scope = AppScope.of(context);
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return;
    final text = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
    final ({Map<String, Object?> data, BackupSummary summary}) parsed;
    try {
      parsed = parseBackupJson(text);
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
      return;
    }
    if (!context.mounted) return;
    final at = parsed.summary.exportedAt;
    final ok = await confirm(
      context,
      'バックアップから復元',
      '${at == null ? '' : '${at.month}/${at.day} ${at.hour}:${at.minute.toString().padLeft(2, '0')} 時点の'}'
          '馬券${parsed.summary.tickets}件で、今の記録をすべて置き換えます。よろしいですか？',
      ok: '復元する',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await restoreBackup(scope.db, scope.settings, parsed.data);
    if (context.mounted) toast(context, '復元しました');
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final canAuto = scope.backup != null;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final last = s.lastBackupAt;
        final folder = s.backupFolderName;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                'バックアップ',
                style: t.labelLarge?.copyWith(color: scheme.primary),
              ),
            ),
            if (scope.cloud case final cloud?)
              ListenableBuilder(
                listenable: cloud,
                builder: (context, _) {
                  final saved = cloud.lastSavedAt;
                  final String status;
                  if (cloud.available == null) {
                    status = '確認しています…';
                  } else if (cloud.available == false) {
                    status =
                        'サインインしていないため、このブラウザの中にだけ保存しています。バックアップファイルを残してください';
                  } else if (cloud.lastError != null) {
                    status = cloud.lastError!;
                  } else {
                    status = saved == null
                        ? '記録を変えるたびに自動で保存します'
                        : '最終 ${saved.month}/${saved.day} ${saved.hour}:${saved.minute.toString().padLeft(2, '0')}';
                  }
                  return ListTile(
                    leading: Icon(
                      cloud.available == true
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                    ),
                    title: const Text('Claude に自動保存'),
                    subtitle: Text(
                      status,
                      style: cloud.lastError != null
                          ? TextStyle(color: scheme.error)
                          : null,
                    ),
                    trailing: cloud.available == true
                        ? TextButton(
                            onPressed: cloud.saveNow,
                            child: const Text('今すぐ'),
                          )
                        : null,
                  );
                },
              ),
            if (canAuto) ...[
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('保存先フォルダ'),
                subtitle: Text(folder ?? '未設定（タップして選ぶ）'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickFolder(context),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cloud_sync_outlined),
                title: const Text('自動バックアップ'),
                subtitle: Text(
                  s.lastBackupError != null
                      ? '前回失敗: ${s.lastBackupError}'
                      : last == null
                      ? '記録を変えるたびに保存します'
                      : '最終 ${last.month}/${last.day} ${last.hour}:${last.minute.toString().padLeft(2, '0')}',
                  style: s.lastBackupError != null
                      ? TextStyle(color: scheme.error)
                      : null,
                ),
                value: s.autoBackup && folder != null,
                onChanged: folder == null ? null : (v) => s.setAutoBackup(v),
              ),
              if (folder != null)
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('今すぐバックアップ'),
                  onTap: () => _backupNow(context),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Google ドライブのフォルダを選ぶと、アプリを消したり機種を変えたりしても「バックアップから復元」で戻せます。'
                  '最新の1つと、日付ごとのファイル（30日分）を残します。',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(kIsWeb ? 'バックアップファイルを保存' : 'バックアップファイルを送る'),
              subtitle: Text(kIsWeb ? 'このブラウザの外に控えを残せます' : 'メールやドライブに保存できます'),
              onTap: () => _share(context),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('バックアップから復元'),
              subtitle: const Text('バックアップファイル（.json）を選んで、記録と設定を戻します'),
              onTap: () => _restore(context),
            ),
          ],
        );
      },
    );
  }
}
