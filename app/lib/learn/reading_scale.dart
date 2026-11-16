import 'package:flutter/material.dart';

import '../ui/theme/tokens.dart';
import 'course.dart';

/// One value of a measure drawn on its scale: rule-of-thumb bands (if the pipeline has a VERIFIED source for them),
/// reference marks, an interval, and the value itself as a highlighter dot with its number above. Every position and
/// label comes from the pipeline; this widget only places them. A key underneath repeats everything in words, so
/// nothing depends on colour and nothing collides at large text sizes.
class ReadingScale extends StatelessWidget {
  const ReadingScale(this.reading, {super.key});

  final ReadingInfo reading;

  /// Band fills: ink laid over paper at rising strength, one hue from light to strong. Checked with the dataviz
  /// palette validator (ordinal ramp: monotone, visible steps, light end at least 2:1 against the paper) in light
  /// and dark mode for three and four bands.
  static List<Color> bandRamp(CaseColors c, int n) {
    const first = 0.36, last = 0.86;
    return [
      for (var i = 0; i < n; i++) Color.alphaBlend(c.ink.withValues(alpha: n == 1 ? last : first + i * (last - first) / (n - 1)), c.paper),
    ];
  }

  /// Everything the scale shows, as one sentence list for screen readers.
  static String describe(ReadingInfo r) {
    final parts = <String>['Scale from ${r.loText} to ${r.hiText}.'];
    final p = r.point;
    final band = r.pointBand;
    if (p != null) parts.add('This value: ${p.text}${band == null ? '' : ', in the band ${band.label}'}.');
    final i = r.interval;
    if (i != null) parts.add('Interval from ${i.loText} to ${i.hiText}.');
    for (final m in r.marks) {
      parts.add('${m.text}: ${m.label}.');
    }
    for (final b in r.bands) {
      parts.add('${b.label}: ${b.loText} to ${b.hiText}.');
    }
    if (r.better != 'neither') parts.add('${r.better == 'higher' ? 'Higher' : 'Lower'} is better.');
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final r = reading;
    if (!r.hasScale) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    const tabular = [FontFeature.tabularFigures()];
    final valueStyle = t.titleSmall!.copyWith(color: c.onHighlighter, fontWeight: FontWeight.w700, fontFeatures: tabular);
    final axisStyle = t.labelMedium!.copyWith(color: c.inkSoft, fontFeatures: tabular);
    double lineHeight(TextStyle s) =>
        (TextPainter(text: TextSpan(text: '0', style: s), textDirection: TextDirection.ltr, textScaler: scaler)..layout()).height;
    final endStyle = t.labelSmall!.copyWith(color: c.inkSoft);
    final valueH = r.point == null ? 0.0 : lineHeight(valueStyle) + 6;
    final axisH = lineHeight(axisStyle);
    final ramp = bandRamp(c, r.bands.length);
    final band = r.pointBand;
    // Marks that sit at an end of the scale are labelled under that end; the others go in the key.
    final loMark = r.marks.where((m) => m.at == r.lo).firstOrNull;
    final hiMark = r.marks.where((m) => m.at == r.hi).firstOrNull;
    final keyMarks = [for (final m in r.marks) if (m != loMark && m != hiMark) m];

    return Semantics(
      container: true,
      label: describe(r),
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          LayoutBuilder(builder: (context, box) {
            // End labels may wrap onto a second line, each within half the width.
            final endW = box.maxWidth / 2 - 8;
            TextPainter? end(ReadingMark? m) => m == null
                ? null
                : (TextPainter(
                    text: TextSpan(text: m.label, style: endStyle),
                    textDirection: TextDirection.ltr,
                    textScaler: scaler,
                    maxLines: 2,
                    ellipsis: '…',
                  )..layout(maxWidth: endW));
            final loLabel = end(loMark), hiLabel = end(hiMark);
            final endH = [loLabel?.height ?? 0.0, hiLabel?.height ?? 0.0].reduce((a, b) => a > b ? a : b);
            return SizedBox(
              height: valueH + _ScalePainter.gapAboveTrack + _ScalePainter.trackH + _ScalePainter.gapBelowTrack + axisH + endH,
              child: CustomPaint(
                painter: _ScalePainter(
                  reading: r,
                  colors: c,
                  ramp: ramp,
                  valueStyle: valueStyle,
                  axisStyle: axisStyle,
                  scaler: scaler,
                  valueH: valueH,
                  loLabel: loLabel,
                  hiLabel: hiLabel,
                ),
              ),
            );
          }),
          Wrap(spacing: 16, runSpacing: 8, children: [
            for (final (i, b) in r.bands.indexed)
              _KeyEntry(
                swatch: Container(
                  width: 18,
                  height: 10,
                  decoration: BoxDecoration(color: ramp[i], borderRadius: BorderRadius.circular(3)),
                ),
                text: '${b.label}, ${b.loText} to ${b.hiText}',
                strong: b == band,
              ),
            for (final m in keyMarks)
              _KeyEntry(
                swatch: Container(width: 3, height: 14, decoration: BoxDecoration(color: c.inkSoft, borderRadius: BorderRadius.circular(2))),
                text: '${m.text}: ${m.label}',
              ),
            if (r.interval case final i?)
              _KeyEntry(
                swatch: Container(width: 18, height: 8, decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(4))),
                text: 'interval, ${i.loText} to ${i.hiText}',
              ),
            if (r.better != 'neither')
              _KeyEntry(
                swatch: Icon(r.better == 'higher' ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 18, color: c.inkSoft),
                text: r.better == 'higher' ? 'higher is better' : 'lower is better',
              ),
          ]),
          if (r.bands.isNotEmpty)
            Text('The bands are a rule of thumb; the source is under "Checked against".', style: t.bodySmall?.copyWith(color: c.inkSoft)),
        ]),
      ),
    );
  }
}

class _KeyEntry extends StatelessWidget {
  const _KeyEntry({required this.swatch, required this.text, this.strong = false});
  final Widget swatch;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
      swatch,
      Flexible(
        child: Text(
          text,
          style: t.bodySmall?.copyWith(
            color: strong ? c.ink : c.inkSoft,
            fontWeight: strong ? FontWeight.w700 : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ]);
  }
}

class _ScalePainter extends CustomPainter {
  _ScalePainter({
    required this.reading,
    required this.colors,
    required this.ramp,
    required this.valueStyle,
    required this.axisStyle,
    required this.scaler,
    required this.valueH,
    this.loLabel,
    this.hiLabel,
  });

  static const trackH = 12.0;
  static const gapAboveTrack = 10.0;
  static const gapBelowTrack = 10.0;
  static const _endPad = 11.0; // room for the dot at either end

  final ReadingInfo reading;
  final CaseColors colors;
  final List<Color> ramp;
  final TextStyle valueStyle;
  final TextStyle axisStyle;
  final TextScaler scaler;
  final double valueH;

  /// Labels of marks sitting at the low and high ends, laid out by the widget (they may wrap).
  final TextPainter? loLabel;
  final TextPainter? hiLabel;

  TextPainter _text(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: scaler)..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final r = reading;
    final c = colors;
    final lo = r.lo!, hi = r.hi!;
    const left = _endPad;
    final right = size.width - _endPad;
    double x(double v) => left + (v.clamp(lo, hi) - lo) / (hi - lo) * (right - left);
    final top = valueH + gapAboveTrack;
    final bottom = top + trackH;
    final midY = top + trackH / 2;

    // Track: bands (with 2 px paper gaps between them) or a plain rule.
    final track = RRect.fromLTRBR(left, top, right, bottom, const Radius.circular(trackH / 2));
    if (r.bands.isEmpty) {
      canvas.drawRRect(track, Paint()..color = c.grid);
    } else {
      canvas.save();
      canvas.clipRRect(track);
      for (final (i, b) in r.bands.indexed) {
        canvas.drawRect(Rect.fromLTRB(x(b.lo), top, x(b.hi), bottom), Paint()..color = ramp[i]);
      }
      for (final b in r.bands.skip(1)) {
        canvas.drawRect(Rect.fromLTRB(x(b.lo) - 1, top, x(b.lo) + 1, bottom), Paint()..color = c.paper);
      }
      canvas.restore();
    }

    // Reference marks: ticks through the track.
    final tick = Paint()
      ..color = c.inkSoft
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final m in r.marks) {
      canvas.drawLine(Offset(x(m.at), top - 5), Offset(x(m.at), bottom + 5), tick);
    }

    // An interval: a thick ink bar with a paper ring so it separates from the track.
    if (r.interval case final i?) {
      final bar = RRect.fromLTRBR(x(i.lo), midY - 4, x(i.hi), midY + 4, const Radius.circular(4));
      canvas.drawRRect(bar.inflate(2), Paint()..color = c.paper);
      canvas.drawRRect(bar, Paint()..color = c.ink);
    }

    // The value: a highlighter dot ringed in paper, its number on a highlighter stroke above it.
    if (r.point case final p?) {
      final px = x(p.at);
      canvas.drawCircle(Offset(px, midY), 9, Paint()..color = c.paper);
      canvas.drawCircle(Offset(px, midY), 7, Paint()..color = c.highlighter);
      canvas.drawCircle(
          Offset(px, midY),
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = c.ink);
      final tp = _text(p.text, valueStyle);
      final w = tp.width + 10;
      final lx = (px - w / 2).clamp(0.0, size.width - w);
      final h = valueH;
      final stroke = Path()
        ..moveTo(lx + 1.5, h * 0.06)
        ..lineTo(lx + w, 0)
        ..lineTo(lx + w - 1.5, h * 0.94)
        ..lineTo(lx, h)
        ..close();
      canvas.drawPath(stroke, Paint()..color = c.highlighter.withValues(alpha: 0.92));
      tp.paint(canvas, Offset(lx + 5, (h - tp.height) / 2));
      canvas.drawLine(Offset(px, h), Offset(px, top - 2), Paint()
        ..color = c.ink
        ..strokeWidth = 1.5);
    }

    // The ends of the scale.
    final ly = bottom + gapBelowTrack;
    final loT = _text(r.loText!, axisStyle);
    final hiT = _text(r.hiText!, axisStyle);
    loT.paint(canvas, Offset((left - loT.width / 2).clamp(0.0, size.width - loT.width), ly));
    hiT.paint(canvas, Offset((right - hiT.width / 2).clamp(0.0, size.width - hiT.width), ly));
    final ey = ly + loT.height;
    loLabel?.paint(canvas, Offset(0, ey));
    if (hiLabel case final h?) h.paint(canvas, Offset(size.width - h.width, ey));
  }

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.reading != reading || old.colors != colors || old.scaler != scaler || old.valueStyle != valueStyle;
}
