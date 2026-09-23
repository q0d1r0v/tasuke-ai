// Regenerates every rasterised form of the app mark from the one painter that
// defines it.
//
//   flutter test tool/generate_icons.dart
//   dart run flutter_launcher_icons
//   dart run flutter_native_splash:create
//
// ⚠️ It writes into assets/images/, so it lives under tool/ and not under
// test/: `flutter test` with no arguments only walks test/, which is what keeps
// CI from rewriting checked-in assets on every run.
//
// ⚠️ Not a golden test and not a check — it is a generator. Running it and then
// committing nothing means the icons already matched the painter.
@Tags(<String>['tool'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/widgets/tasuke_logo.dart';

Future<void> _render(
  String path,
  int pixels,
  TasukeLogoPainter painter, {
  bool circular = false,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Size size = Size.square(pixels.toDouble());

  if (circular) {
    canvas.clipPath(
      Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }
  painter.paint(canvas, size);

  final ui.Image image = await recorder.endRecording().toImage(pixels, pixels);
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  if (png == null) throw StateError('encoding $path produced no bytes');
  File(path).writeAsBytesSync(png.buffer.asUint8List());
  // ignore: avoid_print — this file is a script, not app code.
  print('wrote $path (${pixels}px, ${png.lengthInBytes ~/ 1024} KB)');
}

void main() {
  testWidgets('regenerates the launcher, splash and store marks', (
    WidgetTester tester,
  ) async {
    // ⚠️ `runAsync`. `Picture.toImage` completes from the raster thread, and a
    // test body runs inside FakeAsync where that future never resolves — the
    // generator hangs rather than failing.
    await tester.runAsync(() async {
      const String dir = 'assets/images';

      // iOS and the Play listing: the full-bleed tile.
      await _render('$dir/icon.png', 1024, const TasukeLogoPainter());

      // Android adaptive foreground: the trace alone, inset to survive the
      // circular mask, over `adaptive_icon_background` from pubspec.yaml.
      await _render(
        '$dir/icon_foreground.png',
        1024,
        const TasukeLogoPainter(
          drawTile: false,
          markScale: TasukeLogoPainter.adaptiveSafeScale,
        ),
      );

      // The round launcher variant some OEM launchers ask for by name.
      await _render(
        '$dir/icon_rounded.png',
        1024,
        const TasukeLogoPainter(),
        circular: true,
      );

      // The OS splash, drawn over `flutter_native_splash.color`.
      await _render('$dir/splash_logo.png', 512, const TasukeLogoPainter());

      for (final String name in <String>[
        'icon.png',
        'icon_foreground.png',
        'icon_rounded.png',
        'splash_logo.png',
      ]) {
        expect(File('$dir/$name').lengthSync(), greaterThan(1024));
      }
    });
  });
}
