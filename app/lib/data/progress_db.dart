import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Writable store on the phone: every attempt, score, hint and answer (spec §1 examiner loop),
/// where each case was left, the spaced-review schedule (filled from Prompt 6), and settings.
class ProgressDb {
  ProgressDb._(this._db) {
    _migrate();
  }

  final Database _db;
  static const schemaVersion = 1;

  static Future<ProgressDb> open() async {
    final dir = await getApplicationSupportDirectory();
    return ProgressDb._(sqlite3.open('${dir.path}${Platform.pathSeparator}progress.sqlite'));
  }

  factory ProgressDb.inMemory() => ProgressDb._(sqlite3.openInMemory());

  void close() => _db.close();

  void _migrate() {
    if (_db.userVersion >= schemaVersion) return;
    _db.execute('''
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
    ''');
    _db.userVersion = schemaVersion;
  }

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

  void resetProgress() {
    _db.execute('DELETE FROM attempts; DELETE FROM case_state; DELETE FROM reviews;');
  }
}
