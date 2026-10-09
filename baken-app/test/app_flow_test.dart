import 'package:baken_app/ui/common.dart';
import 'package:baken_app/data/models.dart';
import 'package:baken_app/core/bet_type.dart';
import 'package:baken_app/data/database.dart';
import 'package:baken_app/data/settings.dart';
import 'package:baken_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 実際の DB 処理を待ちながら画面を進める
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f.first);
  await tester.tap(f.first);
  await settle(tester);
}

void main() {
  sqfliteFfiInit();

  testWidgets('年齢確認 → 計算 → 記録 → 結果入力 → 分析', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
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

    await tester.pumpWidget(BakenApp(db: db, settings: settings));
    await settle(tester);

    // 年齢確認
    expect(find.textContaining('20歳以上ですか'), findsOneWidget);
    await tapText(tester, 'はい、20歳以上です');
    expect(find.text('最初の1枚を記録してみましょう'), findsOneWidget);

    // 計算タブ: 馬連ボックス 1,3,7 → 3点
    await tester.tap(find.text('計算').last);
    await settle(tester);
    for (final n in ['1', '3', '7']) {
      await tester.tap(find.text(n).first);
      await tester.pump();
    }
    expect(find.text('3点  合計 300円'), findsOneWidget);

    // 3連単フォーメーションに切り替えて点数が変わる
    await tapText(tester, '3連単');
    await tapText(tester, 'フォーメーション');
    expect(find.text('1着'), findsOneWidget);
    await tapText(tester, '馬連');
    await tapText(tester, 'ボックス');
    for (final n in ['1', '3', '7']) {
      await tester.tap(find.text(n).first);
      await tester.pump();
    }

    // 次へ → オッズ入力 → 記録
    await tapText(tester, '次へ');
    expect(find.text('1-3'), findsOneWidget);
    await tester.tap(find.text('オッズ').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '12.5');
    await tapText(tester, 'OK');
    expect(find.text('12.5倍'), findsOneWidget);

    await tapText(tester, 'この買い目を記録（300円）');
    expect(find.text('馬券を記録'), findsOneWidget);

    // レース名を一覧から選ぶと、競馬場・コース・距離が入る
    await tapText(tester, 'タップして選ぶ（重賞・特別・条件戦）');
    expect(find.text('G1'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, 'じゃぱん');
    await settle(tester);
    await tapText(tester, 'ジャパンカップ');
    expect(find.text('ジャパンカップ'), findsOneWidget);
    expect(find.text('標準: 東京 芝2400m'), findsOneWidget);
    await tapText(tester, '保存（300円）');
    await settle(tester);

    // ホームに結果待ちが出る
    await tester.tap(find.text('ホーム').last);
    await settle(tester);
    expect(find.text('結果待ちのレース'), findsOneWidget);
    await tapText(tester, '結果を入れる');

    // レース詳細 → 結果入力: 1着3 2着1 3着5
    await tapText(tester, '結果を入力');
    final grids = find.text('3');
    await tester.tap(grids.at(0));
    await tester.pump();
    await tester.tap(find.text('1').at(1));
    await tester.pump();
    await tester.tap(find.text('5').at(2));
    await tester.pump();
    // 「記録しました」の通知が消えるのを待つ
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapText(tester, '判定する');
    expect(find.textContaining('馬連 1-3'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '1250');
    await tapText(tester, '保存して確定');

    // レース詳細の収支: 300円 → 1,250円
    expect(find.text('+950円'), findsWidgets);

    // 分析タブ
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    await tester.tap(find.text('分析').last);
    await settle(tester);
    expect(find.text('416.7%'), findsWidgets);

    // ホームに最近の的中が出る
    await tester.tap(find.text('ホーム').last);
    await settle(tester);
    expect(find.text('最近の的中'), findsOneWidget);
    expect(find.text('1,250円'), findsWidgets);

    // 設定タブ
    await tester.tap(find.text('設定').last);
    await settle(tester);
    expect(find.text('予算上限'), findsOneWidget);

    // 記録タブ: 一覧とカレンダー
    await tester.tap(find.text('記録').last);
    await settle(tester);
    expect(find.text('ジャパンカップ'), findsOneWidget);
    expect(find.text('東京 11R  馬連 ボックス'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_month));
    await settle(tester);
    expect(find.text('+0.9k'), findsOneWidget);

    await tester.runAsync(() => db.close());
  });

  testWidgets('レース名を自分で入力して登録する', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'ageConfirmed': true});
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
    await tester.pumpWidget(BakenApp(db: db, settings: settings));
    await settle(tester);

    await tapText(tester, 'かんたん記録');
    // 記録画面の「入力」ボタンから直接入力
    await tapText(tester, '入力');
    await tester.enterText(find.byType(TextField).last, '鷹巣山特別');
    await tapText(tester, '登録して使う');
    expect(find.text('鷹巣山特別'), findsOneWidget);
    expect(settings.customRaceNames, ['鷹巣山特別']);

    // 選択画面の「登録した名前」に出る
    await tapText(tester, '鷹巣山特別');
    expect(find.text('登録した名前'), findsWidgets);
    expect(find.text('鷹巣山特別'), findsOneWidget);

    // 検索して一覧にない名前は、そのまま登録して使える
    await tester.enterText(find.byType(TextField).first, '浦和桜花賞');
    await settle(tester);
    await tapText(tester, '「浦和桜花賞」で登録して使う');
    expect(find.text('浦和桜花賞'), findsOneWidget);
    expect(settings.customRaceNames, ['浦和桜花賞', '鷹巣山特別']);

    await tester.runAsync(() => db.close());
  });

  testWidgets('払戻金の表を貼り付けて結果を入れ、馬券を編集する', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'ageConfirmed': true});
    late AppDatabase db;
    late AppSettings settings;
    await tester.runAsync(() async {
      await initializeDateFormatting('ja_JP');
      db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      settings = await AppSettings.load();
      final d = isoDate(today());
      await db.insertTicket(
        Ticket(
          date: d,
          venue: '東京',
          raceNo: 11,
          raceName: '天皇賞（秋）',
          type: BetType.quinella,
          method: BetMethod.box,
          stakeTotal: 300,
          lines: [
            TicketLine(combo: '3-7', stake: 100),
            TicketLine(combo: '3-12', stake: 100),
            TicketLine(combo: '7-12', stake: 100),
          ],
        ),
        race: Race(
          date: d,
          venue: '東京',
          raceNo: 11,
          name: '天皇賞（秋）',
          fieldSize: 16,
        ),
      );
    });
    await tester.pumpWidget(BakenApp(db: db, settings: settings));
    await settle(tester);

    // ホーム → 結果待ちのレース → 結果を入力
    await tapText(tester, '結果を入れる');
    await tapText(tester, '結果を入力');

    // 払戻金の表を貼り付ける
    await tapText(tester, '払戻金の表を貼り付けて読み取る');
    await tester.enterText(
      find.byType(TextField).last,
      '単勝 7 1,250円 4番人気\n馬連 3-7 1,640円 5番人気\n3連単 7-3-12 38,450円 121番人気',
    );
    await tapText(tester, '読み取る');
    expect(find.textContaining('3券種・3件の払戻金を読み取りました'), findsOneWidget);
    // 3連単から着順が入り、判定まで進んで払戻金が入っている
    await tester.scrollUntilVisible(
      find.text('1640'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1640'), findsOneWidget);
    await tapText(tester, '保存して確定');
    expect(find.text('+1,340円'), findsWidgets);

    // 馬券を編集（メモだけ）→ 確定のまま
    await tester.tap(find.textContaining('馬連 ボックス'));
    await settle(tester);
    await tapText(tester, '編集');
    expect(find.text('馬券を編集'), findsOneWidget);
    await tapText(tester, 'タグ・メモ（任意）');
    await tester.enterText(find.byType(TextField).last, '本命から');
    await tapText(tester, '更新（300円）');
    expect(find.text('+1,340円'), findsWidgets);
    // カードは開いたままなので、メモがそのまま見える
    expect(find.textContaining('本命から'), findsOneWidget);

    await tester.runAsync(() => db.close());
  });
}
