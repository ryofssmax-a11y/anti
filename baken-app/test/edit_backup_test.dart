import 'package:baken_app/core/bet_type.dart';
import 'package:baken_app/core/judge.dart';
import 'package:baken_app/data/backup.dart';
import 'package:baken_app/data/database.dart';
import 'package:baken_app/data/models.dart';
import 'package:baken_app/data/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeTarget implements BackupTarget {
  final files = <String, String>{};
  @override
  Future<void> write(String name, String content) async =>
      files[name] = content;
  @override
  Future<List<String>> list() async => files.keys.toList();
  @override
  Future<void> delete(String name) async => files.remove(name);
}

void main() {
  sqfliteFfiInit();
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() => db.close());

  Race race(int no, {String? name}) => Race(
    date: '2026-10-11',
    venue: '東京',
    raceNo: no,
    name: name,
    fieldSize: 16,
  );

  Ticket quinella(
    List<String> combos, {
    int? id,
    String memo = '',
    String? name,
    int no = 11,
  }) => Ticket(
    id: id,
    date: '2026-10-11',
    venue: '東京',
    raceNo: no,
    raceName: name,
    type: BetType.quinella,
    method: BetMethod.box,
    stakeTotal: combos.length * 100,
    memo: memo,
    lines: [for (final c in combos) TicketLine(combo: c, stake: 100)],
  );

  Future<int> settled() async {
    final id = await db.insertTicket(quinella(['3-7', '1-3']), race: race(11));
    final raceId = (await db.pendingRaces()).single.id!;
    await db.settleRace(
      raceId,
      RaceOutcome(
        fieldSize: 16,
        placings: {
          1: [7],
          2: [3],
          3: [1],
        },
      ),
      {payoutKey(BetType.quinella, '3-7'): 1500},
    );
    return id;
  }

  group('記録の編集', () {
    test('メモとレース名だけなら確定のまま', () async {
      final id = await settled();
      final unsettled = await db.updateTicket(
        quinella(['3-7', '1-3'], id: id, memo: '本命', name: '秋の特別'),
        race: race(11, name: '秋の特別'),
        linesChanged: false,
      );
      expect(unsettled, isFalse);
      final t = (await db.ticketById(id))!;
      expect(t.settled, isTrue);
      expect(t.payoutTotal, 1500);
      expect(t.memo, '本命');
      expect(t.raceName, '秋の特別');
      expect((await db.race(t.raceId!))!.name, '秋の特別');
      expect(t.lines.where((l) => l.status == LineStatus.hit), hasLength(1));
    });

    test('買い目を変えると未確定に戻り、レースも結果待ちに戻る', () async {
      final id = await settled();
      final unsettled = await db.updateTicket(
        quinella(['3-7', '7-12', '1-7'], id: id),
        race: race(11),
        linesChanged: true,
      );
      expect(unsettled, isTrue);
      final t = (await db.ticketById(id))!;
      expect(t.settled, isFalse);
      expect(t.stakeTotal, 300);
      expect(t.lines.map((l) => l.combo), ['3-7', '7-12', '1-7']);
      expect(t.lines.every((l) => l.status == null), isTrue);
      expect(await db.pendingRaces(), hasLength(1));
    });

    test('レース番号を変えると別のレースに移り、空になった元のレースは消える', () async {
      final id = await db.insertTicket(quinella(['3-7']), race: race(11));
      final oldRaceId = (await db.ticketById(id))!.raceId!;
      await db.updateTicket(
        quinella(['3-7'], id: id, no: 10),
        race: race(10),
        linesChanged: false,
      );
      final t = (await db.ticketById(id))!;
      expect(t.raceNo, 10);
      expect(t.raceId, isNot(oldRaceId));
      expect(await db.race(oldRaceId), isNull);
    });

    test('簡易記録の金額を直す', () async {
      final id = await db.insertTicket(
        Ticket(
          date: '2026-10-11',
          venue: '中山',
          stakeTotal: 3000,
          payoutTotal: 0,
          settled: true,
          simple: true,
        ),
      );
      await db.updateTicket(
        Ticket(
          id: id,
          date: '2026-10-12',
          venue: '東京',
          stakeTotal: 2000,
          payoutTotal: 5400,
          settled: true,
          simple: true,
        ),
        linesChanged: false,
      );
      final t = (await db.ticketById(id))!;
      expect(
        [t.date, t.venue, t.stakeTotal, t.payoutTotal, t.settled],
        ['2026-10-12', '東京', 2000, 5400, true],
      );
    });
  });

  group('バックアップ', () {
    test('書き出して別の DB に復元すると同じ記録になる', () async {
      await settled();
      final settings = await AppSettings.load();
      await settings.addCustomRaceName('鷹巣山特別');
      final json = await buildBackupJson(db, settings);

      final db2 = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      SharedPreferences.setMockInitialValues({});
      final settings2 = await AppSettings.load();
      final parsed = parseBackupJson(json);
      expect(parsed.summary.tickets, 1);
      await restoreBackup(db2, settings2, parsed.data);

      final t = (await db2.tickets(withLines: true)).single;
      expect(t.payoutTotal, 1500);
      expect(t.lines, hasLength(2));
      expect(await db2.payoutsFor(t.raceId!), {
        payoutKey(BetType.quinella, '3-7'): 1500,
      });
      expect(settings2.customRaceNames, ['鷹巣山特別']);
      await db2.close();
    });

    test('このアプリ以外のファイルは読み込まない', () {
      expect(() => parseBackupJson('{"foo":1}'), throwsFormatException);
      expect(() => parseBackupJson('not json'), throwsFormatException);
    });

    test('自動バックアップは最新と日付つきを書き、30日より前を消す', () async {
      final settings = await AppSettings.load();
      await settings.setBackupFolder('content://tree/x', 'Drive');
      final target = FakeTarget()
        ..files['baken_backup_2026-08-01.json'] = '{}'
        ..files['other.txt'] = 'x';
      final service = BackupService(
        db: db,
        settings: settings,
        targetFor: (_) => target,
        delay: const Duration(milliseconds: 10),
        now: () => DateTime(2026, 10, 11, 20),
      );
      service.start();
      await db.insertTicket(quinella(['3-7']), race: race(11));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(target.files.keys.toSet(), {
        latestBackupName,
        'baken_backup_2026-10-11.json',
        'other.txt',
      });
      expect(
        parseBackupJson(target.files[latestBackupName]!).summary.tickets,
        1,
      );
      expect(settings.lastBackupAt, isNotNull);
      service.dispose();
    });

    test('自動バックアップが切なら書かない', () async {
      final settings = await AppSettings.load();
      await settings.setBackupFolder('content://tree/x', 'Drive');
      await settings.setAutoBackup(false);
      final target = FakeTarget();
      final service = BackupService(
        db: db,
        settings: settings,
        targetFor: (_) => target,
        delay: const Duration(milliseconds: 10),
      )..start();
      await db.insertTicket(quinella(['3-7']), race: race(11));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(target.files, isEmpty);
      service.dispose();
    });
  });
}
