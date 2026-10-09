import '../../core/selection.dart';
import '../../data/models.dart';

/// 計算画面から記録画面へ渡す内容
class CalcOutput {
  CalcOutput({required this.selection, required this.lines});

  final Selection selection;

  /// 金額・オッズつきの買い目
  final List<TicketLine> lines;

  int get total => lines.fold(0, (s, l) => s + l.stake);
}
