import 'package:flutter/material.dart';

import '../../engine/placeholders.dart';
import 'code_view.dart';

/// Authored text with `{expected.*}` values highlighted (tap for what the number means) and
/// `{captured.*}` outputs rendered as code blocks.
class Prose extends StatelessWidget {
  const Prose(this.text, {super.key, required this.resolver, this.style});

  final String text;
  final Resolver resolver;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge;
    final segs = resolver.segments(text);
    final blocks = <Widget>[];
    var spans = <InlineSpan>[];

    void flush() {
      if (spans.isEmpty) return;
      blocks.add(Text.rich(TextSpan(style: base, children: spans)));
      spans = [];
    }

    for (final s in segs) {
      switch (s) {
        case TextSegment(:final text):
          spans.add(TextSpan(text: text));
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

/// A pipeline number. Tap to see its description (what it measures).
class ValueChip extends StatelessWidget {
  const ValueChip(this.value, {super.key, this.base});
  final ValueSegment value;
  final TextStyle? base;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: value.description,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(4)),
        child: Text(value.display,
            style: (base ?? const TextStyle()).copyWith(
                fontFamily: 'monospace', fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
      ),
    );
  }
}
