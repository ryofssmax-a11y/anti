import '../core/bet_type.dart';
import '../core/expander.dart';
import '../core/selection.dart';
import 'models.dart';

/// レース結果 1件（レースと、100円あたりの払戻金）
typedef RaceResult = ({Race race, Map<String, int> payouts});

/// 払戻金 1つ分
class PayoutEntry {
  const PayoutEntry(this.type, this.combo, this.yen);

  final BetType type;

  /// 組み合わせのキー（例: 3-7、7-3-12）
  final String combo;

  /// 100円あたりの払戻金
  final int yen;

  /// 表示用の組み合わせ（馬単・3連単は →）
  String get label =>
      formatCombination(type, Combination.parse(combo, ordered: type.ordered));

  /// 万馬券（100円が1万円以上）
  bool get big => yen >= 10000;
}

/// 払戻金を、券種の順（単勝→3連単）に並べる。
///
/// 複勝・ワイドのように同じ券種が複数あるときは、[placings]（着順）があれば
/// 結果ページと同じく着順の順に、なければ払戻金の安い順に並べる。
List<PayoutEntry> orderedPayouts(
  Map<String, int> payouts, {
  Map<int, List<int>>? placings,
}) {
  final out = <PayoutEntry>[];
  payouts.forEach((key, yen) {
    final i = key.indexOf('|');
    if (i < 0) return;
    final type = BetType.fromName(key.substring(0, i));
    if (type == null) return;
    out.add(PayoutEntry(type, key.substring(i + 1), yen));
  });
  int rank(int horse) {
    for (final e in placings?.entries ?? const <MapEntry<int, List<int>>>[]) {
      if (e.value.contains(horse)) return e.key;
    }
    return 99;
  }

  List<int> ranks(PayoutEntry e) =>
      Combination.parse(e.combo, ordered: true).numbers.map(rank).toList()
        ..sort();
  out.sort((a, b) {
    final t = a.type.index.compareTo(b.type.index);
    if (t != 0) return t;
    if (placings != null && !a.type.usesFrames) {
      final ra = ranks(a), rb = ranks(b);
      for (var i = 0; i < ra.length && i < rb.length; i++) {
        final c = ra[i].compareTo(rb[i]);
        if (c != 0) return c;
      }
    }
    return a.yen.compareTo(b.yen);
  });
  return out;
}

/// 1〜3着を「7 → 3 → 12」の形にする（同着は 7・3）
String placingText(Race race) {
  final p = race.outcome?.placings;
  if (p == null) return '';
  return [
    for (var r = 1; r <= 3; r++)
      if (p[r] != null && p[r]!.isNotEmpty) p[r]!.join('・'),
  ].join(' → ');
}

/// 券種ごとの集計
class PayoutStat {
  PayoutStat(this.type);

  final BetType type;

  /// 払戻金が入っているレースの数
  int races = 0;

  /// 払戻金の件数（複勝・ワイドは1レース3件など）
  int count = 0;
  int total = 0;
  int max = 0;

  /// 万馬券の件数
  int big = 0;

  int get average => count == 0 ? 0 : total ~/ count;
}

/// 蓄積したレース結果から、券種ごとの平均・最高払戻金を出す
List<PayoutStat> payoutStats(Iterable<RaceResult> results) {
  final stats = {for (final t in BetType.values) t: PayoutStat(t)};
  for (final r in results) {
    final seen = <BetType>{};
    for (final e in orderedPayouts(r.payouts)) {
      final s = stats[e.type]!;
      s.count++;
      s.total += e.yen;
      if (e.yen > s.max) s.max = e.yen;
      if (e.big) s.big++;
      if (seen.add(e.type)) s.races++;
    }
  }
  return [
    for (final s in stats.values)
      if (s.count > 0) s,
  ];
}

/// 検索（レース名・競馬場・日付の一部）
bool matchesResult(RaceResult r, String query) {
  final q = query.trim();
  if (q.isEmpty) return true;
  final race = r.race;
  return [
    race.name ?? '',
    race.venue,
    race.date,
    '${race.venue}${race.raceNo}R',
  ].any((s) => s.contains(q));
}

String _csvCell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// レース結果を CSV にする（表計算ソフトで見る用）
String raceResultsToCsv(Iterable<RaceResult> results) {
  const types = [
    BetType.win,
    BetType.place,
    BetType.bracketQuinella,
    BetType.quinella,
    BetType.wide,
    BetType.exacta,
    BetType.trio,
    BetType.trifecta,
  ];
  final head = [
    '日付',
    '競馬場',
    'R',
    'レース名',
    'コース',
    '距離',
    '頭数',
    '1着',
    '2着',
    '3着',
    '取消',
    for (final t in types) t.label,
  ];
  final lines = [head.join(',')];
  for (final r in results) {
    final race = r.race;
    final p = race.outcome?.placings ?? const {};
    final entries = orderedPayouts(r.payouts, placings: p);
    String cell(BetType t) => entries
        .where((e) => e.type == t)
        .map((e) => '${e.label}:${e.yen}')
        .join(' ');
    lines.add(
      [
        race.date,
        race.venue,
        race.raceNo,
        race.name,
        race.surface,
        race.distance,
        race.outcome?.fieldSize ?? race.fieldSize,
        for (var i = 1; i <= 3; i++) (p[i] ?? const []).join('・'),
        (race.outcome?.scratched.toList() ?? const <int>[]).join('・'),
        for (final t in types) cell(t),
      ].map(_csvCell).join(','),
    );
  }
  return '${lines.join('\n')}\n';
}
