import 'package:case_trainer/data/models.dart';
import 'package:case_trainer/engine/checker.dart';
import 'package:case_trainer/engine/placeholders.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

ResultEntry _r(String key, Object v, String display) =>
    ResultEntry(key: key, value: v, unit: 'u', description: 'd $key', display: display);

StepData _step(Map<String, dynamic> j) => StepData({'id': 's', 'phase': 'brief', 'title': 't', 'prompt': 'p', ...j}, 0);

void main() {
  group('Resolver', () {
    final res = Resolver({'lead': _r('lead', 19.0, '19'), 'p': _r('p', 0.094, '9.4%')}, {'out': 'A  1\nB  2'});

    test('replaces expected and captured placeholders', () {
      expect(res.plain('Lead {expected.lead} months, odds {expected.p}.'), 'Lead 19 months, odds 9.4%.');
      final segs = res.segments('x {captured.out} y');
      expect(segs[1], isA<CapturedSegment>());
      expect((segs[1] as CapturedSegment).output, 'A  1\nB  2');
    });

    test('unknown keys throw instead of rendering blank', () {
      expect(() => res.segments('{expected.nope}'), throwsA(isA<PlaceholderError>()));
      expect(() => res.segments('{captured.nope}'), throwsA(isA<PlaceholderError>()));
    });

    test('every placeholder in the real P50 bundle resolves', () {
      final c = realContent();
      final r = resolverFor(c, p50);
      for (final s in c.steps(p50)) {
        for (final m in placeholderRe.allMatches(s.json.toString())) {
          expect(() => r.segments(m.group(0)!), returnsNormally, reason: '${s.id}: ${m.group(0)}');
        }
      }
      c.close();
    });
  });

  group('Checker', () {
    final mcq = _step({'type': 'mcq', 'options': [
      {'id': 'a', 'text': 'A', 'correct': true, 'explanation': 'yes'},
      {'id': 'b', 'text': 'B', 'explanation': 'no'},
    ]});

    test('mcq', () {
      expect(Checker.mcq(mcq, 'a').correct, isTrue);
      expect(Checker.mcq(mcq, 'b').correct, isFalse);
      expect(Checker.mcq(mcq, 'b').message, 'no');
      expect(Checker.mcq(mcq, null).correct, isFalse);
    });

    test('multi needs the exact set', () {
      final m = _step({'type': 'kpi_builder', 'options': [
        {'id': 'a', 'text': 'A', 'correct': true, 'explanation': ''},
        {'id': 'b', 'text': 'B', 'correct': true, 'explanation': ''},
        {'id': 'c', 'text': 'C', 'explanation': ''},
      ]});
      expect(Checker.multi(m, {'a', 'b'}).correct, isTrue);
      expect(Checker.multi(m, {'a'}).correct, isFalse);
      expect(Checker.multi(m, {'a', 'b', 'c'}).correct, isFalse);
    });

    test('order', () {
      final o = _step({'type': 'order_steps', 'items': ['x', 'y', 'z']});
      expect(Checker.order(o, ['x', 'y', 'z']).correct, isTrue);
      expect(Checker.order(o, ['y', 'x', 'z']).correct, isFalse);
    });

    test('numeric tolerance and percent input', () {
      final n = _step({'type': 'numeric', 'answer_key': 'k', 'tolerance': 0.5, 'unit': 'months'});
      final lead = _r('k', 19.0, '19');
      expect(Checker.numeric(n, '19', lead).correct, isTrue);
      expect(Checker.numeric(n, '19.4', lead).correct, isTrue);
      expect(Checker.numeric(n, '20', lead).correct, isFalse);
      expect(Checker.numeric(n, 'abc', lead).correct, isFalse);
      final pct = _step({'type': 'numeric', 'answer_key': 'k', 'tolerance': 0.01, 'unit': 'share'});
      final share = _r('k', 0.27, '27%');
      expect(Checker.numeric(pct, '27', share).correct, isTrue);
      expect(Checker.numeric(pct, '27%', share).correct, isTrue);
      expect(Checker.numeric(pct, '0.27', share).correct, isTrue);
      expect(Checker.numeric(pct, '35', share).correct, isFalse);
    });

    test('code_fill ignores whitespace and accepts alternatives', () {
      final f = _step({'type': 'code_fill', 'blanks': [
        {'token': 'shift(-k)', 'accept': ['shift(periods=-k)']},
        {'token': 'range(1, HORIZON + 1)'},
      ]});
      expect(Checker.codeFill(f, ['shift( -k )', 'range(1,HORIZON+1)']).correct, isTrue);
      expect(Checker.codeFill(f, ['shift(periods=-k)', 'range(1, HORIZON + 1)']).correct, isTrue);
      expect(Checker.codeFill(f, ['shift(k)', 'range(1, HORIZON + 1)']).correct, isFalse);
    });

    test('code_fix compares with the real snippet', () {
      expect(Checker.codeFix('a = b.shift(-k)\n', 'a = b.shift( -k )').correct, isTrue);
      expect(Checker.codeFix('a = b.shift(k)', 'a = b.shift(-k)').correct, isFalse);
    });

    test('real P50 code_fix: buggy code is wrong, real snippet is right', () {
      final c = realContent();
      final fix = c.steps(p50).firstWhere((s) => s.type == 'code_fix');
      final real = c.snippet(p50, fix.snippet!.file, fix.snippet!.name)!;
      expect(Checker.codeFix(fix.buggyCode!, real).correct, isFalse);
      expect(Checker.codeFix(real, real).correct, isTrue);
      c.close();
    });
  });
}
