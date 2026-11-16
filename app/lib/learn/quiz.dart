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

  /// "What does an AUC of 0.78 mean?" (options are the right reading and three classic misreadings, all written
  /// by the pipeline with the numbers filled in). Only for words with a reading.
  readTheNumber,
}

class QuizOption {
  const QuizOption(this.termId, this.text);

  /// The word this option names or defines; for a misreading, the word's id plus "#" and its index.
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
        QuestionKind.readTheNumber => term.reading!.question,
      };

  /// Shown under the prompt for nameTheWord questions.
  String? get clue => kind == QuestionKind.nameTheWord ? term.short : null;

  bool isCorrect(QuizOption o) => o.termId == term.id;
}

/// Builds one question per word. Words with a reading ask "read the number" on about half the attempts (the owner
/// wants to know what a value such as an AUC of 0.78 means). Other distractors come from the same lesson first,
/// then from lessons of the same kind in the tier (measures with measures, finance with finance), so they are
/// plausible; a word never appears twice among the options.
List<QuizQuestion> buildQuiz(Course course, List<GlossaryTerm> words, {required String seed, int optionCount = 4}) {
  final out = <QuizQuestion>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final h = fnv32('$seed|kind|${w.id}') + i;
    if (w.reading != null && h.isEven) {
      final r = w.reading!;
      final options = [
        QuizOption(w.id, r.meansPlain),
        for (final (j, m) in r.misreadings.indexed) QuizOption('${w.id}#$j', m),
      ]..sort((a, b) => fnv32('$seed|order|${w.id}|${a.termId}').compareTo(fnv32('$seed|order|${w.id}|${b.termId}')));
      out.add(QuizQuestion(term: w, kind: QuestionKind.readTheNumber, options: options));
      continue;
    }
    final kind = (w.reading == null ? h.isEven : fnv32('$seed|kind2|${w.id}').isEven)
        ? QuestionKind.nameTheWord
        : QuestionKind.pickTheMeaning;
    int byHash(GlossaryTerm a, GlossaryTerm b) => fnv32('$seed|${w.id}|${a.id}').compareTo(fnv32('$seed|${w.id}|${b.id}'));
    final measure = course.isMeasure(w);
    final sameLesson = course.termsOf(w.lesson).where((t) => t.id != w.id).toList()..sort(byHash);
    final otherLessons = course.termsOfTier(w.tier).where((t) => t.lesson != w.lesson);
    final rest = [
      ...(otherLessons.where((t) => course.isMeasure(t) == measure).toList()..sort(byHash)),
      ...(otherLessons.where((t) => course.isMeasure(t) != measure).toList()..sort(byHash)),
    ];
    final picks = <GlossaryTerm>[];
    String textOf(GlossaryTerm t) => kind == QuestionKind.nameTheWord ? t.term : t.short;
    for (final c in [...sameLesson.take(2), ...rest, ...sameLesson.skip(2)]) {
      if (picks.length == optionCount - 1) break;
      final text = textOf(c);
      if (text == textOf(w) || picks.any((p) => textOf(p) == text)) continue;
      picks.add(c);
    }
    final options = [
      for (final t in [w, ...picks]) QuizOption(t.id, textOf(t)),
    ]..sort((a, b) => fnv32('$seed|order|${w.id}|${a.termId}').compareTo(fnv32('$seed|order|${w.id}|${b.termId}')));
    out.add(QuizQuestion(term: w, kind: kind, options: options));
  }
  return out;
}
