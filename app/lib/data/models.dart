/// Plain data classes parsed from content.sqlite rows (JSON written by pipeline/build_content.py).
library;

const phaseOrder = ['brief', 'frame', 'predict', 'data', 'explore', 'model', 'decide', 'debrief'];
const phaseLabels = {
  'brief': 'Brief',
  'frame': 'Frame',
  'predict': 'Predict',
  'data': 'Data',
  'explore': 'Explore',
  'model': 'Model',
  'decide': 'Decide',
  'debrief': 'Debrief',
};
const domainOrder = ['aviation', 'f1', 'football', 'finance'];
const domainLabels = {'aviation': 'Aviation', 'f1': 'Formula 1', 'football': 'Football', 'finance': 'Finance'};

/// Free-text steps the examiner grades (mirror of GRADED_TYPES in content_schema.py).
const gradedTypes = {
  'free_text', 'chart_explain', 'result_explain', 'memo',
  'data_expectation', 'cleaning_justification', 'plan_challenge', 'decision_threshold',
};

class CaseInfo {
  CaseInfo(this.json)
      : id = json['id'] as String,
        number = json['number'] as int,
        domain = json['domain'] as String,
        title = json['title'] as String,
        tier = json['tier'] as String;

  final Map<String, dynamic> json;
  final String id;
  final int number;
  final String domain;
  final String title;
  final String tier;

  String get decisionMaker => json['decision_maker'] as String;
  String get decision => json['decision'] as String;
  String get moneyAtStake => json['money_at_stake'] as String;
  List<String> get concepts => List<String>.from(json['concepts'] as List);
  List<String> get sources => List<String>.from(json['sources'] as List);
  List<String> get allowedLiterals => List<String>.from(json['allowed_literals'] as List? ?? const []);
  Map<String, dynamic> get debrief => json['debrief'] as Map<String, dynamic>;
}

class Option {
  Option(Map<String, dynamic> j)
      : id = j['id'] as String,
        text = j['text'] as String,
        correct = j['correct'] as bool? ?? false,
        explanation = j['explanation'] as String? ?? '';
  final String id;
  final String text;
  final bool correct;
  final String explanation;
}

class Blank {
  Blank(Map<String, dynamic> j)
      : token = j['token'] as String,
        accept = List<String>.from(j['accept'] as List? ?? const []);
  final String token;
  final List<String> accept;
}

class StepData {
  StepData(this.json, this.index)
      : id = json['id'] as String,
        phase = json['phase'] as String,
        type = json['type'] as String,
        title = json['title'] as String,
        prompt = json['prompt'] as String;

  final Map<String, dynamic> json;
  final int index;
  final String id;
  final String phase;
  final String type;
  final String title;
  final String prompt;

  String? _s(String k) => json[k] as String?;
  String? get body => _s('body');
  String? get chart => _s('chart');
  String? get dataset => _s('dataset');
  String? get transform => _s('transform');
  String? get flawedPlan => _s('flawed_plan');
  String get scaffold => _s('scaffold') ?? 'none';
  String? get modelAnswer => _s('model_answer');
  String? get analysisPointer => _s('analysis_pointer');
  String? get outputName => _s('output_name');
  String? get buggyCode => _s('buggy_code');
  String? get bugExplanation => _s('bug_explanation');
  String? get answerKey => _s('answer_key');
  String? get unit => _s('unit');
  double? get tolerance => (json['tolerance'] as num?)?.toDouble();
  List<Option> get options =>
      [for (final o in (json['options'] as List? ?? const [])) Option(o as Map<String, dynamic>)];
  List<String> get items => List<String>.from(json['items'] as List? ?? const []);
  List<Blank> get blanks => [for (final b in (json['blanks'] as List? ?? const [])) Blank(b as Map<String, dynamic>)];
  ({String file, String name})? get snippet {
    final s = json['snippet'] as Map<String, dynamic>?;
    return s == null ? null : (file: s['file'] as String, name: s['name'] as String);
  }

  Map<String, dynamic>? get rubric => json['rubric'] as Map<String, dynamic>?;
  bool get isGraded => gradedTypes.contains(type);
  bool get isInfo => type == 'code_read' || type == 'concept_card';
}

class ResultEntry {
  ResultEntry({required this.key, required this.value, required this.unit, required this.description, required this.display});
  final String key;
  final Object? value;
  final String unit;
  final String description;
  final String display;
}

class SourceRef {
  SourceRef(this.json);
  final Map<String, dynamic> json;
  String get key => json['key'] as String;
  String get title => json['title'] as String;
  String get authors => json['authors'] as String;
  String get year => json['year'] as String;
  String get url => json['url'] as String;
  String get quote => json['quote'] as String;
  String get status => json['status'] as String;
  bool get verified => status == 'VERIFIED';
}
