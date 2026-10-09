import 'package:flutter/material.dart';

import '../core/bet_type.dart';
import '../core/expander.dart';
import '../core/judge.dart';
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
    if (!mounted) return;
    for (final h in hits) {
      final key = payoutKey(h.type, h.combo);
      _payouts.putIfAbsent(
        key,
        () => TextEditingController(text: saved[key]?.toString() ?? ''),
      );
    }
    setState(() => _hits = hits);
  }

  Future<void> _save() async {
    final hits = _hits ?? const [];
    final payouts = <String, int>{};
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
                    border: const OutlineInputBorder(),
                  ),
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
