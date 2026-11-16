/// What happens when a case is finished: the report PDF is written, saved to Downloads/CaseTrainer and offered for
/// sharing, and the sector's next problem is named.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../engine/placeholders.dart';
import '../engine/sector_slots.dart';
import '../providers.dart';
import 'case_report.dart';

const _files = MethodChannel('case_trainer/files');

Future<ReportFonts> loadReportFonts() async {
  Future<pw.Font> f(String a) async => pw.Font.ttf(await rootBundle.load(a));
  return ReportFonts(
    regular: await f('assets/fonts/Archivo-Regular.ttf'),
    bold: await f('assets/fonts/Archivo-Bold.ttf'),
    mono: await f('assets/fonts/JetBrainsMono-Regular.ttf'),
  );
}

/// Writes the report and records it; returns (file in app storage, name in Downloads or null).
Future<({String path, String? downloads})> writeReport(WidgetRef ref, CaseInfo info) async {
  final content = ref.read(contentDbProvider);
  final progress = ref.read(progressDbProvider);
  final resolver = Resolver(content.results(info.id), content.captured(info.id));
  final records = collectRecords(content, progress, info.id);
  final summary = await summariseCase(ref.read(claudeClientProvider), info, records, resolver);
  final now = DateTime.now();
  final bytes = await buildCaseReport(
    info: info,
    records: records,
    resolver: resolver,
    sources: content.sources(),
    fonts: await loadReportFonts(),
    summary: summary,
    now: now,
  );
  final name = reportFileName(info, now);
  final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}reports')..createSync(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  String? downloads;
  try {
    downloads = await _files.invokeMethod<String>('saveToDownloads', {'name': name, 'bytes': bytes, 'mime': 'application/pdf'});
  } catch (e) {
    debugPrint('[CaseTrainer] report not saved to Downloads: $e');
  }
  progress.recordReport(info.id, filePath: file.path, downloadName: downloads, summary: summary?.toJson());
  ref.read(progressTickProvider.notifier).bump();
  return (path: file.path, downloads: downloads);
}

Future<void> shareReport(String path, CaseInfo info) => SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: 'application/pdf')],
      subject: 'Case Trainer report: P${info.number} ${info.title}',
      text: 'My worked answers for P${info.number}, ${info.title}.',
    ));

/// Runs after the finish rule passed and the case was marked complete.
Future<void> runFinishFlow(BuildContext context, WidgetRef ref, CaseInfo info) async {
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(spacing: 16, children: [
        SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
        Expanded(child: Text('Writing your case report…')),
      ]),
    ),
  );
  ({String path, String? downloads})? saved;
  Object? error;
  try {
    saved = await writeReport(ref, info);
  } catch (e) {
    error = e;
  }
  nav.pop();
  if (!context.mounted) return;
  final content = ref.read(contentDbProvider);
  final slot = sectorSlot(info.domain, content.cases(), content.catalog(), ref.read(progressDbProvider));
  final next = slot.active != null
      ? 'Next ${domainLabels[info.domain]} case: P${slot.active!.number}, ${slot.active!.title}.'
      : slot.preparing != null
          ? 'Next ${domainLabels[info.domain]} problem: P${slot.preparing!.number}, ${slot.preparing!.title} (being prepared).'
          : null;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('finish_dialog'),
      icon: const Icon(Icons.flag_rounded),
      title: Text('P${info.number} finished'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        if (saved != null)
          Text(saved.downloads != null
              ? 'Your report is saved in ${saved.downloads}.'
              : 'Your report is saved in the app. Use Share to send it to Drive, email or another app.'),
        if (error != null) Text('The report could not be written: $error'),
        if (next != null) Text(next),
      ]),
      actions: [
        if (saved != null)
          TextButton.icon(
            onPressed: () => shareReport(saved!.path, info),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share'),
          ),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done')),
      ],
    ),
  );
}
