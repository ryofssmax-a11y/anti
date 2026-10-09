import 'package:baken_app/core/bet_type.dart';
import 'package:baken_app/core/expander.dart';
import 'package:baken_app/core/judge.dart';
import 'package:baken_app/core/selection.dart';
import 'package:baken_app/data/csv_io.dart';
import 'package:baken_app/data/database.dart';
import 'package:baken_app/data/models.dart';
import 'package:baken_app/data/stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => db.close());

  Race race({int no = 11}) =>
      Race(date: '2026-10-12', venue: '東京', raceNo: no, fieldSize: 16);

  Ticket ticketFrom(Selection sel, int unit) {
    final combos = expand(sel);
    return Ticket(
      date: '2026-10-12',
      venue: '東京',
      raceNo: 11,
      type: sel.type,
      method: sel.method,
      selection: sel,
      stakeTotal: combos.length * unit,
      lines: [for (final c in combos) TicketLine(combo: c.key, stake: unit)],
    );
  }

  test('記録 → 結果入力 → 一括判定 → 集計', () async {
    final box = Selection(
      type: BetType.quinella,
      method: BetMethod.box,
      fieldSize: 16,
      columns: [
        {1, 3, 7, 12},
      ],
    );
    final win = Selection(
      type: BetType.win,
      method: BetMethod.normal,
      fieldSize: 16,
      columns: [
        {3},
      ],
    );
    await db.insertTicket(ticketFrom(box, 200), race: race());
    await db.insertTicket(ticketFrom(win, 1000), race: race());

    final pending = await db.pendingRaces();
    expect(pending, hasLength(1));
    final raceId = pending.single.id!;

    final outcome = RaceOutcome(
      fieldSize: 16,
      placings: {
        1: [7],
        2: [3],
        3: [12],
      },
    );
    final hits = await db.hitsNeedingPayout(raceId, outcome);
    expect(hits.map((h) => '${h.type.name}|${h.combo}'), ['quinella|3-7']);

    await db.settleRace(raceId, outcome, {
      payoutKey(BetType.quinella, '3-7'): 1250,
    });

    expect(await db.pendingRaces(), isEmpty);
    final tickets = await db.tickets(withLines: true);
    final quinella = tickets.firstWhere((t) => t.type == BetType.quinella);
    expect(quinella.settled, isTrue);
    expect(quinella.stakeTotal, 1200); // 6点 × 200円
    expect(quinella.payoutTotal, 2500); // 1250円 × 2
    expect(
      quinella.lines.where((l) => l.status == LineStatus.hit),
      hasLength(1),
    );
    final w = tickets.firstWhere((t) => t.type == BetType.win);
    expect(w.payoutTotal, 0);

    final totals = totalsOf(tickets);
    expect(totals.stake, 2200);
    expect(totals.payout, 2500);
    expect(totals.returnRate, closeTo(113.6, 0.1));
    expect(totals.hits, 1);
  });

  test('取消馬を含む買い目は返還で投資額から除く', () async {
    final box = Selection(
      type: BetType.quinella,
      method: BetMethod.box,
      fieldSize: 16,
      columns: [
        {1, 2, 3},
      ],
    );
    await db.insertTicket(ticketFrom(box, 100), race: race());
    final raceId = (await db.pendingRaces()).single.id!;
    await db.settleRace(
      raceId,
      RaceOutcome(
        fieldSize: 16,
        placings: {
          1: [5],
          2: [6],
          3: [7],
        },
        scratched: {1},
      ),
      {},
    );
    final t = (await db.tickets()).single;
    expect(t.stakeTotal, 100); // 1-2 と 1-3 は返還、2-3 だけ
  });

  test('未確定に戻すとレースが結果待ちに戻る', () async {
    final win = Selection(
      type: BetType.win,
      method: BetMethod.normal,
      columns: [
        {1},
      ],
    );
    await db.insertTicket(ticketFrom(win, 100), race: race());
    final raceId = (await db.pendingRaces()).single.id!;
    await db.settleRace(
      raceId,
      RaceOutcome(
        fieldSize: 16,
        placings: {
          1: [1],
        },
      ),
      {payoutKey(BetType.win, '1'): 350},
    );
    final t = (await db.tickets()).single;
    expect(t.payoutTotal, 350);
    await db.unsettleTicket(t.id!);
    expect(await db.pendingRaces(), hasLength(1));
    expect((await db.tickets()).single.settled, isFalse);
  });

  test('簡易記録と手動確定、削除', () async {
    await db.insertTicket(
      Ticket(
        date: '2026-10-11',
        venue: '中山',
        stakeTotal: 3000,
        payoutTotal: 4200,
        settled: true,
        simple: true,
      ),
    );
    final win5 = Selection(
      type: BetType.win5,
      method: BetMethod.formation,
      columns: [
        {1},
        {2},
        {3},
        {4},
        {5},
      ],
    );
    final id = await db.insertTicket(ticketFrom(win5, 100), race: race());
    await db.settleTicketManually(id, 0);
    expect(totalsOf(await db.tickets()).stake, 3100);
    expect(await db.stakeBetween('2026-10-12', '2026-10-12'), 100);

    await db.deleteTicket(id);
    expect(await db.tickets(), hasLength(1));
    expect(await db.pendingRaces(), isEmpty);
  });

  test('CSV の書き出しと読み込み', () async {
    final box = Selection(
      type: BetType.trio,
      method: BetMethod.box,
      columns: [
        {1, 2, 3, 4},
      ],
    );
    await db.insertTicket(ticketFrom(box, 100), race: race());
    await db.insertTicket(
      Ticket(
        date: '2026-10-11',
        venue: '中山',
        stakeTotal: 3000,
        payoutTotal: 4200,
        settled: true,
        simple: true,
        memo: 'メモ, "引用"あり',
      ),
    );
    final csv = ticketsToCsv(await db.tickets(withLines: true));
    final imported = ticketsFromCsv(csv);
    expect(imported.errors, isEmpty);
    expect(imported.tickets, hasLength(2));
    final simple = imported.tickets.firstWhere((x) => x.ticket.simple).ticket;
    expect(simple.memo, 'メモ, "引用"あり');
    expect(simple.payoutTotal, 4200);
    final trio = imported.tickets.firstWhere((x) => !x.ticket.simple);
    expect(trio.ticket.type, BetType.trio);
    expect(trio.ticket.lines, hasLength(4));
    expect(trio.race?.raceNo, 11);

    final bad = ticketsFromCsv(
      '${csvHeader.join(',')}\n2026/10/12,東京,1,,単勝,通常,ネット投票,1,100,0,1,,',
    );
    expect(bad.errors, hasLength(1));
  });

  test('期間別の breakdown と累積収支', () {
    Ticket t(String date, String venue, int stake, int payout) => Ticket(
      date: date,
      venue: venue,
      stakeTotal: stake,
      payoutTotal: payout,
      settled: true,
      simple: true,
    );
    final list = [
      t('2026-10-04', '中山', 1000, 0),
      t('2026-10-05', '中山', 1000, 3000),
      t('2026-10-05', '阪神', 2000, 0),
      t('2026-10-11', '東京', 1000, 0),
    ];
    final rows = breakdownOf(list, Breakdown.venue);
    expect(rows.first.key, '中山');
    expect(rows.first.value.returnRate, 150);
    final cum = cumulativeProfit(list);
    expect(cum.map((p) => p.cumulative), [-1000, -1000, -2000]);
    final totals = totalsOf(list);
    expect(totals.maxLosingStreak, 2);
    expect(totals.maxPayout, 3000);
  });
}
