import 'package:baken_app/data/race_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('レース名に重複がない', () {
    final names = allRacePresets.map((p) => p.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('平地G1は24競走、障害J・G1は2競走', () {
    expect(gradedRaces.where((p) => p.grade == RaceGrade.g1), hasLength(24));
    expect(gradedRaces.where((p) => p.grade == RaceGrade.jg1), hasLength(2));
  });

  test('重賞は競馬場とコースを持つ', () {
    for (final p in gradedRaces) {
      expect(p.venue, isNotNull, reason: p.name);
      expect(p.surface, isNotNull, reason: p.name);
    }
  });

  test('ひらがな・略称で検索できる', () {
    expect(searchRacePresets('じゃぱん').map((p) => p.name), contains('ジャパンカップ'));
    expect(
      searchRacePresets('ダービー').map((p) => p.name),
      contains('東京優駿（日本ダービー）'),
    );
    expect(
      searchRacePresets('ajcc').map((p) => p.name),
      contains('アメリカジョッキークラブカップ'),
    );
    expect(searchRacePresets('ＪＣ').map((p) => p.name), contains('ジャパンカップ'));
    expect(
      searchRacePresets('未勝利', grades: {RaceGrade.condition}),
      hasLength(4),
    );
  });

  test('名前から情報を引く', () {
    final p = presetByName('有馬記念')!;
    expect(p.grade, RaceGrade.g1);
    expect(p.detail, '中山 芝2500m');
    expect(presetByName('自分で入れた名前'), isNull);
  });

  test('2025年以降の名称変更を反映している', () {
    expect(presetByName('チャーチルダウンズカップ'), isNotNull);
    expect(presetByName('中京2歳ステークス'), isNotNull);
    expect(presetByName('アイルランドトロフィー')!.grade, RaceGrade.g2);
    expect(presetByName('府中牝馬ステークス')!.grade, RaceGrade.g3);
    expect(presetByName('マーメイドステークス'), isNull);
    expect(presetByName('プロキオンステークス')!.grade, RaceGrade.g2);
    expect(presetByName('東海ステークス')!.distance, 1400);
  });
}
