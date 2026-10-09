import 'package:flutter/material.dart';

import 'common.dart';

/// 記録の保存後に予算上限を確かめ、80% と 100% を超えたら知らせる（登録は止めない）。
Future<void> checkBudget(BuildContext context, String date) async {
  final scope = AppScope.of(context);
  final s = scope.settings;
  final d = DateTime.parse(date);
  final weekStart = d.subtract(Duration(days: d.weekday - 1));
  final checks = [
    ('今日', s.budgetDay, date, date),
    (
      '今週',
      s.budgetWeek,
      isoDate(weekStart),
      isoDate(weekStart.add(const Duration(days: 6))),
    ),
    (
      '今月',
      s.budgetMonth,
      isoDate(DateTime(d.year, d.month, 1)),
      isoDate(DateTime(d.year, d.month + 1, 0)),
    ),
  ];
  final messages = <String>[];
  for (final (label, limit, from, to) in checks) {
    if (limit <= 0) continue;
    final spent = await scope.db.stakeBetween(from, to);
    if (spent >= limit) {
      messages.add('$labelの投資額が上限（${yen(limit)}）を超えました。現在 ${yen(spent)}');
    } else if (spent >= limit * 0.8) {
      messages.add('$labelの投資額が上限の80%に達しました。現在 ${yen(spent)} / ${yen(limit)}');
    }
  }
  if (messages.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: const Text('予算上限のお知らせ'),
      content: Text(messages.join('\n\n')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
