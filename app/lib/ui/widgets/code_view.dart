import 'package:flutter/material.dart';

/// Monospace, horizontally scrolling code block with a small Python highlighter.
/// (No package: flutter_highlight is unmaintained, see docs/knowledge/ENVIRONMENT.md.)
class CodeView extends StatelessWidget {
  const CodeView(this.code, {super.key, this.label, this.highlight = true});

  final String code;
  final String? label;
  final bool highlight;

  static const codeKey = ValueKey('code_view');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45, color: theme.colorScheme.onSurface);
    return Container(
      key: codeKey,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F1A20) : const Color(0xFFF2F5F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(label!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.0, color: theme.colorScheme.onSurfaceVariant)),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: SelectableText.rich(TextSpan(style: base, children: highlight ? pythonSpans(code, dark) : [TextSpan(text: code)])),
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
  final cComment = dark ? const Color(0xFF7F9AA6) : const Color(0xFF6B7F88);
  final cString = dark ? const Color(0xFF9BD67F) : const Color(0xFF2F7D32);
  final cNumber = dark ? const Color(0xFFF2A65A) : const Color(0xFFB45309);
  final cKeyword = dark ? const Color(0xFF7FB8FF) : const Color(0xFF1D4ED8);
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
