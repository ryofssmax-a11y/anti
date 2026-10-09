import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'data/backup.dart';
import 'data/cloud_sync.dart';
import 'data/database.dart';
import 'data/settings.dart';
import 'platform/cloud.dart';
import 'ui/common.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja');
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'IPAGothic',
    ], await rootBundle.loadString('assets/fonts/IPA_Font_License.txt'));
  });
  if (kIsWeb) {
    // ブラウザ版: SQLite（wasm）をブラウザの中に置く
    databaseFactory = databaseFactoryFfiWebNoWebWorker;
  }
  final db = await AppDatabase.open();
  final settings = await AppSettings.load();
  final backup = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? (BackupService(db: db, settings: settings)..start())
      : null;
  final store = kIsWeb ? createCloudStore() : null;
  final cloud = store == null
      ? null
      : CloudSyncService(db: db, settings: settings, store: store);
  runApp(BakenApp(db: db, settings: settings, backup: backup, cloud: cloud));
  // 画面を出してから、保存してある記録を確認する
  cloud?.start();
}

class BakenApp extends StatelessWidget {
  const BakenApp({
    super.key,
    required this.db,
    required this.settings,
    this.backup,
    this.cloud,
  });

  final AppDatabase db;
  final AppSettings settings;
  final BackupService? backup;
  final CloudSyncService? cloud;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E7D32),
        brightness: b,
      ),
      fontFamily: kIsWeb ? 'IPAGothic' : null,
      useMaterial3: true,
    );
    return AppScope(
      db: db,
      settings: settings,
      backup: backup,
      cloud: cloud,
      child: MaterialApp(
        title: '馬券収支電卓',
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        locale: const Locale('ja', 'JP'),
        supportedLocales: const [Locale('ja', 'JP')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const AppShell(),
      ),
    );
  }
}
