import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A number marked up the way an analyst highlights a printout: a slightly slanted highlighter stroke behind
/// ink. Used for every pipeline value and every worked-example number, so "real numbers" look the same
/// everywhere.
class HighlightChip extends StatelessWidget {
  const HighlightChip(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = style ?? DefaultTextStyle.of(context).style;
    return CustomPaint(
      painter: _MarkerPainter(c.highlighter),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(
          text,
          style: base.copyWith(
            color: c.onHighlighter,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // A marker stroke: slanted ends, a hair taller on the left, covering most of the line height.
    final path = Path()
      ..moveTo(1.5, h * 0.14)
      ..lineTo(w, h * 0.08)
      ..lineTo(w - 1.5, h * 0.94)
      ..lineTo(0, h * 0.98)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.92));
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.color != color;
}

final _marked = RegExp(r'\[\[(.+?)\]\]');

/// Text whose [[…]] parts (numbers filled in by the pipeline) are shown highlighted.
class MarkedText extends StatelessWidget {
  const MarkedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge!;
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final m in _marked.allMatches(text)) {
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: HighlightChip(m.group(1)!, style: base),
      ));
      pos = m.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

/// A note with a coloured rule down its left edge (feedback, warnings, the plan to challenge).
class RuledNote extends StatelessWidget {
  const RuledNote({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.rule,
    this.background,
    this.foreground,
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final Color? rule;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = foreground ?? c.ink;
    return Container(
      decoration: BoxDecoration(
        color: background ?? c.paperRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: rule ?? c.ink, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        if (title != null)
          Row(spacing: 8, children: [
            if (icon != null) Icon(icon, size: 20, color: rule ?? fg),
            Expanded(
              child: Text(title!, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
            ),
          ]),
        DefaultTextStyle.merge(style: TextStyle(color: fg), child: child),
      ]),
    );
  }
}

/// A sentence-case section heading with a small icon (instead of ALL-CAPS eyebrow labels).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});

  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(spacing: 8, children: [
      if (icon != null) Icon(icon, size: 20, color: c.inkSoft),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
      ?trailing,
    ]);
  }
}
