import '../core/bet_type.dart';
import 'models.dart';

/// CSV の列。書き出しと読み込みで共通。
const csvHeader = [
  '日付',
  '競馬場',
  'レース番号',
  'レース名',
  '券種',
  '買い方',
  '購入方法',
  '買い目',
  '投資額',
  '払戻額',
  '確定',
  'タグ',
  'メモ',
];

String _escape(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// 馬券を1行1件の CSV にする（買い目はスペース区切り）。
String ticketsToCsv(List<Ticket> tickets) {
  final buf = StringBuffer()..writeln(csvHeader.join(','));
  for (final t in tickets) {
    final row = [
      t.date,
      t.venue,
      t.raceNo?.toString() ?? '',
      t.raceName ?? '',
      t.simple ? '簡易記録' : (t.type?.label ?? ''),
      t.method?.label ?? '',
      t.channel.label,
      t.lines.map((l) => l.combo).join(' '),
      '${t.stakeTotal}',
      '${t.payoutTotal}',
      t.settled ? '1' : '0',
      t.tags,
      t.memo,
    ];
    buf.writeln(row.map(_escape).join(','));
  }
  return buf.toString();
}

/// CSV を行と列に分ける（ダブルクォート対応）。
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  row.add(field.toString());
  if (row.any((c) => c.isNotEmpty)) rows.add(row);
  return rows;
}

/// 読み込み結果
class CsvImport {
  CsvImport(this.tickets, this.errors);
  final List<({Ticket ticket, Race? race})> tickets;
  final List<String> errors;
}

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// このアプリで書き出した CSV を読み込む。
///
/// 買い目ごとの的中は復元できないため、投資額と払戻額は馬券単位で取り込み、
/// 投資額は買い目の数で均等に割る。
CsvImport ticketsFromCsv(String text) {
  final rows = parseCsv(text.replaceFirst('﻿', ''));
  final out = <({Ticket ticket, Race? race})>[];
  final errors = <String>[];
  if (rows.isEmpty) return CsvImport(out, ['空のファイルです']);
  final start = rows.first.first == csvHeader.first ? 1 : 0;

  for (var i = start; i < rows.length; i++) {
    final r = [...rows[i], ...List.filled(csvHeader.length, '')];
    final lineNo = i + 1;
    final date = r[0].trim();
    if (!_datePattern.hasMatch(date)) {
      errors.add('$lineNo行目: 日付の形式が正しくありません（例 2026-10-12）');
      continue;
    }
    final stake = int.tryParse(r[8].trim());
    final payout = int.tryParse(r[9].trim()) ?? 0;
    if (stake == null) {
      errors.add('$lineNo行目: 投資額が数値ではありません');
      continue;
    }
    final venue = r[1].trim().isEmpty ? otherVenue : r[1].trim();
    final raceNo = int.tryParse(r[2].trim());
    final simple = r[4] == '簡易記録';
    final type = BetType.values.where((t) => t.label == r[4]).firstOrNull;
    final method = BetMethod.values.where((m) => m.label == r[5]).firstOrNull;
    final channel =
        Channel.values.where((c) => c.label == r[6]).firstOrNull ??
        Channel.online;
    final combos = r[7].split(' ').where((c) => c.isNotEmpty).toList();
    final settled = r[10].trim() != '0';

    final perLine = combos.isEmpty ? 0 : stake ~/ combos.length;
    final lines = [
      for (final c in combos) TicketLine(combo: c, stake: perLine),
    ];
    final ticket = Ticket(
      date: date,
      venue: venue,
      raceNo: raceNo,
      raceName: r[3].isEmpty ? null : r[3],
      type: simple ? null : type,
      method: simple ? null : method,
      channel: channel,
      stakeTotal: stake,
      payoutTotal: payout,
      settled: settled,
      simple: simple || type == null,
      tags: r[11],
      memo: r[12],
      lines: lines,
    );
    final race = (!ticket.simple && raceNo != null)
        ? Race(
            date: date,
            venue: venue,
            raceNo: raceNo,
            name: ticket.raceName,
            settled: settled,
          )
        : null;
    out.add((ticket: ticket, race: race));
  }
  return CsvImport(out, errors);
}
