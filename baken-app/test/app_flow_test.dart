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
}
