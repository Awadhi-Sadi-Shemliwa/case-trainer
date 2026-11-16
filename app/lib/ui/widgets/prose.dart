import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../engine/placeholders.dart';
import '../../learn/course.dart';
import '../../learn/term_linker.dart';
import '../theme/tokens.dart';
import 'code_view.dart';
import 'highlight.dart';

/// Authored text with `{expected.*}` values highlighted (tap for what the number means), `{captured.*}`
/// outputs rendered as code blocks and, when a [linker] is given, glossary words underlined inline (tap for the
/// word's card).
class Prose extends StatefulWidget {
  const Prose(this.text, {super.key, required this.resolver, this.style, this.linker, this.onTerm});

  final String text;
  final Resolver resolver;
  final TextStyle? style;
  final TermLinker? linker;
  final void Function(GlossaryTerm term)? onTerm;

  @override
  State<Prose> createState() => _ProseState();
}

class _ProseState extends State<Prose> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final base = widget.style ?? Theme.of(context).textTheme.bodyLarge;
    final c = context.colors;
    final linkStyle = TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: c.inkSoft,
      decorationThickness: 2,
    );
    final segs = widget.resolver.segments(widget.text);
    final blocks = <Widget>[];
    var spans = <InlineSpan>[];
    final linked = <String>{};

    void flush() {
      if (spans.isEmpty) return;
      blocks.add(Text.rich(TextSpan(style: base, children: spans)));
      spans = [];
    }

    for (final s in segs) {
      switch (s) {
        case TextSegment(:final text):
          if (widget.linker == null || widget.onTerm == null) {
            spans.add(TextSpan(text: text));
          } else {
            for (final p in widget.linker!.split(text, linked: linked)) {
              switch (p) {
                case PlainPiece():
                  spans.add(TextSpan(text: p.text));
                case TermPiece(:final term):
                  final r = TapGestureRecognizer()..onTap = () => widget.onTerm!(term);
                  _recognizers.add(r);
                  spans.add(TextSpan(text: p.text, style: linkStyle, recognizer: r, semanticsLabel: '${p.text}, finance word'));
              }
            }
          }
        case ValueSegment():
          spans.add(WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: ValueChip(s, base: base)));
        case CapturedSegment(:final output):
          flush();
          blocks.add(CodeView(output, label: 'Real output', highlight: false));
      }
    }
    flush();
    if (blocks.length == 1) return blocks.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: blocks);
  }
}

/// Finance words linked inside a rendered paragraph (tests and screenshots use this).
List<({String text, TapGestureRecognizer recognizer})> termLinksIn(RichText rich) {
  final out = <({String text, TapGestureRecognizer recognizer})>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.recognizer is TapGestureRecognizer && span.text != null) {
      out.add((text: span.text!, recognizer: span.recognizer! as TapGestureRecognizer));
    }
    return true;
  });
  return out;
}

/// A pipeline number. Tap to see its description (what it measures).
class ValueChip extends StatelessWidget {
  const ValueChip(this.value, {super.key, this.base});
  final ValueSegment value;
  final TextStyle? base;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: value.description,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 4),
        child: HighlightChip(value.display, style: base),
      );
}
