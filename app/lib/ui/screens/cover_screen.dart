import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../providers.dart';
import '../theme/tokens.dart';
import '../widgets/real_curves.dart';

/// The cover (owner request: "a cover page for the app"). Four real curves, one per sector, drawn from each
/// case's own chart data on graph paper, then one tap to carry on where you left off.
class CoverScreen extends ConsumerStatefulWidget {
  const CoverScreen({super.key});

  @override
  ConsumerState<CoverScreen> createState() => _CoverScreenState();
}

class _CoverScreenState extends ConsumerState<CoverScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  late final List<CaseInfo> _cases;
  late final Future<List<CurvePoints?>> _curves;

  @override
  void initState() {
    super.initState();
    final all = ref.read(contentDbProvider).cases();
    // One case per sector, in the app's sector order.
    _cases = [for (final d in domainOrder) ...all.where((c) => c.domain == d && c.signatureChart != null).take(1)];
    _curves = Future.wait([for (final c in _cases) CurvePoints.load(c.signatureChart!)]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _draw.value = 1;
    } else if (!_draw.isAnimating && _draw.value == 0) {
      _draw.forward();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final content = ref.read(contentDbProvider);
    final last = ref.read(progressDbProvider).lastOpenCase();
    final lastCase = last == null ? null : content.cases().where((x) => x.id == last.caseId).firstOrNull;
    final p = ref.watch(courseProgressProvider);

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // Tall screens: the curves take whatever height is left and the buttons sit at the bottom.
          // Short screens (or large text): everything scrolls with a fixed curve height.
          final roomy = box.maxHeight >= 640 && MediaQuery.textScalerOf(context).scale(16) <= 18;
          Widget curvesArea(double? h) => SizedBox(
                height: h,
                child: FutureBuilder<List<CurvePoints?>>(
                  future: _curves,
                  builder: (context, snap) => LayoutBuilder(builder: (context, area) {
                    final ch = area.maxHeight;
                    return Stack(children: [
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _draw,
                          builder: (context, _) => CustomPaint(
                            key: const ValueKey('cover_curves'),
                            painter: CurvesPainter(
                              curves: snap.data ?? const [],
                              colors: [for (final cs in _cases) c.sector(cs.domain)],
                              surface: c.paper,
                              progress: Curves.easeInOutCubic.transform(_draw.value),
                              strokeWidth: 2.4,
                            ),
                          ),
                        ),
                      ),
                      // Direct labels: sector name in ink beside a swatch, top-left of each lane.
                      for (var k = 0; k < _cases.length; k++)
                        Positioned(
                          left: 0,
                          top: ch / _cases.length * k + 2,
                          child: _LaneLabel(
                            color: c.sector(_cases[k].domain),
                            text: '${domainLabels[_cases[k].domain]}, P${_cases[k].number}',
                          ),
                        ),
                    ]);
                  }),
                ),
              );
          final bottom = <Widget>[
            const SizedBox(height: 8),
            Text('Every line above is real data from the cases.', style: t.bodySmall),
            const SizedBox(height: 24),
            Text('Case\nTrainer', style: t.displayLarge),
            const SizedBox(height: 10),
            Text('Real data, real decisions.', style: t.titleMedium?.copyWith(color: c.inkSoft)),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('cover_continue'),
              onPressed: () {
                context.go('/');
                if (lastCase != null) context.push('/case/${lastCase.id}');
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(lastCase == null ? 'Open the cases' : 'Continue P${lastCase.number}, step ${last!.stepIdx + 1}'),
            ),
            const SizedBox(height: 10),
            Row(spacing: 10, children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('cover_cases'),
                  onPressed: () => context.go('/'),
                  child: const Text('All cases'),
                ),
              ),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('cover_learn'),
                  onPressed: () => context.go('/learn'),
                  child: const Text('Learn finance'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text('${p.knownTotal} of ${p.course.terms.length} words known', style: t.bodySmall, textAlign: TextAlign.center),
          ];
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _GraphPaper(c.grid))),
            if (roomy)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: curvesArea(null)),
                  ...bottom,
                ]),
              )
            else
              ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [curvesArea(260), ...bottom]),
          ]);
        }),
      ),
    );
  }
}

class _LaneLabel extends StatelessWidget {
  const _LaneLabel({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.paper.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.ink)),
      ]),
    );
  }
}

/// Engineering graph paper: a faint minor grid with a stronger line every fifth square.
class _GraphPaper extends CustomPainter {
  _GraphPaper(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 18.0;
    final minor = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;
    final major = Paint()
      ..color = color
      ..strokeWidth = 0.8;
    var i = 0;
    for (var x = 0.0; x <= size.width; x += step, i++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
    }
    i = 0;
    for (var y = 0.0; y <= size.height; y += step, i++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 5 == 0 ? major : minor);
    }
  }

  @override
  bool shouldRepaint(_GraphPaper old) => old.color != color;
}
