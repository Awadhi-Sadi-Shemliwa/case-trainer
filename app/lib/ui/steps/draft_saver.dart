import 'dart:async';

import 'package:flutter/material.dart';

/// Keeps a step's unsubmitted input on the phone (owner request 2026-11-15: text typed, then Back, was lost).
///
/// Call [changed] after every edit. The value is written [delay] later, and at the latest when the step
/// closes ([dispose]: the Back button, system back, leaving the case) or the app leaves the foreground.
/// Writes are synchronous SQLite calls, so nothing is pending once [flush] returns.
class DraftSaver with WidgetsBindingObserver {
  DraftSaver(this._write, {this.delay = const Duration(milliseconds: 300)}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final void Function() _write;
  final Duration delay;
  Timer? _timer;
  bool _dirty = false;

  /// True once something has been written (drives the quiet "Saved on this phone" line).
  final ValueNotifier<bool> saved = ValueNotifier(false);

  void changed() {
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty) return;
    _dirty = false;
    _write();
    saved.value = true;
  }

  /// Drops pending changes, e.g. after a submit stored the answer as an attempt.
  void discard() {
    _timer?.cancel();
    _timer = null;
    _dirty = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) flush();
  }

  void dispose() {
    flush();
    WidgetsBinding.instance.removeObserver(this);
    saved.dispose();
  }
}

/// One quiet line under an input: the draft was restored, or it is saved on this phone.
class DraftStatus extends StatelessWidget {
  const DraftStatus(this.saver, {super.key, this.restored = false, this.leading});

  final DraftSaver saver;
  final bool restored;

  /// Optional text on the left (e.g. a word count).
  final String? leading;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ValueListenableBuilder<bool>(
      valueListenable: saver.saved,
      builder: (context, saved, _) {
        final status = saved ? 'Saved on this phone' : (restored ? 'Your unsent answer is back' : null);
        if (status == null && leading == null) return const SizedBox.shrink();
        return Row(spacing: 8, children: [
          Expanded(child: Text(leading ?? '', style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (status != null)
            Flexible(
              flex: 2,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 4, children: [
                Icon(saved ? Icons.check_rounded : Icons.history_rounded, size: 16, color: style?.color),
                Flexible(
                  child: Text(status,
                      key: const ValueKey('draft_status'), style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
        ]);
      },
    );
  }
}
