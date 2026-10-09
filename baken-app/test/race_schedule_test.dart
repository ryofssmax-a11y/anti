import 'package:baken_app/data/database.dart';
import 'package:baken_app/data/models.dart';
import 'package:baken_app/data/race_names.dart';
import 'package:baken_app/data/race_schedule.dart';
import 'package:baken_app/data/settings.dart';
import 'package:baken_app/ui/common.dart';
import 'package:baken_app/ui/week_races.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_flow_test.dart' show settle;

void main() {
  sqfliteFfiInit();

  group('重賞の日程', () {
    test('2026年の日程にある名前は、すべて重賞の一覧にある', () {
      var count = 0;
      for (
        var d = DateTime(2026, 1, 1);
        d.year == 2026;
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        for (final r in gradedRacesOn(d)) {
          expect(r.preset.grade.isGraded, isTrue, reason: r.name);
          count++;
        }
      }
      // 日程表の名前が一覧と食い違うと数が減る
      final listed = gradedRaces.length;
      expect(count, listed, reason: '重賞の一覧 $listed 件');
    });

    test('開催週は火曜〜月曜で、月曜の祝日開催も同じ週になる', () {
      final w = raceWeekOf(DateTime(2026, 10, 12)); // スワンS（祝・月）
      expect(w.start, DateTime(2026, 10, 6));
      expect(w.end, DateTime(2026, 10, 12));
      final names = gradedRacesInWeek(DateTime(2026, 10, 10))
          .map((r) => r.name);
      expect(names, ['サウジアラビアロイヤルカップ', 'アイルランドトロフィー', 'スワンステークス']);
      expect(raceDaysInWeek(DateTime(2026, 10, 7)), [
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 11),
        DateTime(2026, 10, 12),
      ]);
    });

    test('ダービーの日は、目黒記念が12R', () {
      final day = gradedRacesOn(DateTime(2026, 5, 31));
      expect(day.first.name, '東京優駿（日本ダービー）');
      expect(day.first.raceNo, 11);
      expect(day.last.raceNo, 12);
      // 障害重賞はレース番号を決めない
      expect(
        gradedRacesOn(DateTime(2026, 12, 26))
            .firstWhere((r) => r.name == '中山大障害')
            .raceNo,
        isNull,
      );
    });

    test('ほかの年は2026年の同じ週から推定する', () {
      final arima = gradedRacesOn(DateTime(2027, 12, 26));
      expect(arima.single.name, '有馬記念');
      expect(arima.single.estimated, isTrue);
      expect(gradedRacesOn(DateTime(2026, 12, 27)).single.estimated, isFalse);
    });

    test('月ごとの特別レース', () {
      final names = specialRacesInMonth(10).map((p) => p.name);
      expect(names, contains('アイビーステークス'));
      expect(names, isNot(contains('若駒ステークス')));
    });
  });

  group('画面', () {
    late AppDatabase db;
    late AppSettings settings;

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        db = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        settings = await AppSettings.load();
      });
      await tester.pumpWidget(
        AppScope(
          db: db,
          settings: settings,
          child: MaterialApp(home: child),
        ),
      );
      await settle(tester);
    }

    testWidgets('この週の重賞を選ぶ', (tester) async {
      RacePick? picked;
      await pump(
        tester,
        Scaffold(
          body: WeekRacesPanel(
            date: DateTime(2026, 11, 26),
            onPick: (p) => picked = p,
          ),
        ),
      );
      expect(find.text('ジャパンカップ'), findsOneWidget);
      expect(find.text('京都2歳ステークス'), findsOneWidget);
      await tester.tap(find.text('ジャパンカップ'));
      expect(picked!.date, DateTime(2026, 11, 29));
      expect(picked!.venue, '東京');
      expect(picked!.raceNo, 11);
      await tester.runAsync(() => db.close());
    });

    testWidgets('1R〜最終R の一覧から選ぶ', (tester) async {
      RacePick? picked;
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => picked = await showDayRaceList(
                  context,
                  date: DateTime(2026, 5, 31),
                  venue: '東京',
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => db.insertTicket(
          Ticket(
            date: '2026-05-31',
            venue: '東京',
            raceNo: 3,
            raceName: '3歳未勝利',
            simple: true,
            stakeTotal: 1000,
          ),
          race: Race(date: '2026-05-31', venue: '東京', raceNo: 3, name: '3歳未勝利'),
        ),
      );
      await tester.tap(find.text('開く'));
      await settle(tester);

      expect(find.textContaining('重賞: 東京 東京優駿'), findsOneWidget);
      expect(find.text('3歳未勝利'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('東京優駿（日本ダービー）'), 200);
      await tester.scrollUntilVisible(find.text('目黒記念'), 200);
      expect(find.textContaining('最終'), findsWidgets);
      await tester.tap(find.text('目黒記念'));
      await settle(tester);
      expect(picked!.raceNo, 12);
      expect(picked!.name, '目黒記念');

      // 名前の分からないレースは番号だけ
      await tester.tap(find.text('開く'));
      await settle(tester);
      await tester.tap(find.text('1R'));
      await settle(tester);
      expect(picked!.raceNo, 1);
      expect(picked!.name, isNull);
      await tester.runAsync(() => db.close());
    });
  });
}
