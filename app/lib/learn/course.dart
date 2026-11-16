/// Finance Foundations (owner requests 2026-11-15/16): ranked words in three tiers, written and validated by the
/// pipeline (pipeline/common/glossary.py) and read from content.sqlite. Core ends with three lessons of the
/// data-science measures every case uses (lesson kind "measures"). The app never computes an example number:
/// worked examples and readings arrive with their numbers already filled in, marked as [[…]], and every position
/// on a reading scale comes from the pipeline.
library;

import '../data/progress_db.dart';

class GlossaryTier {
  GlossaryTier(Map<String, dynamic> j, this.ord)
      : id = j['id'] as String,
        title = j['title'] as String,
        blurb = j['blurb'] as String,
        readNext = List<String>.from(j['read_next'] as List? ?? const []);
  final String id;
  final int ord;
  final String title;
  final String blurb;
  final List<String> readNext;
}

class GlossaryLesson {
  GlossaryLesson(Map<String, dynamic> j, {required this.tier, required this.ord})
      : id = j['id'] as String,
        title = j['title'] as String,
        blurb = j['blurb'] as String,
        kind = j['kind'] as String? ?? 'finance',
        sources = List<String>.from(j['sources'] as List? ?? const []);
  final String id;
  final String tier;
  final int ord; // 0-based position inside its tier
  final String title;
  final String blurb;

  /// "finance" (finance words, linked in finance cases) or "measures" (linked in every case).
  final String kind;
  final List<String> sources;

  int get number => ord + 1;
  bool get isMeasures => kind == 'measures';
}

class FormulaInfo {
  FormulaInfo(Map<String, dynamic> j)
      : plain = j['plain'] as String,
        image = j['image'] as String?,
        symbols = [
          for (final s in (j['symbols'] as List? ?? const []))
            (symbol: (s as Map)['symbol'] as String, means: s['means'] as String)
        ];
  final String plain;
  final String? image; // path under assets/content/, tinted to the theme
  final List<({String symbol, String means})> symbols;
}

final _markers = RegExp(r'\[\[(.+?)\]\]');

/// Text with its [[…]] markers removed (the numbers stay).
String unmarked(String text) => text.replaceAllMapped(_markers, (m) => m.group(1)!);

typedef ReadingMark = ({double at, String text, String label});
typedef ReadingBand = ({double lo, double hi, String loText, String hiText, String label});

/// How to read one value of a measure ("What does an AUC of 0.78 mean?"), rendered by the pipeline.
class ReadingInfo {
  ReadingInfo(Map<String, dynamic> j)
      : question = j['question'] as String,
        means = j['means'] as String,
        misreadings = List<String>.from(j['misreadings'] as List),
        lo = _num((j['scale'] as Map?)?['lo']),
        hi = _num((j['scale'] as Map?)?['hi']),
        loText = (j['scale'] as Map?)?['lo_text'] as String?,
        hiText = (j['scale'] as Map?)?['hi_text'] as String?,
        better = (j['scale'] as Map?)?['better'] as String? ?? 'neither',
        point = switch (j['point']) {
          final Map p => (at: _num(p['at'])!, text: p['text'] as String),
          _ => null,
        },
        interval = switch (j['interval']) {
          final Map v => (lo: _num(v['lo'])!, hi: _num(v['hi'])!, loText: v['lo_text'] as String, hiText: v['hi_text'] as String),
          _ => null,
        },
        marks = [
          for (final m in (j['marks'] as List? ?? const []))
            (at: _num((m as Map)['at'])!, text: m['text'] as String, label: m['label'] as String)
        ],
        bands = [
          for (final b in (j['bands'] as List? ?? const []))
            (
              lo: _num((b as Map)['lo'])!,
              hi: _num(b['hi'])!,
              loText: b['lo_text'] as String,
              hiText: b['hi_text'] as String,
              label: b['label'] as String,
            )
        ],
        bandsSource = j['bands_source'] as String?;

  static double? _num(Object? v) => (v as num?)?.toDouble();

  /// The question with its numbers filled in ("What does an AUC of 0.78 mean?").
  final String question;

  /// The right reading, numbers marked as [[…]].
  final String means;

  /// Three classic wrong readings (the distractors of a "read the number" question).
  final List<String> misreadings;

  /// The scale, when the value is drawn on one.
  final double? lo;
  final double? hi;
  final String? loText;
  final String? hiText;

  /// "higher", "lower" or "neither": which way along the scale is better.
  final String better;
  final ({double at, String text})? point;
  final ({double lo, double hi, String loText, String hiText})? interval;
  final List<ReadingMark> marks;

  /// Rule-of-thumb bands from [bandsSource] (a VERIFIED source), contiguous from [lo] to [hi].
  final List<ReadingBand> bands;
  final String? bandsSource;

  bool get hasScale => lo != null && hi != null;
  String get meansPlain => unmarked(means);

  /// The band the point falls in (a value on a boundary belongs to the band above; the top value to the last).
  ReadingBand? get pointBand {
    final p = point;
    if (p == null || bands.isEmpty) return null;
    for (final b in bands) {
      if (p.at >= b.lo && p.at < b.hi) return b;
    }
    return p.at == bands.last.hi ? bands.last : null;
  }
}

class GlossaryTerm {
  GlossaryTerm(this.json, {required this.tier, required this.lesson, required this.rank})
      : id = json['id'] as String,
        term = json['term'] as String,
        short = json['short'] as String,
        plain = json['plain'] as String,
        foolsYou = json['fools_you'] as String,
        aliases = List<String>.from(json['aliases'] as List? ?? const []),
        related = List<String>.from(json['related'] as List? ?? const []),
        sources = List<String>.from(json['sources'] as List? ?? const []),
        usedFor = json['used_for'] as String?,
        inFinance = json['in_finance'] as String?,
        formula = json['formula'] == null ? null : FormulaInfo(json['formula'] as Map<String, dynamic>),
        reading = json['reading'] == null ? null : ReadingInfo(json['reading'] as Map<String, dynamic>),
        exampleText = (json['example'] as Map?)?['text'] as String?,
        inCases = [
          for (final r in (json['in_cases'] as List? ?? const []))
            (caseId: (r as Map)['case'] as String, stepId: r['step'] as String)
        ];

  final Map<String, dynamic> json;
  final String tier;
  final String lesson;
  final int rank; // 1..N, most important first
  final String id;
  final String term;
  final String short;
  final String plain;
  final String foolsYou;
  final List<String> aliases;
  final List<String> related;
  final List<String> sources;

  /// What a measure is for (measures cards).
  final String? usedFor;

  /// How finance uses or names a measure, numbers marked as [[…]] (measures cards).
  final String? inFinance;
  final FormulaInfo? formula;

  /// How to read one value of a measure (most measures cards).
  final ReadingInfo? reading;

  /// Worked example with made-up numbers; every number is wrapped as [[…]] by the pipeline.
  final String? exampleText;
  final List<({String caseId, String stepId})> inCases;

  /// Everything this word may be called in prose: its name and its aliases.
  List<String> get names => [term, ...aliases];
}

class Course {
  Course({required this.id, required this.title, required this.tiers, required this.lessons, required this.terms})
      : byId = {for (final t in terms) t.id: t},
        _lessonById = {for (final l in lessons) l.id: l};

  final String id;
  final String title;
  final List<GlossaryTier> tiers;
  final List<GlossaryLesson> lessons; // in rank order
  final List<GlossaryTerm> terms; // in rank order
  final Map<String, GlossaryTerm> byId;
  final Map<String, GlossaryLesson> _lessonById;

  bool get isEmpty => terms.isEmpty;

  GlossaryLesson lesson(String id) => _lessonById[id] ?? (throw StateError('unknown lesson $id'));

  /// A word from a measures lesson (linked in every case, not only in finance cases).
  bool isMeasure(GlossaryTerm t) => _lessonById[t.lesson]?.isMeasures ?? false;
  GlossaryTier tier(String id) => tiers.firstWhere((t) => t.id == id);
  List<GlossaryLesson> lessonsOf(String tierId) => [for (final l in lessons) if (l.tier == tierId) l];
  List<GlossaryTerm> termsOf(String lessonId) => [for (final t in terms) if (t.lesson == lessonId) t];
  List<GlossaryTerm> termsOfTier(String tierId) => [for (final t in terms) if (t.tier == tierId) t];

  static Course empty() => Course(id: 'finance', title: 'Finance Foundations', tiers: [], lessons: [], terms: []);
}

/// Pass mark of a lesson's quick check (out of ten questions).
const lessonPassMark = 8;

/// What the learner has done, read from progress.sqlite. Rules (owner: "once those are known we move to the
/// others"): the first tier is open; each later tier opens when every lesson of the tier before is passed.
class CourseProgress {
  CourseProgress(this.course, ProgressDb db, {DateTime? now})
      : lessons = db.lessonStates(),
        termStates = db.termStates(),
        due = db.dueTerms(now ?? DateTime.now());

  final Course course;
  final Map<String, ({int bestScore, int attempts, bool passed})> lessons;
  final Map<String, TermState> termStates;
  final List<String> due;

  bool lessonPassed(String lessonId) => lessons[lessonId]?.passed ?? false;
  int lessonAttempts(String lessonId) => lessons[lessonId]?.attempts ?? 0;
  bool known(String termId) => termStates[termId]?.known ?? false;

  bool tierUnlocked(String tierId) {
    final i = course.tiers.indexWhere((t) => t.id == tierId);
    if (i <= 0) return true;
    return course.lessonsOf(course.tiers[i - 1].id).every((l) => lessonPassed(l.id));
  }

  bool tierComplete(String tierId) => course.lessonsOf(tierId).every((l) => lessonPassed(l.id));

  int knownIn(String tierId) => course.termsOfTier(tierId).where((t) => known(t.id)).length;
  int get knownTotal => course.terms.where((t) => known(t.id)).length;

  /// The first lesson, in rank order, that is open and not yet passed.
  GlossaryLesson? get nextLesson {
    for (final l in course.lessons) {
      if (tierUnlocked(l.tier) && !lessonPassed(l.id)) return l;
    }
    return null;
  }

  /// The tier the learner is working in (first unlocked tier that is not complete).
  GlossaryTier? get currentTier {
    for (final t in course.tiers) {
      if (tierUnlocked(t.id) && !tierComplete(t.id)) return t;
    }
    return course.tiers.isEmpty ? null : course.tiers.last;
  }
}
