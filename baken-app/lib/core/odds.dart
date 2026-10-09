/// 合成オッズ・トリガミ判定・資金配分。
///
/// 金額はすべて円の整数、購入単位は100円。
library;

const int unit = 100;

int floorToUnit(num yen) => (yen ~/ unit) * unit;
int ceilToUnit(num yen) => ((yen + unit - 1) ~/ unit) * unit;

/// 合成オッズ = 1 / Σ(1 / オッズ)。オッズが空または不正なら null。
double? syntheticOdds(List<double> odds) {
  if (odds.isEmpty || odds.any((o) => o <= 0)) return null;
  final sum = odds.fold<double>(0, (s, o) => s + 1 / o);
  return 1 / sum;
}

/// 払戻見込み（円）
int expectedPayout(int stake, double odds) => (stake * odds).floor();

/// 当たっても合計金額を下回る買い目か
bool isTorigami(int stake, double odds, int totalStake) =>
    stake > 0 && expectedPayout(stake, odds) < totalStake;

/// 均等払戻: どれが当たっても払戻がほぼ同じになるよう [total] を配分する。
///
/// 各買い目に floor100(total × 合成オッズ ÷ オッズ) を割り当て、
/// 余りは払戻見込みが最も小さい買い目から100円ずつ足す。
List<int> allocateEqualPayout(int total, List<double> odds) {
  final s = syntheticOdds(odds);
  if (s == null || total < unit) return List.filled(odds.length, 0);
  final stakes = [for (final o in odds) floorToUnit(total * s / o)];
  var remainder = floorToUnit(total) - stakes.fold<int>(0, (a, b) => a + b);
  while (remainder >= unit) {
    var minIdx = 0;
    var minPay = double.infinity;
    for (var i = 0; i < odds.length; i++) {
      final pay = stakes[i] * odds[i];
      if (pay < minPay) {
        minPay = pay;
        minIdx = i;
      }
    }
    stakes[minIdx] += unit;
    remainder -= unit;
  }
  return stakes;
}

/// 目標払戻: どれが当たっても [target] 円以上戻るように配分する。
List<int> allocateTargetPayout(int target, List<double> odds) => [
  for (final o in odds) o > 0 ? ceilToUnit(target / o) : 0,
];

/// 傾斜配分: 重みに比例して [total] を配分する。余りは重みの大きい順に100円ずつ。
List<int> allocateWeighted(int total, List<int> weights) {
  final sum = weights.fold<int>(0, (a, b) => a + b);
  if (sum <= 0 || total < unit) return List.filled(weights.length, 0);
  final stakes = [for (final w in weights) floorToUnit(total * w / sum)];
  var remainder = floorToUnit(total) - stakes.fold<int>(0, (a, b) => a + b);
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) => weights[b].compareTo(weights[a]));
  var k = 0;
  while (remainder >= unit && order.isNotEmpty) {
    final i = order[k % order.length];
    if (weights[i] > 0) {
      stakes[i] += unit;
      remainder -= unit;
    }
    k++;
  }
  return stakes;
}
