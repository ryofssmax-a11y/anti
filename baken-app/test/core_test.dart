import 'package:baken_app/core/bet_type.dart';
import 'package:baken_app/core/expander.dart';
import 'package:baken_app/core/judge.dart';
import 'package:baken_app/core/odds.dart';
import 'package:baken_app/core/selection.dart';
import 'package:flutter_test/flutter_test.dart';

Set<int> r(int from, int to) => {for (var i = from; i <= to; i++) i};

int count(Selection s) => expand(s).length;

Selection box(BetType t, int n) =>
    Selection(type: t, method: BetMethod.box, columns: [r(1, n)]);

Selection nagashi(BetType t, AxisMode mode, List<int> axes, int partners) =>
    Selection(
      type: t,
      method: BetMethod.nagashi,
      axisCount: axes.length,
      axisMode: mode,
      columns: [
        for (final a in axes) {a},
        r(11, 10 + partners),
      ],
    );

void main() {
  group('点数（仕様書の計算式と照合）', () {
    for (var n = 2; n <= 18; n++) {
      test('ボックス $n頭', () {
        expect(count(box(BetType.quinella, n)), n * (n - 1) ~/ 2);
        expect(count(box(BetType.wide, n)), n * (n - 1) ~/ 2);
        expect(count(box(BetType.exacta, n)), n * (n - 1));
        if (n >= 3) {
          expect(count(box(BetType.trio, n)), n * (n - 1) * (n - 2) ~/ 6);
          expect(count(box(BetType.trifecta, n)), n * (n - 1) * (n - 2));
        }
      });
    }

    test('3連単18頭ボックスは4,896点', () {
      expect(count(box(BetType.trifecta, 18)), 4896);
    });

    test('枠連ボックスはゾロ目を含まない', () {
      final s = Selection(
        type: BetType.bracketQuinella,
        method: BetMethod.box,
        columns: [r(1, 5)],
      );
      expect(count(s), 10);
    });

    for (var k = 2; k <= 7; k++) {
      test('ながし 相手$k頭', () {
        expect(count(nagashi(BetType.quinella, AxisMode.any, [1], k)), k);
        expect(count(nagashi(BetType.wide, AxisMode.any, [1], k)), k);
        expect(count(nagashi(BetType.exacta, AxisMode.first, [1], k)), k);
        expect(count(nagashi(BetType.exacta, AxisMode.second, [1], k)), k);
        expect(count(nagashi(BetType.exacta, AxisMode.multi, [1], k)), 2 * k);
        expect(
          count(nagashi(BetType.trio, AxisMode.any, [1], k)),
          k * (k - 1) ~/ 2,
        );
        expect(count(nagashi(BetType.trio, AxisMode.any, [1, 2], k)), k);
        for (final m in [AxisMode.first, AxisMode.second, AxisMode.third]) {
          expect(count(nagashi(BetType.trifecta, m, [1], k)), k * (k - 1));
        }
        expect(
          count(nagashi(BetType.trifecta, AxisMode.multi, [1], k)),
          3 * k * (k - 1),
        );
        for (final m in [
          AxisMode.firstSecond,
          AxisMode.firstThird,
          AxisMode.secondThird,
        ]) {
          expect(count(nagashi(BetType.trifecta, m, [1, 2], k)), k);
        }
        expect(
          count(nagashi(BetType.trifecta, AxisMode.multi, [1, 2], k)),
          6 * k,
        );
      });
    }

    test('ながしの相手に軸と同じ馬が入っても数えない', () {
      final s = Selection(
        type: BetType.quinella,
        method: BetMethod.nagashi,
        columns: [
          {1},
          {1, 2, 3},
        ],
      );
      expect(count(s), 2);
    });

    test('3連単ながし 1着軸の並び', () {
      final s = nagashi(BetType.trifecta, AxisMode.first, [5], 3);
      expect(expand(s).map((c) => c.key), contains('5-11-12'));
      expect(expand(s).every((c) => c.numbers.first == 5), isTrue);
    });

    test('フォーメーションは重複と並び違いを除く', () {
      final tri = Selection(
        type: BetType.trifecta,
        method: BetMethod.formation,
        columns: [
          {1, 2},
          {1, 2, 3},
          {1, 2, 3, 4},
        ],
      );
      // 1着1→2着{2,3}→3着は残り2頭ずつ = 4、1着2も同様に4
      expect(count(tri), 8);

      final trio = Selection(
        type: BetType.trio,
        method: BetMethod.formation,
        columns: [
          {1, 2},
          {1, 2, 3},
          {1, 2, 3, 4},
        ],
      );
      expect(expand(trio).map((c) => c.key).toSet(), {
        '1-2-3',
        '1-2-4',
        '1-3-4',
        '2-3-4',
      });
    });

    test('WIN5 は各レースの選択頭数の積', () {
      final s = Selection(
        type: BetType.win5,
        method: BetMethod.formation,
        columns: [r(1, 2), r(1, 3), r(1, 1), r(1, 2), r(1, 4)],
      );
      expect(count(s), 48);
    });

    test('通常は1点', () {
      final s = Selection(
        type: BetType.trifecta,
        method: BetMethod.normal,
        columns: [
          {3},
          {7},
          {12},
        ],
      );
      expect(expand(s).single.key, '3-7-12');
    });

    test('単勝・複勝は選んだ頭数ぶん', () {
      final s = Selection(
        type: BetType.place,
        method: BetMethod.normal,
        columns: [
          {1, 4, 9},
        ],
      );
      expect(count(s), 3);
    });

    test('取消馬を含む買い目を除く', () {
      final s = Selection(
        type: BetType.quinella,
        method: BetMethod.box,
        columns: [r(1, 5)],
        scratched: {3},
      );
      expect(count(s), 6);
    });

    test('列が空なら0点', () {
      expect(
        count(Selection(type: BetType.trio, method: BetMethod.formation)),
        0,
      );
    });
  });

  group('枠番', () {
    test('8頭以下は馬番と同じ', () {
      expect(horsesPerFrame(6), [1, 1, 1, 1, 1, 1, 0, 0]);
      expect(frameOf(6, 6), 6);
    });

    test('18頭は7枠と8枠が3頭', () {
      expect(horsesPerFrame(18), [2, 2, 2, 2, 2, 2, 3, 3]);
      expect(frameOf(1, 18), 1);
      expect(frameOf(13, 18), 7);
      expect(frameOf(15, 18), 7);
      expect(frameOf(16, 18), 8);
      expect(frameOf(18, 18), 8);
    });

    test('枠連ゾロ目は2頭以上いる枠だけ', () {
      final s = Selection(
        type: BetType.bracketQuinella,
        method: BetMethod.formation,
        fieldSize: 9,
        columns: [
          {1, 8},
          {1, 8},
        ],
      );
      // 9頭立ては8枠だけ2頭。1-1 は無効、8-8 と 1-8 は有効
      expect(expand(s).map((c) => c.key).toSet(), {'1-8', '8-8'});
    });
  });

  group('合成オッズと資金配分', () {
    test('合成オッズ', () {
      expect(syntheticOdds([2, 2])!, closeTo(1.0, 1e-9));
      expect(syntheticOdds([3, 6])!, closeTo(2.0, 1e-9));
      expect(syntheticOdds([]), isNull);
      expect(syntheticOdds([0, 2]), isNull);
    });

    test('均等払戻は予算を使い切り、払戻の差が小さい', () {
      final odds = [3.0, 6.0, 12.5];
      final stakes = allocateEqualPayout(10000, odds);
      expect(stakes.fold<int>(0, (a, b) => a + b), 10000);
      expect(stakes.every((s) => s % 100 == 0), isTrue);
      final pays = [for (var i = 0; i < 3; i++) stakes[i] * odds[i]];
      final spread =
          pays.reduce((a, b) => a > b ? a : b) -
          pays.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThanOrEqualTo(100 * 12.5));
    });

    test('目標払戻は100円単位で切り上げ', () {
      expect(allocateTargetPayout(5000, [3.0, 7.0]), [1700, 800]);
    });

    test('傾斜配分', () {
      final stakes = allocateWeighted(6000, [3, 2, 1]);
      expect(stakes, [3000, 2000, 1000]);
      expect(
        allocateWeighted(1000, [1, 1, 1]).fold<int>(0, (a, b) => a + b),
        1000,
      );
    });

    test('トリガミ判定', () {
      expect(isTorigami(100, 2.5, 300), isTrue);
      expect(isTorigami(100, 3.0, 300), isFalse);
    });
  });

  group('的中判定', () {
    final normal = RaceOutcome(
      fieldSize: 16,
      placings: {
        1: [7],
        2: [3],
        3: [12],
      },
    );

    Combination c(List<int> n, BetType t) => Combination(n, ordered: t.ordered);

    test('通常の決着', () {
      expect(judge(BetType.win, c([7], BetType.win), normal), LineStatus.hit);
      expect(judge(BetType.win, c([3], BetType.win), normal), LineStatus.miss);
      expect(
        judge(BetType.place, c([12], BetType.place), normal),
        LineStatus.hit,
      );
      expect(
        judge(BetType.quinella, c([3, 7], BetType.quinella), normal),
        LineStatus.hit,
      );
      expect(
        judge(BetType.exacta, c([7, 3], BetType.exacta), normal),
        LineStatus.hit,
      );
      expect(
        judge(BetType.exacta, c([3, 7], BetType.exacta), normal),
        LineStatus.miss,
      );
      expect(
        judge(BetType.wide, c([7, 12], BetType.wide), normal),
        LineStatus.hit,
      );
      expect(
        judge(BetType.wide, c([7, 1], BetType.wide), normal),
        LineStatus.miss,
      );
      expect(
        judge(BetType.trio, c([12, 3, 7], BetType.trio), normal),
        LineStatus.hit,
      );
      expect(
        judge(BetType.trifecta, c([7, 3, 12], BetType.trifecta), normal),
        LineStatus.hit,
      );
      expect(
        judge(BetType.trifecta, c([3, 7, 12], BetType.trifecta), normal),
        LineStatus.miss,
      );
      // 16頭立て: 7番=4枠, 3番=2枠
      expect(
        judge(
          BetType.bracketQuinella,
          c([2, 4], BetType.bracketQuinella),
          normal,
        ),
        LineStatus.hit,
      );
    });

    test('1着同着', () {
      final dh = RaceOutcome(
        fieldSize: 12,
        placings: {
          1: [2, 5],
          3: [8],
        },
      );
      expect(judge(BetType.win, c([2], BetType.win), dh), LineStatus.hit);
      expect(judge(BetType.win, c([5], BetType.win), dh), LineStatus.hit);
      expect(
        judge(BetType.exacta, c([2, 5], BetType.exacta), dh),
        LineStatus.hit,
      );
      expect(
        judge(BetType.exacta, c([5, 2], BetType.exacta), dh),
        LineStatus.hit,
      );
      expect(
        judge(BetType.trifecta, c([5, 2, 8], BetType.trifecta), dh),
        LineStatus.hit,
      );
    });

    test('3着同着はワイド・複勝・3連複が複数的中', () {
      final dh = RaceOutcome(
        fieldSize: 10,
        placings: {
          1: [1],
          2: [2],
          3: [3, 4],
        },
      );
      expect(judge(BetType.place, c([4], BetType.place), dh), LineStatus.hit);
      expect(judge(BetType.wide, c([1, 4], BetType.wide), dh), LineStatus.hit);
      expect(
        judge(BetType.trio, c([1, 2, 3], BetType.trio), dh),
        LineStatus.hit,
      );
      expect(
        judge(BetType.trio, c([1, 2, 4], BetType.trio), dh),
        LineStatus.hit,
      );
      expect(
        judge(BetType.trio, c([1, 3, 4], BetType.trio), dh),
        LineStatus.miss,
      );
    });

    test('7頭立ての複勝は2着まで', () {
      final small = RaceOutcome(
        fieldSize: 7,
        placings: {
          1: [1],
          2: [2],
          3: [3],
        },
      );
      expect(
        judge(BetType.place, c([3], BetType.place), small),
        LineStatus.miss,
      );
      expect(
        judge(BetType.place, c([2], BetType.place), small),
        LineStatus.hit,
      );
    });

    test('取消馬を含む買い目は返還', () {
      final out = RaceOutcome(
        fieldSize: 16,
        placings: {
          1: [7],
          2: [3],
          3: [12],
        },
        scratched: {5},
      );
      expect(
        judge(BetType.quinella, c([5, 7], BetType.quinella), out),
        LineStatus.refund,
      );
    });

    test('結果のJSON往復', () {
      final back = RaceOutcome.fromJson(normal.toJson());
      expect(back.placings, normal.placings);
      expect(back.fieldSize, 16);
    });
  });

  test('選択内容のJSON往復', () {
    final s = nagashi(BetType.trifecta, AxisMode.multi, [1, 2], 4);
    final back = Selection.fromJson(s.toJson())!;
    expect(expand(back).length, expand(s).length);
    expect(back.axisMode, AxisMode.multi);
  });
}
