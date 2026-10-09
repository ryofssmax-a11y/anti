/// ブラウザ版（Claude のアーティファクト）でだけ使う機能。
///
/// アプリ版では何もしない実装になる。
library;

export 'cloud_stub.dart' if (dart.library.js_interop) 'cloud_web.dart';

/// 記録を外部（アーティファクトのデータ保存）に置く先
abstract class CloudStore {
  /// 使えるか（アーティファクトの中で開いていて、サインインしているか）
  Future<bool> available();

  /// 保存してあるバックアップ JSON。なければ空文字、使えなければ null。
  Future<String?> load();

  /// バックアップ JSON を保存する。
  Future<bool> save(String json);
}
