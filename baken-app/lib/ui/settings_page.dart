import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/csv_io.dart';
import '../platform/cloud.dart';
import 'backup_section.dart';
import 'common.dart';

/// 設定タブ
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _editBudgets(BuildContext context) async {
    final s = AppScope.of(context).settings;
    final day = TextEditingController(
      text: s.budgetDay == 0 ? '' : '${s.budgetDay}',
    );
    final week = TextEditingController(
      text: s.budgetWeek == 0 ? '' : '${s.budgetWeek}',
    );
    final month = TextEditingController(
      text: s.budgetMonth == 0 ? '' : '${s.budgetMonth}',
    );
    InputDecoration deco(String l) => InputDecoration(
      labelText: l,
      suffixText: '円',
      hintText: '設定なし',
      border: const OutlineInputBorder(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('予算上限'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('記録したときに、上限の80%と100%を超えたらお知らせします。空欄は設定なし。'),
            const SizedBox(height: 12),
            TextField(
              controller: day,
              keyboardType: TextInputType.number,
              decoration: deco('1日'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: week,
              keyboardType: TextInputType.number,
              decoration: deco('1週間（月〜日）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: month,
              keyboardType: TextInputType.number,
              decoration: deco('1か月'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    int v(TextEditingController c) =>
        int.tryParse(c.text.replaceAll(',', '')) ?? 0;
    await s.setBudgets(day: v(day), week: v(week), month: v(month));
  }

  Future<void> _export(BuildContext context) async {
    final db = AppScope.of(context).db;
    final tickets = await db.tickets(withLines: true);
    if (tickets.isEmpty) {
      if (context.mounted) toast(context, '書き出す記録がありません');
      return;
    }
    final csv = '\uFEFF${ticketsToCsv(tickets.reversed.toList())}';
    final name = 'baken_${isoDate(today())}.csv';
    if (kIsWeb) {
      final ok = await saveTextFile(name, csv);
      if (context.mounted && !ok) toast(context, 'ファイルを保存できませんでした');
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    // Excel で文字化けしないよう BOM を付ける
    await file.writeAsString(csv, encoding: utf8);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: '馬券の記録（CSV）'),
    );
  }

  Future<void> _import(BuildContext context) async {
    final db = AppScope.of(context).db;
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final result = ticketsFromCsv(utf8.decode(bytes, allowMalformed: true));
    if (!context.mounted) return;
    final ok = await confirm(
      context,
      'CSV を読み込む',
      '${result.tickets.length}件を追加します。'
          '${result.errors.isEmpty ? '' : '\n読み込めない行が${result.errors.length}行あります。\n${result.errors.take(3).join('\n')}'}'
          '\n今ある記録はそのまま残ります。',
      ok: '追加',
    );
    if (!ok) return;
    for (final x in result.tickets) {
      await db.insertTicket(x.ticket, race: x.race);
    }
    if (context.mounted) toast(context, '${result.tickets.length}件を読み込みました');
  }

  Future<void> _deleteAll(BuildContext context) async {
    final ok = await confirm(
      context,
      'すべての記録を削除',
      '記録をすべて削除します。元に戻せません。先に CSV を書き出しておくことをおすすめします。',
      ok: 'すべて削除',
      destructive: true,
    );
    if (ok && context.mounted) {
      await AppScope.of(context).db.deleteAll();
      if (context.mounted) toast(context, '削除しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          children: [
            const _Header('お金の管理'),
            ListTile(
              leading: const Icon(Icons.savings_outlined),
              title: const Text('予算上限'),
              subtitle: Text(
                [
                  '1日 ${s.budgetDay == 0 ? 'なし' : yen(s.budgetDay)}',
                  '1週間 ${s.budgetWeek == 0 ? 'なし' : yen(s.budgetWeek)}',
                  '1か月 ${s.budgetMonth == 0 ? 'なし' : yen(s.budgetMonth)}',
                ].join('  '),
              ),
              onTap: () => _editBudgets(context),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('1点あたりの金額（初期値）'),
              trailing: StakeStepper(
                value: s.defaultUnit,
                onChanged: s.setDefaultUnit,
              ),
            ),
            const BackupSection(),
            const _Header('データ'),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('CSV に書き出す'),
              subtitle: const Text('表計算ソフトで見るときに使えます'),
              onTap: () => _export(context),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('CSV を読み込む'),
              subtitle: const Text('このアプリで書き出した CSV を追加します'),
              onTap: () => _import(context),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('すべての記録を削除'),
              onTap: () => _deleteAll(context),
            ),
            const _Header('ご利用にあたって'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('20歳未満の方は馬券を購入できません'),
              subtitle: Text(
                'このアプリは記録と計算の道具です。馬券の販売や投票の代行は行いません。計算結果は参考値で、的中や利益を約束するものではありません。',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.support_agent),
              title: Text('のめり込みが心配なときは'),
              subtitle: Text(
                'ギャンブル等依存症の相談は、お住まいの都道府県・政令指定都市の精神保健福祉センターで受け付けています。',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('記録の保存先'),
              subtitle: Text('記録はこの端末の中にだけ保存し、外部には送信しません。'),
            ),
            const AboutListTile(
              icon: Icon(Icons.apps),
              applicationName: '馬券収支電卓',
              applicationVersion: '0.1.0（MVP）',
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
