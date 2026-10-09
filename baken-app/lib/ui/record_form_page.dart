import 'package:flutter/material.dart';

import '../core/bet_type.dart';
import '../core/expander.dart';
import '../core/selection.dart';
import '../data/models.dart';
import '../data/race_names.dart';
import 'budget.dart';
import 'calc/calc_output.dart';
import 'calc/calculator_page.dart';
import 'common.dart';
import 'record_inputs.dart';

/// 詳細記録。レースと買い目を入れて保存する。
class RecordFormPage extends StatefulWidget {
  const RecordFormPage({super.key, this.prefill, this.race});

  /// 計算画面から渡された買い目
  final CalcOutput? prefill;

  /// 同じレースに馬券を追加するとき
  final Race? race;

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  late DateTime _date = widget.race == null
      ? today()
      : DateTime.parse(widget.race!.date);
  String _venue = jraVenues[4];
  late int _raceNo = widget.race?.raceNo ?? 11;
  late String? _name = widget.race?.name;
  late String? _surface = widget.race?.surface;
  late int? _distance = widget.race?.distance;
  late int _fieldSize =
      widget.prefill?.selection.fieldSize ?? widget.race?.fieldSize ?? 18;
  Channel _channel = Channel.online;
  final _tags = TextEditingController();
  final _memo = TextEditingController();
  late CalcOutput? _bets = widget.prefill;
  bool _saving = false;
  bool _autoFilled = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (widget.race != null) {
      _venue = widget.race!.venue;
    } else {
      final s = AppScope.of(context).settings;
      _venue = s.lastVenue ?? _venue;
      _channel = Channel.fromName(s.lastChannel);
    }
  }

  @override
  void dispose() {
    _tags.dispose();
    _memo.dispose();
    super.dispose();
  }

  void _onRaceName(String? name) {
    final p = presetByName(name);
    setState(() {
      _name = name;
      _autoFilled = false;
      if (p == null) return;
      if (p.venue != null) _venue = p.venue!;
      if (p.surface != null) _surface = p.surface;
      if (p.distance != null) _distance = p.distance;
      if (p.grade.isGraded && p.grade.index <= RaceGrade.g3.index) _raceNo = 11;
      _autoFilled = p.venue != null || p.surface != null;
    });
  }

  Future<void> _pickBets() async {
    final out = await Navigator.push<CalcOutput>(
      context,
      MaterialPageRoute(
        builder: (_) => CalculatorPage(
          pickMode: true,
          initial: _bets?.selection,
          fieldSize: _fieldSize,
        ),
      ),
    );
    if (out != null) {
      setState(() {
        _bets = out;
        _fieldSize = out.selection.fieldSize;
      });
    }
  }

  Future<void> _save() async {
    final bets = _bets;
    if (bets == null || bets.lines.isEmpty) {
      toast(context, '買い目を入力してください');
      return;
    }
    setState(() => _saving = true);
    final scope = AppScope.of(context);
    final date = isoDate(_date);
    final sel = bets.selection;
    final race = Race(
      date: date,
      venue: _venue,
      raceNo: _raceNo,
      name: _name,
      surface: _surface,
      distance: _distance,
      fieldSize: sel.type == BetType.win5 ? _fieldSize : sel.fieldSize,
    );
    final ticket = Ticket(
      date: date,
      venue: _venue,
      raceNo: _raceNo,
      raceName: race.name,
      type: sel.type,
      method: sel.type.isSingle ? BetMethod.normal : sel.method,
      channel: _channel,
      selection: sel,
      stakeTotal: bets.total,
      tags: _tags.text.trim(),
      memo: _memo.text.trim(),
      lines: bets.lines,
    );
    await scope.db.insertTicket(ticket, race: race);
    await scope.settings.rememberRecordInput(
      venue: _venue,
      channel: _channel.name,
    );
    if (!mounted) return;
    await checkBudget(context, date);
    if (!mounted) return;
    toast(context, '記録しました');
    Navigator.pop(context, true);
  }

  Future<void> _editDistance() async {
    final controller = TextEditingController(text: _distance?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('距離'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (v != null) setState(() => _distance = int.tryParse(v));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final bets = _bets;
    final fixed = widget.race != null;
    return Scaffold(
      appBar: AppBar(title: Text(fixed ? '馬券を追加' : '馬券を記録')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          RaceNameField(name: _name, onPicked: _onRaceName, enabled: !fixed),
          if (_autoFilled)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                '競馬場・コース・距離を入れました。年によって違う場合は下で変えてください。',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const FieldLabel('日付'),
          DateChooser(
            date: _date,
            onChanged: (d) => setState(() => _date = d),
            enabled: !fixed,
          ),
          const FieldLabel('競馬場'),
          VenueChooser(
            venue: _venue,
            onChanged: (v) => setState(() => _venue = v),
            enabled: !fixed,
          ),
          const FieldLabel('レース番号'),
          RaceNoChooser(
            raceNo: _raceNo,
            onChanged: (n) => setState(() => _raceNo = n),
            enabled: !fixed,
          ),
          const FieldLabel('コース'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in surfaces)
                ChoiceChip(
                  label: Text(s),
                  selected: _surface == s,
                  onSelected: (on) => setState(() => _surface = on ? s : null),
                ),
              ActionChip(
                avatar: const Icon(Icons.straighten, size: 18),
                label: Text(_distance == null ? '距離' : '${_distance}m'),
                onPressed: _editDistance,
              ),
            ],
          ),
          const FieldLabel('買い目'),
          if (bets == null)
            FilledButton.tonalIcon(
              onPressed: _pickBets,
              icon: const Icon(Icons.calculate),
              label: const Text('買い目を入力'),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                title: Text(
                  '${bets.selection.type.label}${bets.selection.type.isSingle ? '' : ' ${bets.selection.method.label}'}'
                  '  ${bets.lines.length}点',
                ),
                subtitle: Text(
                  '${bets.lines.take(6).map((l) => formatCombination(bets.selection.type, Combination.parse(l.combo, ordered: bets.selection.type.ordered))).join('、')}'
                  '${bets.lines.length > 6 ? ' ほか' : ''}\n合計 ${yen(bets.total)}',
                ),
                isThreeLine: true,
                trailing: TextButton(
                  onPressed: _pickBets,
                  child: const Text('変更'),
                ),
              ),
            ),
          const FieldLabel('購入方法'),
          SegmentedButton<Channel>(
            showSelectedIcon: false,
            segments: [
              for (final c in Channel.values)
                ButtonSegment(value: c, label: Text(c.label)),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => setState(() => _channel = s.first),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('タグ・メモ（任意）'),
            children: [
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'タグ（カンマ区切り）',
                  hintText: '例: 本命勝負, 穴狙い',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memo,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'メモ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(bets == null ? '保存' : '保存（${yen(bets.total)}）'),
          ),
        ),
      ),
    );
  }
}

/// 簡易記録。投資額と払戻額だけを入れる。
class SimpleRecordPage extends StatefulWidget {
  const SimpleRecordPage({super.key});

  @override
  State<SimpleRecordPage> createState() => _SimpleRecordPageState();
}

class _SimpleRecordPageState extends State<SimpleRecordPage> {
  DateTime _date = today();
  String _venue = jraVenues[4];
  String? _name;
  final _stake = TextEditingController();
  final _payout = TextEditingController(text: '0');
  final _memo = TextEditingController();
  final _tags = TextEditingController();
  Channel _channel = Channel.online;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final s = AppScope.of(context).settings;
    _venue = s.lastVenue ?? _venue;
    _channel = Channel.fromName(s.lastChannel);
  }

  @override
  void dispose() {
    _stake.dispose();
    _payout.dispose();
    _memo.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final stake = int.tryParse(_stake.text.replaceAll(',', ''));
    final payout = int.tryParse(_payout.text.replaceAll(',', '')) ?? 0;
    if (stake == null || stake <= 0) {
      toast(context, '投資額を入力してください');
      return;
    }
    final scope = AppScope.of(context);
    final date = isoDate(_date);
    await scope.db.insertTicket(
      Ticket(
        date: date,
        venue: _venue,
        raceName: _name,
        channel: _channel,
        stakeTotal: stake,
        payoutTotal: payout,
        settled: true,
        simple: true,
        memo: _memo.text.trim(),
        tags: _tags.text.trim(),
      ),
    );
    await scope.settings.rememberRecordInput(
      venue: _venue,
      channel: _channel.name,
    );
    if (!mounted) return;
    await checkBudget(context, date);
    if (!mounted) return;
    toast(context, '記録しました');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('簡易記録')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text('買い目が分からない過去分や、1日分をまとめて入れたいときに使います。'),
          const SizedBox(height: 12),
          RaceNameField(
            name: _name,
            onPicked: (n) => setState(() {
              _name = n;
              final v = presetByName(n)?.venue;
              if (v != null) _venue = v;
            }),
          ),
          const FieldLabel('日付'),
          DateChooser(date: _date, onChanged: (d) => setState(() => _date = d)),
          const FieldLabel('競馬場'),
          VenueChooser(
            venue: _venue,
            onChanged: (v) => setState(() => _venue = v),
          ),
          const FieldLabel('金額'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stake,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '投資額',
                    suffixText: '円',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _payout,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '払戻額',
                    suffixText: '円',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const FieldLabel('購入方法'),
          SegmentedButton<Channel>(
            showSelectedIcon: false,
            segments: [
              for (final c in Channel.values)
                ButtonSegment(value: c, label: Text(c.label)),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => setState(() => _channel = s.first),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('タグ・メモ（任意）'),
            children: [
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'タグ（カンマ区切り）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memo,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'メモ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(onPressed: _save, child: const Text('保存')),
        ),
      ),
    );
  }
}
