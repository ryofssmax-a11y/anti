import 'package:flutter/material.dart';

import 'analysis_page.dart';
import 'calc/calculator_page.dart';
import 'common.dart';
import 'home_page.dart';
import 'records_page.dart';
import 'settings_page.dart';

/// 下部タブ（ホーム・記録・計算・分析・設定）
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        if (!settings.ageConfirmed) return const _AgeGate();
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              HomePage(onOpenCalculator: () => setState(() => _index = 2)),
              const RecordsPage(),
              const CalculatorPage(),
              const AnalysisPage(),
              const SettingsPage(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'ホーム',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: '記録',
              ),
              NavigationDestination(
                icon: Icon(Icons.calculate_outlined),
                selectedIcon: Icon(Icons.calculate),
                label: '計算',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: '分析',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '設定',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 初回起動時の年齢確認
class _AgeGate extends StatefulWidget {
  const _AgeGate();

  @override
  State<_AgeGate> createState() => _AgeGateState();
}

class _AgeGateState extends State<_AgeGate> {
  bool _declined = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.calculate,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '馬券収支電卓',
                style: t.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                _declined
                    ? '20歳未満の方は馬券を購入できません。このアプリは20歳以上の方を対象にしています。'
                    : '20歳未満の方は馬券を購入できません。\nあなたは20歳以上ですか？',
                style: t.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'このアプリは馬券の記録と計算のための道具です。馬券の販売や投票の代行は行いません。計算結果は参考値で、的中や利益を約束するものではありません。',
                style: t.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (!_declined) ...[
                FilledButton(
                  onPressed: () => AppScope.of(context).settings.confirmAge(),
                  child: const Text('はい、20歳以上です'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _declined = true),
                  child: const Text('いいえ'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
