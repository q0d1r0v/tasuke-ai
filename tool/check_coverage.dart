#!/usr/bin/env dart

// Enforces line-coverage floors against coverage/lcov.info.
//
//   dart run tool/check_coverage.dart
//   dart run tool/check_coverage.dart --min 80 --min-path 'lib/core/time/**=95'
//
// ⚠️ Written in Dart on purpose. Neither `lcov` nor `genhtml` is installed on
// this machine, and neither is worth adding as a build dependency for what
// amounts to summing two integers per file. The parser below reads the ~40-line
// subset of the LCOV format that `flutter test --coverage` actually emits.
//
// The other reason is that a single global floor is close to useless. A repo can
// sit at 85% overall while the date grammar — the one component where a wrong
// answer is silent and user-visible — sits at 40%, because widget tests inflate
// the average. `--min-path` is what makes the floor mean something: it lets the
// modules whose bugs cannot be seen carry a much higher bar than the UI.

import 'dart:io';

/// Never counted, in either the overall number or a `--min-path` rule.
///
/// All four are generated or vendored: counting them measures the generator, and
/// the generated files are large enough to move the overall figure by several
/// points in whichever direction happens to be convenient.
const List<String> _defaultExcludes = <String>[
  '**/*.g.dart',
  '**/*.freezed.dart',
  '**/*.drift.dart',
  'lib/app/l10n/**',
];

void main(List<String> args) {
  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('check_coverage: ${error.message}');
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final File lcov = File(options.lcovPath);
  if (!lcov.existsSync()) {
    stderr.writeln('check_coverage: no coverage file at ${options.lcovPath}');
    stderr.writeln(
      'check_coverage: generate one first:  '
      "flutter test --exclude-tags 'golden || migration || device' --coverage",
    );
    exitCode = 1;
    return;
  }

  final List<_FileCoverage> all = _parseLcov(lcov.readAsLinesSync());
  if (all.isEmpty) {
    stderr.writeln('check_coverage: ${options.lcovPath} contains no records.');
    exitCode = 1;
    return;
  }

  final List<RegExp> excludes = <RegExp>[
    for (final String glob in <String>[
      ..._defaultExcludes,
      ...options.extraExcludes,
    ])
      _globToRegExp(glob),
  ];

  final List<_FileCoverage> counted = all
      .where(
        (_FileCoverage file) =>
            !excludes.any((RegExp re) => re.hasMatch(file.path)),
      )
      .toList(growable: false);

  final int skipped = all.length - counted.length;

  stdout.writeln('check_coverage: ${options.lcovPath}');
  stdout.writeln(
    'check_coverage: ${counted.length} files counted, '
    '$skipped excluded as generated',
  );
  stdout.writeln('');

  bool failed = false;

  // ── Overall ────────────────────────────────────────────────────────────────
  final _Totals overall = _Totals.of(counted);
  final bool overallOk = overall.percent >= options.min;
  failed |= !overallOk;
  stdout.writeln(
    _row(ok: overallOk, label: 'overall', totals: overall, floor: options.min),
  );

  // ── Per-path rules ─────────────────────────────────────────────────────────
  for (final _PathRule rule in options.pathRules) {
    final RegExp pattern = _globToRegExp(rule.glob);
    final List<_FileCoverage> matched = counted
        .where((_FileCoverage file) => pattern.hasMatch(file.path))
        .toList(growable: false);

    if (matched.isEmpty) {
      // A rule that matches nothing is a rule that has silently stopped
      // protecting anything — almost always a moved directory. Fail loudly
      // rather than report a vacuous pass.
      failed = true;
      stdout.writeln('  ✗ ${rule.glob.padRight(44)} matched NO files');
      continue;
    }

    final _Totals totals = _Totals.of(matched);
    final bool ok = totals.percent >= rule.min;
    failed |= !ok;
    stdout.writeln(
      _row(
        ok: ok,
        label: '${rule.glob} (${matched.length} files)',
        totals: totals,
        floor: rule.min,
      ),
    );
  }

  if (failed) {
    stdout.writeln('');
    stdout.writeln('Least-covered counted files:');
    final List<_FileCoverage> worst = counted.toList()
      ..sort(
        (_FileCoverage a, _FileCoverage b) => a.percent.compareTo(b.percent),
      );
    for (final _FileCoverage file in worst.take(15)) {
      stdout.writeln(
        '  ${file.percent.toStringAsFixed(1).padLeft(5)}%  '
        '${file.hit}/${file.found}  ${file.path}',
      );
    }
    stdout.writeln('');
    stderr.writeln('✗ check_coverage: below the floor.');
    exitCode = 1;
    return;
  }

  stdout.writeln('');
  stdout.writeln('✓ check_coverage: every floor met.');
}

String get _usage => '''
Usage: dart run tool/check_coverage.dart [options]

  --min <pct>                 Overall floor, 0-100. Default 80.
  --min-path <glob>=<pct>     Extra floor for the files matching <glob>.
                              Repeatable. A glob matching nothing is a failure.
  --exclude <glob>            Exclude additionally. Repeatable.
  --lcov <path>               Default coverage/lcov.info.
  -h, --help

Globs: `*` matches within one path segment, `?` one character, `**` any depth,
and `**/` also matches zero segments (so `**/*.g.dart` matches `lib/a.g.dart`).

Always excluded: ${_defaultExcludes.join(', ')}''';

/// One `--min-path` rule.
final class _PathRule {
  const _PathRule(this.glob, this.min);

  final String glob;
  final double min;
}

final class _Options {
  const _Options({
    required this.min,
    required this.pathRules,
    required this.extraExcludes,
    required this.lcovPath,
    required this.help,
  });

  factory _Options.parse(List<String> args) {
    double min = 80;
    final List<_PathRule> rules = <_PathRule>[];
    final List<String> excludes = <String>[];
    String lcovPath = 'coverage/lcov.info';
    bool help = false;

    String valueFor(String flag, int index) {
      if (index + 1 >= args.length) {
        throw FormatException('$flag needs a value');
      }
      return args[index + 1];
    }

    for (int i = 0; i < args.length; i++) {
      final String arg = args[i];
      switch (arg) {
        case '-h':
        case '--help':
          help = true;
        case '--min':
          min = _parsePercent(valueFor(arg, i));
          i++;
        case '--min-path':
          rules.add(_parseRule(valueFor(arg, i)));
          i++;
        case '--exclude':
          excludes.add(valueFor(arg, i));
          i++;
        case '--lcov':
          lcovPath = valueFor(arg, i);
          i++;
        default:
          throw FormatException('unknown argument "$arg"');
      }
    }

    return _Options(
      min: min,
      pathRules: rules,
      extraExcludes: excludes,
      lcovPath: lcovPath,
      help: help,
    );
  }

  final double min;
  final List<_PathRule> pathRules;
  final List<String> extraExcludes;
  final String lcovPath;
  final bool help;
}

double _parsePercent(String raw) {
  final double? value = double.tryParse(raw);
  if (value == null || value < 0 || value > 100) {
    throw FormatException('"$raw" is not a percentage between 0 and 100');
  }
  return value;
}

_PathRule _parseRule(String raw) {
  // Split on the LAST '=' so a glob may contain one.
  final int split = raw.lastIndexOf('=');
  if (split <= 0 || split == raw.length - 1) {
    throw FormatException('"$raw" is not <glob>=<pct>');
  }
  return _PathRule(
    raw.substring(0, split),
    _parsePercent(raw.substring(split + 1)),
  );
}

/// Line coverage for one source file.
final class _FileCoverage {
  const _FileCoverage(this.path, this.found, this.hit);

  final String path;
  final int found;
  final int hit;

  double get percent => found == 0 ? 100 : (hit / found) * 100;
}

final class _Totals {
  const _Totals(this.found, this.hit);

  factory _Totals.of(Iterable<_FileCoverage> files) {
    int found = 0;
    int hit = 0;
    for (final _FileCoverage file in files) {
      found += file.found;
      hit += file.hit;
    }
    return _Totals(found, hit);
  }

  final int found;
  final int hit;

  double get percent => found == 0 ? 100 : (hit / found) * 100;
}

String _row({
  required bool ok,
  required String label,
  required _Totals totals,
  required double floor,
}) =>
    '  ${ok ? '✓' : '✗'} ${label.padRight(44)} '
    '${totals.percent.toStringAsFixed(1).padLeft(5)}%  '
    '(${totals.hit}/${totals.found})  floor ${floor.toStringAsFixed(0)}%';

/// Parses the `SF:` / `DA:` / `end_of_record` subset of LCOV.
///
/// `DA:` lines are summed rather than trusting the `LF:`/`LH:` summary records,
/// and a file appearing in more than one record is merged by taking the highest
/// hit count per line — which is what happens when the same library is reached
/// from two test entry points.
List<_FileCoverage> _parseLcov(List<String> lines) {
  final Map<String, Map<int, int>> perFile = <String, Map<int, int>>{};
  String? current;

  for (final String line in lines) {
    if (line.startsWith('SF:')) {
      current = _normalisePath(line.substring(3).trim());
      perFile.putIfAbsent(current, () => <int, int>{});
    } else if (line.startsWith('DA:') && current != null) {
      final List<String> parts = line.substring(3).split(',');
      if (parts.length < 2) {
        continue;
      }
      final int? lineNumber = int.tryParse(parts[0]);
      final int? hits = int.tryParse(parts[1]);
      if (lineNumber == null || hits == null) {
        continue;
      }
      final Map<int, int> counts = perFile[current]!;
      final int previous = counts[lineNumber] ?? 0;
      counts[lineNumber] = hits > previous ? hits : previous;
    } else if (line.trim() == 'end_of_record') {
      current = null;
    }
  }

  return <_FileCoverage>[
    for (final MapEntry<String, Map<int, int>> entry in perFile.entries)
      _FileCoverage(
        entry.key,
        entry.value.length,
        entry.value.values.where((int hits) => hits > 0).length,
      ),
  ];
}

/// Makes an `SF:` path comparable with a glob written relative to the repo root.
///
/// `flutter test --coverage` normally writes repo-relative paths, but a run
/// through a different working directory writes absolute ones, and then every
/// `--min-path` rule silently matches nothing.
String _normalisePath(String raw) {
  final String posix = raw.replaceAll(r'\', '/');
  final String root = Directory.current.path.replaceAll(r'\', '/');
  if (posix.startsWith('$root/')) {
    return posix.substring(root.length + 1);
  }
  return posix.startsWith('./') ? posix.substring(2) : posix;
}

/// Converts a path glob to an anchored [RegExp].
///
/// `**/` collapses to "zero or more segments" rather than "one or more", which
/// is the behaviour every `.gitignore` and every CI config already assumes:
/// without it `**/*.g.dart` would miss a generated file sitting directly in
/// `lib/`.
RegExp _globToRegExp(String glob) {
  final StringBuffer out = StringBuffer('^');
  int i = 0;
  while (i < glob.length) {
    final String char = glob[i];
    if (char == '*') {
      final bool isDoubleStar = i + 1 < glob.length && glob[i + 1] == '*';
      if (isDoubleStar) {
        final bool followedBySlash = i + 2 < glob.length && glob[i + 2] == '/';
        if (followedBySlash) {
          out.write('(?:[^/]+/)*');
          i += 3;
        } else {
          out.write('.*');
          i += 2;
        }
      } else {
        out.write('[^/]*');
        i += 1;
      }
    } else if (char == '?') {
      out.write('[^/]');
      i += 1;
    } else {
      out.write(RegExp.escape(char));
      i += 1;
    }
  }
  out.write(r'$');
  return RegExp(out.toString());
}
