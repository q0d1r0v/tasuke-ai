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

  /// Hard ceiling on tasks from one utterance. A model that returns 200 is
  /// malfunctioning, and rendering 200 Confirm cards is worse than truncating.
  static const int maxTasksPerCapture = 20;

  /// How far ahead a date may be before it is treated as a hallucination.
  static const int maxFutureDays = 3650;

  /// How far back. One day, so "yesterday" survives as an overdue task.
  static const int maxPastDays = 1;

  /// How long inference may run before the pipeline gives up.
  static const Duration extractionTimeout = Duration(seconds: 45);

  /// Free tier: voice captures per local day.
  static const int freeDailyCaptures = 5;
}
