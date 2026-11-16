import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Writable store on the phone: every attempt, score, hint and answer (spec §1 examiner loop),
/// where each case was left, unsubmitted drafts, the spaced-review schedule, finance-learning progress and settings.
class ProgressDb {
  ProgressDb._(this._db) {
    _migrate();
  }

  final Database _db;

  /// v1: attempts, case_state, reviews, settings. v2 (2026-11-15): drafts, term_progress, lesson_progress.
  /// v3 (2026-11-16): examiner_feedback (the Claude examiner's verdict per attempt), case_reports (finished-case PDFs).
  static const schemaVersion = 3;

  static Future<ProgressDb> open() async {
    final dir = await getApplicationSupportDirectory();
    return ProgressDb.openFile('${dir.path}${Platform.pathSeparator}progress.sqlite');
  }

  /// Opens (and migrates) a progress file directly; tests use it to check upgrades keep old data.
  factory ProgressDb.openFile(String path) => ProgressDb._(sqlite3.open(path));

  factory ProgressDb.inMemory() => ProgressDb._(sqlite3.openInMemory());

  void close() => _db.close();

  /// Each version only ADDS tables, so upgrading never touches saved attempts.
  void _migrate() {
    final from = _db.userVersion;
    if (from >= schemaVersion) return;
    _db.execute('BEGIN IMMEDIATE');
    try {
      if (from < 1) _db.execute(_v1);
      if (from < 2) _db.execute(_v2);
      if (from < 3) _db.execute(_v3);
      _db.userVersion = schemaVersion;
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  static const _v1 = '''
      CREATE TABLE IF NOT EXISTS attempts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        case_id TEXT NOT NULL, step_id TEXT NOT NULL, attempt_no INTEGER NOT NULL,
        answer_json TEXT NOT NULL,
        correct INTEGER,          -- 1/0 for checked steps, NULL when not graded yet
        score REAL,               -- examiner score 0-100 (Prompt 6)
        hints_used INTEGER NOT NULL DEFAULT 0,
        started_at TEXT NOT NULL, submitted_at TEXT NOT NULL, duration_ms INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS attempts_step ON attempts(case_id, step_id);
      CREATE TABLE IF NOT EXISTS case_state(
        case_id TEXT PRIMARY KEY, step_idx INTEGER NOT NULL, max_idx INTEGER NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS reviews(
        case_id TEXT NOT NULL, step_id TEXT NOT NULL, due_at TEXT NOT NULL, interval_days INTEGER NOT NULL,
        PRIMARY KEY(case_id, step_id)
      );
      CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    ''';

  static const _v2 = '''
      CREATE TABLE IF NOT EXISTS drafts(
        case_id TEXT NOT NULL, step_id TEXT NOT NULL,
        value_json TEXT NOT NULL,   -- whatever the step had in its inputs, not yet submitted
        updated_at TEXT NOT NULL,
        PRIMARY KEY(case_id, step_id)
      );
      CREATE TABLE IF NOT EXISTS term_progress(
        term_id TEXT PRIMARY KEY,
        known INTEGER NOT NULL DEFAULT 0,  -- 1 once answered correctly in a lesson check
        box INTEGER NOT NULL DEFAULT 0,    -- spaced-review rung: 0..3 -> due after 1, 3, 7, 21 days
        due_at TEXT,                       -- next review (UTC ISO); NULL until known
        correct INTEGER NOT NULL DEFAULT 0, wrong INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS lesson_progress(
        lesson_id TEXT PRIMARY KEY,
        best_score INTEGER NOT NULL, attempts INTEGER NOT NULL,
        passed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL
      );
    ''';

  static const _v3 = '''
      CREATE TABLE IF NOT EXISTS examiner_feedback(
        attempt_id INTEGER PRIMARY KEY,   -- attempts.id
        case_id TEXT NOT NULL, step_id TEXT NOT NULL,
        status TEXT NOT NULL,             -- graded | noAttempt
        score REAL, passed INTEGER NOT NULL DEFAULT 0,
        feedback_json TEXT NOT NULL,      -- GradeResult.toJson()
        model TEXT, input_tokens INTEGER, output_tokens INTEGER,
        created_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS feedback_step ON examiner_feedback(case_id, step_id);
      CREATE TABLE IF NOT EXISTS case_reports(
        case_id TEXT NOT NULL, created_at TEXT NOT NULL,
        file_path TEXT NOT NULL,          -- copy in app storage
        download_name TEXT,               -- name in Downloads/CaseTrainer, when saved there
        summary_json TEXT,                -- the examiner's case summary
        PRIMARY KEY(case_id, created_at)
      );
    ''';

  String _now() => DateTime.now().toUtc().toIso8601String();

  // ------------------------------------------------------------------ attempts
  int attemptCount(String caseId, String stepId) =>
      _db.select('SELECT COUNT(*) AS n FROM attempts WHERE case_id = ? AND step_id = ?', [caseId, stepId]).first['n'] as int;

  /// Records one attempt and returns its attempt number (1-based).
  int recordAttempt({
    required String caseId,
    required String stepId,
    required Object answer,
    required DateTime startedAt,
    bool? correct,
    double? score,
    int hintsUsed = 0,
  }) {
    final n = attemptCount(caseId, stepId) + 1;
    final now = DateTime.now();
    _db.execute(
      'INSERT INTO attempts(case_id, step_id, attempt_no, answer_json, correct, score, hints_used, started_at, submitted_at, duration_ms) '
      'VALUES(?,?,?,?,?,?,?,?,?,?)',
      [caseId, stepId, n, jsonEncode(answer), correct == null ? null : (correct ? 1 : 0), score, hintsUsed,
        startedAt.toUtc().toIso8601String(), now.toUtc().toIso8601String(), now.difference(startedAt).inMilliseconds],
    );
    return n;
  }

  Map<String, dynamic>? lastAttempt(String caseId, String stepId) {
    final rows = _db.select(
        'SELECT * FROM attempts WHERE case_id = ? AND step_id = ? ORDER BY attempt_no DESC LIMIT 1', [caseId, stepId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {for (final k in r.keys) k: r[k]};
  }

  // ------------------------------------------------------------------ examiner (v3)
  /// Records a free-text attempt together with the examiner's verdict; returns the attempt number.
  /// Answers the examiner could not grade (offline, no credit) are NOT recorded: the attempt is not used up.
  int recordExaminedAttempt({
    required String caseId,
    required String stepId,
    required String answer,
    required DateTime startedAt,
    required Map<String, dynamic> feedback,
    required String status,
    double? score,
    bool passed = false,
    String? model,
    int? inputTokens,
    int? outputTokens,
    int hintsUsed = 0,
  }) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final n = recordAttempt(caseId: caseId, stepId: stepId, answer: answer, startedAt: startedAt, score: score, hintsUsed: hintsUsed);
      final id = _db.lastInsertRowId;
      _db.execute(
        'INSERT INTO examiner_feedback(attempt_id, case_id, step_id, status, score, passed, feedback_json, model, '
        'input_tokens, output_tokens, created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [id, caseId, stepId, status, score, passed ? 1 : 0, jsonEncode(feedback), model, inputTokens, outputTokens, _now()],
      );
      _db.execute('COMMIT');
      return n;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Examined attempts of one step, oldest first (attempts saved before the examiner existed are not included).
  List<ExaminedAttempt> examinedAttempts(String caseId, String stepId) => [
        for (final r in _db.select(
            'SELECT a.attempt_no, a.answer_json, a.submitted_at, a.hints_used, f.status, f.score, f.passed, f.feedback_json '
            'FROM attempts a JOIN examiner_feedback f ON f.attempt_id = a.id '
            'WHERE a.case_id = ? AND a.step_id = ? ORDER BY a.id',
            [caseId, stepId]))
          ExaminedAttempt._(r)
      ];

  /// Number of attempts the examiner has counted on this step (the 3-attempt ladder runs on this).
  int examinedCount(String caseId, String stepId) => _db.select(
      'SELECT COUNT(*) AS n FROM examiner_feedback WHERE case_id = ? AND step_id = ?', [caseId, stepId]).first['n'] as int;

  bool examinerPassed(String caseId, String stepId) => _db.select(
      'SELECT 1 FROM examiner_feedback WHERE case_id = ? AND step_id = ? AND passed = 1 LIMIT 1', [caseId, stepId]).isNotEmpty;

  /// Best examiner score on a step, or null when never graded.
  double? bestScore(String caseId, String stepId) => (_db.select(
          "SELECT MAX(score) AS s FROM examiner_feedback WHERE case_id = ? AND step_id = ? AND status = 'graded'",
          [caseId, stepId]).first['s'] as num?)
      ?.toDouble();

  /// Calls made to the examiner and their estimated cost (from each verdict's stored usage).
  ({int calls, double cost, int inputTokens, int outputTokens, int cacheReadTokens}) examinerUsage() {
    var calls = 0, input = 0, output = 0, cacheRead = 0;
    var cost = 0.0;
    for (final r in _db.select("SELECT feedback_json FROM examiner_feedback WHERE status = 'graded'")) {
      final u = (jsonDecode(r['feedback_json'] as String) as Map)['usage'] as Map?;
      if (u == null) continue;
      calls++;
      input += (u['input_tokens'] as num?)?.toInt() ?? 0;
      output += (u['output_tokens'] as num?)?.toInt() ?? 0;
      cacheRead += (u['cache_read_input_tokens'] as num?)?.toInt() ?? 0;
      cost += (u['cost_usd'] as num?)?.toDouble() ?? 0;
    }
    return (calls: calls, cost: cost, inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead);
  }

  /// Puts a step on the spaced re-test ladder (1, 3, 7, 21 days) once it is passed or revealed.
  void scheduleReview(String caseId, String stepId, {DateTime? now}) {
    final due = (now ?? DateTime.now()).toUtc().add(Duration(days: reviewLadderDays.first)).toIso8601String();
    _db.execute(
      'INSERT INTO reviews(case_id, step_id, due_at, interval_days) VALUES(?,?,?,?) ON CONFLICT(case_id, step_id) DO NOTHING',
      [caseId, stepId, due, reviewLadderDays.first],
    );
  }

  /// Marks a case unfinished again (it was finished with steps still unanswered, before the finish rule existed).
  void reopenCase(String caseId) =>
      _db.execute('UPDATE case_state SET completed = 0, updated_at = ? WHERE case_id = ?', [_now(), caseId]);

  // ------------------------------------------------------------------ finished-case reports (v3)
  void recordReport(String caseId, {required String filePath, String? downloadName, Map<String, dynamic>? summary}) =>
      _db.execute(
        'INSERT INTO case_reports(case_id, created_at, file_path, download_name, summary_json) VALUES(?,?,?,?,?)',
        [caseId, _now(), filePath, downloadName, summary == null ? null : jsonEncode(summary)],
      );

  /// The newest report of a case, or null.
  ({String filePath, String? downloadName, DateTime createdAt, Map<String, dynamic>? summary})? latestReport(String caseId) {
    final rows = _db.select('SELECT * FROM case_reports WHERE case_id = ? ORDER BY created_at DESC LIMIT 1', [caseId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      filePath: r['file_path'] as String,
      downloadName: r['download_name'] as String?,
      createdAt: DateTime.parse(r['created_at'] as String),
      summary: r['summary_json'] == null ? null : jsonDecode(r['summary_json'] as String) as Map<String, dynamic>,
    );
  }

  /// Every attempt of a case, oldest first (for the report).
  List<Map<String, dynamic>> attemptsOf(String caseId) => [
        for (final r in _db.select('SELECT * FROM attempts WHERE case_id = ? ORDER BY id', [caseId])) {for (final k in r.keys) k: r[k]}
      ];

  bool solved(String caseId, String stepId) => _db.select(
      'SELECT 1 FROM attempts WHERE case_id = ? AND step_id = ? AND correct = 1 LIMIT 1', [caseId, stepId]).isNotEmpty;

  // ------------------------------------------------------------------ case position (resume)
  ({int stepIdx, int maxIdx, bool completed})? caseState(String caseId) {
    final rows = _db.select('SELECT step_idx, max_idx, completed FROM case_state WHERE case_id = ?', [caseId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (stepIdx: r['step_idx'] as int, maxIdx: r['max_idx'] as int, completed: (r['completed'] as int) == 1);
  }

  void saveCaseState(String caseId, int stepIdx, {bool completed = false}) {
    final prev = caseState(caseId);
    final maxIdx = prev == null ? stepIdx : (stepIdx > prev.maxIdx ? stepIdx : prev.maxIdx);
    _db.execute(
      'INSERT INTO case_state(case_id, step_idx, max_idx, completed, updated_at) VALUES(?,?,?,?,?) '
      'ON CONFLICT(case_id) DO UPDATE SET step_idx = excluded.step_idx, max_idx = excluded.max_idx, '
      'completed = MAX(case_state.completed, excluded.completed), updated_at = excluded.updated_at',
      [caseId, stepIdx, maxIdx, completed ? 1 : 0, _now()],
    );
  }

  // ------------------------------------------------------------------ drafts (typed input survives Back and restarts)
  /// Stores whatever a step's inputs hold right now (text, blanks, selection, order), not yet submitted.
  void saveDraft(String caseId, String stepId, Object value) => _db.execute(
        'INSERT INTO drafts(case_id, step_id, value_json, updated_at) VALUES(?,?,?,?) '
        'ON CONFLICT(case_id, step_id) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at',
        [caseId, stepId, jsonEncode(value), _now()],
      );

  /// The unsubmitted input of a step (decoded JSON), or null when there is none.
  Object? draft(String caseId, String stepId) {
    final rows = _db.select('SELECT value_json FROM drafts WHERE case_id = ? AND step_id = ?', [caseId, stepId]);
    return rows.isEmpty ? null : jsonDecode(rows.first['value_json'] as String);
  }

  void clearDraft(String caseId, String stepId) =>
      _db.execute('DELETE FROM drafts WHERE case_id = ? AND step_id = ?', [caseId, stepId]);

  // ------------------------------------------------------------------ finance learning
  /// Spaced re-test ladder in days (same as the examiner's, docs/knowledge/GRADING.md).
  static const reviewLadderDays = [1, 3, 7, 21];

  TermState? termState(String termId) {
    final rows = _db.select('SELECT * FROM term_progress WHERE term_id = ?', [termId]);
    return rows.isEmpty ? null : TermState._(rows.first);
  }

  Map<String, TermState> termStates() =>
      {for (final r in _db.select('SELECT * FROM term_progress')) r['term_id'] as String: TermState._(r)};

  /// One answer about a word, from a lesson check or a review.
  /// First correct answer makes the word known (due again in a day). Each later correct review climbs the ladder;
  /// a wrong answer drops a known word back to the first rung.
  void recordTermAnswer(String termId, {required bool correct, DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    final prev = termState(termId);
    final wasKnown = prev?.known ?? false;
    final known = wasKnown || correct;
    final box = !correct ? 0 : (wasKnown ? ((prev!.box + 1).clamp(0, reviewLadderDays.length - 1)) : 0);
    final due = known ? t.add(Duration(days: reviewLadderDays[box])).toIso8601String() : null;
    _db.execute(
      'INSERT INTO term_progress(term_id, known, box, due_at, correct, wrong, updated_at) VALUES(?,?,?,?,?,?,?) '
      'ON CONFLICT(term_id) DO UPDATE SET known = excluded.known, box = excluded.box, due_at = excluded.due_at, '
      'correct = term_progress.correct + excluded.correct, wrong = term_progress.wrong + excluded.wrong, '
      'updated_at = excluded.updated_at',
      [termId, known ? 1 : 0, box, due, correct ? 1 : 0, correct ? 0 : 1, t.toIso8601String()],
    );
  }

  /// Known words whose review is due at [now], oldest first.
  List<String> dueTerms(DateTime now) => [
        for (final r in _db.select(
            'SELECT term_id FROM term_progress WHERE known = 1 AND due_at <= ? ORDER BY due_at, term_id',
            [now.toUtc().toIso8601String()]))
          r['term_id'] as String
      ];

  void recordLesson(String lessonId, {required int score, required bool passed}) => _db.execute(
        'INSERT INTO lesson_progress(lesson_id, best_score, attempts, passed, updated_at) VALUES(?,?,1,?,?) '
        'ON CONFLICT(lesson_id) DO UPDATE SET best_score = MAX(lesson_progress.best_score, excluded.best_score), '
        'attempts = lesson_progress.attempts + 1, passed = MAX(lesson_progress.passed, excluded.passed), '
        'updated_at = excluded.updated_at',
        [lessonId, score, passed ? 1 : 0, _now()],
      );

  Map<String, ({int bestScore, int attempts, bool passed})> lessonStates() => {
        for (final r in _db.select('SELECT * FROM lesson_progress'))
          r['lesson_id'] as String: (
            bestScore: r['best_score'] as int,
            attempts: r['attempts'] as int,
            passed: (r['passed'] as int) == 1,
          )
      };

  void resetLearning() => _db.execute('DELETE FROM term_progress; DELETE FROM lesson_progress;');

  // ------------------------------------------------------------------ summaries
  ({int attempts, int stepsAttempted, int checkedSolved, int freeTextSaved}) caseSummary(String caseId) {
    final r = _db.select('''
      SELECT COUNT(*) AS attempts,
             COUNT(DISTINCT step_id) AS steps,
             COUNT(DISTINCT CASE WHEN correct = 1 THEN step_id END) AS solved,
             COUNT(DISTINCT CASE WHEN correct IS NULL THEN step_id END) AS free
      FROM attempts WHERE case_id = ?''', [caseId]).first;
    return (
      attempts: r['attempts'] as int,
      stepsAttempted: r['steps'] as int,
      checkedSolved: r['solved'] as int,
      freeTextSaved: r['free'] as int,
    );
  }

  /// Share of checked-step first attempts that were correct (null when none yet).
  double? firstTryRate(String caseId) {
    final r = _db.select('''
      SELECT AVG(correct) AS rate FROM attempts
      WHERE case_id = ? AND attempt_no = 1 AND correct IS NOT NULL''', [caseId]).first;
    return (r['rate'] as num?)?.toDouble();
  }

  // ------------------------------------------------------------------ settings
  String? setting(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) =>
      _db.execute('INSERT INTO settings(key, value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value = excluded.value', [key, value]);

  /// Case progress only (attempts, positions, drafts, reviews). Finance learning has its own reset.
  void resetProgress() {
    _db.execute('DELETE FROM attempts; DELETE FROM case_state; DELETE FROM reviews; DELETE FROM drafts;');
  }

  /// Most recently touched case that is not finished (the cover's "Continue" target), or null.
  ({String caseId, int stepIdx})? lastOpenCase() {
    final rows = _db.select(
        'SELECT case_id, step_idx FROM case_state WHERE completed = 0 ORDER BY updated_at DESC LIMIT 1');
    if (rows.isEmpty) return null;
    return (caseId: rows.first['case_id'] as String, stepIdx: rows.first['step_idx'] as int);
  }
}

/// One free-text attempt with the examiner's verdict.
class ExaminedAttempt {
  ExaminedAttempt._(Row r)
      : attemptNo = r['attempt_no'] as int,
        answer = jsonDecode(r['answer_json'] as String) as String,
        submittedAt = DateTime.parse(r['submitted_at'] as String),
        hintsUsed = r['hints_used'] as int,
        status = r['status'] as String,
        score = (r['score'] as num?)?.toDouble(),
        passed = (r['passed'] as int) == 1,
        feedback = jsonDecode(r['feedback_json'] as String) as Map<String, dynamic>;

  final int attemptNo;
  final String answer;
  final DateTime submittedAt;
  final int hintsUsed;
  final String status;
  final double? score;
  final bool passed;
  final Map<String, dynamic> feedback;
}

/// Learning state of one finance word.
class TermState {
  TermState._(Row r)
      : known = (r['known'] as int) == 1,
        box = r['box'] as int,
        dueAt = r['due_at'] == null ? null : DateTime.parse(r['due_at'] as String),
        correct = r['correct'] as int,
        wrong = r['wrong'] as int;

  final bool known;
  final int box;
  final DateTime? dueAt;
  final int correct;
  final int wrong;
}
