/// One active problem per sector (owner request 2026-11-16: "when i finish one problem ... another problem is placed
/// at the football place"). The slot holds the first unfinished built case in build order; when every built case of
/// the sector is finished it shows the next problem of the curriculum as "being prepared".
library;

import '../data/models.dart';
import '../data/progress_db.dart';

class SectorSlot {
  const SectorSlot({required this.domain, this.active, this.preparing, this.finished = const []});
  final String domain;

  /// The case to work on now.
  final CaseInfo? active;

  /// When nothing built is left: the next curriculum problem, not built yet.
  final CatalogProblem? preparing;

  /// Finished cases of this sector, most recent build-order first.
  final List<CaseInfo> finished;
}

int _rank(CatalogProblem? p) => p?.buildRank ?? 1000 + (p?.number ?? 0);

SectorSlot sectorSlot(String domain, List<CaseInfo> cases, List<CatalogProblem> catalog, ProgressDb progress) {
  final byNumber = {for (final p in catalog) p.number: p};
  final built = cases.where((c) => c.domain == domain).toList()
    ..sort((a, b) => _rank(byNumber[a.number]).compareTo(_rank(byNumber[b.number])));
  final done = [for (final c in built) if (progress.caseState(c.id)?.completed ?? false) c];
  final active = built.where((c) => !done.contains(c)).firstOrNull;
  CatalogProblem? preparing;
  if (active == null) {
    final next = catalog.where((p) => p.domain == domain && !p.built && (p.tier == 'A' || p.tier == 'A*')).toList()
      ..sort((a, b) => _rank(a).compareTo(_rank(b)));
    preparing = next.firstOrNull;
  }
  return SectorSlot(domain: domain, active: active, preparing: preparing, finished: done);
}
