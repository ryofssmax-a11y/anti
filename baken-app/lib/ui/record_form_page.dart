import 'package:flutter/material.dart';

import '../core/bet_type.dart';
import '../core/expander.dart';
import '../core/selection.dart';
import '../data/models.dart';
import 'budget.dart';
import 'calc/calc_output.dart';
import 'calc/calculator_page.dart';
import 'common.dart';

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
  late String _venue = widget.race?.venue ?? jraVenues[5];
  late int _raceNo = widget.race?.raceNo ?? 11;
  late final _name = TextEditingController(text: widget.race?.name ?? '');
  late String? _surface = widget.race?.surface;
  late final _distance = TextEditingController(
    text: widget.race?.distance?.toString() ?? '',
  );
  late int _fieldSize =
      widget.prefill?.selection.fieldSize ?? widget.race?.fieldSize ?? 18;
  Channel _channel = Channel.online;
  final _tags = TextEditingController();
  final _memo = TextEditingController();
  late CalcOutput? _bets = widget.prefill;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _distance.dispose();
    _tags.dispose();
    _memo.dispose();
    super.dispose();
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
    final db = AppScope.of(context).db;
    final date = isoDate(_date);
    final sel = bets.selection;
    final race = Race(
      date: date,
      venue: _venue,
      raceNo: _raceNo,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      surface: _surface,
      distance: int.tryParse(_distance.text),
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
    await db.insertTicket(ticket, race: race);
    if (!mounted) return;
    await checkBudget(context, date);
    if (!mounted) return;
    toast(context, '記録しました');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bets = _bets;
    final fixedRace = widget.race != null;
    return Scaffold(
      appBar: AppBar(title: const Text('馬券を記録')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('レース', style: t.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(jpDate(isoDate(_date))),
                  onPressed: fixedRace
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) setState(() => _date = d);
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _venue,
                  decoration: const InputDecoration(
                    labelText: '競馬場',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final v in allVenues)
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: fixedRace
                      ? null
                      : (v) => setState(() => _venue = v ?? _venue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  initialValue: _raceNo,
                  decoration: const InputDecoration(
                    labelText: 'レース',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var n = 1; n <= 12; n++)
                      DropdownMenuItem(value: n, child: Text('${n}R')),
                  ],
                  onChanged: fixedRace
                      ? null
                      : (v) => setState(() => _raceNo = v ?? _raceNo),
                ),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('レースの詳細（任意）'),
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'レース名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _surface,
                      decoration: const InputDecoration(
                        labelText: '芝・ダート',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('未選択')),
                        for (final s in surfaces)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) => setState(() => _surface = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _distance,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '距離',
                        suffixText: 'm',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
          const SizedBox(height: 8),
          Text('買い目', style: t.titleSmall),
          const SizedBox(height: 8),
          if (bets == null)
            OutlinedButton.icon(
              onPressed: _pickBets,
              icon: const Icon(Icons.calculate),
              label: const Text('買い目を入力'),
            )
          else
            Card(
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
          const SizedBox(height: 16),
          Text('購入方法', style: t.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<Channel>(
            showSelectedIcon: false,
            segments: [
              for (final c in Channel.values)
                ButtonSegment(value: c, label: Text(c.label)),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => setState(() => _channel = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: 'タグ（カンマ区切り）',
              hintText: '例: 本命勝負, G1',
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
  String _venue = jraVenues[5];
  final _stake = TextEditingController();
  final _payout = TextEditingController(text: '0');
  final _memo = TextEditingController();
  final _tags = TextEditingController();
  Channel _channel = Channel.online;

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
    final date = isoDate(_date);
    await AppScope.of(context).db.insertTicket(
      Ticket(
        date: date,
        venue: _venue,
        channel: _channel,
        stakeTotal: stake,
        payoutTotal: payout,
        settled: true,
        simple: true,
        memo: _memo.text.trim(),
        tags: _tags.text.trim(),
      ),
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
        padding: const EdgeInsets.all(16),
        children: [
          const Text('買い目が分からない過去分や、まとめて入れたいときに使います。'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(jpDate(isoDate(_date))),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _venue,
            decoration: const InputDecoration(
              labelText: '競馬場',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final v in allVenues)
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: (v) => setState(() => _venue = v ?? _venue),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stake,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '投資額',
              suffixText: '円',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _payout,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '払戻額',
              suffixText: '円',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<Channel>(
            showSelectedIcon: false,
            segments: [
              for (final c in Channel.values)
                ButtonSegment(value: c, label: Text(c.label)),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => setState(() => _channel = s.first),
          ),
          const SizedBox(height: 16),
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
