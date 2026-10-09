import 'bet_type.dart';

/// JRA の枠順決定ルールに沿って、枠番ごとの頭数を返す（index 0 = 1枠）。
List<int> horsesPerFrame(int fieldSize) {
  final counts = List<int>.filled(8, 0);
  if (fieldSize <= 8) {
    for (var f = 0; f < fieldSize; f++) {
      counts[f] = 1;
    }
    return counts;
  }
  final base = fieldSize ~/ 8;
  final extra = fieldSize % 8;
  for (var f = 0; f < 8; f++) {
    counts[f] = base + (f >= 8 - extra ? 1 : 0);
  }
  return counts;
}

/// 馬番から枠番を求める。
int frameOf(int horseNo, int fieldSize) {
  final counts = horsesPerFrame(fieldSize);
  var upTo = 0;
  for (var f = 0; f < 8; f++) {
    upTo += counts[f];
    if (horseNo <= upTo) return f + 1;
  }
  return 8;
}

/// 買い目の組み合わせ1点。
class Combination {
  Combination(List<int> numbers, {required bool ordered})
    : numbers = List.unmodifiable(ordered ? numbers : ([...numbers]..sort()));

  final List<int> numbers;

  String get key => numbers.join('-');

  @override
  bool operator ==(Object other) => other is Combination && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;

  static Combination parse(String key, {required bool ordered}) =>
      Combination(key.split('-').map(int.parse).toList(), ordered: ordered);
}

/// 計算画面での選択内容。
///
/// [columns] の意味は買い方で変わる。
/// - 通常（単勝・複勝）: columns[0] に選んだ馬。1頭 = 1点。
/// - 通常（その他）: 着順・頭目ごとに1頭ずつ。
/// - ボックス: columns[0] に選んだ馬。
/// - ながし: 先頭から軸の頭数ぶん軸（各1頭）、最後の列が相手。
/// - フォーメーション / WIN5: 着順・レースごとの列。
class Selection {
  Selection({
    required this.type,
    required this.method,
    this.fieldSize = 18,
    this.axisCount = 1,
    AxisMode? axisMode,
    List<Set<int>>? columns,
    Set<int>? scratched,
  }) : axisMode = axisMode ?? axisModesFor(type, axisCount).first,
       columns =
           columns ??
           List.generate(
             columnCountFor(type, method, axisCount),
             (_) => <int>{},
           ),
       scratched = scratched ?? <int>{};

  final BetType type;
  final BetMethod method;
  final int fieldSize;
  final int axisCount;
  final AxisMode axisMode;
  final List<Set<int>> columns;
  final Set<int> scratched;

  static int columnCountFor(BetType type, BetMethod method, int axisCount) {
    if (type.isSingle) return 1;
    return switch (method) {
      BetMethod.normal || BetMethod.formation => type.size,
      BetMethod.box => 1,
      BetMethod.nagashi => axisCount + 1,
    };
  }

  /// 選べる番号の最大値（枠連は枠番、WIN5 は各レース18頭まで）
  int get maxNumber {
    if (type.usesFrames) return fieldSize < 8 ? fieldSize : 8;
    if (type == BetType.win5) return 18;
    return fieldSize;
  }

  /// 列ごとに1つしか選べないか
  bool isSingleSelectColumn(int index) {
    if (type.isSingle) return false;
    if (method == BetMethod.normal) return true;
    if (method == BetMethod.nagashi) return index < axisCount;
    return false;
  }

  List<String> get columnLabels {
    if (type.isSingle || method == BetMethod.box) return const ['馬番'];
    if (type == BetType.win5) {
      return const ['1レース目', '2レース目', '3レース目', '4レース目', '5レース目'];
    }
    final unit = type.usesFrames ? '枠' : '頭';
    if (method == BetMethod.nagashi) {
      final axes = <String>[];
      if (axisCount == 1) {
        axes.add(switch (axisMode) {
          AxisMode.first => '軸（1着）',
          AxisMode.second => '軸（2着）',
          AxisMode.third => '軸（3着）',
          _ => '軸',
        });
      } else {
        axes.addAll(switch (axisMode) {
          AxisMode.firstSecond => ['軸（1着）', '軸（2着）'],
          AxisMode.firstThird => ['軸（1着）', '軸（3着）'],
          AxisMode.secondThird => ['軸（2着）', '軸（3着）'],
          _ => ['軸1', '軸2'],
        });
      }
      return [...axes, '相手'];
    }
    if (type.ordered) {
      return List.generate(type.size, (i) => '${i + 1}着');
    }
    return List.generate(type.size, (i) => '${i + 1}$unit目');
  }

  Selection copyWith({
    int? fieldSize,
    List<Set<int>>? columns,
    Set<int>? scratched,
    AxisMode? axisMode,
  }) => Selection(
    type: type,
    method: method,
    fieldSize: fieldSize ?? this.fieldSize,
    axisCount: axisCount,
    axisMode: axisMode ?? this.axisMode,
    columns: columns ?? this.columns.map((c) => {...c}).toList(),
    scratched: scratched ?? {...this.scratched},
  );

  Map<String, Object?> toJson() => {
    'type': type.name,
    'method': method.name,
    'fieldSize': fieldSize,
    'axisCount': axisCount,
    'axisMode': axisMode.name,
    'columns': columns.map((c) => (c.toList()..sort())).toList(),
    'scratched': scratched.toList()..sort(),
  };

  static Selection? fromJson(Map<String, Object?> json) {
    final type = BetType.fromName(json['type'] as String?);
    final method = BetMethod.fromName(json['method'] as String?);
    if (type == null || method == null) return null;
    final axisCount = (json['axisCount'] as num?)?.toInt() ?? 1;
    final cols =
        (json['columns'] as List?)
            ?.map((c) => (c as List).map((n) => (n as num).toInt()).toSet())
            .toList() ??
        [];
    final expected = columnCountFor(type, method, axisCount);
    if (cols.length != expected) return null;
    return Selection(
      type: type,
      method: method,
      fieldSize: (json['fieldSize'] as num?)?.toInt() ?? 18,
      axisCount: axisCount,
      axisMode: AxisMode.fromName(json['axisMode'] as String?),
      columns: cols,
      scratched:
          (json['scratched'] as List?)
              ?.map((n) => (n as num).toInt())
              .toSet() ??
          {},
    );
  }
}
