import 'package:drift/drift.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/core/time/local_date_time.dart';

/// `'YYYY-MM-DD'` ↔ [LocalDate].
///
/// The converter throws on a malformed string rather than returning null,
/// because the only writer of this column is [toSql] two lines up. A bad value
/// here is database corruption, not user input, and swallowing it would turn a
/// loud bug into a task that silently loses its date.
final class LocalDateConverter extends TypeConverter<LocalDate, String> {
  const LocalDateConverter();

  @override
  LocalDate fromSql(String fromDb) => LocalDate.parseIso(fromDb);

  @override
  String toSql(LocalDate value) => value.toIso();
}

/// `'YYYY-MM-DDTHH:MM'` ↔ [LocalDateTime].
///
/// ⚠️ No offset, no `Z`, no seconds. The missing offset is the feature — see
/// the time-split note at the top of `tables.dart`. Seconds are omitted
/// because no OS scheduler honours them anyway and their absence keeps the
/// string a fixed 16 characters, which keeps the index entries uniform.
final class LocalDateTimeConverter
    extends TypeConverter<LocalDateTime, String> {
  const LocalDateTimeConverter();

  @override
  LocalDateTime fromSql(String fromDb) => LocalDateTime.parseIso(fromDb);

  @override
  String toSql(LocalDateTime value) => value.toIso();
}

/// Epoch milliseconds ↔ a UTC [DateTime].
///
/// ⚠️ Deliberately not drift's own `dateTime()` column. Drift stores those as
/// unix **seconds** unless the `store_date_time_values_as_text` build option is
/// flipped — so the representation of every timestamp in the app would depend
/// on a line in a `build.yaml` that nobody reviews, and switching it is a
/// migration. Seconds also make two tasks completed in the same second sort
/// arbitrarily, which the Stats list notices.
///
/// [fromSql] always returns a `DateTime` with `isUtc == true`; callers that
/// want wall-clock must ask for `.toLocal()` explicitly, so the conversion is
/// always visible at the call site.
final class UtcInstantConverter extends TypeConverter<DateTime, int> {
  const UtcInstantConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.toUtc().millisecondsSinceEpoch;
}

/// Normalises a title into the form stored in `tasks.title_folded` and used as
/// the search needle.
///
/// Three things happen, and each one fixes a search that otherwise fails:
///
///  1. **Lowercasing.** SQLite's `LIKE` is case-insensitive for ASCII only, so
///     "Café" vs "café" is already broken without this, never mind Cyrillic.
///  2. **Diacritic stripping**, both precomposed (`é`, U+00E9) and decomposed
///     (`e` + U+0301). A user typing "cafe" expects to find "café"; a user who
///     dictated "café" gets whichever form whisper emitted, and the two forms
///     are different strings.
///  3. **Removing `%`, `_` and `\`.** These are `LIKE` metacharacters. Stripped
///     from *both* the stored column and the needle, the pattern is guaranteed
///     wildcard-free, so the query needs no `ESCAPE` clause — and a task
///     titled "100% done" is still found by searching "done".
///
/// ⚠️ Must be applied on every write to `title`. A row whose `title_folded` is
/// stale is invisible to search and looks fine everywhere else, which makes it
/// a bug report about "search not working sometimes".
String foldForSearch(String raw) {
  final StringBuffer out = StringBuffer();
  for (final int rune in raw.toLowerCase().runes) {
    // Combining diacritical marks. Dropping them folds decomposed input to the
    // same string the precomposed form produces via [_deaccented].
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    if (rune == 0x25 || rune == 0x5F || rune == 0x5C) continue; // % _ \
    final String? plain = _deaccented[rune];
    if (plain != null) {
      out.write(plain);
      continue;
    }
    out.writeCharCode(rune);
  }
  // Collapse whitespace last, so a stripped metacharacter cannot leave a
  // double space behind and make the two sides of the comparison disagree.
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Precomposed Latin letters that carry a mark, mapped to their base form.
///
/// A hand-written table rather than Unicode NFD, because Dart's core library
/// has no normaliser and pulling one in for the Latin-1 and Latin Extended-A
/// blocks — which is the whole of what an English app plus European names
/// needs — would be a dependency for 60 lines of data. `ß`, `æ` and `œ` expand
/// to two letters, which is what a user searching for them types.
const Map<int, String> _deaccented = <int, String>{
  0xE0: 'a',
  0xE1: 'a',
  0xE2: 'a',
  0xE3: 'a',
  0xE4: 'a',
  0xE5: 'a',
  0xE6: 'ae',
  0xE7: 'c',
  0xE8: 'e',
  0xE9: 'e',
  0xEA: 'e',
  0xEB: 'e',
  0xEC: 'i',
  0xED: 'i',
  0xEE: 'i',
  0xEF: 'i',
  0xF0: 'd',
  0xF1: 'n',
  0xF2: 'o',
  0xF3: 'o',
  0xF4: 'o',
  0xF5: 'o',
  0xF6: 'o',
  0xF8: 'o',
  0xF9: 'u',
  0xFA: 'u',
  0xFB: 'u',
  0xFC: 'u',
  0xFD: 'y',
  0xFF: 'y',
  0xFE: 'th',
  0xDF: 'ss',
  0x101: 'a',
  0x103: 'a',
  0x105: 'a',
  0x107: 'c',
  0x109: 'c',
  0x10B: 'c',
  0x10D: 'c',
  0x10F: 'd',
  0x111: 'd',
  0x113: 'e',
  0x115: 'e',
  0x117: 'e',
  0x119: 'e',
  0x11B: 'e',
  0x11D: 'g',
  0x11F: 'g',
  0x121: 'g',
  0x123: 'g',
  0x125: 'h',
  0x127: 'h',
  0x129: 'i',
  0x12B: 'i',
  0x12D: 'i',
  0x12F: 'i',
  0x131: 'i',
  0x135: 'j',
  0x137: 'k',
  0x13A: 'l',
  0x13C: 'l',
  0x13E: 'l',
  0x140: 'l',
  0x142: 'l',
  0x144: 'n',
  0x146: 'n',
  0x148: 'n',
  0x14D: 'o',
  0x14F: 'o',
  0x151: 'o',
  0x153: 'oe',
  0x155: 'r',
  0x157: 'r',
  0x159: 'r',
  0x15B: 's',
  0x15D: 's',
  0x15F: 's',
  0x161: 's',
  0x163: 't',
  0x165: 't',
  0x167: 't',
  0x169: 'u',
  0x16B: 'u',
  0x16D: 'u',
  0x16F: 'u',
  0x171: 'u',
  0x173: 'u',
  0x175: 'w',
  0x177: 'y',
  0x17A: 'z',
  0x17C: 'z',
  0x17E: 'z',
};
