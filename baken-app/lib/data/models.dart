import 'dart:convert';

import '../core/bet_type.dart';
import '../core/judge.dart';
import '../core/selection.dart';

/// レース（開催日・競馬場・レース番号で一意）
class Race {
  Race({
    this.id,
    required this.date,
    required this.venue,
    required this.raceNo,
    this.name,
    this.surface,
    this.distance,
    this.fieldSize = 18,
    this.settled = false,
    this.outcome,
  });

  final int? id;

  /// YYYY-MM-DD
  final String date;
  final String venue;
  final int raceNo;
  final String? name;
  final String? surface;
  final int? distance;
  final int fieldSize;
  final bool settled;
  final RaceOutcome? outcome;

  String get title =>
      '$venue ${raceNo}R${name == null || name!.isEmpty ? '' : ' $name'}';

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'date': date,
    'venue': venue,
    'race_no': raceNo,
    'name': name,
    'surface': surface,
    'distance': distance,
    'field_size': fieldSize,
    'settled': settled ? 1 : 0,
    'outcome': outcome == null ? null : jsonEncode(outcome!.toJson()),
  };

  static Race fromRow(Map<String, Object?> row) => Race(
    id: row['id'] as int?,
    date: row['date'] as String,
    venue: row['venue'] as String,
    raceNo: row['race_no'] as int,
    name: row['name'] as String?,
    surface: row['surface'] as String?,
    distance: row['distance'] as int?,
    fieldSize: (row['field_size'] as int?) ?? 18,
    settled: (row['settled'] as int?) == 1,
    outcome: row['outcome'] == null
        ? null
        : RaceOutcome.fromJson(
            jsonDecode(row['outcome'] as String) as Map<String, Object?>,
          ),
  );
}

/// 1回の購入（馬券1枚、または簡易記録1件）
class Ticket {
  Ticket({
    this.id,
    this.raceId,
    required this.date,
    required this.venue,
    this.raceNo,
    this.raceName,
    this.type,
    this.method,
    this.channel = Channel.online,
    this.selection,
    required this.stakeTotal,
    this.payoutTotal = 0,
    this.settled = false,
    this.simple = false,
    this.memo = '',
    this.tags = '',
    DateTime? createdAt,
    this.lines = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final int? raceId;
  final String date;
  final String venue;
  final int? raceNo;
  final String? raceName;
  final BetType? type;
  final BetMethod? method;
  final Channel channel;
  final Selection? selection;

  /// 投資額（返還分を除く）
  final int stakeTotal;
  final int payoutTotal;
  final bool settled;

  /// 簡易記録（投資額と払戻額だけ）
  final bool simple;
  final String memo;

  /// カンマ区切りのタグ
  final String tags;
  final DateTime createdAt;
  final List<TicketLine> lines;

  int get profit => payoutTotal - stakeTotal;
  bool get isHit => payoutTotal > 0;

  String get typeLabel {
    if (simple) return '簡易記録';
    final t = type?.label ?? '';
    final m = method?.label ?? '';
    return m.isEmpty ? t : '$t $m';
  }

  List<String> get tagList =>
      tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  Ticket copyWith({List<TicketLine>? lines, int? raceId}) => Ticket(
    id: id,
    raceId: raceId ?? this.raceId,
    date: date,
    venue: venue,
    raceNo: raceNo,
    raceName: raceName,
    type: type,
    method: method,
    channel: channel,
    selection: selection,
    stakeTotal: stakeTotal,
    payoutTotal: payoutTotal,
    settled: settled,
    simple: simple,
    memo: memo,
    tags: tags,
    createdAt: createdAt,
    lines: lines ?? this.lines,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'race_id': raceId,
    'date': date,
    'venue': venue,
    'race_no': raceNo,
    'race_name': raceName,
    'bet_type': type?.name,
    'method': method?.name,
    'channel': channel.name,
    'selection': selection == null ? null : jsonEncode(selection!.toJson()),
    'stake_total': stakeTotal,
    'payout_total': payoutTotal,
    'settled': settled ? 1 : 0,
    'simple': simple ? 1 : 0,
    'memo': memo,
    'tags': tags,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  static Ticket fromRow(
    Map<String, Object?> row, [
    List<TicketLine> lines = const [],
  ]) {
    final sel = row['selection'] as String?;
    return Ticket(
      id: row['id'] as int?,
      raceId: row['race_id'] as int?,
      date: row['date'] as String,
      venue: row['venue'] as String,
      raceNo: row['race_no'] as int?,
      raceName: row['race_name'] as String?,
      type: BetType.fromName(row['bet_type'] as String?),
      method: BetMethod.fromName(row['method'] as String?),
      channel: Channel.fromName(row['channel'] as String?),
      selection: sel == null
          ? null
          : Selection.fromJson(jsonDecode(sel) as Map<String, Object?>),
      stakeTotal: (row['stake_total'] as int?) ?? 0,
      payoutTotal: (row['payout_total'] as int?) ?? 0,
      settled: (row['settled'] as int?) == 1,
      simple: (row['simple'] as int?) == 1,
      memo: (row['memo'] as String?) ?? '',
      tags: (row['tags'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
      lines: lines,
    );
  }
}

/// 展開後の買い目1点
class TicketLine {
  TicketLine({
    this.id,
    this.ticketId,
    required this.combo,
    required this.stake,
    this.oddsX10,
    this.status,
    this.payout = 0,
  });

  final int? id;
  final int? ticketId;

  /// 例: "3-7-12"（順不同の券種は昇順）
  final String combo;
  final int stake;

  /// オッズを10倍した整数（12.5倍 → 125）
  final int? oddsX10;

  /// null = 未確定
  final LineStatus? status;
  final int payout;

  double? get odds => oddsX10 == null ? null : oddsX10! / 10;

  Map<String, Object?> toRow(int ticketId) => {
    if (id != null) 'id': id,
    'ticket_id': ticketId,
    'combo': combo,
    'stake': stake,
    'odds_x10': oddsX10,
    'status': status?.name,
    'payout': payout,
  };

  static TicketLine fromRow(Map<String, Object?> row) {
    final s = row['status'] as String?;
    return TicketLine(
      id: row['id'] as int?,
      ticketId: row['ticket_id'] as int?,
      combo: row['combo'] as String,
      stake: row['stake'] as int,
      oddsX10: row['odds_x10'] as int?,
      status: s == null ? null : LineStatus.values.byName(s),
      payout: (row['payout'] as int?) ?? 0,
    );
  }
}

/// 払戻金の入力キー（券種と組み合わせ）
String payoutKey(BetType type, String combo) => '${type.name}|$combo';
