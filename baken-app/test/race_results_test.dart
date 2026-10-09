import 'package:baken_app/core/bet_type.dart';
import 'package:baken_app/core/judge.dart';
import 'package:baken_app/core/payout_parser.dart';
import 'package:baken_app/data/database.dart';
import 'package:baken_app/data/models.dart';
import 'package:baken_app/data/race_results.dart';
import 'package:baken_app/data/settings.dart';
import 'package:baken_app/ui/common.dart';
import 'package:baken_app/ui/race_results.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_flow_test.dart' show settle, tapText;

const _table = '''
単勝 7 1,250円
複勝 7 3 12 280円 150円 330円
馬連 3-7 1,640円
3連単 7-3-12 38,450円
''';

Map<String, int> _payouts(String text) {
  final out = <String, int>{};
  parsePayoutText(text).payouts.forEach((type, m) {
    m.forEach((combo, v) => out[payoutKey(type, combo)] = v);
  });
  return out;
}

void main() {
  sqfliteFfiInit();

  group('レース結果のデータ', () {
    late AppDatabase db;

    setUp(() async {
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
    });
    tearDown(() => db.close());

    final outcome = RaceOutcome(
      fieldSize: 16,
      placings: {
        1: [7],
        2: [3],
        3: [12],
      },
    );

    test('馬券のないレースも結果として残せる', () async {
      final id = await db.upsertRace(
        Race(date: '2026-10-11', venue: '東京', raceNo: 11, name: '毎日王冠'),
      );
      await db.settleRace(id, outcome, _payouts(_table));
      final results = await db.raceResults();
      expect(results, hasLength(1));
      expect(results.single.race.name, '毎日王冠');
      expect(results.single.payouts, hasLength(6));
      expect(placingText(results.single.race), '7 → 3 → 12');
      expect(await db.raceResultCount(), 1);
    });

    test('馬券を消しても、結果を入れたレースは残る', () async {
      final ticketId = await db.insertTicket(
        Ticket(
          date: '2026-10-11',
          venue: '東京',
          raceNo: 11,
          simple: true,
          stakeTotal: 1000,
        ),
        race: Race(date: '2026-10-11', venue: '東京', raceNo: 11),
      );
      final raceId = (await db.ticketById(ticketId))!.raceId!;
      await db.settleRace(raceId, outcome, _payouts(_table));
      await db.deleteTicket(ticketId);
      expect(await db.race(raceId), isNotNull);

      // 結果を入れていないレースは、馬券と一緒に消える
      final t2 = await db.insertTicket(
        Ticket(
          date: '2026-10-11',
          venue: '京都',
          raceNo: 5,
          simple: true,
          stakeTotal: 500,
        ),
        race: Race(date: '2026-10-11', venue: '京都', raceNo: 5),
      );
      final r2 = (await db.ticketById(t2))!.raceId!;
      await db.deleteTicket(t2);
      expect(await db.race(r2), isNull);
    });

    test('払戻金の並び・集計・CSV', () {
      final payouts = _payouts(_table);
      final entries = orderedPayouts(payouts);
      expect(entries.map((e) => e.type.label).toList(), [
        '単勝',
        '複勝',
        '複勝',
        '複勝',
        '馬連',
        '3連単',
      ]);
      expect(entries.last.label, '7→3→12');
      expect(entries.last.big, isTrue);

      final race = Race(
        id: 1,
        date: '2026-10-11',
        venue: '東京',
        raceNo: 11,
        name: '毎日王冠',
        settled: true,
        outcome: outcome,
      );
      final r2 = (race: race, payouts: {payoutKey(BetType.win, '3'): 450});
      final stats = payoutStats([(race: race, payouts: payouts), r2]);
      final win = stats.firstWhere((s) => s.type == BetType.win);
      expect(win.races, 2);
      expect(win.average, (1250 + 450) ~/ 2);
      expect(win.max, 1250);
      final place = stats.firstWhere((s) => s.type == BetType.place);
      expect(place.races, 1);
      expect(place.count, 3);
      expect(stats.firstWhere((s) => s.type == BetType.trifecta).big, 1);

      final csv = raceResultsToCsv([(race: race, payouts: payouts)]);
      final lines = csv.trim().split('\n');
      expect(lines.first, startsWith('日付,競馬場,R,レース名'));
      expect(lines[1], startsWith('2026-10-11,東京,11,毎日王冠'));
      expect(lines[1], contains('7→3→12:38450'));
      // 複勝は着順の順（7 → 3 → 12）
      expect(lines[1], contains('7:280 3:150 12:330'));
      final byRank = orderedPayouts(payouts, placings: outcome.placings);
      expect(byRank.where((e) => e.type == BetType.place).map((e) => e.combo), [
        '7',
        '3',
        '12',
      ]);
    });

    test('検索', () {
      final r = (
        race: Race(date: '2026-10-11', venue: '東京', raceNo: 11, name: '毎日王冠'),
        payouts: <String, int>{},
      );
      expect(matchesResult(r, '毎日'), isTrue);
      expect(matchesResult(r, '2026-10'), isTrue);
      expect(matchesResult(r, '東京11R'), isTrue);
      expect(matchesResult(r, '京都'), isFalse);
    });
  });

  testWidgets('結果だけ記録して、レース結果の一覧で見る', (tester) async {
    // 記録画面の項目がすべて画面に収まる高さにする
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    late AppDatabase db;
    late AppSettings settings;
    await tester.runAsync(() async {
      await initializeDateFormatting('ja_JP');
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
        child: const MaterialApp(home: ResultsPage()),
      ),
    );
    await settle(tester);
    expect(find.text('まだレース結果がありません'), findsOneWidget);

    // 結果を記録 → レースを選ぶ → 払戻金の表を貼り付けて保存
    await tapText(tester, '結果を記録');
    final kyoto = find.widgetWithText(ChoiceChip, '京都');
    await tester.tap(kyoto);
    await settle(tester);
    final r10 = find.widgetWithText(ChoiceChip, '10R');
    await tester.tap(r10);
    await settle(tester);
    await tapText(tester, '京都 10R の結果を入力');
    await tapText(tester, '払戻金の表を貼り付けて読み取る');
    await tester.enterText(find.byType(TextField).last, _table);
    await tapText(tester, '読み取る');
    expect(find.textContaining('レース結果として残します'), findsOneWidget);
    await tapText(tester, '保存して確定');

    // 一覧に出る
    expect(find.text('京都 10R'), findsOneWidget);
    expect(find.textContaining('7 → 3 → 12'), findsOneWidget);
    expect(find.text('38,450円'), findsOneWidget);
    expect(find.text('1 レースの結果をためています'), findsOneWidget);

    // 開くと、着順と払戻金の表が見られる
    await tapText(tester, '京都 10R');
    expect(find.text('レース結果'), findsOneWidget);
    expect(find.text('7→3→12'), findsOneWidget);
    expect(find.text('1,640円'), findsOneWidget);

    await tester.runAsync(() => db.close());
  });
}
