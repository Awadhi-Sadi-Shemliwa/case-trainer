/// Quick-check questions built deterministically from the words themselves (no model, no randomness that
/// differs between devices): each question's distractors and option order come from a stable FNV hash of the
/// lesson, the word and the attempt number, so a retry shuffles differently but reproducibly.
library;

import '../util/hash.dart';
import 'course.dart';

enum QuestionKind {
  /// "Which word matches this meaning?" (options are words)
  nameTheWord,

  /// "What does `word` mean?" (options are short definitions)
  pickTheMeaning,
}

class QuizOption {
  const QuizOption(this.termId, this.text);
  final String termId;
  final String text;
}

class QuizQuestion {
  const QuizQuestion({required this.term, required this.kind, required this.options});
  final GlossaryTerm term;
  final QuestionKind kind;
  final List<QuizOption> options;

  String get prompt => switch (kind) {
        QuestionKind.nameTheWord => 'Which word matches this meaning?',
        QuestionKind.pickTheMeaning => 'What does "${term.term}" mean?',
      };

  /// Shown under the prompt for nameTheWord questions.
  String? get clue => kind == QuestionKind.nameTheWord ? term.short : null;

  bool isCorrect(QuizOption o) => o.termId == term.id;
}

/// Builds one question per word. Distractors come from the same lesson first, then the same tier, so they are
/// plausible; a word never appears twice among the options.
List<QuizQuestion> buildQuiz(Course course, List<GlossaryTerm> words, {required String seed, int optionCount = 4}) {
  final out = <QuizQuestion>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final kind = (fnv32('$seed|kind|${w.id}') + i).isEven ? QuestionKind.nameTheWord : QuestionKind.pickTheMeaning;
    final pool = <GlossaryTerm>[
      ...course.termsOf(w.lesson).where((t) => t.id != w.id),
      ...course.termsOfTier(w.tier).where((t) => t.lesson != w.lesson),
    ];
    final sameLesson = pool.where((t) => t.lesson == w.lesson).toList()
      ..sort((a, b) => fnv32('$seed|${w.id}|${a.id}').compareTo(fnv32('$seed|${w.id}|${b.id}')));
    final rest = pool.where((t) => t.lesson != w.lesson).toList()
      ..sort((a, b) => fnv32('$seed|${w.id}|${a.id}').compareTo(fnv32('$seed|${w.id}|${b.id}')));
    final picks = <GlossaryTerm>[];
    for (final c in [...sameLesson.take(2), ...rest, ...sameLesson.skip(2)]) {
      if (picks.length == optionCount - 1) break;
      final text = kind == QuestionKind.nameTheWord ? c.term : c.short;
      final mine = kind == QuestionKind.nameTheWord ? w.term : w.short;
      if (text == mine || picks.any((p) => (kind == QuestionKind.nameTheWord ? p.term : p.short) == text)) continue;
      picks.add(c);
    }
    final options = [
      for (final t in [w, ...picks]) QuizOption(t.id, kind == QuestionKind.nameTheWord ? t.term : t.short),
    ]..sort((a, b) => fnv32('$seed|order|${w.id}|${a.termId}').compareTo(fnv32('$seed|order|${w.id}|${b.termId}')));
    out.add(QuizQuestion(term: w, kind: kind, options: options));
  }
  return out;
}
