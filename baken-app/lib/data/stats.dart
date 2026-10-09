import 'models.dart';

/// 集計値
class Totals {
  int count = 0;
  int hits = 0;
  int stake = 0;
  int payout = 0;
  int maxPayout = 0;
  Ticket? maxPayoutTicket;
  int maxLosingStreak = 0;
  int _streak = 0;

  int get profit => payout - stake;

  /// 回収率（%）。投資がなければ null
  double? get returnRate => stake == 0 ? null : payout / stake * 100;

  /// 的中率（%）
  double? get hitRate => count == 0 ? null : hits / count * 100;

  /// 件数が少なく参考値にとどまるか
  bool get isTentative => count < 10;

  void add(Ticket t) {
    count++;
    stake += t.stakeTotal;
    payout += t.payoutTotal;
    if (t.isHit) {
      hits++;
      _streak = 0;
    } else {
      _streak++;
      if (_streak > maxLosingStreak) maxLosingStreak = _streak;
    }
    if (t.payoutTotal > maxPayout) {
      maxPayout = t.payoutTotal;
      maxPayoutTicket = t;
    }
  }
}

/// 確定済みの馬券を古い順に並べる
List<Ticket> chronological(Iterable<Ticket> tickets) {
  final list = tickets.where((t) => t.settled).toList();
  list.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
  });
  return list;
}

Totals totalsOf(Iterable<Ticket> tickets) {
  final t = Totals();
  for (final x in chronological(tickets)) {
    t.add(x);
  }
  return t;
}

/// 切り口
enum Breakdown {
  betType('券種'),
  method('買い方'),
  venue('競馬場'),
  channel('購入方法');

  const Breakdown(this.label);
  final String label;

  String keyOf(Ticket t) => switch (this) {
    Breakdown.betType => t.simple ? '簡易記録' : (t.type?.label ?? '不明'),
    Breakdown.method => t.simple ? '簡易記録' : (t.method?.label ?? '不明'),
    Breakdown.venue => t.venue,
    Breakdown.channel => t.channel.label,
  };
}

/// 切り口ごとの集計。投資額の多い順。
List<MapEntry<String, Totals>> breakdownOf(
  Iterable<Ticket> tickets,
  Breakdown by,
) {
  final map = <String, Totals>{};
  for (final t in chronological(tickets)) {
    map.putIfAbsent(by.keyOf(t), Totals.new).add(t);
  }
  return map.entries.toList()
    ..sort((a, b) => b.value.stake.compareTo(a.value.stake));
}

/// 日ごとの累積収支（古い順）
List<({DateTime date, int cumulative})> cumulativeProfit(
  Iterable<Ticket> tickets,
) {
  final byDay = <String, int>{};
  for (final t in chronological(tickets)) {
    byDay[t.date] = (byDay[t.date] ?? 0) + t.profit;
  }
  var sum = 0;
  return [
    for (final e in byDay.entries)
      (date: DateTime.parse(e.key), cumulative: sum += e.value),
  ];
}

/// 日ごとの収支
Map<String, int> dailyProfit(Iterable<Ticket> tickets) {
  final byDay = <String, int>{};
  for (final t in tickets.where((t) => t.settled)) {
    byDay[t.date] = (byDay[t.date] ?? 0) + t.profit;
  }
  return byDay;
}
