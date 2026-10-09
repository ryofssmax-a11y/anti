import 'bet_type.dart';
import 'selection.dart';

/// 選択内容を買い目1点ずつに展開する。
///
/// 点数は公式ではなく、ここで展開した件数を正とする。
List<Combination> expand(Selection s) {
  final type = s.type;
  final cols = s.columns;
  if (cols.any((c) => c.isEmpty)) return const [];

  final List<List<Set<int>>> patterns;
  var allowSame = type.usesFrames;

  if (type.isSingle) {
    final horses = cols[0].toList()..sort();
    return [
      for (final h in horses)
        if (!s.scratched.contains(h)) Combination([h], ordered: true),
    ];
  }

  switch (s.method) {
    case BetMethod.normal:
    case BetMethod.formation:
      patterns = [cols];
    case BetMethod.box:
      allowSame = false;
      patterns = [List.filled(type.size, cols[0])];
    case BetMethod.nagashi:
      patterns = _nagashiPatterns(s);
  }

  final frameCounts = horsesPerFrame(s.fieldSize);
  final seen = <String>{};
  final out = <Combination>[];
  for (final pattern in patterns) {
    _product(pattern, 0, <int>[], (picked) {
      if (type != BetType.win5) {
        if (!_validRepeats(picked, allowSame, frameCounts)) return;
        if (!type.usesFrames && picked.any(s.scratched.contains)) return;
      }
      final combo = Combination(picked, ordered: type.ordered);
      if (seen.add(combo.key)) out.add(combo);
    });
  }
  out.sort(_compare);
  return out;
}

int _compare(Combination a, Combination b) {
  for (var i = 0; i < a.numbers.length && i < b.numbers.length; i++) {
    final c = a.numbers[i].compareTo(b.numbers[i]);
    if (c != 0) return c;
  }
  return a.numbers.length.compareTo(b.numbers.length);
}

/// 同じ番号が2回入る組み合わせを除く。枠連のゾロ目はその枠に2頭以上いるときだけ有効。
bool _validRepeats(List<int> picked, bool allowSame, List<int> frameCounts) {
  final counts = <int, int>{};
  for (final n in picked) {
    counts[n] = (counts[n] ?? 0) + 1;
  }
  for (final e in counts.entries) {
    if (e.value < 2) continue;
    if (!allowSame) return false;
    if (e.value > 2) return false;
    final idx = e.key - 1;
    if (idx < 0 || idx >= 8 || frameCounts[idx] < 2) return false;
  }
  return true;
}

void _product(
  List<Set<int>> cols,
  int i,
  List<int> acc,
  void Function(List<int>) emit,
) {
  if (i == cols.length) {
    emit(List.of(acc));
    return;
  }
  final values = cols[i].toList()..sort();
  for (final v in values) {
    acc.add(v);
    _product(cols, i + 1, acc, emit);
    acc.removeLast();
  }
}

List<List<Set<int>>> _nagashiPatterns(Selection s) {
  final type = s.type;
  final axes = s.columns.sublist(0, s.axisCount);
  final partners = s.columns.last;

  if (!type.ordered) {
    // 馬連・ワイド・枠連・3連複: 軸と相手の組み合わせ（並び順は問わない）
    return [
      [...axes, for (var i = s.axisCount; i < type.size; i++) partners],
    ];
  }

  if (type == BetType.exacta) {
    final a = axes[0];
    return switch (s.axisMode) {
      AxisMode.second => [
        [partners, a],
      ],
      AxisMode.multi => [
        [a, partners],
        [partners, a],
      ],
      _ => [
        [a, partners],
      ],
    };
  }

  // 3連単
  if (s.axisCount == 1) {
    final a = axes[0];
    final first = [a, partners, partners];
    final second = [partners, a, partners];
    final third = [partners, partners, a];
    return switch (s.axisMode) {
      AxisMode.second => [second],
      AxisMode.third => [third],
      AxisMode.multi => [first, second, third],
      _ => [first],
    };
  }

  final a1 = axes[0];
  final a2 = axes[1];
  return switch (s.axisMode) {
    AxisMode.firstThird => [
      [a1, partners, a2],
    ],
    AxisMode.secondThird => [
      [partners, a1, a2],
    ],
    AxisMode.multi => [
      [a1, a2, partners],
      [a2, a1, partners],
      [a1, partners, a2],
      [a2, partners, a1],
      [partners, a1, a2],
      [partners, a2, a1],
    ],
    _ => [
      [a1, a2, partners],
    ],
  };
}

/// 買い目を人が読める形に整える（例: 馬連 3-7）
String formatCombination(BetType type, Combination c) {
  final sep = type.ordered ? '→' : '-';
  return c.numbers.join(type == BetType.win5 ? '/' : sep);
}
