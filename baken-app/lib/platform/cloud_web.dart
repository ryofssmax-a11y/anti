import 'dart:js_interop';

import 'cloud.dart';

/// ページ側の JavaScript（index.html の bakenCloud）
@JS('bakenCloud')
external _BakenCloud? get _bakenCloud;

extension type _BakenCloud(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> available();
  external JSPromise<JSString?> load();
  external JSPromise<JSBoolean> save(JSString json);
  external JSPromise<JSBoolean> download(JSString filename, JSString text);
}

class _WebCloudStore implements CloudStore {
  _WebCloudStore(this._js);
  final _BakenCloud _js;

  @override
  Future<bool> available() async => (await _js.available().toDart).toDart;

  @override
  Future<String?> load() async => (await _js.load().toDart)?.toDart;

  @override
  Future<bool> save(String json) async =>
      (await _js.save(json.toJS).toDart).toDart;
}

CloudStore? createCloudStore() {
  final js = _bakenCloud;
  return js == null ? null : _WebCloudStore(js);
}

Future<bool> saveTextFile(String filename, String text) async {
  final js = _bakenCloud;
  if (js == null) return false;
  return (await js.download(filename.toJS, text.toJS).toDart).toDart;
}
