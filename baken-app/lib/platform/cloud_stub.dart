import 'cloud.dart';

CloudStore? createCloudStore() => null;

/// ファイルを保存させる（ブラウザ版のみ）。アプリ版では false。
Future<bool> saveTextFile(String filename, String text) async => false;
