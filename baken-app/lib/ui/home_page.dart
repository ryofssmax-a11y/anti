import 'package:flutter/material.dart';

import '../core/bet_type.dart';
import '../data/models.dart';
import '../data/stats.dart';
import 'common.dart';
import 'race_name_picker.dart';
import 'race_page.dart';
import 'record_form_page.dart';

/// ホーム。今月の収支、すぐ使える操作、結果待ち、最近の的中。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onOpenCalculator});

  final VoidCallback onOpenCalculator;

  @override
  Widget build(BuildContext context) {
    final now = today();
    final from = isoDate(DateTime(now.year, now.month, 1));
    final to = isoDate(DateTime(now.year, now.month + 1, 0));

    return Scaffold(
      body: SafeArea(
        child: DbQuery<_HomeData>(
          key: ValueKey(from),
          load: (db) async => _HomeData(
            month: await db.tickets(from: from, to: to),
            pending: await db.pendingRaces(),
            hits: await db.recentHits(),
          ),
          builder: (context, data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Greeting(now: now),
              const SizedBox(height: 12),
              _HeroCard(month: now.month, tickets: data.month),
              const SizedBox(height: 16),
              _QuickActions(
                pending: data.pending,
                onOpenCalculator: onOpenCalculator,
              ),
              _BudgetMeter(tickets: data.month),
              if (data.pending.isNotEmpty) ...[
                const _SectionTitle(icon: Icons.sports_score, text: '結果待ちのレース'),
                for (final r in data.pending) _PendingCard(race: r),
              ],
              if (data.hits.isNotEmpty) ...[
                const _SectionTitle(
                  icon: Icons.celebration_outlined,
                  text: '最近の的中',
                ),
                for (final t in data.hits) _HitCard(ticket: t),
              ],
              const SizedBox(height: 24),
              Text(
                '馬券は20歳になってから。無理のない範囲で楽しみましょう。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeData {
  _HomeData({required this.month, required this.pending, required this.hits});
  final List<Ticket> month;
  final List<Race> pending;
  final List<Ticket> hits;
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hour = DateTime.now().hour;
    final hello = hour < 5
        ? 'こんばんは'
        : hour < 11
        ? 'おはようございます'
        : hour < 18
        ? 'こんにちは'
        : 'こんばんは';
    final message = switch (now.weekday) {
      DateTime.saturday || DateTime.sunday => '今日は開催日。レースを楽しみましょう',
      DateTime.friday => '週末のレース、どれに注目していますか？',
      DateTime.monday => '週末の振り返りをしておきましょう',
      _ => '今週もおつかれさまです',
    };
    const w = ['月', '火', '水', '木', '金', '土', '日'];
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${now.month}月${now.day}日（${w[now.weekday - 1]}）',
            style: t.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hello,
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(message, style: t.bodyMedium),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.month, required this.tickets});
  final int month;
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final totals = totalsOf(tickets);
    final rate = totals.returnRate;
    final comment = totals.count == 0
        ? '最初の1枚を記録してみましょう'
        : rate! >= 100
        ? 'プラス収支です。いい流れ！'
        : rate >= 80
        ? 'あと少しでプラス圏です'
        : '記録を続けると、得意な条件が見えてきます';
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.85);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E7D32), Color(0xFF00897B)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$month月の収支',
                      style: t.titleSmall?.copyWith(color: soft),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        signedYen(totals.profit),
                        style: t.headlineLarge?.copyWith(
                          color: white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _RateGauge(rate: rate),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill('投資 ${yen(totals.stake)}'),
              _Pill('払戻 ${yen(totals.payout)}'),
              _Pill('的中 ${totals.hits}回'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            comment,
            style: t.bodyMedium?.copyWith(
              color: white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateGauge extends StatelessWidget {
  const _RateGauge({required this.rate});
  final double? rate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: ((rate ?? 0) / 100).clamp(0.0, 1.0),
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              color: (rate ?? 0) >= 100
                  ? const Color(0xFFFFD54F)
                  : Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '回収率',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
              Text(
                rate == null ? '―' : '${rate!.round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.pending, required this.onOpenCalculator});
  final List<Race> pending;
  final VoidCallback onOpenCalculator;

  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    final tiles = [
      _ActionTile(
        icon: Icons.calculate_rounded,
        label: '買い目を計算',
        color: const Color(0xFF1E88E5),
        onTap: onOpenCalculator,
      ),
      _ActionTile(
        icon: Icons.edit_note_rounded,
        label: '馬券を記録',
        color: const Color(0xFF43A047),
        onTap: () => open(const RecordFormPage()),
      ),
      _ActionTile(
        icon: Icons.bolt_rounded,
        label: 'かんたん記録',
        color: const Color(0xFFFB8C00),
        onTap: () => open(const SimpleRecordPage()),
      ),
      _ActionTile(
        icon: Icons.flag_rounded,
        label: '結果を入力',
        color: const Color(0xFF8E24AA),
        badge: pending.isEmpty ? null : '${pending.length}',
        onTap: () {
          if (pending.isEmpty) {
            toast(context, '結果待ちのレースはありません');
          } else if (pending.length == 1) {
            open(RacePage(raceId: pending.first.id!));
          } else {
            showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (ctx) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in pending)
                      ListTile(
                        leading:
                            GradeBadge.forName(r.name, small: true) ??
                            const Icon(Icons.flag_outlined),
                        title: Text(r.name ?? '${r.venue} ${r.raceNo}R'),
                        subtitle: Text(
                          '${jpDate(r.date)}  ${r.venue} ${r.raceNo}R',
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          open(RacePage(raceId: r.id!));
                        },
                      ),
                  ],
                ),
              ),
            );
          }
        },
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            children: [
              Badge(
                isLabelVisible: badge != null,
                label: Text(badge ?? ''),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color, size: 26),
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetMeter extends StatelessWidget {
  const _BudgetMeter({required this.tickets});
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final limit = AppScope.of(context).settings.budgetMonth;
    if (limit <= 0) return const SizedBox.shrink();
    final spent = tickets.fold<int>(0, (s, t) => s + t.stakeTotal);
    final ratio = spent / limit;
    final scheme = Theme.of(context).colorScheme;
    final color = ratio >= 1
        ? scheme.error
        : ratio >= 0.8
        ? const Color(0xFFFB8C00)
        : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('今月の予算', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              Text(
                '${yen(spent)} / ${yen(limit)}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 10,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.race});
  final Race race;

  @override
  Widget build(BuildContext context) {
    final badge = GradeBadge.forName(race.name, small: true);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.hourglass_top_rounded)),
        title: Row(
          children: [
            if (badge != null) ...[badge, const SizedBox(width: 6)],
            Flexible(
              child: Text(
                race.name ?? '${race.venue} ${race.raceNo}R',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text('${jpDate(race.date)}  ${race.venue} ${race.raceNo}R'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '結果を入れる',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RacePage(raceId: race.id!)),
        ),
      ),
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final badge = GradeBadge.forName(ticket.raceName, small: true);
    final hitLines = ticket.lines
        .where((l) => l.payout > 0)
        .map((l) => l.combo)
        .toList();
    final type = ticket.type;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFF3CD),
          child: Icon(Icons.emoji_events, color: Color(0xFFB8860B)),
        ),
        title: Row(
          children: [
            if (badge != null) ...[badge, const SizedBox(width: 6)],
            Flexible(
              child: Text(
                ticket.raceName ??
                    '${ticket.venue}${ticket.raceNo == null ? '' : ' ${ticket.raceNo}R'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          [
            jpDate(ticket.date),
            if (type != null) type.label,
            if (type != null && hitLines.isNotEmpty && type != BetType.win5)
              hitLines.join('、'),
          ].join('  '),
        ),
        trailing: Text(
          yen(ticket.payoutTotal),
          style: t.titleMedium?.copyWith(
            color: Colors.blue.shade700,
            fontWeight: FontWeight.w700,
          ),
        ),
        onTap: ticket.raceId == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RacePage(raceId: ticket.raceId!),
                ),
              ),
      ),
    );
  }
}
