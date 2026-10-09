import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/bet_type.dart';
import '../core/judge.dart';
import '../core/selection.dart';
import 'models.dart';

/// 端末内の SQLite に記録を保存する。変更があるとリスナーに通知する。
class AppDatabase extends ChangeNotifier {
  AppDatabase._(this._db);

  final Database _db;

  static const _version = 1;

  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'baken.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _create(db),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE races (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        venue TEXT NOT NULL,
        race_no INTEGER NOT NULL,
        name TEXT,
        surface TEXT,
        distance INTEGER,
        field_size INTEGER NOT NULL DEFAULT 18,
        settled INTEGER NOT NULL DEFAULT 0,
        outcome TEXT,
        UNIQUE(date, venue, race_no)
      )''');
    await db.execute('''
      CREATE TABLE payouts (
        race_id INTEGER NOT NULL REFERENCES races(id) ON DELETE CASCADE,
        bet_type TEXT NOT NULL,
        combo TEXT NOT NULL,
        payout_per_100 INTEGER NOT NULL,
        PRIMARY KEY(race_id, bet_type, combo)
      )''');
    await db.execute('''
      CREATE TABLE tickets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        race_id INTEGER REFERENCES races(id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        venue TEXT NOT NULL,
        race_no INTEGER,
        race_name TEXT,
        bet_type TEXT,
        method TEXT,
        channel TEXT NOT NULL,
        selection TEXT,
        stake_total INTEGER NOT NULL,
        payout_total INTEGER NOT NULL DEFAULT 0,
        settled INTEGER NOT NULL DEFAULT 0,
        simple INTEGER NOT NULL DEFAULT 0,
        memo TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE ticket_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_id INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        combo TEXT NOT NULL,
        stake INTEGER NOT NULL,
        odds_x10 INTEGER,
        status TEXT,
        payout INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX idx_tickets_date ON tickets(date)');
    await db.execute(
      'CREATE INDEX idx_lines_ticket ON ticket_lines(ticket_id)',
    );
  }

  Future<void> close() => _db.close();

  // ---- レース ----

  Future<Race?> race(int id) async {
    final rows = await _db.query('races', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Race.fromRow(rows.first);
  }

  /// 結果が未入力で、馬券が登録されているレース
  Future<List<Race>> pendingRaces() async {
    final rows = await _db.rawQuery('''
      SELECT r.* FROM races r
      WHERE r.settled = 0 AND EXISTS (
        SELECT 1 FROM tickets t WHERE t.race_id = r.id AND t.settled = 0)
      ORDER BY r.date DESC, r.venue, r.race_no''');
    return rows.map(Race.fromRow).toList();
  }

  Future<Map<String, int>> payoutsFor(int raceId) async {
    final rows = await _db.query(
      'payouts',
      where: 'race_id = ?',
      whereArgs: [raceId],
    );
    return {
      for (final r in rows)
        payoutKey(
          BetType.values.byName(r['bet_type'] as String),
          r['combo'] as String,
        ): r['payout_per_100'] as int,
    };
  }

  // ---- 馬券 ----

  /// 馬券を保存する。[race] があればレースに紐づける。
  Future<int> insertTicket(Ticket ticket, {Race? race}) async {
    final id = await _db.transaction((txn) async {
      int? raceId = ticket.raceId;
      if (race != null) {
        raceId = await _upsertRaceTxn(txn, race);
      }
      final row = ticket.copyWith(raceId: raceId).toRow()..remove('id');
      final ticketId = await txn.insert('tickets', row);
      for (final line in ticket.lines) {
        await txn.insert('ticket_lines', line.toRow(ticketId)..remove('id'));
      }
      return ticketId;
    });
    notifyListeners();
    return id;
  }

  Future<int> _upsertRaceTxn(Transaction txn, Race race) async {
    final existing = await txn.query(
      'races',
      columns: ['id', 'settled'],
      where: 'date = ? AND venue = ? AND race_no = ?',
      whereArgs: [race.date, race.venue, race.raceNo],
    );
    if (existing.isEmpty) {
      return txn.insert('races', race.toRow()..remove('id'));
    }
    final id = existing.first['id'] as int;
    final settled = existing.first['settled'] == 1;
    await txn.update(
      'races',
      {
        if (race.name != null && race.name!.isNotEmpty) 'name': race.name,
        if (race.surface != null) 'surface': race.surface,
        if (race.distance != null) 'distance': race.distance,
        if (!settled) 'field_size': race.fieldSize,
        // 確定済みのレースに馬券を足したら、もう一度結果を確定させる
        'settled': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return id;
  }

  Future<void> deleteTicket(int id) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'tickets',
        columns: ['race_id'],
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete('tickets', where: 'id = ?', whereArgs: [id]);
      final raceId = rows.isEmpty ? null : rows.first['race_id'] as int?;
      if (raceId != null) {
        final left = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM tickets WHERE race_id = ?', [
            raceId,
          ]),
        );
        if ((left ?? 0) == 0) {
          await txn.delete('races', where: 'id = ?', whereArgs: [raceId]);
        }
      }
    });
    notifyListeners();
  }

  Future<List<TicketLine>> linesFor(int ticketId) async {
    final rows = await _db.query(
      'ticket_lines',
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
      orderBy: 'id',
    );
    return rows.map(TicketLine.fromRow).toList();
  }

  /// 期間内の馬券（[from]・[to] は YYYY-MM-DD、両端を含む）
  Future<List<Ticket>> tickets({
    String? from,
    String? to,
    bool? settled,
    bool withLines = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(to);
    }
    if (settled != null) {
      where.add('settled = ?');
      args.add(settled ? 1 : 0);
    }
    final rows = await _db.query(
      'tickets',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, venue, race_no, created_at',
    );
    if (!withLines) return rows.map((r) => Ticket.fromRow(r)).toList();
    return [
      for (final r in rows) Ticket.fromRow(r, await linesFor(r['id'] as int)),
    ];
  }

  Future<List<Ticket>> ticketsForRace(int raceId) async {
    final rows = await _db.query(
      'tickets',
      where: 'race_id = ?',
      whereArgs: [raceId],
      orderBy: 'created_at',
    );
    return [
      for (final r in rows) Ticket.fromRow(r, await linesFor(r['id'] as int)),
    ];
  }

  /// 期間内の投資額（未確定を含む）。予算アラートに使う。
  Future<int> stakeBetween(String from, String to) async {
    final v = Sqflite.firstIntValue(
      await _db.rawQuery(
        'SELECT COALESCE(SUM(stake_total), 0) FROM tickets WHERE date >= ? AND date <= ?',
        [from, to],
      ),
    );
    return v ?? 0;
  }

  // ---- 結果入力と確定 ----

  /// 結果から、まだ払戻金が必要な的中買い目（券種と組み合わせ）を求める。
  Future<List<({BetType type, String combo})>> hitsNeedingPayout(
    int raceId,
    RaceOutcome outcome,
  ) async {
    final out = <({BetType type, String combo})>[];
    final seen = <String>{};
    for (final t in await ticketsForRace(raceId)) {
      final type = t.type;
      if (type == null || type == BetType.win5 || t.simple) continue;
      for (final l in t.lines) {
        final c = Combination.parse(l.combo, ordered: type.ordered);
        if (judge(type, c, outcome) == LineStatus.hit &&
            seen.add(payoutKey(type, l.combo))) {
          out.add((type: type, combo: l.combo));
        }
      }
    }
    return out;
  }

  /// 結果と払戻金（100円あたり）を保存し、レースの全買い目を一括で判定する。
  /// WIN5 は対象外（手動で確定する）。
  Future<void> settleRace(
    int raceId,
    RaceOutcome outcome,
    Map<String, int> payouts,
  ) async {
    await _db.transaction((txn) async {
      await txn.update(
        'races',
        {
          'settled': 1,
          'field_size': outcome.fieldSize,
          'outcome': jsonEncode(outcome.toJson()),
        },
        where: 'id = ?',
        whereArgs: [raceId],
      );
      await txn.delete('payouts', where: 'race_id = ?', whereArgs: [raceId]);
      for (final e in payouts.entries) {
        final parts = e.key.split('|');
        await txn.insert('payouts', {
          'race_id': raceId,
          'bet_type': parts[0],
          'combo': parts[1],
          'payout_per_100': e.value,
        });
      }

      final tickets = await txn.query(
        'tickets',
        where: 'race_id = ?',
        whereArgs: [raceId],
      );
      for (final row in tickets) {
        final type = BetType.fromName(row['bet_type'] as String?);
        if (type == null || type == BetType.win5 || row['simple'] == 1) {
          continue;
        }
        final ticketId = row['id'] as int;
        final lineRows = await txn.query(
          'ticket_lines',
          where: 'ticket_id = ?',
          whereArgs: [ticketId],
        );
        var stakeTotal = 0;
        var payoutTotal = 0;
        for (final lr in lineRows) {
          final line = TicketLine.fromRow(lr);
          final status = judge(
            type,
            Combination.parse(line.combo, ordered: type.ordered),
            outcome,
          );
          final per100 = payouts[payoutKey(type, line.combo)] ?? 0;
          final payout = status == LineStatus.hit
              ? per100 * line.stake ~/ 100
              : 0;
          if (status != LineStatus.refund) stakeTotal += line.stake;
          payoutTotal += payout;
          await txn.update(
            'ticket_lines',
            {'status': status.name, 'payout': payout},
            where: 'id = ?',
            whereArgs: [line.id],
          );
        }
        await txn.update(
          'tickets',
          {
            'stake_total': stakeTotal,
            'payout_total': payoutTotal,
            'settled': 1,
          },
          where: 'id = ?',
          whereArgs: [ticketId],
        );
      }
    });
    notifyListeners();
  }

  /// 払戻額を手入力して確定する（WIN5 など自動判定できない馬券用）。
  Future<void> settleTicketManually(int ticketId, int payout) async {
    await _db.update(
      'tickets',
      {'payout_total': payout, 'settled': 1},
      where: 'id = ?',
      whereArgs: [ticketId],
    );
    notifyListeners();
  }

  /// 確定を取り消して未確定に戻す。
  Future<void> unsettleTicket(int ticketId) async {
    await _db.transaction((txn) async {
      final lines = await txn.query(
        'ticket_lines',
        where: 'ticket_id = ?',
        whereArgs: [ticketId],
      );
      final stake = lines.fold<int>(0, (s, l) => s + (l['stake'] as int));
      await txn.update(
        'ticket_lines',
        {'status': null, 'payout': 0},
        where: 'ticket_id = ?',
        whereArgs: [ticketId],
      );
      final row = (await txn.query(
        'tickets',
        columns: ['simple', 'race_id'],
        where: 'id = ?',
        whereArgs: [ticketId],
      )).firstOrNull;
      final simple = row?['simple'] == 1;
      final raceId = row?['race_id'] as int?;
      if (raceId != null) {
        await txn.update(
          'races',
          {'settled': 0},
          where: 'id = ?',
          whereArgs: [raceId],
        );
      }
      await txn.update(
        'tickets',
        {if (!simple) 'stake_total': stake, 'payout_total': 0, 'settled': 0},
        where: 'id = ?',
        whereArgs: [ticketId],
      );
    });
    notifyListeners();
  }

  Future<void> deleteAll() async {
    await _db.transaction((txn) async {
      await txn.delete('ticket_lines');
      await txn.delete('tickets');
      await txn.delete('payouts');
      await txn.delete('races');
    });
    notifyListeners();
  }
}
