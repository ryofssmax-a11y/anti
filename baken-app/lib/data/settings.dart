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

  /// 前回の記録で選んだ競馬場・購入方法（次の入力の初期値にする）
  String? get lastVenue => _prefs.getString('lastVenue');
  String? get lastChannel => _prefs.getString('lastChannel');

  Future<void> rememberRecordInput({
    required String venue,
    required String channel,
  }) async {
    await _prefs.setString('lastVenue', venue);
    await _prefs.setString('lastChannel', channel);
  }

  /// 自分で登録したレース名（新しい順）
  List<String> get customRaceNames =>
      _prefs.getStringList('customRaceNames') ?? const [];

  Future<void> addCustomRaceName(String name) async {
    final list = [name, ...customRaceNames.where((n) => n != name)];
    await _prefs.setStringList('customRaceNames', list);
    notifyListeners();
  }

  Future<void> removeCustomRaceName(String name) async {
    await _prefs.setStringList(
      'customRaceNames',
      customRaceNames.where((n) => n != name).toList(),
    );
    notifyListeners();
  }

  // ---- 自動バックアップ ----

  /// バックアップ先のフォルダ（Android のフォルダ選択で得た URI と表示名）
  String? get backupFolderUri => _prefs.getString('backupFolderUri');
  String? get backupFolderName => _prefs.getString('backupFolderName');
  bool get autoBackup => _prefs.getBool('autoBackup') ?? false;
  DateTime? get lastBackupAt {
    final ms = _prefs.getInt('lastBackupAt');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String? get lastBackupError => _prefs.getString('lastBackupError');

  Future<void> setBackupFolder(String uri, String name) async {
    await _prefs.setString('backupFolderUri', uri);
    await _prefs.setString('backupFolderName', name);
    await _prefs.setBool('autoBackup', true);
    notifyListeners();
  }

  Future<void> setAutoBackup(bool on) async {
    await _prefs.setBool('autoBackup', on);
    notifyListeners();
  }

  Future<void> recordBackupResult({String? error}) async {
    if (error == null) {
      await _prefs.setInt(
        'lastBackupAt',
        DateTime.now().millisecondsSinceEpoch,
      );
      await _prefs.remove('lastBackupError');
    } else {
      await _prefs.setString('lastBackupError', error);
    }
    notifyListeners();
  }

  /// バックアップに含める設定
  static const _backupKeys = [
    'customRaceNames',
    'templates',
    'budgetDay',
    'budgetWeek',
    'budgetMonth',
    'defaultUnit',
    'lastVenue',
    'lastChannel',
  ];

  Map<String, Object?> exportForBackup() => {
    for (final k in _backupKeys)
      if (_prefs.get(k) != null) k: _prefs.get(k),
  };

  Future<void> importFromBackup(Map<String, Object?> values) async {
    for (final k in _backupKeys) {
      final v = values[k];
      if (v is String) {
        await _prefs.setString(k, v);
      } else if (v is int) {
        await _prefs.setInt(k, v);
      } else if (v is bool) {
        await _prefs.setBool(k, v);
      } else if (v is List) {
        await _prefs.setStringList(k, v.map((e) => '$e').toList());
      }
    }
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
