import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../ui/theme/tokens.dart';
import 'course.dart';
import 'quiz.dart';
import 'quiz_runner.dart';
import 'term_card.dart';

/// One lesson: read its ten words (swipe or Next), then take the quick check. Eight of ten passes the lesson;
/// every word answered correctly becomes known.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.lessonId});
  final String lessonId;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _quiz = false;
  int _round = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int to) => _pages.animateToPage(to, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseProvider);
    final lesson = course.lesson(widget.lessonId);
    final tier = course.tier(lesson.tier);
    final words = course.termsOf(lesson.id);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final pageCount = words.length + 1;
    final progress = ref.read(progressDbProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(lesson.title, style: t.titleLarge, overflow: TextOverflow.ellipsis),
          Text('Lesson ${lesson.number} of ${course.lessonsOf(tier.id).length}, ${tier.title.toLowerCase()} tier',
              style: t.bodySmall),
        ]),
      ),
      body: SafeArea(
        child: _quiz
            ? ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  QuizRunner(
                    key: ValueKey('round_$_round'),
                    questions: buildQuiz(course, words,
                        seed: '${lesson.id}|${progress.lessonStates()[lesson.id]?.attempts ?? 0}'),
                    passMark: lessonPassMark,
                    onAnswer: (term, ok) {
                      progress.recordTermAnswer(term.id, correct: ok);
                      ref.read(progressTickProvider.notifier).bump();
                    },
                    onFinished: (score, missed) {
                      progress.recordLesson(lesson.id, score: score, passed: score >= lessonPassMark);
                      ref.read(progressTickProvider.notifier).bump();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _round++),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Take the check again'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _quiz = false;
                      _page = 0;
                    }),
                    child: const Text('Read the words again'),
                  ),
                ],
              )
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(spacing: 4, children: [
                    for (var i = 0; i < pageCount; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: 5,
                          decoration: BoxDecoration(
                            color: i < _page ? c.ink : (i == _page ? c.highlighter : c.grid),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  ]),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: pageCount,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => i < words.length
                        ? ListView(
                            key: PageStorageKey('word_${words[i].id}'),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            children: [TermCard(words[i], compact: true)],
                          )
                        : ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 32), children: [
                            Text('Quick check', style: t.headlineMedium),
                            const SizedBox(height: 8),
                            Text(
                              'Ten questions, one per word. Get $lessonPassMark right to pass the lesson. '
                              'Words you get right become known and come back for review later.',
                              style: t.bodyLarge,
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              key: const ValueKey('start_check'),
                              onPressed: () => setState(() => _quiz = true),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Start the quick check'),
                            ),
                          ]),
                  ),
                ),
              ]),
      ),
      bottomNavigationBar: _quiz
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(spacing: 12, children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _page == 0 ? null : () => _go(_page - 1),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back'),
                    ),
                  ),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('lesson_next'),
                      onPressed: _page >= pageCount - 1 ? null : () => _go(_page + 1),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(_page == words.length - 1 ? 'Quick check' : 'Next word'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

/// Words due today, one question each; right answers climb the review ladder, wrong ones go back to a day.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  late final List<GlossaryTerm> _words;
  late final String _seed;

  @override
  void initState() {
    super.initState();
    final course = ref.read(courseProvider);
    final due = ref.read(courseProgressProvider).due;
    _words = [for (final id in due.take(20)) ?course.byId[id]];
    final now = DateTime.now();
    _seed = 'review|${now.year}-${now.month}-${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final progress = ref.read(progressDbProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          if (_words.isEmpty) ...[
            Text('Nothing to review today', style: t.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Words come back for review a day after you first get them right, then after three, seven and '
              'twenty-one days. Pass a lesson to add more.',
              style: t.bodyLarge,
            ),
          ] else
            QuizRunner(
              questions: buildQuiz(ref.read(courseProvider), _words, seed: _seed),
              onAnswer: (term, ok) {
                progress.recordTermAnswer(term.id, correct: ok);
                ref.read(progressTickProvider.notifier).bump();
              },
              onFinished: (_, _) {},
            ),
        ]),
      ),
    );
  }
}
