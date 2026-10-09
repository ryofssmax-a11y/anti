/// 券種
enum BetType {
  win('単勝', 1, ordered: true),
  place('複勝', 1, ordered: true),
  bracketQuinella('枠連', 2, ordered: false),
  quinella('馬連', 2, ordered: false),
  wide('ワイド', 2, ordered: false),
  exacta('馬単', 2, ordered: true),
  trio('3連複', 3, ordered: false),
  trifecta('3連単', 3, ordered: true),
  win5('WIN5', 5, ordered: true);

  const BetType(this.label, this.size, {required this.ordered});

  final String label;

  /// 1つの買い目に含まれる馬（枠・レース）の数
  final int size;

  /// 着順の並びを区別するか
  final bool ordered;

  bool get isSingle => size == 1;
  bool get usesFrames => this == BetType.bracketQuinella;

  List<BetMethod> get methods => switch (this) {
    BetType.win || BetType.place => const [BetMethod.normal],
    BetType.win5 => const [BetMethod.formation],
    _ => BetMethod.values,
  };

  static BetType? fromName(String? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// 買い方
enum BetMethod {
  normal('通常'),
  box('ボックス'),
  nagashi('ながし'),
  formation('フォーメーション');

  const BetMethod(this.label);
  final String label;

  static BetMethod? fromName(String? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// ながしの軸の置き方
enum AxisMode {
  /// 軸1頭（馬連・ワイド・枠連・3連複、または馬単・3連単の着順固定）
  first('1着'),
  second('2着'),
  third('3着'),
  firstSecond('1着・2着'),
  firstThird('1着・3着'),
  secondThird('2着・3着'),
  multi('マルチ'),

  /// 着順を問わない（馬連・ワイド・枠連・3連複）
  any('軸');

  const AxisMode(this.label);
  final String label;

  static AxisMode? fromName(String? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// 着順を区別する券種で、軸の数に応じて選べる置き方
List<AxisMode> axisModesFor(BetType type, int axisCount) {
  if (!type.ordered) return const [AxisMode.any];
  if (type == BetType.exacta) {
    return const [AxisMode.first, AxisMode.second, AxisMode.multi];
  }
  if (type == BetType.trifecta) {
    return axisCount == 1
        ? const [
            AxisMode.first,
            AxisMode.second,
            AxisMode.third,
            AxisMode.multi,
          ]
        : const [
            AxisMode.firstSecond,
            AxisMode.firstThird,
            AxisMode.secondThird,
            AxisMode.multi,
          ];
  }
  return const [AxisMode.any];
}

/// 軸の頭数として選べる値
List<int> axisCountsFor(BetType type) =>
    type.size == 3 ? const [1, 2] : const [1];

/// 購入方法
enum Channel {
  online('ネット投票'),
  venue('現地・WINS'),
  other('その他');

  const Channel(this.label);
  final String label;

  static Channel fromName(String? name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return Channel.online;
  }
}

/// 競馬場
const jraVenues = ['札幌', '函館', '福島', '新潟', '東京', '中山', '中京', '京都', '阪神', '小倉'];
const narVenues = [
  '門別',
  '盛岡',
  '水沢',
  '浦和',
  '船橋',
  '大井',
  '川崎',
  '金沢',
  '笠松',
  '名古屋',
  '園田',
  '姫路',
  '高知',
  '佐賀',
  '帯広（ばんえい）',
];
const otherVenue = 'その他';
const allVenues = [...jraVenues, ...narVenues, otherVenue];

const surfaces = ['芝', 'ダート', '障害'];
