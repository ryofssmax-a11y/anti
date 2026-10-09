import 'package:flutter/material.dart';

import '../data/race_names.dart';
import 'common.dart';

/// 重賞の格を色つきで示すバッジ（G1 青・G2 赤・G3 緑）
class GradeBadge extends StatelessWidget {
  const GradeBadge(this.grade, {super.key, this.small = false});

  final RaceGrade grade;
  final bool small;

  static GradeBadge? forName(String? name, {bool small = false}) {
    final g = presetByName(name)?.grade;
    if (g == null || !(g.isGraded || g == RaceGrade.listed)) return null;
    return GradeBadge(g, small: small);
  }

  Color get color => switch (grade) {
    RaceGrade.g1 || RaceGrade.jg1 => const Color(0xFF1565C0),
    RaceGrade.g2 || RaceGrade.jg2 => const Color(0xFFC62828),
    RaceGrade.g3 || RaceGrade.jg3 => const Color(0xFF2E7D32),
    RaceGrade.listed => const Color(0xFF6A1B9A),
    _ => const Color(0xFF757575),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 5 : 7,
        vertical: small ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        grade.label,
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 一覧の絞り込み
enum _Filter {
  all('すべて', null),
  history('最近', null),
  g1('G1', {RaceGrade.g1}),
  g2('G2', {RaceGrade.g2}),
  g3('G3', {RaceGrade.g3}),
  jump('障害重賞', {RaceGrade.jg1, RaceGrade.jg2, RaceGrade.jg3}),
  special('特別・OP', {RaceGrade.special, RaceGrade.listed}),
  condition('条件戦', {RaceGrade.condition}),
  nar('地方', {RaceGrade.nar});

  const _Filter(this.label, this.grades);
  final String label;
  final Set<RaceGrade>? grades;
}

/// レース名を選ぶ画面。名前（文字列）を返す。一覧にない名前もそのまま使える。
class RaceNamePickerPage extends StatefulWidget {
  const RaceNamePickerPage({super.key, this.initial});

  final String? initial;

  @override
  State<RaceNamePickerPage> createState() => _RaceNamePickerPageState();
}

class _RaceNamePickerPageState extends State<RaceNamePickerPage> {
  final _query = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _query.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          decoration: const InputDecoration(
            hintText: 'レース名で検索（例: ありま、ダービー）',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
        ),
        actions: [
          if (q.isNotEmpty)
            IconButton(
              tooltip: '検索をクリア',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_query.clear),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: DbQuery<List<String>>(
              load: (db) => db.recentRaceNames(),
              builder: (context, recent) {
                final items = _items(q, recent);
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final it = items[i];
                    if (it is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          it,
                          style: t.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    }
                    if (it is _Free) {
                      return ListTile(
                        leading: const Icon(Icons.edit),
                        title: Text('「${it.name}」をレース名にする'),
                        onTap: () => Navigator.pop(context, it.name),
                      );
                    }
                    final p = it as RacePreset;
                    final badge = GradeBadge.forName(p.name);
                    return ListTile(
                      leading: SizedBox(
                        width: 48,
                        child: Center(
                          child: badge ?? const Icon(Icons.flag_outlined),
                        ),
                      ),
                      title: Text(p.name),
                      subtitle: p.detail.isEmpty ? null : Text(p.detail),
                      selected: p.name == widget.initial,
                      onTap: () => Navigator.pop(context, p.name),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 表示する行（見出し String・候補 RacePreset・自由入力 _Free）
  List<Object> _items(String q, List<String> recent) {
    final out = <Object>[];
    if (q.isNotEmpty && presetByName(q) == null) out.add(_Free(q));

    final recentPresets = [
      for (final n in recent)
        if (q.isEmpty || normalizeRaceText(n).contains(normalizeRaceText(q)))
          presetByName(n) ?? RacePreset(n, RaceGrade.special),
    ];

    if (_filter == _Filter.history) {
      if (recentPresets.isEmpty) out.add('まだ記録したレースはありません');
      out.addAll(recentPresets);
      return out;
    }

    if (_filter == _Filter.all && recentPresets.isNotEmpty && q.isEmpty) {
      out
        ..add('最近のレース')
        ..addAll(recentPresets.take(5));
    }

    final found = searchRacePresets(q, grades: _filter.grades);
    if (_filter != _Filter.all) {
      out.addAll(found);
      return out;
    }
    const sections = [
      ('G1', {RaceGrade.g1}),
      ('G2', {RaceGrade.g2}),
      ('G3', {RaceGrade.g3}),
      ('障害重賞', {RaceGrade.jg1, RaceGrade.jg2, RaceGrade.jg3}),
      ('特別・オープン', {RaceGrade.special, RaceGrade.listed}),
      ('条件戦', {RaceGrade.condition}),
      ('地方競馬', {RaceGrade.nar}),
    ];
    for (final (label, grades) in sections) {
      final part = found.where((p) => grades.contains(p.grade)).toList();
      if (part.isEmpty) continue;
      out
        ..add(label)
        ..addAll(part);
    }
    if (found.isEmpty && q.isNotEmpty) out.add('一覧に見つかりません。上の行からそのまま使えます');
    return out;
  }
}

class _Free {
  const _Free(this.name);
  final String name;
}
