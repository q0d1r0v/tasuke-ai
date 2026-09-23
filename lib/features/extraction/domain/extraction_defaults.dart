/// Every tunable number the extractor uses, in one place.
///
/// They are constants rather than settings because each one is a product
/// decision that a test pins; scattering them through the grammar files is how
/// "morning" ends up meaning 9 in one place and 8 in another.
abstract final class ExtractionDefaults {
  /// When a task has a date but no time, and the user turns a reminder on.
  static const int allDayReminderMinute = 9 * 60;

  // Named times of day. Each is asserted in time_grammar_test.
  static const int morningMinute = 9 * 60;
  static const int afternoonMinute = 14 * 60;
  static const int eveningMinute = 18 * 60;
  static const int nightMinute = 20 * 60;
  static const int noonMinute = 12 * 60;
  static const int midnightMinute = 0;

  /// A bare weekday resolves **strictly forward**: "Friday", said on a Friday,
  /// means next Friday. Saying "Friday" about today is unnatural; saying it
  /// about the one coming up is what people mean.
  static const bool bareWeekdayIsStrictlyForward = true;

  /// A bare time already past today rolls to tomorrow — but only when no date
  /// was given. "3 PM" at 4 PM means tomorrow; "today at 3 PM" at 4 PM is an
  /// overdue task the user knowingly created.
  static const bool bareTimeRollsToTomorrow = true;

  /// An absolute date with no year that has already passed rolls to next year.
  static const bool bareDateRollsToNextYear = true;

  /// The longest utterance the recorder accepts.
  static const Duration maxRecordingDuration = Duration(seconds: 60);

  /// Below this the recorder refuses rather than transcribing a cough.
  static const Duration minRecordingDuration = Duration(milliseconds: 900);

  /// Hard ceiling on tasks from one utterance. A transcript that splits into
  /// 200 is a whisper repetition loop, not a to-do list, and rendering 200
  /// Confirm cards is worse than truncating.
  static const int maxTasksPerCapture = 20;

  /// How long the pipeline waits for extraction before it gives up on it and
  /// runs the fallback extractor once more.
  ///
  /// ⚠️ It was 45 s, sized for on-device language-model inference, which the
  /// app no longer does. The rule-based extractor takes a few milliseconds on
  /// a normal note and about 1.5 s on a laptop for the worst transcript
  /// whisper can produce (60 s of a repetition loop), so 5 s only ever means
  /// a hung extractor, and it still fits the 10 s p95 budget for Stop →
  /// Confirm. It bounds the wait, not the work: `extract` does everything
  /// before it returns its future, so the timer starts once the work is
  /// done. It only bites if extraction ever moves off this isolate.
  static const Duration extractionTimeout = Duration(seconds: 5);

  /// How long the recogniser may take to finalise after Stop before the
  /// pipeline gives up and keeps whatever it already heard.
  ///
  /// ⚠️ There was no bound here at all. `stopRecording` awaited the transcript
  /// completer directly, so a whisper session that never finalised — a dead
  /// worker isolate, a native abort — left the Processing screen animating
  /// forever with no way out but killing the app. 30 s is generous: the whole
  /// budget for Stop → Confirm is 10 s at p95.
  static const Duration transcriptionTimeout = Duration(seconds: 30);

  /// Free tier: voice captures per local day. The next one opens the paywall.
  ///
  /// Every string that shows this number is an ICU plural, so changing it
  /// needs no copy edits in the app — but the store texts (store/terms.html,
  /// assets/legal/terms_en.md, store/REVIEW_NOTES.md, store/PRODUCTS.md,
  /// store/store-listing.txt) state it in words and must move with it —
  /// `store_products_test.dart` checks the listing.
  static const int freeDailyCaptures = 1;
}
