import 'bet_type.dart';
import 'selection.dart';

/// 払戻金の読み取り結果
class ParsedPayouts {
  ParsedPayouts(this.payouts);

  /// 券種 → 組み合わせのキー（Combination.key）→ 100円あたりの払戻金
  final Map<BetType, Map<String, int>> payouts;

  bool get isEmpty => payouts.values.every((m) => m.isEmpty);
  int get count => payouts.values.fold(0, (s, m) => s + m.length);

  /// 3連単の組み合わせが1つだけなら、そこから1〜3着を出す（同着のときは出さない）
  Map<int, List<int>>? get placings {
    final tri = payouts[BetType.trifecta];
    if (tri == null || tri.length != 1) return null;
    final nums = tri.keys.single.split('-').map(int.parse).toList();
    return {
      1: [nums[0]],
      2: [nums[1]],
      3: [nums[2]],
    };
  }
}

/// 券種名の書き方（長いものを先に）
const _typeWords = <String, BetType?>{
  '３連単': BetType.trifecta,
  '3連単': BetType.trifecta,
  '三連単': BetType.trifecta,
  '３連複': BetType.trio,
  '3連複': BetType.trio,
  '三連複': BetType.trio,
  'ワイド': BetType.wide,
  '馬単': BetType.exacta,
  '馬連': BetType.quinella,
  '枠連': BetType.bracketQuinella,
  '枠単': null, // 地方の枠単は対象外（読み飛ばす）
  '複勝': BetType.place,
  '単勝': BetType.win,
  'WIN5': null,
};

/// 全角の数字・記号を半角にそろえる
String _halfWidth(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF10 && r <= 0xFF19) {
      buf.writeCharCode(r - 0xFEE0); // ０-９
    } else if (r == 0xFF0C) {
      buf.write(','); // ，
    } else {
      buf.writeCharCode(r);
    }
  }
  return buf.toString();
}

/// JRA や競馬サイトの「払戻金」の表をコピーした文字から、払戻金を読み取る。
///
/// 次のような書き方に対応する。
///   単勝 7 1,250円 4番人気
///   馬単 7-3 3,980円 / 馬単 7 → 3 3,980円
///   複勝 7 3 12 280円 150円 330円（番号と金額が別々に並ぶ形）
ParsedPayouts parsePayoutText(String text) {
  var s = _halfWidth(text);
  // 人気の数字は番号と紛らわしいので先に消す
  s = s.replaceAll(RegExp(r'\d+\s*番?人気'), ' ');
  s = s.replaceAll(RegExp(r'[（(]\s*\d+\s*[)）]'), ' ');

  final keyword = RegExp(_typeWords.keys.map(RegExp.escape).join('|'));
  final marks = keyword.allMatches(s).toList();
  final out = <BetType, Map<String, int>>{};

  for (var i = 0; i < marks.length; i++) {
    final type = _typeWords[marks[i].group(0)];
    final end = i + 1 < marks.length ? marks[i + 1].start : s.length;
    if (type == null) continue;
    final segment = s.substring(marks[i].end, end);
    final found = _parseSegment(type, segment);
    if (found.isNotEmpty) {
      (out[type] ??= {}).addAll(found);
    }
  }
  return ParsedPayouts(out);
}

Map<String, int> _parseSegment(BetType type, String segment) {
  const sep = r'\s*[-－‐ー−→>＞=＝]\s*';
  const num = r'\d{1,2}';
  final combo = type.size == 1
      ? '(?<![\\d,])$num(?![\\d,])'
      : '$num(?:$sep$num){${type.size - 1}}';
  // 金額は「円」つき、またはカンマ区切りのもの。金額を先に読んで番号と取り違えないようにする
  final token = RegExp(
    '(?<amount>\\d{1,3}(?:,\\d{3})+\\s*円?|\\d+\\s*円)|(?<combo>$combo)',
  );

  final combos = <List<int>>[];
  final amounts = <int>[];
  for (final m in token.allMatches(segment)) {
    final a = m.namedGroup('amount');
    if (a != null) {
      amounts.add(int.parse(a.replaceAll(RegExp(r'[^\d]'), '')));
      continue;
    }
    final nums = RegExp(r'\d+')
        .allMatches(m.namedGroup('combo')!)
        .map((x) => int.parse(x.group(0)!))
        .toList();
    final max = type.usesFrames ? 8 : 18;
    if (nums.every((n) => n >= 1 && n <= max)) combos.add(nums);
  }

  // 番号と金額を出てきた順に組にする（人気などの余分な数字は後ろに来るので切り捨てる）
  final out = <String, int>{};
  for (var i = 0; i < combos.length && i < amounts.length; i++) {
    if (amounts[i] < 100) continue;
    out[Combination(combos[i], ordered: type.ordered).key] = amounts[i];
  }
  return out;
}
