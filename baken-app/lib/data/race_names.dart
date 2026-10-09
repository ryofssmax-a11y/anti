/// レース名の選択肢。
///
/// 重賞は 2026年度の JRA 番組（2025年の名称変更と、2026年の阪神スタンド改修明けの
/// 実施場の変更を反映）をもとにした標準の競馬場・コース・距離を持つ。
/// 年によって実施場や距離が変わることがあるので、記録画面ではあくまで初期値として入れ、
/// 利用者が変えられるようにしている。
library;

enum RaceGrade {
  g1('G1'),
  g2('G2'),
  g3('G3'),
  jg1('J・G1'),
  jg2('J・G2'),
  jg3('J・G3'),
  listed('L'),
  special('特別'),
  condition('条件戦'),
  nar('地方');

  const RaceGrade(this.label);
  final String label;

  bool get isGraded => index <= RaceGrade.jg3.index;
}

class RacePreset {
  const RacePreset(
    this.name,
    this.grade, {
    this.venue,
    this.surface,
    this.distance,
    this.aliases = const [],
  });

  final String name;
  final RaceGrade grade;
  final String? venue;

  /// 芝・ダート・障害
  final String? surface;
  final int? distance;

  /// 略称など、検索に使う別名
  final List<String> aliases;

  String get detail => [
    ?venue,
    if (surface != null)
      '$surface${distance ?? ''}${distance == null ? '' : 'm'}',
  ].join(' ');
}

RacePreset _g(
  RaceGrade g,
  String name,
  String venue,
  String surface,
  int? distance, [
  List<String> aliases = const [],
]) => RacePreset(
  name,
  g,
  venue: venue,
  surface: surface,
  distance: distance,
  aliases: aliases,
);

const _t = '芝';
const _d = 'ダート';
const _j = '障害';

final List<RacePreset> gradedRaces = [
  // ---- G1 ----
  _g(RaceGrade.g1, 'フェブラリーステークス', '東京', _d, 1600, ['フェブラリーS']),
  _g(RaceGrade.g1, '高松宮記念', '中京', _t, 1200),
  _g(RaceGrade.g1, '大阪杯', '阪神', _t, 2000),
  _g(RaceGrade.g1, '桜花賞', '阪神', _t, 1600),
  _g(RaceGrade.g1, '皐月賞', '中山', _t, 2000),
  _g(RaceGrade.g1, '天皇賞（春）', '京都', _t, 3200, ['天皇賞春', '春天']),
  _g(RaceGrade.g1, 'NHKマイルカップ', '東京', _t, 1600, ['NHKマイルC']),
  _g(RaceGrade.g1, 'ヴィクトリアマイル', '東京', _t, 1600),
  _g(RaceGrade.g1, '優駿牝馬（オークス）', '東京', _t, 2400, ['オークス']),
  _g(RaceGrade.g1, '東京優駿（日本ダービー）', '東京', _t, 2400, ['日本ダービー', 'ダービー']),
  _g(RaceGrade.g1, '安田記念', '東京', _t, 1600),
  _g(RaceGrade.g1, '宝塚記念', '阪神', _t, 2200),
  _g(RaceGrade.g1, 'スプリンターズステークス', '中山', _t, 1200, ['スプリンターズS']),
  _g(RaceGrade.g1, '秋華賞', '京都', _t, 2000),
  _g(RaceGrade.g1, '菊花賞', '京都', _t, 3000),
  _g(RaceGrade.g1, '天皇賞（秋）', '東京', _t, 2000, ['天皇賞秋', '秋天']),
  _g(RaceGrade.g1, 'エリザベス女王杯', '京都', _t, 2200, ['エリ女']),
  _g(RaceGrade.g1, 'マイルチャンピオンシップ', '京都', _t, 1600, ['マイルCS']),
  _g(RaceGrade.g1, 'ジャパンカップ', '東京', _t, 2400, ['JC', 'ジャパンC']),
  _g(RaceGrade.g1, 'チャンピオンズカップ', '中京', _d, 1800, ['チャンピオンズC']),
  _g(RaceGrade.g1, '阪神ジュベナイルフィリーズ', '阪神', _t, 1600, ['阪神JF']),
  _g(RaceGrade.g1, '朝日杯フューチュリティステークス', '阪神', _t, 1600, ['朝日杯FS']),
  _g(RaceGrade.g1, 'ホープフルステークス', '中山', _t, 2000, ['ホープフルS']),
  _g(RaceGrade.g1, '有馬記念', '中山', _t, 2500, ['グランプリ']),

  // ---- G2 ----
  _g(RaceGrade.g2, '日経新春杯', '京都', _t, 2400),
  _g(RaceGrade.g2, 'プロキオンステークス', '京都', _d, 1800, ['プロキオンS']),
  _g(RaceGrade.g2, 'アメリカジョッキークラブカップ', '中山', _t, 2200, ['AJCC']),
  _g(RaceGrade.g2, '京都記念', '京都', _t, 2200),
  _g(RaceGrade.g2, '中山記念', '中山', _t, 1800),
  _g(RaceGrade.g2, 'チューリップ賞', '阪神', _t, 1600),
  _g(RaceGrade.g2, '弥生賞ディープインパクト記念', '中山', _t, 2000, ['弥生賞']),
  _g(RaceGrade.g2, '金鯱賞', '中京', _t, 2000),
  _g(RaceGrade.g2, 'フィリーズレビュー', '阪神', _t, 1400),
  _g(RaceGrade.g2, '阪神大賞典', '阪神', _t, 3000),
  _g(RaceGrade.g2, 'スプリングステークス', '中山', _t, 1800, ['スプリングS']),
  _g(RaceGrade.g2, '日経賞', '中山', _t, 2500),
  _g(RaceGrade.g2, 'ニュージーランドトロフィー', '中山', _t, 1600, ['NZT']),
  _g(RaceGrade.g2, '阪神牝馬ステークス', '阪神', _t, 1600, ['阪神牝馬S']),
  _g(RaceGrade.g2, 'フローラステークス', '東京', _t, 2000, ['フローラS']),
  _g(RaceGrade.g2, 'マイラーズカップ', '京都', _t, 1600, ['マイラーズC']),
  _g(RaceGrade.g2, '青葉賞', '東京', _t, 2400),
  _g(RaceGrade.g2, '京都新聞杯', '京都', _t, 2200),
  _g(RaceGrade.g2, '京王杯スプリングカップ', '東京', _t, 1400, ['京王杯SC']),
  _g(RaceGrade.g2, '目黒記念', '東京', _t, 2500),
  _g(RaceGrade.g2, '札幌記念', '札幌', _t, 2000),
  _g(RaceGrade.g2, '紫苑ステークス', '中山', _t, 2000, ['紫苑S']),
  _g(RaceGrade.g2, 'セントウルステークス', '阪神', _t, 1200, ['セントウルS']),
  _g(RaceGrade.g2, 'ローズステークス', '阪神', _t, 1800, ['ローズS']),
  _g(RaceGrade.g2, 'セントライト記念', '中山', _t, 2200),
  _g(RaceGrade.g2, '神戸新聞杯', '阪神', _t, 2400),
  _g(RaceGrade.g2, 'オールカマー', '中山', _t, 2200),
  _g(RaceGrade.g2, '毎日王冠', '東京', _t, 1800),
  _g(RaceGrade.g2, '京都大賞典', '京都', _t, 2400),
  _g(RaceGrade.g2, 'アイルランドトロフィー', '東京', _t, 1800),
  _g(RaceGrade.g2, '富士ステークス', '東京', _t, 1600, ['富士S']),
  _g(RaceGrade.g2, 'スワンステークス', '京都', _t, 1400, ['スワンS']),
  _g(RaceGrade.g2, '京王杯2歳ステークス', '東京', _t, 1400, ['京王杯2歳S']),
  _g(RaceGrade.g2, 'アルゼンチン共和国杯', '東京', _t, 2500, ['AR共和国杯']),
  _g(RaceGrade.g2, 'デイリー杯2歳ステークス', '京都', _t, 1600, ['デイリー杯2歳S']),
  _g(RaceGrade.g2, '東京スポーツ杯2歳ステークス', '東京', _t, 1800, ['東スポ杯2歳S']),
  _g(RaceGrade.g2, 'ステイヤーズステークス', '中山', _t, 3600, ['ステイヤーズS']),
  _g(RaceGrade.g2, '阪神カップ', '阪神', _t, 1400, ['阪神C']),

  // ---- G3 ----
  _g(RaceGrade.g3, '中山金杯', '中山', _t, 2000),
  _g(RaceGrade.g3, '京都金杯', '京都', _t, 1600),
  _g(RaceGrade.g3, 'シンザン記念', '京都', _t, 1600),
  _g(RaceGrade.g3, 'フェアリーステークス', '中山', _t, 1600, ['フェアリーS']),
  _g(RaceGrade.g3, '小倉牝馬ステークス', '小倉', _t, 2000, ['小倉牝馬S']),
  _g(RaceGrade.g3, '京成杯', '中山', _t, 2000),
  _g(RaceGrade.g3, '根岸ステークス', '東京', _d, 1400, ['根岸S']),
  _g(RaceGrade.g3, 'シルクロードステークス', '京都', _t, 1200, ['シルクロードS']),
  _g(RaceGrade.g3, '東京新聞杯', '東京', _t, 1600),
  _g(RaceGrade.g3, 'きさらぎ賞', '京都', _t, 1800),
  _g(RaceGrade.g3, 'クイーンカップ', '東京', _t, 1600, ['クイーンC']),
  _g(RaceGrade.g3, '共同通信杯', '東京', _t, 1800),
  _g(RaceGrade.g3, 'ダイヤモンドステークス', '東京', _t, 3400, ['ダイヤモンドS']),
  _g(RaceGrade.g3, '小倉大賞典', '小倉', _t, 1800),
  _g(RaceGrade.g3, '阪急杯', '阪神', _t, 1400),
  _g(RaceGrade.g3, 'オーシャンステークス', '中山', _t, 1200, ['オーシャンS']),
  _g(RaceGrade.g3, '中山牝馬ステークス', '中山', _t, 1800, ['中山牝馬S']),
  _g(RaceGrade.g3, 'ファルコンステークス', '中京', _t, 1400, ['ファルコンS']),
  _g(RaceGrade.g3, 'フラワーカップ', '中山', _t, 1800, ['フラワーC']),
  _g(RaceGrade.g3, '愛知杯', '中京', _t, 1400),
  _g(RaceGrade.g3, '毎日杯', '阪神', _t, 1800),
  _g(RaceGrade.g3, 'マーチステークス', '中山', _d, 1800, ['マーチS']),
  _g(RaceGrade.g3, 'ダービー卿チャレンジトロフィー', '中山', _t, 1600, ['ダービー卿CT']),
  _g(RaceGrade.g3, 'チャーチルダウンズカップ', '阪神', _t, 1600, ['チャーチルダウンズC', 'アーリントンC']),
  _g(RaceGrade.g3, 'アンタレスステークス', '阪神', _d, 1800, ['アンタレスS']),
  _g(RaceGrade.g3, '福島牝馬ステークス', '福島', _t, 1800, ['福島牝馬S']),
  _g(RaceGrade.g3, 'ユニコーンステークス', '京都', _d, 1900, ['ユニコーンS']),
  _g(RaceGrade.g3, '新潟大賞典', '新潟', _t, 2000),
  _g(RaceGrade.g3, 'エプソムカップ', '東京', _t, 1800, ['エプソムC']),
  _g(RaceGrade.g3, '平安ステークス', '京都', _d, 1900, ['平安S']),
  _g(RaceGrade.g3, '葵ステークス', '京都', _t, 1200, ['葵S']),
  _g(RaceGrade.g3, '函館スプリントステークス', '函館', _t, 1200, ['函館SS']),
  _g(RaceGrade.g3, '府中牝馬ステークス', '東京', _t, 1800, ['府中牝馬S']),
  _g(RaceGrade.g3, 'しらさぎステークス', '阪神', _t, 1600, ['しらさぎS']),
  _g(RaceGrade.g3, '函館記念', '函館', _t, 2000),
  _g(RaceGrade.g3, 'ラジオNIKKEI賞', '福島', _t, 1800),
  _g(RaceGrade.g3, '北九州記念', '小倉', _t, 1200),
  _g(RaceGrade.g3, '七夕賞', '福島', _t, 2000),
  _g(RaceGrade.g3, '函館2歳ステークス', '函館', _t, 1200, ['函館2歳S']),
  _g(RaceGrade.g3, '東海ステークス', '中京', _d, 1400, ['東海S']),
  _g(RaceGrade.g3, '小倉記念', '小倉', _t, 2000),
  _g(RaceGrade.g3, '中京記念', '中京', _t, 1600),
  _g(RaceGrade.g3, 'アイビスサマーダッシュ', '新潟', _t, 1000, ['アイビスSD']),
  _g(RaceGrade.g3, 'クイーンステークス', '札幌', _t, 1800, ['クイーンS']),
  _g(RaceGrade.g3, 'エルムステークス', '札幌', _d, 1700, ['エルムS']),
  _g(RaceGrade.g3, 'レパードステークス', '新潟', _d, 1800, ['レパードS']),
  _g(RaceGrade.g3, '関屋記念', '新潟', _t, 1600),
  _g(RaceGrade.g3, 'CBC賞', '中京', _t, 1200),
  _g(RaceGrade.g3, '新潟2歳ステークス', '新潟', _t, 1600, ['新潟2歳S']),
  _g(RaceGrade.g3, 'キーンランドカップ', '札幌', _t, 1200, ['キーンランドC']),
  _g(RaceGrade.g3, '中京2歳ステークス', '中京', _t, 1400, ['中京2歳S']),
  _g(RaceGrade.g3, '新潟記念', '新潟', _t, 2000),
  _g(RaceGrade.g3, '札幌2歳ステークス', '札幌', _t, 1800, ['札幌2歳S']),
  _g(RaceGrade.g3, '京成杯オータムハンデキャップ', '中山', _t, 1600, ['京成杯AH']),
  _g(RaceGrade.g3, 'チャレンジカップ', '阪神', _t, 2000, ['チャレンジC']),
  _g(RaceGrade.g3, 'シリウスステークス', '阪神', _d, 2000, ['シリウスS']),
  _g(RaceGrade.g3, 'サウジアラビアロイヤルカップ', '東京', _t, 1600, ['サウジアラビアRC']),
  _g(RaceGrade.g3, 'アルテミスステークス', '東京', _t, 1600, ['アルテミスS']),
  _g(RaceGrade.g3, 'ファンタジーステークス', '京都', _t, 1400, ['ファンタジーS']),
  _g(RaceGrade.g3, 'みやこステークス', '京都', _d, 1800, ['みやこS']),
  _g(RaceGrade.g3, '武蔵野ステークス', '東京', _d, 1600, ['武蔵野S']),
  _g(RaceGrade.g3, '福島記念', '福島', _t, 2000),
  _g(RaceGrade.g3, '京都2歳ステークス', '京都', _t, 2000, ['京都2歳S']),
  _g(RaceGrade.g3, '京阪杯', '京都', _t, 1200),
  _g(RaceGrade.g3, '鳴尾記念', '阪神', _t, 1800),
  _g(RaceGrade.g3, '中日新聞杯', '中京', _t, 2000),
  _g(RaceGrade.g3, 'カペラステークス', '中山', _d, 1200, ['カペラS']),
  _g(RaceGrade.g3, 'ターコイズステークス', '中山', _t, 1600, ['ターコイズS']),

  // ---- 障害重賞（距離は年により変わるため入れない） ----
  _g(RaceGrade.jg1, '中山グランドジャンプ', '中山', _j, null, ['中山GJ']),
  _g(RaceGrade.jg1, '中山大障害', '中山', _j, null),
  _g(RaceGrade.jg2, '阪神スプリングジャンプ', '阪神', _j, null),
  _g(RaceGrade.jg2, '京都ハイジャンプ', '京都', _j, null),
  _g(RaceGrade.jg2, '東京ハイジャンプ', '東京', _j, null),
  _g(RaceGrade.jg3, '東京ジャンプステークス', '東京', _j, null),
  _g(RaceGrade.jg3, '小倉ジャンプステークス', '小倉', _j, null, ['小倉サマージャンプ']),
  _g(RaceGrade.jg3, '新潟ジャンプステークス', '新潟', _j, null),
  _g(RaceGrade.jg3, '阪神ジャンプステークス', '阪神', _j, null),
  _g(RaceGrade.jg3, '京都ジャンプステークス', '京都', _j, null),
];

RacePreset _s(String name) => RacePreset(name, RaceGrade.special);

/// 主な特別競走・オープン・リステッド競走（重賞以外）
final List<RacePreset> specialRaces = [
  // 古馬のオープン・リステッド
  for (final n in [
    'ニューイヤーステークス',
    '淀短距離ステークス',
    '白富士ステークス',
    'カーバンクルステークス',
    '大和ステークス',
    '洛陽ステークス',
    'バレンタインステークス',
    '斑鳩ステークス',
    'アルデバランステークス',
    '仁川ステークス',
    '大阪城ステークス',
    'ポラリスステークス',
    '総武ステークス',
    '千葉ステークス',
    '東風ステークス',
    '六甲ステークス',
    '名古屋城ステークス',
    '春雷ステークス',
    '大阪-ハンブルクカップ',
    '福島民報杯',
    '天王山ステークス',
    '欅ステークス',
    '鞍馬ステークス',
    '都大路ステークス',
    '栗東ステークス',
    'メイステークス',
    '安土城ステークス',
    'ブリリアントステークス',
    '大沼ステークス',
    'マリーンステークス',
    '巴賞',
    '五稜郭ステークス',
    'TVh賞',
    'UHB賞',
    'しらかばステークス',
    '札幌日経オープン',
    '丹頂ステークス',
    '朱鷺ステークス',
    'BSN賞',
    'NST賞',
    '新潟日報賞',
    '佐渡ステークス',
    '信越ステークス',
    '関越ステークス',
    '福島テレビオープン',
    'ポートアイランドステークス',
    'オパールステークス',
    '西宮ステークス',
    'ラジオ日本賞',
    'エニフステークス',
    'グリーンチャンネルカップ',
    '太秦ステークス',
    'オクトーバーステークス',
    'カシオペアステークス',
    '霜月ステークス',
    '銀嶺ステークス',
    'リゲルステークス',
    'ギャラクシーステークス',
    '摩耶ステークス',
    'ディセンバーステークス',
    'ベテルギウスステークス',
    '日本海ステークス',
    '阿武隈ステークス',
    '豊明ステークス',
    'ペガサスジャンプステークス',
  ])
    _s(n),
  // 3歳
  for (final n in [
    'ジュニアカップ',
    '若駒ステークス',
    'ヒヤシンスステークス',
    'エルフィンステークス',
    'すみれステークス',
    '若葉ステークス',
    'アネモネステークス',
    '忘れな草賞',
    'スイートピーステークス',
    '橘ステークス',
    '鳳雛ステークス',
    '白百合ステークス',
    '若竹賞',
    'こぶし賞',
    'ゆきやなぎ賞',
    '君子蘭賞',
    '山吹賞',
    '水仙賞',
    'フリージア賞',
    'ミモザ賞',
    'セントポーリア賞',
    '梅花賞',
    'つばき賞',
    '春菜賞',
    '菜の花賞',
  ])
    _s(n),
  // 2歳
  for (final n in [
    'ダリア賞',
    'クローバー賞',
    'コスモス賞',
    'ひまわり賞',
    '野路菊ステークス',
    'りんどう賞',
    'サフラン賞',
    '芙蓉ステークス',
    'カンナステークス',
    'ききょうステークス',
    'もみじステークス',
    'アイビーステークス',
    '萩ステークス',
    '紫菊賞',
    '百日草特別',
    '赤松賞',
    '黄菊賞',
    '白菊賞',
    '秋明菊賞',
    '葉牡丹賞',
    'ベゴニア賞',
    'つわぶき賞',
    'ひいらぎ賞',
    'エリカ賞',
  ])
    _s(n),
];

RacePreset _c(String name, [String? surface]) =>
    RacePreset(name, RaceGrade.condition, surface: surface);

/// よくあるレース形式（条件戦）
final List<RacePreset> conditionRaces = [
  _c('2歳新馬'),
  _c('3歳新馬'),
  _c('2歳未勝利'),
  _c('3歳未勝利'),
  _c('2歳1勝クラス'),
  _c('3歳1勝クラス'),
  _c('3歳以上1勝クラス'),
  _c('4歳以上1勝クラス'),
  _c('3歳以上2勝クラス'),
  _c('4歳以上2勝クラス'),
  _c('3歳以上3勝クラス'),
  _c('4歳以上3勝クラス'),
  _c('2歳オープン'),
  _c('3歳オープン'),
  _c('3歳以上オープン'),
  _c('4歳以上オープン'),
  _c('障害3歳以上未勝利', _j),
  _c('障害4歳以上未勝利', _j),
  _c('障害3歳以上オープン', _j),
  _c('障害4歳以上オープン', _j),
];

RacePreset _n(String name, [List<String> aliases = const []]) =>
    RacePreset(name, RaceGrade.nar, aliases: aliases);

/// 地方競馬の主な重賞と、クラス名
final List<RacePreset> narRaces = [
  for (final n in [
    '東京大賞典',
    '帝王賞',
    '川崎記念',
    'かしわ記念',
    'JBCクラシック',
    'JBCスプリント',
    'JBCレディスクラシック',
    'JBC2歳優駿',
    'マイルチャンピオンシップ南部杯',
    'ジャパンダートクラシック',
    '全日本2歳優駿',
    '東京ダービー',
    '羽田盃',
    '東京盃',
    '日本テレビ盃',
    'さきたま杯',
    '浦和記念',
    '名古屋グランプリ',
    '東京スプリント',
    'かきつばた記念',
    '黒船賞',
    'マリーンカップ',
    'エンプレス杯',
    'クイーン賞',
    '関東オークス',
    'スパーキングレディーカップ',
    'ブリーダーズゴールドカップ',
    '白山大賞典',
    '兵庫ゴールドトロフィー',
    '名古屋大賞典',
    'ダイオライト記念',
    '佐賀記念',
    '北海道スプリントカップ',
    'レディスプレリュード',
    '兵庫チャンピオンシップ',
    '京浜盃',
    '雲取賞',
    '東京2歳優駿牝馬',
    'ハイセイコー記念',
    '平和賞',
    '鎌倉記念',
    '黒潮盃',
    '金盃',
    '大井記念',
    '東京記念',
    '勝島王冠',
    'フジノウェーブ記念',
    '報知オールスターカップ',
    '習志野きらっとスプリント',
    '東京シンデレラマイル',
    '東海菊花賞',
    'みちのく大賞典',
    'ダービーグランプリ',
    'ばんえい記念',
  ])
    _n(n),
  for (final c in ['A1', 'A2', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'])
    _n('$c（地方）', [c]),
];

final List<RacePreset> allRacePresets = [
  ...gradedRaces,
  ...specialRaces,
  ...conditionRaces,
  ...narRaces,
];

final Map<String, RacePreset> _byName = {
  for (final p in allRacePresets) p.name: p,
};

/// 名前からレースの情報を引く（自由入力の名前なら null）
RacePreset? presetByName(String? name) => name == null ? null : _byName[name];

/// 検索用に表記をそろえる（ひらがな→カタカナ、全角英数→半角、大文字→小文字、空白除去）
String normalizeRaceText(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    var c = r;
    if (c >= 0x3041 && c <= 0x3096) c += 0x60; // ひらがな → カタカナ
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角英数記号 → 半角
    if (c == 0x20 || c == 0x3000) continue;
    buf.writeCharCode(c);
  }
  return buf.toString().toLowerCase();
}

/// レース名を検索する。[query] が空なら [grades] に当てはまる全件。
List<RacePreset> searchRacePresets(String query, {Set<RaceGrade>? grades}) {
  final q = normalizeRaceText(query);
  return [
    for (final p in allRacePresets)
      if ((grades == null || grades.contains(p.grade)) &&
          (q.isEmpty ||
              normalizeRaceText(p.name).contains(q) ||
              p.aliases.any((a) => normalizeRaceText(a).contains(q))))
        p,
  ];
}
