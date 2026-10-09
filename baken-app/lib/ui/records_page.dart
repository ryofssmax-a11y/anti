import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/stats.dart';
import 'common.dart';
import 'race_name_picker.dart';
import 'race_page.dart';
import 'race_results.dart';
import 'record_form_page.dart';

/// 記録タブ。月ごとの一覧とカレンダー。
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  DateTime _month = DateTime(today().year, today().month);
  bool _calendar = false;
  String? _day;

  String get _from => isoDate(_month);
  String get _to => isoDate(DateTime(_month.year, _month.month + 1, 0));

  void _shift(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _day = null;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('記録'),
        actions: [
          IconButton(
            tooltip: 'レース結果',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ResultsPage()),
            ),
          ),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.list),
                tooltip: '一覧',
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.calendar_month),
                tooltip: 'カレンダー',
              ),
            ],
            selected: {_calendar},
            onSelectionChanged: (s) => setState(() => _calendar = s.first),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddRecordSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('記録'),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '前の月',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_month.year}年${_month.month}月',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                tooltip: '次の月',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Expanded(
            child: DbQuery<List<Ticket>>(
              key: ValueKey(_from),
              load: (db) => db.tickets(from: _from, to: _to),
              builder: (context, tickets) {
                final totals = totalsOf(tickets);
                final pending = tickets.where((t) => !t.settled).length;
                final summary = Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      StatTile(label: '投資', value: yen(totals.stake)),
                      StatTile(label: '払戻', value: yen(totals.payout)),
                      StatTile(
                        label: '収支',
                        value: signedYen(totals.profit),
                        color: profitColor(context, totals.profit),
                      ),
                      StatTile(label: '回収率', value: percent(totals.returnRate)),
                      if (pending > 0)
                        StatTile(label: '未確定', value: '$pending件'),
                    ],
                  ),
                );
                if (_calendar) {
                  final dayTickets = _day == null
                      ? <Ticket>[]
                      : tickets.where((t) => t.date == _day).toList();
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      summary,
                      _MonthCalendar(
                        month: _month,
                        daily: dailyProfit(tickets),
                        hasPending: {
                          for (final t in tickets)
                            if (!t.settled) t.date,
                        },
                        selected: _day,
                        onTap: (d) =>
                            setState(() => _day = d == _day ? null : d),
                      ),
                      if (_day != null) ..._dayGroups(context, dayTickets),
                    ],
                  );
                }
                if (tickets.isEmpty) {
                  return ListView(
                    children: [
                      summary,
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'この月の記録はありません。右下の「記録」から追加できます。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  );
                }
                final dates = tickets.map((t) => t.date).toSet().toList()
                  ..sort((a, b) => b.compareTo(a));
                return ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    summary,
                    for (final d in dates)
                      ..._dayGroups(
                        context,
                        tickets.where((t) => t.date == d).toList(),
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
}

/// 1日分の記録をレースごとにまとめた行
List<Widget> _dayGroups(BuildContext context, List<Ticket> tickets) {
  if (tickets.isEmpty) {
    return const [
      Padding(padding: EdgeInsets.all(24), child: Text('この日の記録はありません')),
    ];
  }
  final t = Theme.of(context).textTheme;
  final dayProfit = tickets
      .where((x) => x.settled)
      .fold<int>(0, (s, x) => s + x.profit);
  final byRace = <int, List<Ticket>>{};
  final simple = <Ticket>[];
  for (final x in tickets) {
    if (x.raceId == null) {
      simple.add(x);
    } else {
      byRace.putIfAbsent(x.raceId!, () => []).add(x);
    }
  }
  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(jpDate(tickets.first.date), style: t.titleSmall),
          const Spacer(),
          Text(
            signedYen(dayProfit),
            style: t.titleSmall?.copyWith(
              color: profitColor(context, dayProfit),
            ),
          ),
        ],
      ),
    ),
    for (final entry in byRace.entries)
      _RaceRow(raceId: entry.key, tickets: entry.value),
    for (final s in simple) _SimpleRow(ticket: s),
  ];
}

class _RaceRow extends StatelessWidget {
  const _RaceRow({required this.raceId, required this.tickets});

  final int raceId;
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final first = tickets.first;
    final stake = tickets.fold<int>(0, (s, x) => s + x.stakeTotal);
    final settled = tickets.every((x) => x.settled);
    final profit = tickets.fold<int>(0, (s, x) => s + x.profit);
    final name = tickets.map((x) => x.raceName).whereType<String>().firstOrNull;
    final badge = GradeBadge.forName(name, small: true);
    final types = tickets.map((x) => x.typeLabel).toSet().join('・');
    return ListTile(
      title: Row(
        children: [
          if (badge != null) ...[badge, const SizedBox(width: 6)],
          Flexible(
            child: Text(
              name ?? '${first.venue} ${first.raceNo}R',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Text(
        name == null ? types : '${first.venue} ${first.raceNo}R  $types',
      ),
      trailing: settled
          ? Text(
              signedYen(profit),
              style: TextStyle(
                color: profitColor(context, profit),
                fontWeight: FontWeight.w600,
              ),
            )
          : Chip(
              label: Text('未確定 ${yen(stake)}'),
              visualDensity: VisualDensity.compact,
            ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RacePage(raceId: raceId)),
      ),
    );
  }
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        children: [
          if (GradeBadge.forName(ticket.raceName, small: true)
              case final b?) ...[
            b,
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              '${ticket.raceName ?? ticket.venue}  簡易記録',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${yen(ticket.stakeTotal)} → ${yen(ticket.payoutTotal)}${ticket.memo.isEmpty ? '' : '  ${ticket.memo}'}',
      ),
      trailing: Text(
        signedYen(ticket.profit),
        style: TextStyle(
          color: profitColor(context, ticket.profit),
          fontWeight: FontWeight.w600,
        ),
      ),
      onLongPress: () => _delete(context),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SimpleRecordPage(editing: ticket)),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      '簡易記録を削除',
      '${jpDate(ticket.date)} ${ticket.venue}（${yen(ticket.stakeTotal)}）を削除しますか？',
      ok: '削除',
      destructive: true,
    );
    if (ok && context.mounted) {
      await AppScope.of(context).db.deleteTicket(ticket.id!);
    }
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.daily,
    required this.hasPending,
    required this.selected,
    required this.onTap,
  });

  final DateTime month;
  final Map<String, int> daily;
  final Set<String> hasPending;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month, 1).weekday - 1; // 月曜始まり
    const heads = ['月', '火', '水', '木', '金', '土', '日'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              for (final h in heads)
                Expanded(
                  child: Center(child: Text(h, style: t.labelSmall)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.85,
            children: [
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= days; d++)
                Builder(
                  builder: (context) {
                    final iso = isoDate(DateTime(month.year, month.month, d));
                    final p = daily[iso];
                    final isSel = iso == selected;
                    return InkWell(
                      onTap: () => onTap(iso),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: isSel ? scheme.primaryContainer : null,
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Column(
                          children: [
                            Text('$d', style: t.labelMedium),
                            const Spacer(),
                            if (p != null)
                              FittedBox(
                                child: Text(
                                  '${p > 0 ? '+' : ''}${p ~/ 100 / 10}k',
                                  style: t.labelSmall?.copyWith(
                                    color: profitColor(context, p),
                                  ),
                                ),
                              ),
                            if (hasPending.contains(iso))
                              Icon(
                                Icons.circle,
                                size: 6,
                                color: scheme.tertiary,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('数字は収支（1k = 1,000円）。点は未確定の馬券がある日', style: t.labelSmall),
          ),
        ],
      ),
    );
  }
}

/// 記録の追加方法を選ぶ
Future<void> showAddRecordSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('詳細記録'),
            subtitle: const Text('レースと買い目を入れる。結果を入れると自動で判定'),
            onTap: () => Navigator.pop(ctx, 'detail'),
          ),
          ListTile(
            leading: const Icon(Icons.bolt),
            title: const Text('簡易記録'),
            subtitle: const Text('投資額と払戻額だけ'),
            onTap: () => Navigator.pop(ctx, 'simple'),
          ),
          ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: const Text('レース結果だけ記録'),
            subtitle: const Text('馬券を買っていないレースの着順・払戻金'),
            onTap: () => Navigator.pop(ctx, 'result'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => switch (choice) {
        'detail' => const RecordFormPage(),
        'result' => const ResultEntryPage(),
        _ => const SimpleRecordPage(),
      },
    ),
  );
}
