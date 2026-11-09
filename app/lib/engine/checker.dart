/// Deterministic checks for the non-free-text step types. No model, no randomness:
/// the correct answer is in the content bundle and every comparison is exact (or within the
/// tolerance the content declares).
library;

import '../data/models.dart';

class CheckResult {
  const CheckResult(this.correct, {this.message = ''});
  final bool correct;
  final String message;
}

/// Removes all whitespace so `shift( -k )` equals `shift(-k)`.
String normaliseCode(String s) => s.replaceAll(RegExp(r'\s+'), '');

class Checker {
  const Checker._();

  static CheckResult mcq(StepData step, String? selectedId) {
    if (selectedId == null) return const CheckResult(false, message: 'Choose an option first.');
    final opt = step.options.firstWhere((o) => o.id == selectedId);
    return CheckResult(opt.correct, message: opt.explanation);
  }

  /// multi_select and kpi_builder: the selected set must equal the correct set exactly.
  static CheckResult multi(StepData step, Set<String> selected) {
    final correct = {for (final o in step.options.where((o) => o.correct)) o.id};
    final missed = correct.difference(selected).length;
    final wrong = selected.difference(correct).length;
    if (missed == 0 && wrong == 0) return const CheckResult(true, message: 'All correct.');
    final parts = <String>[
      if (missed > 0) '$missed correct ${missed == 1 ? "choice is" : "choices are"} missing',
      if (wrong > 0) '$wrong selected ${wrong == 1 ? "choice is" : "choices are"} wrong',
    ];
    return CheckResult(false, message: '${parts.join(' and ')}.');
  }

  static CheckResult order(StepData step, List<String> userOrder) {
    final target = step.items;
    var inPlace = 0;
    for (var i = 0; i < target.length && i < userOrder.length; i++) {
      if (target[i] == userOrder[i]) inPlace++;
    }
    final ok = inPlace == target.length;
    return CheckResult(ok, message: ok ? 'Correct order.' : '$inPlace of ${target.length} are in the right place.');
  }

  /// numeric: |answer - value| <= tolerance. If the result is shown as a percentage, "27" and "27%"
  /// are read as 0.27 too.
  static CheckResult numeric(StepData step, String input, ResultEntry result) {
    final cleaned = input.trim().replaceAll(',', '');
    final isPct = cleaned.endsWith('%') || result.display.endsWith('%');
    final x = double.tryParse(cleaned.replaceAll('%', '').trim());
    if (x == null) return const CheckResult(false, message: 'Enter a number.');
    final target = (result.value as num).toDouble();
    final tol = step.tolerance ?? 0;
    final candidates = <double>[x, if (isPct) x / 100];
    final ok = candidates.any((c) => (c - target).abs() <= tol + 1e-9);
    return CheckResult(ok, message: ok ? 'Correct.' : 'Not within the tolerance. Look at the evidence again.');
  }

  /// code_fill: each blank must match its token (or an accepted spelling), ignoring whitespace.
  static CheckResult codeFill(StepData step, List<String> inputs) {
    final blanks = step.blanks;
    var right = 0;
    for (var i = 0; i < blanks.length; i++) {
      final got = normaliseCode(i < inputs.length ? inputs[i] : '');
      final ok = [blanks[i].token, ...blanks[i].accept].any((a) => normaliseCode(a) == got);
      if (ok) right++;
    }
    final all = right == blanks.length;
    return CheckResult(all, message: all ? 'Matches the real pipeline code.' : '$right of ${blanks.length} blanks are right.');
  }

  /// code_fix: the edited code must equal the real snippet, ignoring whitespace.
  static CheckResult codeFix(String edited, String realSnippet) {
    final ok = normaliseCode(edited) == normaliseCode(realSnippet);
    return CheckResult(ok, message: ok ? 'Fixed. This is the real pipeline code.' : 'Still not the same as the working code.');
  }
}
