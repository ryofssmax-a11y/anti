import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/expander.dart';
import '../../core/odds.dart';
import '../../core/selection.dart';
import '../../data/models.dart';
import '../common.dart';
import '../record_form_page.dart';
import 'calc_output.dart';

enum _Alloc {
  equal('均等払戻'),
  target('目標払戻'),
  weighted('傾斜配分');

  const _Alloc(this.label);
  final String label;
}

/// 買い目の一覧。オッズを入れると合成オッズ・トリガミ判定・資金配分を出す。
class CalcResultPage extends StatefulWidget {
  const CalcResultPage({
    super.key,
    required this.selection,
    required this.unitStake,
    this.pickMode = false,
  });

  final Selection selection;
  final int unitStake;
  final bool pickMode;

  @override
  State<CalcResultPage> createState() => _CalcResultPageState();
}

class _CalcResultPageState extends State<CalcResultPage> {
  late final List<Combination> _combos = expand(widget.selection);
  late final List<int> _stakes = List.filled(_combos.length, widget.unitStake);
  late final List<int?> _odds = List.filled(_combos.length, null);
  late final List<bool> _active = List.filled(_combos.length, true);
  late final List<int> _weights = List.filled(_combos.length, 1);
  _Alloc _mode = _Alloc.equal;
  late int _amount = (_combos.length * widget.unitStake).clamp(100, 1 << 31);

  List<int> get _activeIdx => [
    for (var i = 0; i < _combos.length; i++)
      if (_active[i]) i,
  ];

  int get _total => _activeIdx.fold(0, (s, i) => s + _stakes[i]);

  bool get _allOdds =>
      _activeIdx.isNotEmpty && _activeIdx.every((i) => _odds[i] != null);

  String _label(int i) => formatCombination(widget.selection.type, _combos[i]);

  Future<void> _editOdds(int i) async {
    final controller = TextEditingController(
      text: _odds[i] == null ? '' : (_odds[i]! / 10).toStringAsFixed(1),
    );
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_label(i)} のオッズ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: '倍',
            helperText:
                widget.selection.type.name == 'place' ||
                    widget.selection.type.name == 'wide'
                ? '幅がある場合は下限を入れてください'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (v != null && v >= 1.0) setState(() => _odds[i] = (v * 10).round());
  }

  Future<void> _editStake(int i) async {
    final controller = TextEditingController(text: '${_stakes[i]}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_label(i)} の金額'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            suffixText: '円',
            helperText: '100円単位',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (v != null && v >= 0) setState(() => _stakes[i] = floorToUnit(v));
  }

  void _allocate() {
    final idx = _activeIdx;
    if (_mode != _Alloc.weighted && !_allOdds) {
      toast(context, 'すべての買い目にオッズを入れてください');
      return;
    }
    final odds = [for (final i in idx) _odds[i]! / 10];
    final stakes = switch (_mode) {
      _Alloc.equal => allocateEqualPayout(_amount, odds),
      _Alloc.target => allocateTargetPayout(_amount, odds),
      _Alloc.weighted => allocateWeighted(_amount, [
        for (final i in idx) _weights[i],
      ]),
    };
    final short = stakes.where((s) => s == 0).length;
    setState(() {
      for (var k = 0; k < idx.length; k++) {
        _stakes[idx[k]] = stakes[k];
      }
    });
    if (short > 0) {
      toast(context, '予算不足で$short点が0円になりました。買い目を外すか予算を増やしてください');
    }
  }

  List<TicketLine> _lines() => [
    for (final i in _activeIdx)
      if (_stakes[i] > 0)
        TicketLine(combo: _combos[i].key, stake: _stakes[i], oddsX10: _odds[i]),
  ];

  void _copy() {
    final s = widget.selection;
    final head =
        '${s.type.label}${s.type.isSingle ? '' : ' ${s.method.label}'}';
    final body = [
      for (final i in _activeIdx)
        if (_stakes[i] > 0) '${_label(i)}  ${yen(_stakes[i])}',
    ].join('\n');
    Clipboard.setData(ClipboardData(text: '$head\n$body\n合計 ${yen(_total)}'));
    toast(context, '買い目をコピーしました');
  }

  Future<void> _submit() async {
    final out = CalcOutput(selection: widget.selection, lines: _lines());
    if (out.lines.isEmpty) {
      toast(context, '金額が入った買い目がありません');
      return;
    }
    if (widget.pickMode) {
      Navigator.pop(context, out);
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RecordFormPage(prefill: out)),
    );
    if (saved == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = _total;
    final synth = _allOdds
        ? syntheticOdds([for (final i in _activeIdx) _odds[i]! / 10])
        : null;
    final pays = [
      for (final i in _activeIdx)
        if (_odds[i] != null && _stakes[i] > 0)
          expectedPayout(_stakes[i], _odds[i]! / 10),
    ];
    final torigami = {
      for (final i in _activeIdx)
        if (_odds[i] != null && isTorigami(_stakes[i], _odds[i]! / 10, total))
          i,
    };
    final s = widget.selection;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${s.type.label}${s.type.isSingle ? '' : ' ${s.method.label}'}',
        ),
        actions: [
          IconButton(
            tooltip: 'コピー',
            icon: const Icon(Icons.copy),
            onPressed: _copy,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _combos.length + 1,
        itemBuilder: (context, index) {
          if (index > 0) {
            final i = index - 1;
            return _LineTile(
              label: _label(i),
              stake: _stakes[i],
              odds: _odds[i],
              active: _active[i],
              torigami: torigami.contains(i),
              weight: _mode == _Alloc.weighted ? _weights[i] : null,
              onToggle: (v) => setState(() => _active[i] = v),
              onOdds: () => _editOdds(i),
              onStake: () => _editStake(i),
              onWeight: () => setState(() => _weights[i] = _weights[i] % 5 + 1),
            );
          }
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          StatTile(label: '点数', value: '${_activeIdx.length}点'),
                          StatTile(label: '合計金額', value: yen(total)),
                          StatTile(
                            label: '合成オッズ',
                            value: synth == null
                                ? '―'
                                : '${synth.toStringAsFixed(2)}倍',
                            color: synth != null && synth < 1
                                ? scheme.error
                                : null,
                          ),
                          if (pays.isNotEmpty)
                            StatTile(
                              label: '払戻見込み',
                              value:
                                  pays.reduce((a, b) => a < b ? a : b) ==
                                      pays.reduce((a, b) => a > b ? a : b)
                                  ? yen(pays.first)
                                  : '${yen(pays.reduce((a, b) => a < b ? a : b))}〜${yen(pays.reduce((a, b) => a > b ? a : b))}',
                            ),
                        ],
                      ),
                      if (synth != null && synth < 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '合成オッズが1倍未満です。どれが当たっても損をします。',
                            style: t.bodyMedium?.copyWith(color: scheme.error),
                          ),
                        ),
                      if (torigami.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'トリガミ（当たっても合計金額を下回る）: ${torigami.length}点',
                            style: t.bodyMedium?.copyWith(color: scheme.error),
                          ),
                        ),
                      if (!_allOdds)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '各買い目のオッズをタップして入力すると、合成オッズとトリガミ判定を出します。',
                            style: t.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('資金配分', style: t.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<_Alloc>(
                        showSelectedIcon: false,
                        segments: [
                          for (final m in _Alloc.values)
                            ButtonSegment(value: m, label: Text(m.label)),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (v) =>
                            setState(() => _mode = v.first),
                      ),
                      const SizedBox(height: 8),
                      Text(switch (_mode) {
                        _Alloc.equal => 'どれが当たっても払戻がほぼ同じになるよう、予算を配分します。',
                        _Alloc.target => 'どれが当たっても目標額以上戻るよう、必要な金額を出します。',
                        _Alloc.weighted => '各買い目の重み（右の数字）に比例して予算を分けます。',
                      }, style: t.bodySmall),
                      Row(
                        children: [
                          Text(_mode == _Alloc.target ? '目標払戻' : '予算'),
                          StakeStepper(
                            value: _amount,
                            label: _mode == _Alloc.target ? '目標払戻' : '予算',
                            onChanged: (v) => setState(() => _amount = v),
                          ),
                          const Spacer(),
                          FilledButton.tonal(
                            onPressed: _allocate,
                            child: const Text('配分する'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: _submit,
            icon: Icon(widget.pickMode ? Icons.check : Icons.edit_note),
            label: Text(
              widget.pickMode
                  ? 'この買い目を使う（${yen(total)}）'
                  : 'この買い目を記録（${yen(total)}）',
            ),
          ),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.label,
    required this.stake,
    required this.odds,
    required this.active,
    required this.torigami,
    required this.weight,
    required this.onToggle,
    required this.onOdds,
    required this.onStake,
    required this.onWeight,
  });

  final String label;
  final int stake;
  final int? odds;
  final bool active;
  final bool torigami;
  final int? weight;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOdds;
  final VoidCallback onStake;
  final VoidCallback onWeight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = active ? null : scheme.onSurface.withValues(alpha: 0.38);
    return ListTile(
      dense: true,
      leading: Checkbox(value: active, onChanged: (v) => onToggle(v ?? true)),
      title: Text(label, style: t.titleMedium?.copyWith(color: muted)),
      subtitle: odds == null
          ? null
          : Text(
              '払戻見込み ${yen(expectedPayout(stake, odds! / 10))}${torigami ? '  トリガミ' : ''}',
              style: TextStyle(color: torigami ? scheme.error : muted),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: active ? onOdds : null,
            child: Text(
              odds == null ? 'オッズ' : '${(odds! / 10).toStringAsFixed(1)}倍',
            ),
          ),
          TextButton(
            onPressed: active ? onStake : null,
            child: Text(yen(stake)),
          ),
          if (weight != null)
            IconButton(
              tooltip: '重み（タップで1〜5）',
              onPressed: active ? onWeight : null,
              icon: CircleAvatar(
                radius: 12,
                child: Text('$weight', style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}
