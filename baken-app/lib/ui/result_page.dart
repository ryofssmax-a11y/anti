import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bet_type.dart';
import '../core/expander.dart';
import '../core/judge.dart';
import '../core/payout_parser.dart';
import '../core/selection.dart';
import '../data/models.dart';
import 'calc/number_grid.dart';
import 'common.dart';

/// レース結果の入力。着順を入れると、そのレースの全買い目を一括で判定する。
class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.race});

  final Race race;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  late int _fieldSize = widget.race.outcome?.fieldSize ?? widget.race.fieldSize;
  late final Map<int, Set<int>> _ranks = {
    for (var r = 1; r <= 3; r++) r: {...?widget.race.outcome?.placings[r]},
  };
  late final Set<int> _scratched = {...?widget.race.outcome?.scratched};

  /// 判定後に出す払戻入力
  List<({BetType type, String combo})>? _hits;
  final Map<String, TextEditingController> _payouts = {};
  bool _saving = false;

  /// 貼り付けで読み取った払戻金（payoutKey → 100円あたり）
  final Map<String, int> _pasted = {};
  String? _pasteInfo;

  /// 記録時のオッズから仮に入れた払戻金のキー
  final Set<String> _fromOdds = {};

  @override
  void dispose() {
    for (final c in _payouts.values) {
      c.dispose();
    }
    super.dispose();
  }

  RaceOutcome get _outcome => RaceOutcome(
    fieldSize: _fieldSize,
    placings: {for (final e in _ranks.entries) e.key: e.value.toList()},
    scratched: _scratched,
  );

  void _toggleRank(int rank, int horse) {
    setState(() {
      _hits = null;
      final set = _ranks[rank]!;
      if (set.contains(horse)) {
        set.remove(horse);
      } else {
        for (final other in _ranks.values) {
          other.remove(horse);
        }
        set.add(horse);
      }
    });
  }

  Future<void> _judge() async {
    if (_ranks[1]!.isEmpty) {
      toast(context, '1着の馬を選んでください');
      return;
    }
    final db = AppScope.of(context).db;
    final hits = await db.hitsNeedingPayout(widget.race.id!, _outcome);
    final saved = await db.payoutsFor(widget.race.id!);
    // 記録時にオッズを入れていれば、払戻金の目安にする
    final odds = <String, int>{};
    for (final t in await db.ticketsForRace(widget.race.id!)) {
      final type = t.type;
      if (type == null) continue;
      for (final l in t.lines) {
        if (l.oddsX10 != null) odds[payoutKey(type, l.combo)] = l.oddsX10! * 10;
      }
    }
    if (!mounted) return;
    for (final h in hits) {
      final key = payoutKey(h.type, h.combo);
      final c = _payouts.putIfAbsent(key, TextEditingController.new);
      if (c.text.isNotEmpty) continue;
      final v = saved[key] ?? _pasted[key];
      if (v != null) {
        c.text = '$v';
      } else if (odds[key] != null) {
        c.text = '${odds[key]}';
        _fromOdds.add(key);
      }
    }
    setState(() => _hits = hits);
  }

  Future<void> _paste() async {
    final controller = TextEditingController();
    // ブラウザ版はクリップボードを読めないので、入力欄に貼り付けてもらう
    if (!kIsWeb) {
      try {
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        if (clip?.text != null && parsePayoutText(clip!.text!).count > 0) {
          controller.text = clip.text!;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('払戻金の表を貼り付け'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('JRA や競馬サイトのレース結果ページで、払戻金の表をコピーして貼り付けてください。'),
                const PayoutTableHelp(),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  minLines: 5,
                  decoration: const InputDecoration(
                    hintText:
                        '単勝 7 1,250円\n馬連 3-7 1,640円\n3連単 7-3-12 38,450円 …',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                if (!kIsWeb)
                  TextButton.icon(
                    icon: const Icon(Icons.content_paste),
                    label: const Text('コピーした文字を貼り付け'),
                    onPressed: () async {
                      final d = await Clipboard.getData(Clipboard.kTextPlain);
                      if (d?.text != null) controller.text = d!.text!;
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('読み取る'),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    final parsed = parsePayoutText(text);
    if (parsed.isEmpty) {
      toast(context, '払戻金を読み取れませんでした。表の部分をコピーしてください');
      return;
    }
    var placed = false;
    setState(() {
      _pasted.clear();
      parsed.payouts.forEach((type, m) {
        m.forEach((combo, v) => _pasted[payoutKey(type, combo)] = v);
      });
      for (final e in _pasted.entries) {
        final c = _payouts[e.key];
        if (c != null) {
          c.text = '${e.value}';
          _fromOdds.remove(e.key);
        }
      }
      final p = parsed.placings;
      final noRanks = _ranks.values.every((r) => r.isEmpty);
      if (p != null &&
          noRanks &&
          p.values.every((h) => h.every((n) => n <= _fieldSize))) {
        for (final e in p.entries) {
          _ranks[e.key] = {...e.value};
        }
        placed = true;
      }
      _pasteInfo =
          '${parsed.payouts.length}券種・${parsed.count}件の払戻金を読み取りました'
          '${placed ? '。3連単から着順も入れました' : ''}';
      _hits = null;
    });
    if (placed || _ranks[1]!.isNotEmpty) await _judge();
  }

  Future<void> _save() async {
    final hits = _hits ?? const [];
    // 読み取った払戻金はすべて保存しておく（あとで馬券を足したときに使える）
    final payouts = <String, int>{..._pasted};
    for (final h in hits) {
      final key = payoutKey(h.type, h.combo);
      final v = int.tryParse(_payouts[key]!.text.replaceAll(',', ''));
      if (v == null || v < 100) {
        toast(context, '${h.type.label} ${h.combo} の払戻金（100円あたり）を入れてください');
        return;
      }
      payouts[key] = v;
    }
    setState(() => _saving = true);
    await AppScope.of(context).db
        .settleRace(widget.race.id!, _outcome, payouts);
    if (!mounted) return;
    toast(context, '結果を保存し、買い目を判定しました');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hits = _hits;
    return Scaffold(
      appBar: AppBar(title: Text('結果入力  ${widget.race.title}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.tonalIcon(
            onPressed: _paste,
            icon: const Icon(Icons.content_paste_go),
            label: const Text('払戻金の表を貼り付けて読み取る'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              _pasteInfo ?? '結果ページの払戻金をコピーして貼り付けると、払戻金（と3連単から着順）をまとめて入れます。',
              style: t.bodySmall?.copyWith(
                color: _pasteInfo == null
                    ? scheme.onSurfaceVariant
                    : scheme.primary,
              ),
            ),
          ),
          Row(
            children: [
              Text('出走頭数', style: t.bodyLarge),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _fieldSize,
                items: [
                  for (var n = 2; n <= 18; n++)
                    DropdownMenuItem(value: n, child: Text('$n頭')),
                ],
                onChanged: (n) => setState(() {
                  _hits = null;
                  _fieldSize = n ?? _fieldSize;
                  for (final s in _ranks.values) {
                    s.removeWhere((h) => h > _fieldSize);
                  }
                  _scratched.removeWhere((h) => h > _fieldSize);
                }),
              ),
            ],
          ),
          Text(
            '同着のときは、同じ着順に複数の馬を選んでください。',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          for (var r = 1; r <= 3; r++) ...[
            const SizedBox(height: 16),
            Text('$r着', style: t.titleSmall),
            const SizedBox(height: 4),
            NumberGrid(
              max: _fieldSize,
              selected: _ranks[r]!,
              disabled: _scratched,
              onToggle: (h) => _toggleRank(r, h),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('取消・除外の馬（${_scratched.length}頭）'),
            subtitle: const Text('この馬を含む買い目は返還になります'),
            children: [
              NumberGrid(
                max: _fieldSize,
                selected: _scratched,
                onToggle: (h) => setState(() {
                  _hits = null;
                  if (!_scratched.remove(h)) {
                    _scratched.add(h);
                    for (final s in _ranks.values) {
                      s.remove(h);
                    }
                  }
                }),
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 16),
          if (hits == null)
            FilledButton(onPressed: _judge, child: const Text('判定する'))
          else ...[
            Text('払戻金（100円あたり）', style: t.titleSmall),
            const SizedBox(height: 4),
            if (hits.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('このレースの買い目に的中はありません。'),
              ),
            for (final h in hits)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _payouts[payoutKey(h.type, h.combo)],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        '${h.type.label} ${formatCombination(h.type, Combination.parse(h.combo, ordered: h.type.ordered))}',
                    suffixText: '円',
                    helperText: _fromOdds.contains(payoutKey(h.type, h.combo))
                        ? '記録時のオッズから計算。確定の払戻金と違えば直してください'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) =>
                      _fromOdds.remove(payoutKey(h.type, h.combo)),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('保存して確定'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 「払戻金の表」の説明（貼り付け画面で開いて読む）
class PayoutTableHelp extends StatelessWidget {
  const PayoutTableHelp({super.key});

  static const _rows = [
    ('単勝', '7', '1,250円'),
    ('複勝', '7 / 3 / 12', '280円 / 150円 / 330円'),
    ('枠連', '2-4', '1,020円'),
    ('馬連', '3-7', '1,640円'),
    ('ワイド', '3-7 / 7-12 / 3-12', '560円 / 1,230円 / 980円'),
    ('馬単', '7-3', '3,980円'),
    ('3連複', '3-7-12', '5,670円'),
    ('3連単', '7-3-12', '38,450円'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final small = t.bodySmall;
    final muted = small?.copyWith(color: scheme.onSurfaceVariant);
    Widget cell(String s, {bool head = false, TextAlign? align}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        s,
        textAlign: align,
        style: head ? small?.copyWith(fontWeight: FontWeight.w600) : small,
      ),
    );
    Widget heading(String s) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(s, style: t.labelLarge),
    );
    Widget bullet(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('・', style: small),
          Expanded(child: Text(s, style: small)),
        ],
      ),
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: Icon(Icons.help_outline, color: scheme.primary),
        title: Text('貼り付ける「払戻金の表」とは？', style: t.bodyMedium),
        children: [
          Text(
            'レースが終わると、結果ページの下のほうに、券種ごとの当たり番号と'
            '払戻金（100円あたり）の一覧が載ります。たとえばこんな表です。',
            style: small,
          ),
          const SizedBox(height: 8),
          Table(
            border: TableBorder.all(color: scheme.outlineVariant),
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1.3),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                ),
                children: [
                  cell('券種', head: true),
                  cell('馬番', head: true),
                  cell('払戻金', head: true),
                ],
              ),
              for (final (type, combo, yen) in _rows)
                TableRow(
                  children: [
                    cell(type),
                    cell(combo),
                    cell(yen, align: TextAlign.right),
                  ],
                ),
            ],
          ),
          heading('使い方'),
          bullet('JRA のサイトや競馬サイトで、レース結果ページを開く'),
          bullet('払戻金の表の部分を長押しで選んでコピーする（表の外まで多めに選んでも大丈夫）'),
          bullet('下の欄に貼り付けて「読み取る」を押す'),
          const SizedBox(height: 4),
          Text(
            '当たった買い目の払戻金が入ります。3連単の組み合わせが1つだけのときは、'
            '1〜3着の着順も入ります（同着で2つあるときは入れません）。',
            style: small,
          ),
          heading('読み取れる書き方'),
          bullet('表でなくても「券種名 → 馬番 → 金額」の順なら読めます（例: 馬連 3-7 1,640円）'),
          bullet('全角の数字（７－３　１，６４０円）や「三連単」などの書き方も読めます'),
          bullet('地方競馬の枠単と WIN5 は読み飛ばします'),
          const SizedBox(height: 4),
          Text('「読み取れませんでした」と出たときは、表の部分だけを選び直してください。', style: muted),
        ],
      ),
    );
  }
}
