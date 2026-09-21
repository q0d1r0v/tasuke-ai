import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Applies to every file under `test/` (and nothing under `integration_test/`).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadAppFonts();
  await testMain();
}

/// Loads the bundled Inter faces.
///
/// ⚠️ Without this every widget test lays text out in the flutter_test stub
/// font, where all glyphs are the same box. Overflow assertions then measure
/// the wrong width, and goldens are pictures of rectangles. Hoisted here rather
/// than into each harness so no golden can forget it.
Future<void> _loadAppFonts() async {
  final FontLoader inter = FontLoader('Inter');
  inter.addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
  await inter.load();

  // ⚠️ The Material icon font too. `flutter_test` does not register it, so
  // every `Icon` renders as an empty box — which passes an overflow assertion
  // (the box is the right size) and quietly makes every golden a picture of
  // rectangles where the design has glyphs.
  final ByteData iconData = await rootBundle.load(
    'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  );
  final FontLoader cupertino = FontLoader('CupertinoIcons')
    ..addFont(Future<ByteData>.value(iconData));
  await cupertino.load();

  final FontLoader material = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await material.load();
}
