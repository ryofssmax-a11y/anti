import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/settings.dart';

/// アプリ全体で使う DB と設定を配る。
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.db,
    required this.settings,
    required super.child,
  });

  final AppDatabase db;
  final AppSettings settings;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      db != oldWidget.db || settings != oldWidget.settings;
}

final _yen = NumberFormat('#,##0', 'ja_JP');

String yen(int v) => '${_yen.format(v)}円';

/// 符号つきの金額（収支用）
String signedYen(int v) => '${v > 0 ? '+' : ''}${_yen.format(v)}円';

String percent(double? v) => v == null ? '―' : '${v.toStringAsFixed(1)}%';

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String jpDate(String iso) {
  final d = DateTime.parse(iso);
  const w = ['月', '火', '水', '木', '金', '土', '日'];
  return '${d.month}/${d.day}（${w[d.weekday - 1]}）';
}

DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// 収支の色（プラスは青、マイナスは赤）
Color profitColor(BuildContext context, int v) {
  final scheme = Theme.of(context).colorScheme;
  if (v > 0) return Colors.blue.shade700;
  if (v < 0) return scheme.error;
  return scheme.onSurfaceVariant;
}

/// 指標を並べるタイル
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: t.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: t.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 100円単位で増減する金額入力
class StakeStepper extends StatelessWidget {
  const StakeStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String? label;

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: '$value');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label ?? '金額'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            suffixText: '円',
            helperText: '100円単位',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.replaceAll(',', ''));
              Navigator.pop(ctx, v == null ? null : (v ~/ 100) * 100);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null && result >= 100) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '100円減らす',
          onPressed: value > 100 ? () => onChanged(value - 100) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        InkWell(
          onTap: () => _edit(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              yen(value),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        IconButton(
          tooltip: '100円増やす',
          onPressed: () => onChanged(value + 100),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String ok = 'OK',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// DB の内容を読み込んで表示する。記録が変わると読み直す。
///
/// 読み込む条件が変わったら、呼び出し側で [key] を変えて作り直す。
class DbQuery<T> extends StatefulWidget {
  const DbQuery({super.key, required this.load, required this.builder});

  final Future<T> Function(AppDatabase db) load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<DbQuery<T>> createState() => _DbQueryState<T>();
}

class _DbQueryState<T> extends State<DbQuery<T>> {
  AppDatabase? _db;
  T? _data;
  bool _loaded = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = AppScope.of(context).db;
    if (db != _db) {
      _db?.removeListener(_reload);
      _db = db..addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _db?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final gen = ++_generation;
    final data = await widget.load(_db!);
    if (!mounted || gen != _generation) return;
    setState(() {
      _data = data;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, _data as T);
  }
}
