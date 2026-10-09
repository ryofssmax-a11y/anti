import 'package:flutter/material.dart';

import '../core/bet_type.dart';
import '../core/expander.dart';
import '../core/judge.dart';
import '../core/selection.dart';
import '../data/database.dart';
import '../data/models.dart';
import 'common.dart';
import 'race_name_picker.dart';
import 'race_results.dart';
import 'record_form_page.dart';
import 'result_page.dart';

/// レースの詳細。馬券と買い目、結果入力への入口。
class RacePage extends StatefulWidget {
  const RacePage({super.key, required this.raceId});

  final int raceId;

  @override
  State<RacePage> createState() => _RacePageState();
}

class _RacePageState extends State<RacePage> {
  Future<({Race? race, List<Ticket> tickets, Map<String, int> payouts})> _load(
    AppDatabase db,
  ) async {
    final race = await db.race(widget.raceId);
    final tickets = race == null
        ? <Ticket>[]
        : await db.ticketsForRace(widget.raceId);
    final payouts = race == null || !race.settled
        ? <String, int>{}
        : await db.payoutsFor(widget.raceId);
    return (race: race, tickets: tickets, payouts: payouts);
  }

  Future<void> _manualSettle(Ticket t) async {
    final controller = TextEditingController(
      text: t.settled ? '${t.payoutTotal}' : '0',
    );
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('払戻額を入力して確定'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            suffixText: '円',
            helperText: '外れは0円',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              int.tryParse(controller.text.replaceAll(',', '')),
            ),
            child: const Text('確定'),
          ),
        ],
      ),
    );
    if (v != null && v >= 0 && mounted) {
      await AppScope.of(context).db.settleTicketManually(t.id!, v);
    }
  }

  Future<void> _delete(Ticket t, int count) async {
    final ok = await confirm(
      context,
      '馬券を削除',
      '${t.typeLabel}（${yen(t.stakeTotal)}）を削除します。元に戻せません。',
      ok: '削除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final last = count == 1;
    await AppScope.of(context).db.deleteTicket(t.id!);
    if (last && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DbQuery(
      load: _load,
      builder: (context, data) =>
          _build(context, data.race, data.tickets, data.payouts),
    );
  }

  Widget _build(
    BuildContext context,
    Race? race,
    List<Ticket> tickets,
    Map<String, int> payouts,
  ) {
    if (race == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('このレースは削除されました')),
      );
    }
    final t = Theme.of(context).textTheme;
    final stake = tickets.fold<int>(0, (s, x) => s + x.stakeTotal);
    final payout = tickets.fold<int>(0, (s, x) => s + x.payoutTotal);
    final allSettled = tickets.every((x) => x.settled);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (GradeBadge.forName(race.name) case final b?) ...[
              b,
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                race.name ?? race.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      jpDate(race.date),
                      '${race.venue} ${race.raceNo}R',
                      if (race.surface != null) race.surface!,
                      if (race.distance != null) '${race.distance}m',
                      '${race.fieldSize}頭',
                    ].join('  '),
                    style: t.bodyMedium,
                  ),
                  if (tickets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        StatTile(label: '投資', value: yen(stake)),
                        StatTile(
                          label: '払戻',
                          value: allSettled ? yen(payout) : '未確定',
                        ),
                        if (allSettled)
                          StatTile(
                            label: '収支',
                            value: signedYen(payout - stake),
                            color: profitColor(context, payout - stake),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.flag),
                          label: Text(race.settled ? '結果を修正' : '結果を入力'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ResultPage(race: race),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('馬券を追加'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecordFormPage(race: race),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (race.settled) RaceResultCard(race: race, payouts: payouts),
          for (final ticket in tickets)
            _TicketCard(
              ticket: ticket,
              onDelete: () => _delete(ticket, tickets.length),
              onManualSettle: () => _manualSettle(ticket),
              onUnsettle: () =>
                  AppScope.of(context).db.unsettleTicket(ticket.id!),
              onEdit: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RecordFormPage(editing: ticket, race: race),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.onDelete,
    required this.onManualSettle,
    required this.onUnsettle,
    required this.onEdit,
  });

  final Ticket ticket;
  final VoidCallback onDelete;
  final VoidCallback onManualSettle;
  final VoidCallback onUnsettle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final type = ticket.type ?? BetType.win;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ExpansionTile(
        shape: const Border(),
        title: Text('${ticket.typeLabel}  ${ticket.lines.length}点'),
        subtitle: Text(
          ticket.settled
              ? '${yen(ticket.stakeTotal)} → ${yen(ticket.payoutTotal)}  ${signedYen(ticket.profit)}'
              : '${yen(ticket.stakeTotal)}  未確定${type == BetType.win5 ? '（WIN5は払戻を手入力）' : ''}',
          style: TextStyle(
            color: ticket.settled ? profitColor(context, ticket.profit) : null,
          ),
        ),
        children: [
          if (ticket.tagList.isNotEmpty || ticket.memo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  [
                    ticket.channel.label,
                    if (ticket.tagList.isNotEmpty)
                      'タグ: ${ticket.tagList.join('、')}',
                    if (ticket.memo.isNotEmpty) ticket.memo,
                  ].join('\n'),
                  style: t.bodySmall,
                ),
              ),
            ),
          for (final l in ticket.lines)
            ListTile(
              dense: true,
              leading: Icon(
                switch (l.status) {
                  LineStatus.hit => Icons.check_circle,
                  LineStatus.refund => Icons.undo,
                  LineStatus.miss => Icons.close,
                  null => Icons.radio_button_unchecked,
                },
                color: switch (l.status) {
                  LineStatus.hit => Colors.blue.shade700,
                  LineStatus.refund => scheme.tertiary,
                  _ => scheme.outline,
                },
              ),
              title: Text(
                formatCombination(
                  type,
                  Combination.parse(l.combo, ordered: type.ordered),
                ),
              ),
              subtitle: l.odds == null
                  ? null
                  : Text('${l.odds!.toStringAsFixed(1)}倍'),
              trailing: Text(switch (l.status) {
                LineStatus.hit => '${yen(l.stake)} → ${yen(l.payout)}',
                LineStatus.refund => '${yen(l.stake)} 返還',
                _ => yen(l.stake),
              }),
            ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('編集'),
              ),
              if (ticket.settled)
                TextButton(onPressed: onUnsettle, child: const Text('未確定に戻す'))
              else
                TextButton(
                  onPressed: onManualSettle,
                  child: const Text('払戻を手入力して確定'),
                ),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('削除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
