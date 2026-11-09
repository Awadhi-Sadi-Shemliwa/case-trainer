import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

const contentAsset = 'assets/content/content.sqlite';

/// Read-only access to the content bundle written by pipeline/build_content.py.
/// The app never computes results: every number comes from the `results` table.
class ContentDb {
  ContentDb._(this._db);

  final Database _db;

  /// Copies the bundled asset to app storage when it is missing or different, then opens it read-only.
  static Future<ContentDb> openBundled() async {
    final sw = Stopwatch()..start();
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}content.sqlite');
    final bytes = (await rootBundle.load(contentAsset)).buffer.asUint8List();
    var copied = false;
    if (!file.existsSync() || !listEquals(file.readAsBytesSync(), bytes)) {
      await file.writeAsBytes(bytes, flush: true);
      copied = true;
    }
    final db = ContentDb.openFile(file.path);
    debugPrint('[CaseTrainer] content.sqlite ${copied ? "copied" : "up to date"} '
        '(${bytes.length} bytes) in ${sw.elapsedMilliseconds} ms');
    return db;
  }

  /// Opens a content file directly (tests use the real bundle from app/assets/content/).
  factory ContentDb.openFile(String path) => ContentDb._(sqlite3.open(path, mode: OpenMode.readOnly));

  void close() => _db.close();

  Map<String, String> meta() => {for (final r in _db.select('SELECT key, value FROM meta')) r['key'] as String: r['value'] as String};

  List<CaseInfo> cases() => [
        for (final r in _db.select('SELECT json FROM cases ORDER BY ord'))
          CaseInfo(jsonDecode(r['json'] as String) as Map<String, dynamic>)
      ];

  CaseInfo caseById(String id) {
    final rows = _db.select('SELECT json FROM cases WHERE id = ?', [id]);
    if (rows.isEmpty) throw StateError('unknown case $id');
    return CaseInfo(jsonDecode(rows.first['json'] as String) as Map<String, dynamic>);
  }

  List<StepData> steps(String caseId) => [
        for (final r in _db.select('SELECT idx, json FROM steps WHERE case_id = ? ORDER BY idx', [caseId]))
          StepData(jsonDecode(r['json'] as String) as Map<String, dynamic>, r['idx'] as int)
      ];

  Map<String, ResultEntry> results(String caseId) => {
        for (final r in _db.select('SELECT key, value_json, unit, description, display FROM results WHERE case_id = ?', [caseId]))
          r['key'] as String: ResultEntry(
            key: r['key'] as String,
            value: jsonDecode(r['value_json'] as String),
            unit: r['unit'] as String,
            description: r['description'] as String,
            display: r['display'] as String,
          )
      };

  Map<String, String> captured(String caseId) => {
        for (final r in _db.select('SELECT name, output FROM captured WHERE case_id = ?', [caseId]))
          r['name'] as String: r['output'] as String
      };

  String? snippet(String caseId, String file, String name) {
    final rows = _db.select('SELECT code FROM snippets WHERE case_id = ? AND file = ? AND name = ?', [caseId, file, name]);
    return rows.isEmpty ? null : rows.first['code'] as String;
  }

  Map<String, dynamic>? dataset(String caseId, String key) {
    final rows = _db.select('SELECT json FROM datasets WHERE case_id = ? AND key = ?', [caseId, key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  Map<String, dynamic>? transform(String caseId, String id) {
    final rows = _db.select('SELECT json FROM transforms WHERE case_id = ? AND id = ?', [caseId, id]);
    return rows.isEmpty ? null : jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  List<SourceRef> sources() => [
        for (final r in _db.select('SELECT * FROM sources ORDER BY key'))
          SourceRef({for (final c in r.keys) c: r[c]})
      ];
}
