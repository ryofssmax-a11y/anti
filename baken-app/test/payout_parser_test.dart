import 'package:baken_app/core/bet_type.dart';
import 'package:baken_app/core/payout_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JRA の払戻金の表（タブ区切り・人気つき）', () {
    const text = '''
単勝	7	1,250円	4番人気
複勝	7	280円	4番人気
3	150円	1番人気
12	330円	6番人気
枠連	2-4	1,020円	3番人気
ワイド	3-7	450円	3番人気
7-12	1,300円	15番人気
3-12	720円	8番人気
馬連	3-7	1,640円	5番人気
馬単	7-3	3,980円	14番人気
3連複	3-7-12	5,670円	18番人気
3連単	7-3-12	38,450円	121番人気
''';
    final p = parsePayoutText(text);
    expect(p.payouts[BetType.win], {'7': 1250});
    expect(p.payouts[BetType.place], {'7': 280, '3': 150, '12': 330});
    expect(p.payouts[BetType.bracketQuinella], {'2-4': 1020});
    expect(p.payouts[BetType.wide], {'3-7': 450, '7-12': 1300, '3-12': 720});
    expect(p.payouts[BetType.quinella], {'3-7': 1640});
    expect(p.payouts[BetType.exacta], {'7-3': 3980});
    expect(p.payouts[BetType.trio], {'3-7-12': 5670});
    expect(p.payouts[BetType.trifecta], {'7-3-12': 38450});
    expect(p.count, 12);
    expect(p.placings, {
      1: [7],
      2: [3],
      3: [12],
    });
  });

  test('番号と金額が別々に並ぶ形・矢印・人気が数字だけ', () {
    const text = '''
単勝 7 1,250円 4
複勝 7
3
12 280円
150円
330円 4
1
6
馬単 7 → 3 3,980円 14
3連単 7 → 3 → 12 38,450円 121
''';
    final p = parsePayoutText(text);
    expect(p.payouts[BetType.win], {'7': 1250});
    expect(p.payouts[BetType.place], {'7': 280, '3': 150, '12': 330});
    expect(p.payouts[BetType.exacta], {'7-3': 3980});
    expect(p.payouts[BetType.trifecta], {'7-3-12': 38450});
  });

  test('全角数字と順不同の券種は並べ替える', () {
    final p = parsePayoutText('馬連　７－３　１，６４０円\n３連複　１２－７－３　５，６７０円');
    expect(p.payouts[BetType.quinella], {'3-7': 1640});
    expect(p.payouts[BetType.trio], {'3-7-12': 5670});
  });

  test('同着で3連単が2つあるときは着順を決めない', () {
    final p = parsePayoutText('3連単 7-3-12 38,450円 3-7-12 41,200円');
    expect(p.payouts[BetType.trifecta], hasLength(2));
    expect(p.placings, isNull);
  });

  test('関係のない文字は空', () {
    expect(parsePayoutText('今日はいい天気').isEmpty, isTrue);
  });
}
