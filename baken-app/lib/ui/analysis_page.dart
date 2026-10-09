import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/stats.dart';
import 'common.dart';

enum _Period {
  today('今日'),
  week('今週'),
  month('今月'),
  year('今年'),
  all('全期間'),
  custom('期間指定');

  const _Period(this.label);
  final String label;
}

/// 分析タブ。期間 → 切り口 → 指標。
class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  _Period _period = _Period.month;
  DateTimeRange? _custom;
  Breakdown _by = Breakdown.betType;

  (String?, String?) get _range {
    final d = today();
    return switch (_period) {
      _Period.today => (isoDate(d), isoDate(d)),
      _Period.week => (
        isoDate(d.subtract(Duration(days: d.weekday - 1))),
        isoDate(d.add(Duration(days: 7 - d.weekday))),
      ),
      _Period.month => (
        isoDate(DateTime(d.year, d.month, 1)),
        isoDate(DateTime(d.year, d.month + 1, 0)),
      ),
      _Period.year => ('${d.year}-01-01', '${d.year}-12-31'),
      _Period.all => (null, null),
      _Period.custom =>
        _custom == null
            ? (null, null)
            : (isoDate(_custom!.start), isoDate(_custom!.end)),
    };
  }

  Future<void> _pickPeriod(_Period p) async {
    if (p == _Period.custom) {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _custom,
      );
      if (r == null) return;
      setState(() {
        _custom = r;
        _period = p;
      });
    } else {
      setState(() => _period = p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('分析')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final p in _Period.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        p == _Period.custom && _custom != null
                            ? '${_custom!.start.month}/${_custom!.start.day}〜${_custom!.end.month}/${_custom!.end.day}'
                            : p.label,
                      ),
                      selected: _period == p,
                      onSelected: (_) => _pickPeriod(p),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: DbQuery<List<Ticket>>(
              key: ValueKey('$from|$to'),
              load: (db) => db.tickets(from: from, to: to, settled: true),
              builder: (context, tickets) {
                final totals = totalsOf(tickets);
                if (totals.count == 0) {
                  return const Center(child: Text('この期間に確定した記録はありません'));
                }
                final rows = breakdownOf(tickets, _by);
                final best = totals.maxPayoutTicket;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 12,
                          children: [
                            StatTile(label: '投資', value: yen(totals.stake)),
                            StatTile(label: '払戻', value: yen(totals.payout)),
                            StatTile(
                              label: '収支',
                              value: signedYen(totals.profit),
                              color: profitColor(context, totals.profit),
                            ),
                            StatTile(
                              label: '回収率',
                              value: percent(totals.returnRate),
                            ),
                            StatTile(
                              label: '的中率',
                              value:
                                  '${percent(totals.hitRate)}（${totals.hits}/${totals.count}）',
                            ),
                            StatTile(
                              label: '最大連敗',
                              value: '${totals.maxLosingStreak}回',
                            ),
                            if (best != null && totals.maxPayout > 0)
                              StatTile(
                                label: '最高払戻',
                                value:
                                    '${yen(totals.maxPayout)}（${jpDate(best.date)} ${best.venue}${best.raceNo == null ? '' : ' ${best.raceNo}R'}）',
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('累積収支', style: t.titleSmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: _CumulativeChart(
                        points: cumulativeProfit(tickets),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('切り口別の回収率', style: t.titleSmall),
                        const Spacer(),
                        DropdownButton<Breakdown>(
                          value: _by,
                          items: [
                            for (final b in Breakdown.values)
                              DropdownMenuItem(value: b, child: Text(b.label)),
                          ],
                          onChanged: (b) => setState(() => _by = b ?? _by),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final e in rows)
                      _BreakdownRow(
                        name: e.key,
                        totals: e.value,
                        maxRate: _maxRate(rows),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '縦線は回収率100%。件数が10件未満の切り口は参考値です。',
                      style: t.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _maxRate(List<MapEntry<String, Totals>> rows) {
    var m = 150.0;
    for (final r in rows) {
      final v = r.value.returnRate ?? 0;
      if (v > m) m = v;
    }
    return m;
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.name,
    required this.totals,
    required this.maxRate,
  });

  final String name;
  final Totals totals;
  final double maxRate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rate = totals.returnRate ?? 0;
    final over = rate >= 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: t.bodyMedium)),
              Text(
                '${percent(totals.returnRate)}${totals.isTentative ? '（参考値）' : ''}',
                style: t.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: over ? Colors.blue.shade700 : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return SizedBox(
                height: 12,
                child: Stack(
                  children: [
                    Container(
                      width: w * (rate / maxRate).clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        color: over ? Colors.blue.shade600 : scheme.outline,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Positioned(
                      left: w * (100 / maxRate) - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: scheme.onSurface),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          Text(
            '${totals.count}件  投資 ${yen(totals.stake)}  払戻 ${yen(totals.payout)}',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CumulativeChart extends StatelessWidget {
  const _CumulativeChart({required this.points});

  final List<({DateTime date, int cumulative})> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.length < 2) {
      return const Center(child: Text('2日分以上の記録があるとグラフを表示します'));
    }
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].cumulative.toDouble()),
    ];
    final last = points.last.cumulative;
    final color = last >= 0 ? Colors.blue.shade600 : scheme.error;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: v == 0 ? scheme.onSurface : scheme.outlineVariant,
            strokeWidth: v == 0 ? 1.2 : 0.6,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  '${(v / 1000).round()}千',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: ((points.length - 1) / 4).ceilToDouble().clamp(
                1,
                double.infinity,
              ),
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                final d = points[i].date;
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${d.month}/${d.day}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${points[s.x.round()].date.month}/${points[s.x.round()].date.day}\n${signedYen(s.y.round())}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: color,
            barWidth: 2,
            dotData: FlDotData(show: points.length <= 31),
          ),
        ],
      ),
    );
  }
}
