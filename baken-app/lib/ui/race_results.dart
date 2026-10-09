import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/bet_type.dart';
import '../data/models.dart';
import '../data/race_names.dart';
import '../data/race_results.dart';
import '../platform/cloud.dart';
import 'common.dart';
import 'race_name_picker.dart';
import 'race_page.dart';
import 'record_inputs.dart';
import 'result_page.dart';
import 'week_races.dart';

const _medal = [Color(0xFFC9A227), Color(0xFF9EA4AA), Color(0xFFB0793F)];

/// 着順の馬番（丸）
class _HorseNo extends StatelessWidget {
  const _HorseNo(this.no, {this.color});
  final int no;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? scheme.surfaceContainerHighest,
      ),
      child: Text(
        '$no',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: color == null ? null : Colors.white,
        ),
      ),
    );
  }
}

/// レース結果（着順と払戻金の表）
class RaceResultCard extends StatelessWidget {
  const RaceResultCard({super.key, required this.race, required this.payouts});

  final Race race;
  final Map<String, int> payouts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final placings = race.outcome?.placings ?? const {};
    final scratched = race.outcome?.scratched ?? const <int>{};
    final entries = orderedPayouts(payouts, placings: placings);
    final small = t.bodyMedium;
    Widget cell(String s, {TextStyle? style, TextAlign? align}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(s, style: style ?? small, textAlign: align),
    );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: scheme.primary),
                const SizedBox(width: 8),
                Text('レース結果', style: t.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var r = 1; r <= 3; r++)
                  Expanded(
                    child: Column(
                      children: [
                        Text('$r着', style: t.labelMedium),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: [
                            for (final h in placings[r] ?? const <int>[])
                              _HorseNo(h, color: _medal[r - 1]),
                            if ((placings[r] ?? const []).isEmpty)
                              Text('―', style: t.titleMedium),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (scratched.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '取消・除外  ${(scratched.toList()..sort()).join('・')}番',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Text(
                '払戻金は記録されていません。「結果を修正」から払戻金の表を貼り付けると残せます。',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: scheme.outlineVariant),
                  top: BorderSide(color: scheme.outlineVariant),
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(1),
                  2: IntrinsicColumnWidth(),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                    ),
                    children: [
                      cell('券種', style: t.labelMedium),
                      cell('組み合わせ', style: t.labelMedium),
                      cell('払戻金', style: t.labelMedium),
                    ],
                  ),
                  for (var i = 0; i < entries.length; i++)
                    TableRow(
                      children: [
                        cell(
                          i == 0 || entries[i - 1].type != entries[i].type
                              ? entries[i].type.label
                              : '',
                          style: t.labelLarge,
                        ),
                        cell(entries[i].label),
                        cell(
                          yen(entries[i].yen),
                          align: TextAlign.right,
                          style: entries[i].big
                              ? small?.copyWith(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w700,
                                )
                              : small,
                        ),
                      ],
                    ),
                ],
              ),
            if (entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '100円あたりの払戻金。赤字は万馬券です。',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 蓄積したレース結果の一覧
class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _export(List<RaceResult> results) async {
    if (results.isEmpty) {
      toast(context, '書き出すレース結果がありません');
      return;
    }
    final csv = '﻿${raceResultsToCsv(results)}';
    final name = 'race_results_${isoDate(today())}.csv';
    if (kIsWeb) {
      final ok = await saveTextFile(name, csv);
      if (mounted && !ok) toast(context, 'ファイルを保存できませんでした');
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsString(csv, encoding: utf8);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'レース結果（CSV）'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DbQuery<List<RaceResult>>(
      load: (db) => db.raceResults(),
      builder: (context, all) {
        final results = [
          for (final r in all)
            if (matchesResult(r, _query.text)) r,
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('レース結果'),
            actions: [
              IconButton(
                tooltip: 'CSV に書き出す',
                icon: const Icon(Icons.upload_file),
                onPressed: () => _export(results),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ResultEntryPage()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('結果を記録'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'レース名・競馬場・日付（2026-10）で探す',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '消す',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(_query.clear),
                          ),
                  ),
                ),
              ),
              if (all.isEmpty)
                const _EmptyResults()
              else ...[
                _StatsCard(results: results, total: all.length),
                ..._grouped(context, results),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _grouped(BuildContext context, List<RaceResult> results) {
    final t = Theme.of(context).textTheme;
    final out = <Widget>[];
    String? day;
    for (final r in results) {
      if (r.race.date != day) {
        day = r.race.date;
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '${day.substring(0, 4)}年 ${jpDate(day)}',
              style: t.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      }
      out.add(_ResultRow(result: r));
    }
    if (results.isEmpty) {
      out.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('見つかりませんでした')),
        ),
      );
    }
    return out;
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('まだレース結果がありません', style: t.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '馬券の結果を入力すると、着順と払戻金がここにたまっていきます。'
            '馬券を買っていないレースも「結果を記録」から残せます。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 券種ごとの平均・最高払戻金
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.results, required this.total});

  final List<RaceResult> results;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final stats = payoutStats(results);
    Widget cell(
      String s, {
      TextStyle? style,
      TextAlign align = TextAlign.right,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Text(s, style: style ?? t.bodySmall, textAlign: align),
    );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.insights, color: scheme.primary),
          title: Text(
            results.length == total
                ? '$total レースの結果をためています'
                : '$total レース中 ${results.length} レース',
            style: t.titleSmall,
          ),
          subtitle: const Text('券種ごとの平均・最高払戻金を見る'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (stats.isEmpty)
              const Text('払戻金の入ったレースがまだありません')
            else
              Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: scheme.outlineVariant),
                ),
                columnWidths: const {0: IntrinsicColumnWidth()},
                children: [
                  TableRow(
                    children: [
                      cell('券種', style: t.labelSmall, align: TextAlign.left),
                      cell('レース', style: t.labelSmall),
                      cell('平均', style: t.labelSmall),
                      cell('最高', style: t.labelSmall),
                      cell('万馬券', style: t.labelSmall),
                    ],
                  ),
                  for (final s in stats)
                    TableRow(
                      children: [
                        cell(
                          s.type.label,
                          style: t.labelLarge,
                          align: TextAlign.left,
                        ),
                        cell('${s.races}'),
                        cell(yen(s.average)),
                        cell(yen(s.max)),
                        cell(s.big == 0 ? '―' : '${s.big}回'),
                      ],
                    ),
                ],
              ),
            if (stats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '100円あたり。複勝・ワイドは当たり組み合わせすべての平均です。',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});
  final RaceResult result;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final race = result.race;
    final entries = orderedPayouts(result.payouts);
    PayoutEntry? pick(BetType type) =>
        entries.where((e) => e.type == type).firstOrNull;
    final main = pick(BetType.trifecta) ?? pick(BetType.quinella);
    final name = race.name;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Text('${race.raceNo}R', style: t.labelMedium),
      ),
      title: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ?GradeBadge.forName(name, small: true),
          Text(
            name == null || name.isEmpty
                ? '${race.venue} ${race.raceNo}R'
                : name,
          ),
        ],
      ),
      subtitle: Text(
        [
          '${race.venue}${race.raceNo}R',
          if (placingText(race).isNotEmpty) placingText(race),
        ].join('  '),
      ),
      trailing: main == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(main.type.label, style: t.labelSmall),
                Text(
                  yen(main.yen),
                  style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: main.big ? scheme.error : null,
                  ),
                ),
              ],
            ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RacePage(raceId: race.id!)),
      ),
    );
  }
}

/// 馬券を買っていないレースの結果だけを記録する
class ResultEntryPage extends StatefulWidget {
  const ResultEntryPage({super.key});

  @override
  State<ResultEntryPage> createState() => _ResultEntryPageState();
}

class _ResultEntryPageState extends State<ResultEntryPage> {
  DateTime _date = today();
  String _venue = jraVenues[4];
  int _raceNo = 11;
  String? _name;
  bool _initialized = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _venue = AppScope.of(context).settings.lastVenue ?? _venue;
  }

  void _apply(RacePick pick) => setState(() {
    _date = pick.date;
    if (pick.venue.isNotEmpty) {
      _venue = pick.venue;
    } else if (presetByName(pick.name)?.venue case final v?) {
      _venue = v;
    }
    if (pick.raceNo != null) _raceNo = pick.raceNo!;
    if (pick.name != null || isGradedName(_name)) _name = pick.name;
  });

  Future<void> _next() async {
    setState(() => _busy = true);
    final db = AppScope.of(context).db;
    final preset = presetByName(_name);
    final id = await db.upsertRace(
      Race(
        date: isoDate(_date),
        venue: _venue,
        raceNo: _raceNo,
        name: _name,
        surface: preset?.surface,
        distance: preset?.distance,
      ),
    );
    final race = await db.race(id);
    if (!mounted || race == null) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ResultPage(race: race)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('レース結果を記録')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '馬券を買っていないレースも、結果（着順と払戻金）をデータとして残せます。'
            'レースを選んで、次の画面で払戻金の表を貼り付けてください。',
            style: t.bodyMedium,
          ),
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
          WeekRacesPanel(date: _date, selectedName: _name, onPick: _apply),
          const FieldLabel('競馬場'),
          VenueChooser(
            venue: _venue,
            onChanged: (v) => setState(() => _venue = v),
          ),
          const FieldLabel('レース番号'),
          RaceNoChooser(
            raceNo: _raceNo,
            onChanged: (n) => setState(() => _raceNo = n),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final pick = await showDayRaceList(
                  context,
                  date: _date,
                  venue: _venue,
                  raceNo: _raceNo,
                );
                if (pick != null) _apply(pick);
              },
              icon: const Icon(Icons.format_list_numbered),
              label: const Text('この日の 1R〜最終R の一覧から選ぶ'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _next,
            icon: const Icon(Icons.arrow_forward),
            label: Text('$_venue ${_raceNo}R の結果を入力'),
          ),
        ],
      ),
    );
  }
}
