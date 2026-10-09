import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/stats.dart';
import 'common.dart';
import 'race_page.dart';
import 'records_page.dart';

/// ホーム。今月の収支と未確定のレース。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onOpenCalculator});

  final VoidCallback onOpenCalculator;

  @override
  Widget build(BuildContext context) {
    final now = today();
    final from = isoDate(DateTime(now.year, now.month, 1));
    final to = isoDate(DateTime(now.year, now.month + 1, 0));
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('馬券収支電卓')),
      body: DbQuery<({List<Ticket> month, List<Race> pending})>(
        key: ValueKey(from),
        load: (db) async => (
          month: await db.tickets(from: from, to: to),
          pending: await db.pendingRaces(),
        ),
        builder: (context, data) {
          final totals = totalsOf(data.month);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${now.month}月の収支', style: t.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        signedYen(totals.profit),
                        style: t.headlineMedium?.copyWith(
                          color: profitColor(context, totals.profit),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 24,
                        runSpacing: 8,
                        children: [
                          StatTile(label: '投資', value: yen(totals.stake)),
                          StatTile(label: '払戻', value: yen(totals.payout)),
                          StatTile(
                            label: '回収率',
                            value: percent(totals.returnRate),
                          ),
                          StatTile(
                            label: '的中率',
                            value: percent(totals.hitRate),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpenCalculator,
                      icon: const Icon(Icons.calculate),
                      label: const Text('買い目を計算'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => showAddRecordSheet(context),
                      icon: const Icon(Icons.add),
                      label: const Text('記録する'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('結果待ちのレース（${data.pending.length}）', style: t.titleSmall),
              const SizedBox(height: 4),
              if (data.pending.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('結果待ちのレースはありません。', style: t.bodyMedium),
                )
              else
                for (final r in data.pending)
                  Card(
                    child: ListTile(
                      title: Text(r.title),
                      subtitle: Text(jpDate(r.date)),
                      trailing: const Text('結果を入力'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RacePage(raceId: r.id!),
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
