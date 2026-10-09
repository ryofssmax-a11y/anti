import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/database.dart';
import 'data/settings.dart';
import 'ui/common.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja_JP');
  final db = await AppDatabase.open();
  final settings = await AppSettings.load();
  runApp(BakenApp(db: db, settings: settings));
}

class BakenApp extends StatelessWidget {
  const BakenApp({super.key, required this.db, required this.settings});

  final AppDatabase db;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E7D32),
        brightness: b,
      ),
      useMaterial3: true,
    );
    return AppScope(
      db: db,
      settings: settings,
      child: MaterialApp(
        title: '馬券収支電卓',
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
