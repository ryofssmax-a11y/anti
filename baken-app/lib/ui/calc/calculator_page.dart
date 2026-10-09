import 'package:flutter/material.dart';

import '../../core/bet_type.dart';
import '../../core/expander.dart';
import '../../core/selection.dart';
import '../../data/settings.dart';
import '../common.dart';
import 'calc_output.dart';
import 'calc_result_page.dart';
import 'number_grid.dart';

/// 買い目計算。
///
/// [pickMode] のときは記録画面から呼ばれ、決めた買い目を [CalcOutput] で返す。
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({
    super.key,
    this.pickMode = false,
    this.initial,
    this.fieldSize,
  });

  final bool pickMode;
  final Selection? initial;
  final int? fieldSize;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  late Selection _sel;
  int? _unit;

  @override
  void initState() {
    super.initState();
    _sel =
        widget.initial ??
        Selection(
          type: BetType.quinella,
          method: BetMethod.box,
          fieldSize: widget.fieldSize ?? 18,
        );
  }

  int get unit => _unit ?? AppScope.of(context).settings.defaultUnit;

  void _reset({
    BetType? type,
    BetMethod? method,
    int? axisCount,
    AxisMode? axisMode,
  }) {
    final t = type ?? _sel.type;
    var m = method ?? _sel.method;
    if (!t.methods.contains(m)) m = t.methods.first;
    var ac = axisCount ?? _sel.axisCount;
    if (!axisCountsFor(t).contains(ac)) ac = 1;
    var am = axisMode ?? _sel.axisMode;
    final modes = axisModesFor(t, ac);
    if (!modes.contains(am)) am = modes.first;
    setState(() {
      _sel = Selection(
        type: t,
        method: m,
        fieldSize: _sel.fieldSize,
        axisCount: ac,
        axisMode: am,
        scratched: _sel.scratched,
      );
    });
  }

  void _toggle(int column, int n) {
    final cols = _sel.columns.map((c) => {...c}).toList();
    final col = cols[column];
    if (col.contains(n)) {
      col.remove(n);
    } else {
      if (_sel.isSingleSelectColumn(column)) col.clear();
      col.add(n);
    }
    setState(() => _sel = _sel.copyWith(columns: cols));
  }

  void _setFieldSize(int n) {
    final cols = _sel.columns
        .map((c) => c.where((x) => x <= n).toSet())
        .toList();
    final max = _sel.copyWith(fieldSize: n).maxNumber;
    setState(
      () => _sel = _sel.copyWith(
        fieldSize: n,
        columns: cols.map((c) => c.where((x) => x <= max).toSet()).toList(),
        scratched: _sel.scratched.where((x) => x <= n).toSet(),
      ),
    );
  }

  Future<void> _next(List<dynamic> combos) async {
    final out = await Navigator.push<CalcOutput>(
      context,
      MaterialPageRoute(
        builder: (_) => CalcResultPage(
          selection: _sel,
          unitStake: unit,
          pickMode: widget.pickMode,
        ),
      ),
    );
    if (out != null && mounted && widget.pickMode) Navigator.pop(context, out);
  }

  Future<void> _saveTemplate() async {
    final settings = AppScope.of(context).settings;
    final controller = TextEditingController(
      text: '${_sel.type.label} ${_sel.type.isSingle ? '' : _sel.method.label}'
          .trim(),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('テンプレートとして保存'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名前'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await settings.saveTemplates([
      ...settings.templates,
      BetTemplate(name, _sel, unit),
    ]);
    if (mounted) toast(context, '「$name」を保存しました');
  }

  Future<void> _loadTemplate() async {
    final settings = AppScope.of(context).settings;
    final picked = await showModalBottomSheet<BetTemplate>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: settings,
        builder: (ctx, _) {
          final list = settings.templates;
          if (list.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('保存したテンプレートはありません。右上のメニューから今の選択を保存できます。'),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < list.length; i++)
                ListTile(
                  title: Text(list[i].name),
                  subtitle: Text(
                    '${expand(list[i].selection).length}点 × ${yen(list[i].unitStake)}',
                  ),
                  onTap: () => Navigator.pop(ctx, list[i]),
                  trailing: IconButton(
                    tooltip: '削除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        settings.saveTemplates([...list]..removeAt(i)),
                  ),
                ),
            ],
          );
        },
      ),
    );
    if (picked != null) {
      setState(() {
        _sel = picked.selection;
        _unit = picked.unitStake;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final combos = expand(_sel);
    final total = combos.length * unit;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final labels = _sel.columnLabels;
    final showScratch = !_sel.type.usesFrames && _sel.type != BetType.win5;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? '買い目を入力' : '買い目計算'),
        actions: [
          IconButton(
            tooltip: '選択をクリア',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _reset(),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'save' ? _saveTemplate() : _loadTemplate(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'load', child: Text('テンプレートを読み込む')),
              PopupMenuItem(value: 'save', child: Text('テンプレートとして保存')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final bt in BetType.values)
                ChoiceChip(
                  label: Text(bt.label),
                  selected: _sel.type == bt,
                  onSelected: (_) => _reset(type: bt),
                ),
            ],
          ),
          if (_sel.type.methods.length > 1) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<BetMethod>(
                showSelectedIcon: false,
                segments: [
                  for (final m in _sel.type.methods)
                    ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {_sel.method},
                onSelectionChanged: (s) => _reset(method: s.first),
              ),
            ),
          ],
          if (_sel.method == BetMethod.nagashi) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (axisCountsFor(_sel.type).length > 1)
                  for (final c in axisCountsFor(_sel.type))
                    ChoiceChip(
                      label: Text('軸$c頭'),
                      selected: _sel.axisCount == c,
                      onSelected: (_) => _reset(axisCount: c),
                    ),
                if (axisModesFor(_sel.type, _sel.axisCount).length > 1)
                  for (final m in axisModesFor(_sel.type, _sel.axisCount))
                    ChoiceChip(
                      label: Text(m.label),
                      selected: _sel.axisMode == m,
                      onSelected: (_) => _reset(axisMode: m),
                    ),
              ],
            ),
          ],
          if (_sel.type != BetType.win5) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('出走頭数', style: t.bodyLarge),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _sel.fieldSize,
                  items: [
                    for (var n = 2; n <= 18; n++)
                      DropdownMenuItem(value: n, child: Text('$n頭')),
                  ],
                  onChanged: (n) => n == null ? null : _setFieldSize(n),
                ),
              ],
            ),
          ],
          for (var i = 0; i < _sel.columns.length; i++) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(labels[i], style: t.titleSmall),
                const SizedBox(width: 8),
                if (_sel.isSingleSelectColumn(i))
                  Text(
                    '1頭',
                    style: t.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                if (!_sel.isSingleSelectColumn(i))
                  TextButton(
                    onPressed: () {
                      final cols = _sel.columns.map((c) => {...c}).toList();
                      final all = {for (var n = 1; n <= _sel.maxNumber; n++) n}
                        ..removeAll(showScratch ? _sel.scratched : <int>{});
                      cols[i] = cols[i].length == all.length ? <int>{} : all;
                      setState(() => _sel = _sel.copyWith(columns: cols));
                    },
                    child: const Text('全選択'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            NumberGrid(
              max: _sel.maxNumber,
              selected: _sel.columns[i],
              single: _sel.isSingleSelectColumn(i),
              disabled: showScratch ? _sel.scratched : const {},
              onToggle: (n) => _toggle(i, n),
            ),
          ],
          if (_sel.type.usesFrames)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '枠連はボックスにゾロ目を含めません。ゾロ目はその枠に2頭以上いるときだけ有効です。',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (showScratch) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('取消・除外の馬（${_sel.scratched.length}頭）'),
              subtitle: const Text('選んだ馬を含む買い目を除きます'),
              children: [
                NumberGrid(
                  max: _sel.fieldSize,
                  selected: _sel.scratched,
                  onToggle: (n) {
                    final s = {..._sel.scratched};
                    s.contains(n) ? s.remove(n) : s.add(n);
                    setState(() => _sel = _sel.copyWith(scratched: s));
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 3,
          color: scheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${combos.length}点  合計 ${yen(total)}',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          Text('1点', style: t.bodySmall),
                          StakeStepper(
                            value: unit,
                            label: '1点あたりの金額',
                            onChanged: (v) => setState(() => _unit = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: combos.isEmpty ? null : () => _next(combos),
                  child: const Text('次へ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
