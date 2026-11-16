import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Real code or real output on an ink-navy panel (both themes), horizontally scrolling, with a small Python
/// highlighter. (No package: flutter_highlight is unmaintained, see docs/knowledge/ENVIRONMENT.md.)
class CodeView extends StatelessWidget {
  const CodeView(this.code, {super.key, this.label, this.highlight = true});

  final String code;
  final String? label;
  final bool highlight;

  /// Excluded by the no-hard-coded-numbers test: everything inside is real code or real output.
  static const codeKey = ValueKey('code_view');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = TextStyle(fontFamily: fontCode, fontSize: 13, height: 1.5, color: c.codeFg, fontFeatures: codeFeatures);
    return Container(
      key: codeKey,
      decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(label!,
                style: TextStyle(fontFamily: fontCode, fontSize: 12, fontWeight: FontWeight.w600, color: c.codeFg.withValues(alpha: 0.7))),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: SelectableText.rich(TextSpan(style: base, children: highlight ? pythonSpans(code, true) : [TextSpan(text: code)])),
        ),
      ]),
    );
  }
}

const _keywords = {
  'for', 'in', 'if', 'else', 'elif', 'return', 'def', 'import', 'from', 'as', 'with', 'not', 'and', 'or',
  'None', 'True', 'False', 'continue', 'break', 'class', 'lambda', 'is', 'while', 'try', 'except',
};
final _token = RegExp(r'''(#[^\n]*)|([rbf]?"(?:[^"\\\n]|\\.)*"|[rbf]?'(?:[^'\\\n]|\\.)*')|(\b\d+(?:\.\d+)?\b)|([A-Za-z_][A-Za-z0-9_]*)''');

/// Splits Python source into coloured spans (comments, strings, numbers, keywords, calls).
List<TextSpan> pythonSpans(String code, bool dark) {
  final cComment = dark ? const Color(0xFF8B9BB4) : const Color(0xFF6B7F88);
  final cString = dark ? const Color(0xFFA6DA95) : const Color(0xFF2F7D32);
  final cNumber = dark ? const Color(0xFFF6D84A) : const Color(0xFFB45309);
  final cKeyword = dark ? const Color(0xFF8FB8FF) : const Color(0xFF1D4ED8);
  final cCall = dark ? const Color(0xFFD7B6FF) : const Color(0xFF7C3AED);
  final out = <TextSpan>[];
  var pos = 0;
  for (final m in _token.allMatches(code)) {
    if (m.start > pos) out.add(TextSpan(text: code.substring(pos, m.start)));
    final t = m.group(0)!;
    Color? c;
    var bold = false;
    if (m.group(1) != null) {
      c = cComment;
    } else if (m.group(2) != null) {
      c = cString;
    } else if (m.group(3) != null) {
      c = cNumber;
    } else if (_keywords.contains(t)) {
      c = cKeyword;
      bold = true;
    } else if (m.end < code.length && code[m.end] == '(') {
      c = cCall;
    }
    out.add(TextSpan(text: t, style: c == null ? null : TextStyle(color: c, fontWeight: bold ? FontWeight.w600 : null)));
    pos = m.end;
  }
  if (pos < code.length) out.add(TextSpan(text: code.substring(pos)));
  return out;
}
