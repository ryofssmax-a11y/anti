import 'bet_type.dart';
import 'selection.dart';

/// レースの確定着順（1〜3着）。同着は同じ着順に複数頭を入れる。
class RaceOutcome {
  RaceOutcome({
    required this.fieldSize,
    required Map<int, List<int>> placings,
    Set<int>? scratched,
  }) : placings = {
         for (final e in placings.entries)
           if (e.value.isNotEmpty) e.key: ([...e.value]..sort()),
       },
       scratched = scratched ?? {};

  final int fieldSize;

  /// 着順 → 馬番
  final Map<int, List<int>> placings;

  /// 取消・除外の馬番
  final Set<int> scratched;

  bool get isComplete => placings.containsKey(1);

  /// 複勝の対象になる着順の範囲（8頭以上は3着まで、5〜7頭は2着まで、4頭以下は発売なし）
  int get placeDepth => fieldSize >= 8
      ? 3
      : fieldSize >= 5
      ? 2
      : 0;

  /// 同着を並べ替えて考えられる上位の並び（最大3頭）をすべて返す。
  List<List<int>> finishingOrders() {
    final ranks = placings.keys.toList()..sort();
    var orders = <List<int>>[[]];
    for (final r in ranks) {
      if (orders.first.length >= 3) break;
      final group = placings[r]!;
      final next = <List<int>>[];
      for (final o in orders) {
        for (final perm in _permutations(group)) {
          next.add([...o, ...perm]);
        }
      }
      orders = next;
    }
    return [for (final o in orders) o.length > 3 ? o.sublist(0, 3) : o];
  }

  Map<String, Object?> toJson() => {
    'fieldSize': fieldSize,
    'placings': {for (final e in placings.entries) '${e.key}': e.value},
    'scratched': scratched.toList()..sort(),
  };

  static RaceOutcome fromJson(Map<String, Object?> json) => RaceOutcome(
    fieldSize: (json['fieldSize'] as num?)?.toInt() ?? 18,
    placings: {
      for (final e in ((json['placings'] as Map?) ?? {}).entries)
        int.parse(e.key as String): (e.value as List)
            .map((n) => (n as num).toInt())
            .toList(),
    },
    scratched: ((json['scratched'] as List?) ?? [])
        .map((n) => (n as num).toInt())
        .toSet(),
  );
}

List<List<int>> _permutations(List<int> items) {
  if (items.length <= 1) return [List.of(items)];
  final out = <List<int>>[];
  for (var i = 0; i < items.length; i++) {
    final rest = [...items]..removeAt(i);
    for (final p in _permutations(rest)) {
      out.add([items[i], ...p]);
    }
  }
  return out;
}

/// 判定結果
enum LineStatus { hit, miss, refund }

/// 買い目1点の的中を判定する。WIN5 はこのアプリでは手動判定。
LineStatus judge(BetType type, Combination c, RaceOutcome r) {
  final nums = c.numbers;

  if (!type.usesFrames &&
      type != BetType.win5 &&
      nums.any(r.scratched.contains)) {
    return LineStatus.refund;
  }
  if (type.usesFrames) {
    // 枠連は、その枠の馬がすべて取消のときだけ返還
    final counts = horsesPerFrame(r.fieldSize);
    for (final f in nums) {
      final horses = [
        for (var h = 1; h <= r.fieldSize; h++)
          if (frameOf(h, r.fieldSize) == f) h,
      ];
      if (horses.isNotEmpty &&
          horses.every(r.scratched.contains) &&
          counts[f - 1] > 0) {
        return LineStatus.refund;
      }
    }
  }

  final orders = r.finishingOrders();
  bool any(bool Function(List<int> o) test) => orders.any(test);

  final hit = switch (type) {
    BetType.win => any((o) => o.isNotEmpty && o[0] == nums[0]),
    BetType.place =>
      r.placeDepth > 0 && any((o) => o.take(r.placeDepth).contains(nums[0])),
    BetType.quinella => any(
      (o) => o.length >= 2 && _sameSet(o.sublist(0, 2), nums),
    ),
    BetType.exacta => any(
      (o) => o.length >= 2 && o[0] == nums[0] && o[1] == nums[1],
    ),
    BetType.wide => any(
      (o) => o.length >= 3 && o.take(3).toSet().containsAll(nums),
    ),
    BetType.trio => any(
      (o) => o.length >= 3 && _sameSet(o.sublist(0, 3), nums),
    ),
    BetType.trifecta => any(
      (o) =>
          o.length >= 3 &&
          o[0] == nums[0] &&
          o[1] == nums[1] &&
          o[2] == nums[2],
    ),
    BetType.bracketQuinella => any(
      (o) =>
          o.length >= 2 &&
          _sameSet([
            frameOf(o[0], r.fieldSize),
            frameOf(o[1], r.fieldSize),
          ], nums),
    ),
    BetType.win5 => false,
  };
  return hit ? LineStatus.hit : LineStatus.miss;
}

bool _sameSet(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  final x = [...a]..sort();
  final y = [...b]..sort();
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
