/// What a live whisper session is primed with, and on which passes.
///
/// The app's setting is [WhisperDecoding.app]: the final pass — the one whose
/// text becomes the user's tasks — is primed with [whisperNamesPrompt], and
/// the live previews are not primed at all.
///
/// Measured with the device-free eval (test/asr/asr_eval_test.dart): 705 TTS
/// clips of the tuning split, each variant decoded right after its no-prompt
/// twin so the two share the machine's load. "net" is notes whose tasks came
/// out exactly right minus notes that stopped doing so; the time is the final
/// pass's, median of the paired ratios.
///
/// | final pass decoded with           |  net | exact tasks |  its time  |
/// |-----------------------------------|------|-------------|------------|
/// | greedy, no prompt (before)        |    — | 69.9–70.5%  |          — |
/// | **30 Uzbek names**                |  +49 | **76.9%**   |   **+13%** |
/// | 15 of the names                   |  +35 | 74.9%       |        +9% |
/// | fillers only: "Um, uh, so, okay." |  +18 | 73.0%       |      +2.5% |
/// | fillers and to-do verbs           |  +10 | 71.9%       |        +5% |
/// | beam search, 5 beams              |  +18 | 73.0%       |       +19% |
/// | beam search, 3 beams              |   −1 | 70.4%       |       +10% |
/// | 30 names and 5 beams              |  +60 | 79.0%       |       +34% |
/// | temperature fallback, never fired |    0 | 70.5%       |         0% |
///
/// Up to the names prompt every step buys about three notes per 1% of final
/// pass; beams on top buy half a note per 1% and cross the +25% that a
/// six-second Stop on a mid-range phone can afford.
///
/// ⚠️ Expect less than the table. The held-out split (461 clips, run once,
/// never tuned on) gained +13 notes, 67.2% → 70.1%, for the same +14% final
/// pass — all of it on the notes that say a listed name (44 → 63 of 98); the
/// rest moved 266 → 260 of 363, inside the ±8 notes two identical runs
/// differ by. It helps as far as a user's people are on the list.
///
/// ⚠️ Why names and nothing else, when whisper is so easily steered:
///
/// * A prompt that contains a clock time or a to-do sentence teaches whisper
///   to write "a.m."/"p.m." the speaker never said, which moves the task to
///   the wrong half of the day. The names prompt has neither, and invents
///   about as many as no prompt: 3 against 5 on the tuning split, 3 against
///   2 held out, one of which moved a task's time.
/// * The gain is on notes that say one of the listed names ("reply to ASIS"
///   → "reply to Aziz"); names outside the list gain little. Swapping half
///   the list for names from the user's own recent tasks was simulated on the
///   tuning split and did worse than the fixed list (+25 against +49).
/// * The prompt is decoded against the full encoder output, which is where
///   its cost comes from — roughly twice the decoder time of an unprimed
///   pass. On the previews that cost buys nothing (their text is replaced by
///   the final pass), and the preview still running when Stop is pressed is
///   part of what the user waits for, so previews run unprimed
///   ([promptOnPreviews] false). Primed previews made the whole session 25%
///   slower instead of 12%.
final class WhisperDecoding {
  const WhisperDecoding({this.initialPrompt, this.promptOnPreviews = true});

  /// Text whisper treats as what came before the audio: it biases spelling
  /// and style, not content. Null for none.
  final String? initialPrompt;

  /// Whether the live previews are primed too, or only the final pass.
  final bool promptOnPreviews;

  /// What the app ships.
  static const WhisperDecoding app = WhisperDecoding(
    initialPrompt: whisperNamesPrompt,
    promptOnPreviews: false,
  );

  /// No prompt anywhere: the behaviour before [app], kept for comparisons.
  static const WhisperDecoding unprimed = WhisperDecoding();
}

/// Thirty common Uzbek given names, fifteen male and fifteen female.
///
/// ⚠️ From general knowledge of Uzbek naming, never from the eval corpora:
/// a list copied out of the test notes would score perfectly on them and say
/// nothing about a user's own contacts. base.en has never seen most of these
/// spelt ("Bekzod" was "backside", "Jasur's" was "jess or"), so the spelling
/// here is the one users type: Latin, no apostrophes.
const List<String> uzbekGivenNames = <String>[
  'Aziz',
  'Bekzod',
  'Jasur',
  'Otabek',
  'Sardor',
  'Timur',
  'Umid',
  'Akmal',
  'Bobur',
  'Dilshod',
  'Farrukh',
  'Rustam',
  'Sherzod',
  'Jahongir',
  'Ulugbek',
  'Dilnoza',
  'Gulnora',
  'Madina',
  'Nodira',
  'Shahnoza',
  'Zarina',
  'Nigora',
  'Sevara',
  'Malika',
  'Mohira',
  'Feruza',
  'Kamola',
  'Dildora',
  'Nilufar',
  'Laylo',
];

/// [uzbekGivenNames] as whisper is given them: one comma-separated list, one
/// full stop. Spelt out rather than joined because a default argument must be
/// a constant; `whisper_decoding_test.dart` keeps the two in step.
///
/// ⚠️ No clock times, no digits, no sentences: see [WhisperDecoding].
const String whisperNamesPrompt =
    'Aziz, Bekzod, Jasur, Otabek, Sardor, Timur, Umid, Akmal, Bobur, '
    'Dilshod, Farrukh, Rustam, Sherzod, Jahongir, Ulugbek, Dilnoza, Gulnora, '
    'Madina, Nodira, Shahnoza, Zarina, Nigora, Sevara, Malika, Mohira, '
    'Feruza, Kamola, Dildora, Nilufar, Laylo.';
