import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/selection.dart';

/// 保存した買い目のテンプレート
class BetTemplate {
  BetTemplate(this.name, this.selection, this.unitStake);

  final String name;
  final Selection selection;
  final int unitStake;

  Map<String, Object?> toJson() => {
    'name': name,
    'selection': selection.toJson(),
    'unit': unitStake,
  };

  static BetTemplate? fromJson(Map<String, Object?> json) {
    final sel = Selection.fromJson(
      (json['selection'] as Map).cast<String, Object?>(),
    );
    if (sel == null) return null;
    return BetTemplate(
      json['name'] as String? ?? '',
      sel,
      (json['unit'] as num?)?.toInt() ?? 100,
    );
  }
}

/// 端末に保存する設定
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  bool get ageConfirmed => _prefs.getBool('ageConfirmed') ?? false;
  Future<void> confirmAge() async {
    await _prefs.setBool('ageConfirmed', true);
    notifyListeners();
  }

  /// 予算上限（円、0 = 設定なし）
  int get budgetDay => _prefs.getInt('budgetDay') ?? 0;
  int get budgetWeek => _prefs.getInt('budgetWeek') ?? 0;
  int get budgetMonth => _prefs.getInt('budgetMonth') ?? 0;

  Future<void> setBudgets({
    required int day,
    required int week,
    required int month,
  }) async {
    await _prefs.setInt('budgetDay', day);
    await _prefs.setInt('budgetWeek', week);
    await _prefs.setInt('budgetMonth', month);
    notifyListeners();
  }

  /// 1点あたりの金額の初期値
  int get defaultUnit => _prefs.getInt('defaultUnit') ?? 100;
  Future<void> setDefaultUnit(int v) async {
    await _prefs.setInt('defaultUnit', v);
    notifyListeners();
  }

  /// 複勝・ワイドのオッズ（幅）のうち計算に使う方。true = 下限
  bool get useLowerOdds => _prefs.getBool('useLowerOdds') ?? true;
  Future<void> setUseLowerOdds(bool v) async {
    await _prefs.setBool('useLowerOdds', v);
    notifyListeners();
  }

  List<BetTemplate> get templates {
    final raw = _prefs.getString('templates');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => BetTemplate.fromJson((e as Map).cast<String, Object?>()))
          .whereType<BetTemplate>()
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> saveTemplates(List<BetTemplate> list) async {
    await _prefs.setString(
      'templates',
      jsonEncode(list.map((t) => t.toJson()).toList()),
    );
    notifyListeners();
  }
}
