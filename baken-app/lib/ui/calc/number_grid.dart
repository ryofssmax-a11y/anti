import 'package:flutter/material.dart';

/// マークシート式の番号選択
class NumberGrid extends StatelessWidget {
  const NumberGrid({
    super.key,
    required this.max,
    required this.selected,
    required this.onToggle,
    this.disabled = const {},
    this.single = false,
  });

  final int max;
  final Set<int> selected;
  final Set<int> disabled;
  final bool single;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var n = 1; n <= max; n++)
          _Cell(
            number: n,
            selected: selected.contains(n),
            disabled: disabled.contains(n),
            single: single,
            scheme: scheme,
            onTap: () => onToggle(n),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.number,
    required this.selected,
    required this.disabled,
    required this.single,
    required this.scheme,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final bool disabled;
  final bool single;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? scheme.primary : Colors.transparent;
    final fg = disabled
        ? scheme.onSurface.withValues(alpha: 0.3)
        : selected
        ? scheme.onPrimary
        : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: '$number番${disabled ? '（取消）' : ''}',
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(single ? 22 : 8),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(single ? 22 : 8),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
            ),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              decoration: disabled ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}
