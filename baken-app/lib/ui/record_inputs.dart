import 'package:flutter/material.dart';

import '../core/bet_type.dart';
import '../data/race_names.dart';
import 'common.dart';
import 'race_name_picker.dart';

/// 記録画面の入力部品。タップだけで選べるようにする。

/// 直近の指定曜日（今日を含む過去方向）
DateTime lastWeekday(DateTime from, int weekday) =>
    from.subtract(Duration(days: (from.weekday - weekday) % 7));

/// レース名の選択欄
class RaceNameField extends StatelessWidget {
  const RaceNameField({
    super.key,
    required this.name,
    required this.onPicked,
    this.enabled = true,
  });

  final String? name;
  final ValueChanged<String?> onPicked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final preset = presetByName(name);
    final badge = GradeBadge.forName(name);
    final has = name != null && name!.isNotEmpty;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: !enabled
            ? null
            : () async {
                final picked = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RaceNamePickerPage(initial: name),
                  ),
                );
                if (picked != null) onPicked(picked);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'レース名',
                      style: t.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (has)
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ?badge,
                          Text(
                            name!,
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'タップして選ぶ（重賞・特別・条件戦）',
                        style: t.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (preset != null && preset.detail.isNotEmpty)
                      Text(
                        '標準: ${preset.detail}',
                        style: t.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (has && enabled)
                IconButton(
                  tooltip: 'レース名を消す',
                  icon: const Icon(Icons.close),
                  onPressed: () => onPicked(null),
                )
              else if (enabled)
                TextButton.icon(
                  onPressed: () async {
                    final n = await showRaceNameInputDialog(context);
                    if (n != null) onPicked(n);
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('入力'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日付（今日・昨日・土曜・日曜のチップと、カレンダー）
class DateChooser extends StatelessWidget {
  const DateChooser({
    super.key,
    required this.date,
    required this.onChanged,
    this.enabled = true,
  });

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final now = today();
    final options = <(String, DateTime)>[
      ('今日', now),
      ('昨日', now.subtract(const Duration(days: 1))),
      ('土曜', lastWeekday(now, DateTime.saturday)),
      ('日曜', lastWeekday(now, DateTime.sunday)),
    ];
    final matched = options.any((o) => o.$2 == date);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (label, d) in options)
          ChoiceChip(
            label: Text('$label ${d.month}/${d.day}'),
            selected: d == date,
            onSelected: enabled ? (_) => onChanged(d) : null,
          ),
        ActionChip(
          avatar: const Icon(Icons.event, size: 18),
          label: Text(matched ? '日付を選ぶ' : jpDate(isoDate(date))),
          onPressed: !enabled
              ? null
              : () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) onChanged(d);
                },
        ),
      ],
    );
  }
}

/// 競馬場（JRA 10場はチップ、地方・その他は一覧から）
class VenueChooser extends StatelessWidget {
  const VenueChooser({
    super.key,
    required this.venue,
    required this.onChanged,
    this.enabled = true,
  });

  final String venue;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isJra = jraVenues.contains(venue);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in jraVenues)
          ChoiceChip(
            label: Text(v),
            selected: v == venue,
            onSelected: enabled ? (_) => onChanged(v) : null,
          ),
        ChoiceChip(
          label: Text(isJra ? '地方・その他' : venue),
          selected: !isJra,
          onSelected: !enabled
              ? null
              : (_) async {
                  final v = await showModalBottomSheet<String>(
                    context: context,
                    showDragHandle: true,
                    builder: (ctx) => ListView(
                      shrinkWrap: true,
                      children: [
                        for (final v in [...narVenues, otherVenue])
                          ListTile(
                            title: Text(v),
                            onTap: () => Navigator.pop(ctx, v),
                          ),
                      ],
                    ),
                  );
                  if (v != null) onChanged(v);
                },
        ),
      ],
    );
  }
}

/// レース番号（1〜12R のチップ）
class RaceNoChooser extends StatelessWidget {
  const RaceNoChooser({
    super.key,
    required this.raceNo,
    required this.onChanged,
    this.enabled = true,
  });

  final int raceNo;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var n = 1; n <= 12; n++)
          ChoiceChip(
            label: SizedBox(
              width: 24,
              child: Text('${n}R', textAlign: TextAlign.center),
            ),
            selected: n == raceNo,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: enabled ? (_) => onChanged(n) : null,
          ),
      ],
    );
  }
}

/// 項目の見出し
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
