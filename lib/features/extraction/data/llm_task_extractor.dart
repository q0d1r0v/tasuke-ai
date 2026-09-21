import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:tasuke_ai/core/error/failure.dart';
import 'package:tasuke_ai/core/logging/log.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';
import 'package:tasuke_ai/features/extraction/domain/extracted_task.dart';
import 'package:tasuke_ai/features/extraction/domain/extraction_defaults.dart';
import 'package:tasuke_ai/features/extraction/domain/task_extractor.dart';

/// Turns the model's raw text into tasks, or null when it did not survive
/// validation.
///
/// A function rather than the validator class itself so this file depends on
/// *behaviour* and not on a sibling's type: the validator also resolves
/// `when_text` through `WhenParser`, and that is a domain concern this adapter
/// has no business knowing the shape of.
typedef ExtractionOutputParser = List<ExtractedTask>? Function(
  String raw, {
  required LocalDateTime now,
});

/// The on-device language model, through llama.cpp.
///
/// ## Why the model is never asked for a date
///
/// The required output shape is
/// `[{"title": "...", "when_text": "the raw phrase, unchanged",
/// "has_reminder": true}]`, and `when_text` is a **copy of the user's own
/// words** — "tomorrow at 3 PM", "next Friday", "the 14th".
///
/// LFM2-350M-Extract is very good at pulling spans out of text and hopeless at
/// arithmetic. Ask it for `"date": "2026-09-22"` and it will confidently return
/// the wrong day of the week, the wrong month at a boundary, and last year's
/// date every January — none of which fails loudly. Ask it only to *quote*,
/// and every case it gets wrong is a case where the user's words really were
/// ambiguous.
///
/// The arithmetic is then done by `WhenParser`, which is deterministic, takes
/// `now` as a parameter and has a fixture table of a hundred and fifty cases.
/// That division — model for language, code for calendars — is the whole design
/// of this feature, and moving date logic into the prompt would quietly undo it.
final class LlmTaskExtractor implements TaskExtractor {
  LlmTaskExtractor({
    required this._modelPath,
    required this._parse,
    LlamaEngine Function()? engineFactory,
    this._timeout = ExtractionDefaults.extractionTimeout,
  }) : _engineFactory = engineFactory ?? (() => LlamaEngine(LlamaBackend()));

  /// The grammar that makes an invalid shape unrepresentable.
  ///
  /// Grammar-constrained decoding rejects any token that cannot continue a valid
  /// parse, so the model *cannot* emit prose, a code fence, a trailing comma or
  /// a fourth key. That is worth far more here than a bigger model would be: the
  /// entire class of "it answered in Markdown this time" bugs is gone, and the
  /// retry below then only ever has to deal with semantically wrong content.
  ///
  /// ⚠️ Keep the key order in [taskGrammar] identical to the order in the
  /// prompt's examples. GBNF fixes the order at the grammar level, and a prompt
  /// that demonstrates a different one makes the model fight the constraint
  /// token by token — slower, and worse output.
  static const String taskGrammar = r'''
root  ::= "[" ws ( task ( ws "," ws task )* ws )? "]"
task  ::= "{" ws "\"title\"" ws ":" ws string ws
              "," ws "\"when_text\"" ws ":" ws string ws
              "," ws "\"has_reminder\"" ws ":" ws bool ws "}"
string ::= "\"" char* "\""
char  ::= [^"\\\n] | "\\" ( ["\\/bfnrt] | "u" hex hex hex hex )
hex   ::= [0-9a-fA-F]
bool  ::= "true" | "false"
ws    ::= [ \t\n]*
''';

  /// Developer-facing, never rendered: a prompt is not a user-visible string and
  /// does not belong in the ARB. The app is English-only, and so is the model.
  static const String systemPrompt = '''
You extract to-do items from a spoken note. Reply with ONLY a JSON array.

For each task emit exactly three keys, in this order:
  "title"        — what to do, imperative, no date or time words in it
  "when_text"    — the words from the note that say WHEN, copied EXACTLY, or ""
  "has_reminder" — true only if the speaker asked to be reminded or alerted

Never convert "when_text" into a date. Never compute one. Never guess a day of
the week. Copy the speaker's words and stop. If the note says no when, use "".

Note: "Tomorrow at 3 PM send the build to James and Friday check App Store"
[{"title":"Send the build to James","when_text":"Tomorrow at 3 PM","has_reminder":false},{"title":"Check App Store","when_text":"Friday","has_reminder":false}]

Note: "Remind me to call mum tonight"
[{"title":"Call mum","when_text":"tonight","has_reminder":true}]

Note: "Buy milk"
[{"title":"Buy milk","when_text":"","has_reminder":false}]''';

  /// Sent once, after a reply that parsed as JSON but did not survive
  /// validation. Short on purpose: a long scolding prompt costs prefill time on
  /// a device that has none to spare, and the grammar has already ruled out
  /// every syntactic problem.
  static const String repairPrompt =
      'That did not match the required shape. Reply again with ONLY the JSON '
      'array. Copy the when-words exactly; do not convert them to a date.';

  final Future<String?> Function() _modelPath;
  final ExtractionOutputParser _parse;
  final LlamaEngine Function() _engineFactory;
  final Duration _timeout;

  LlamaEngine? _engine;
  String? _loadedPath;

  @override
  Future<bool> isReady() async => await _modelPath() != null;

  @override
  Future<List<ExtractedTask>> extract(
    String transcript, {
    required LocalDateTime now,
  }) async {
    if (transcript.trim().isEmpty) return const <ExtractedTask>[];

    try {
      // One budget for the whole call, retry included. A second attempt that
      // starts after the user has already been staring at a spinner for its
      // whole budget is worse than no second attempt.
      return await _extract(transcript, now).timeout(_timeout);
    } on TimeoutException {
      Log.w('extraction ran past ${_timeout.inSeconds}s');
      throw const ExtractionFailure(
        'The model took too long',
        kind: ExtractionFailureKind.timeout,
      );
    }
  }

  Future<List<ExtractedTask>> _extract(
    String transcript,
    LocalDateTime now,
  ) async {
    final LlamaEngine engine = await _ensureLoaded();

    final List<LlamaChatMessage> messages = <LlamaChatMessage>[
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: systemPrompt,
      ),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Note: "$transcript"',
      ),
    ];

    final String first = await _generate(engine, messages);
    final List<ExtractedTask>? tasks = _parse(first, now: now);
    if (tasks != null) return tasks;

    // Exactly one retry. A model that produced nonsense twice will produce it a
    // third time, and the user is watching a spinner the whole while; the
    // pipeline falls back to the rule-based extractor from here, which always
    // returns *something*.
    Log.w('extractor output failed validation, retrying once');
    final String second = await _generate(engine, <LlamaChatMessage>[
      ...messages,
      LlamaChatMessage.fromText(role: LlamaChatRole.assistant, text: first),
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: repairPrompt,
      ),
    ]);
    final List<ExtractedTask>? repaired = _parse(second, now: now);
    if (repaired != null) return repaired;

    Log.w('extractor output failed validation twice');
    throw const ExtractionFailure(
      'The model did not produce usable tasks',
      kind: ExtractionFailureKind.invalidOutput,
    );
  }

  /// Runs one constrained generation and returns the raw text.
  ///
  /// The heavy work is not on this isolate: llamadart's llama.cpp backend owns a
  /// worker isolate and every token is decoded there. Spawning another isolate
  /// around it would not help — an FFI handle cannot cross an isolate boundary —
  /// and would break the engine's own lifecycle serialisation.
  Future<String> _generate(
    LlamaEngine engine,
    List<LlamaChatMessage> messages,
  ) async {
    final StringBuffer out = StringBuffer();
    await for (final LlamaCompletionChunk chunk in engine.create(
      messages,
      params: GenerationParams(
        grammar: taskGrammar,
        // Extraction is a copying task, not a creative one. Anything above ~0.2
        // starts inventing titles that were never said, and at 0 the model gets
        // stuck repeating a phrase when the note is repetitive.
        temp: 0.1,
        topP: 0.9,
        // Twenty tasks is the hard ceiling the validator enforces; this is
        // roughly that many objects' worth of tokens plus slack.
        maxTokens: 768,
      ),
      // No thinking budget: this model has no reasoning trace, and enabling it
      // only adds tokens the grammar then has to reject one by one.
      enableThinking: false,
    )) {
      final String? delta = chunk.choices.isEmpty
          ? null
          : chunk.choices.first.delta.content;
      if (delta != null) out.write(delta);
    }
    return out.toString();
  }

  Future<LlamaEngine> _ensureLoaded() async {
    final String? path = await _modelPath();
    if (path == null) {
      throw const ExtractionFailure(
        'The language model has not been downloaded',
        kind: ExtractionFailureKind.modelNotInstalled,
      );
    }

    final LlamaEngine? existing = _engine;
    if (existing != null && _loadedPath == path) return existing;
    if (existing != null) await existing.dispose();

    final LlamaEngine engine = _engineFactory();
    // ⚠️ `ModelSource.path`, not `ModelSource.parse('file://…')`. `parse`
    // rejects a `file:` scheme outright — it understands local paths, http(s)
    // and `hf://` and nothing else — so the file URL form throws an
    // ArgumentError before a single token is decoded.
    await engine.loadModelSource(
      ModelSource.path(path),
      // A voice note is a couple of sentences. A 4096-token context would
      // allocate a KV cache many times the size of anything this app will ever
      // put in it, on a phone that is also holding a whisper model.
      modelParams: const ModelParams(contextSize: 1024),
    );
    _engine = engine;
    _loadedPath = path;
    return engine;
  }

  /// Frees the model from native memory. The extractor is kept loaded between
  /// captures on purpose — loading costs seconds — so something has to let go
  /// of it when the app stops needing it.
  Future<void> dispose() async {
    final LlamaEngine? engine = _engine;
    _engine = null;
    _loadedPath = null;
    try {
      await engine?.dispose();
    } on Object catch (error) {
      Log.w('disposing the llama engine threw — $error');
    }
  }
}
