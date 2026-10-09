import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/race_names.dart';
import '../data/race_schedule.dart';
import 'common.dart';
import 'race_name_picker.dart';
import 'record_inputs.dart';

/// 週のレース一覧や 1R〜最終R の一覧で選んだレース
class RacePick {
  const RacePick({
    required this.date,
    required this.venue,
    this.raceNo,
    this.name,
  });

  final DateTime date;
  final String venue;
  final int? raceNo;

  /// 分かっているレース名（分からなければ null）
  final String? name;
}

/// 最終レースの番号
const lastRaceNo = 12;

const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

String _md(DateTime d) => '${d.month}/${d.day}（${_weekdays[d.weekday - 1]}）';

/// 選んだ日付の週に行われる重賞と、この時期の特別レース。
class WeekRacesPanel extends StatelessWidget {
  const WeekRacesPanel({
    super.key,
    required this.date,
    required this.onPick,
    this.selectedName,
  });

  final DateTime date;
  final ValueChanged<RacePick> onPick;
  final String? selectedName;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final week = raceWeekOf(date);
    final graded = gradedRacesInWeek(date);
    final specials = specialRacesInMonth(date.month);
    final estimated = date.year != scheduleYear;
    return Card.outlined(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Icon(Icons.event_note, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'この週の重賞  ${_md(week.start.add(const Duration(days: 4)))}〜${_md(week.end)}',
                    style: t.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          if (estimated)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '$scheduleYear年の日程から推定しています',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (graded.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Text(
                'この週は重賞がありません',
                style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final r in graded)
            ListTile(
              dense: true,
              selected: r.name == selectedName && r.date == date,
              leading: GradeBadge(r.preset.grade),
              title: Text(r.name),
              subtitle: Text(
                '${_md(r.date)} ${r.venue}'
                '${r.raceNo == null ? '' : ' ${r.raceNo}R'}'
                '${r.preset.detail.isEmpty ? '' : '・${r.preset.detail.replaceFirst('${r.venue} ', '')}'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onPick(
                RacePick(
                  date: r.date,
                  venue: r.venue,
                  raceNo: r.raceNo,
                  name: r.name,
                ),
              ),
            ),
          if (specials.isNotEmpty)
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                title: Text('${date.month}月ごろの特別・オープン（${specials.length}）'),
                subtitle: const Text('例年の時期の目安です。日付はそのままです'),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in specials)
                        ActionChip(
                          label: Text(p.name),
                          onPressed: () => onPick(
                            RacePick(date: date, venue: '', name: p.name),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 1R〜最終R の一覧を開いて、選んだレースを返す
Future<RacePick?> showDayRaceList(
  BuildContext context, {
  required DateTime date,
  required String venue,
  int? raceNo,
}) => Navigator.push<RacePick>(
  context,
  MaterialPageRoute(
    builder: (_) => DayRacesPage(date: date, venue: venue, raceNo: raceNo),
  ),
);

/// 開催日・競馬場ごとの 1R〜最終R の一覧
class DayRacesPage extends StatefulWidget {
  const DayRacesPage({
    super.key,
    required this.date,
    required this.venue,
    this.raceNo,
  });

  final DateTime date;
  final String venue;
  final int? raceNo;

  @override
  State<DayRacesPage> createState() => _DayRacesPageState();
}

class _DayRacesPageState extends State<DayRacesPage> {
  /// その週の開催日
  late final List<DateTime> _days = raceDaysInWeek(widget.date);

  /// 選んだ日が開催日でなければ、その週の次の開催日（なければ最後の開催日）
  late DateTime _date = _days.contains(widget.date)
      ? widget.date
      : _days.firstWhere(
          (d) => d.isAfter(widget.date),
          orElse: () => _days.last,
        );
  late String _venue = _venueFor(_date, widget.venue);

  /// その日に重賞のない競馬場なら、重賞のある競馬場にする
  static String _venueFor(DateTime d, String current) {
    final vs = {for (final r in gradedRacesOn(d)) r.venue};
    return vs.isEmpty || vs.contains(current) ? current : vs.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final graded = gradedRacesOn(_date);
    final gradedVenues = {for (final r in graded) r.venue};
    final byNo = {
      for (final r in graded)
        if (r.venue == _venue && r.raceNo != null) r.raceNo!: r,
    };
    final undecided = [
      for (final r in graded)
        if (r.venue == _venue && r.raceNo == null) r,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('レースを選ぶ（1R〜最終R）')),
      body: DbQuery<List<Race>>(
        key: ValueKey(isoDate(_date)),
        load: (db) => db.racesOn(isoDate(_date)),
        builder: (context, recorded) {
          final mine = {
            for (final r in recorded)
              if (r.venue == _venue) r.raceNo: r,
          };
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in _days)
                      ChoiceChip(
                        label: Text(_md(d)),
                        selected: d == _date,
                        onSelected: (_) => setState(() {
                          _date = d;
                          _venue = _venueFor(d, _venue);
                        }),
                      ),
                  ],
                ),
              ),
              if (gradedVenues.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    '重賞: ${[for (final r in graded) '${r.venue} ${r.name}'].join('、')}',
                    style: t.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: VenueChooser(
                  venue: _venue,
                  onChanged: (v) => setState(() => _venue = v),
                ),
              ),
              const Divider(height: 1),
              for (final r in undecided)
                ListTile(
                  leading: const SizedBox(width: 40, child: Text('―')),
                  title: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      GradeBadge(r.preset.grade, small: true),
                      Text(r.name),
                    ],
                  ),
                  subtitle: const Text('レース番号は一覧の中から選び直してください'),
                  onTap: () => Navigator.pop(
                    context,
                    RacePick(date: _date, venue: _venue, name: r.name),
                  ),
                ),
              for (var n = 1; n <= lastRaceNo; n++)
                _RaceRow(
                  no: n,
                  graded: byNo[n],
                  recorded: mine[n],
                  selected:
                      _date == widget.date &&
                      _venue == widget.venue &&
                      n == widget.raceNo,
                  onTap: () => Navigator.pop(
                    context,
                    RacePick(
                      date: _date,
                      venue: _venue,
                      raceNo: n,
                      name: byNo[n]?.name ?? mine[n]?.name,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RaceRow extends StatelessWidget {
  const _RaceRow({
    required this.no,
    required this.graded,
    required this.recorded,
    required this.selected,
    required this.onTap,
  });

  final int no;
  final ScheduledRace? graded;
  final Race? recorded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = graded?.name ?? recorded?.name;
    final has = name != null && name.isNotEmpty;
    final label = no == lastRaceNo
        ? '最終レース'
        : no == 11
        ? 'メインレース'
        : '$noレース';
    final info = [
      if (graded != null && graded!.preset.detail.isNotEmpty)
        graded!.preset.detail,
      if (recorded != null) '記録あり',
    ];
    return ListTile(
      dense: !has,
      selected: selected,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: graded != null
            ? scheme.primary
            : scheme.surfaceContainerHighest,
        foregroundColor: graded != null
            ? scheme.onPrimary
            : scheme.onSurfaceVariant,
        child: Text(
          '${no}R',
          style: t.labelMedium?.copyWith(
            color: graded != null ? scheme.onPrimary : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: has
          ? Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [?GradeBadge.forName(name, small: true), Text(name)],
            )
          : Text(
              label,
              style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
      subtitle: has || info.isNotEmpty
          ? Text([if (has) label, ...info].join('・'))
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// 名前が重賞かどうか（一覧で番号だけ選んだとき、前の重賞名を消すため）
bool isGradedName(String? name) => presetByName(name)?.grade.isGraded ?? false;
