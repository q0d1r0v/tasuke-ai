import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

import '_harness.dart';

/// The vector art: the catalogue, the still illustrations and the breathing
/// blob.
///
/// ⚠️ The manifest group is the important one. A mistyped asset path is not a
/// compile error and not an analyzer warning — it is an "Unable to load asset"
/// exception on one screen of one build, and flutter_svg swallows it into an
/// empty box rather than crashing, so the screen just renders blank.
void main() {
  group('TasukeArt manifest', () {
    test('every declared picture exists on disk', () {
      for (final String asset in TasukeArt.all) {
        expect(
          File(asset).existsSync(),
          isTrue,
          reason: '$asset is named in TasukeArt but is not in the repo',
        );
      }
    });

    test(
      'every declared picture is reachable through the asset bundle',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        for (final String asset in TasukeArt.all) {
          // ⚠️ Through `rootBundle`, not `File`. The two differ exactly when
          // pubspec.yaml has not listed the directory — which is the whole
          // failure mode, because `assets/images/` does NOT pick up
          // `assets/images/blob/`.
          await expectLater(
            rootBundle.loadString(asset),
            completion(isNotEmpty),
            reason:
                '$asset is not declared under flutter.assets in pubspec.yaml',
          );
        }
      },
    );

    test('no picture leans on an SVG filter', () {
      // flutter_svg drops <filter> silently: a drop shadow simply does not
      // render, and art that needed one to separate from its background comes
      // out flat. The shadow belongs in Dart, on the widget that hosts the
      // picture.
      for (final String asset in TasukeArt.all) {
        final String source = File(asset).readAsStringSync();
        for (final String marker in <String>[
          'filter="url(',
          '<feDropShadow',
          '<feGaussianBlur',
        ]) {
          expect(
            source,
            isNot(contains(marker)),
            reason: '$asset uses $marker, which flutter_svg ignores',
          );
        }
      }
    });

    test('no two frames are the same drawing', () {
      // ⚠️ The supplied set shipped frame 08 byte-identical to frame 01 — the
      // artboard's closing frame, which a loop provides for free by wrapping.
      // Animating both held one image for 600 ms once per cycle, and that
      // hitch is exactly what reads as a broken animation rather than a slow
      // one. A duplicate is invisible in review and obvious on a phone.
      final Map<String, String> byDigest = <String, String>{};
      for (int i = 0; i < TasukeArt.blobFrameCount; i++) {
        final String path = TasukeArt.blobFrame(i);
        final String digest = md5
            .convert(File(path).readAsBytesSync())
            .toString();
        expect(
          byDigest[digest],
          isNull,
          reason: '$path is identical to ${byDigest[digest]}',
        );
        byDigest[digest] = path;
      }
    });

    test('the blob frames are a contiguous, correctly padded run', () {
      expect(TasukeArt.blobFrame(0), endsWith('blob_frame_01.svg'));
      // ⚠️ Derived, not hard-coded: the frame count has already changed twice.
      final String last = (TasukeArt.blobFrameCount).toString().padLeft(2, '0');
      expect(
        TasukeArt.blobFrame(TasukeArt.blobFrameCount - 1),
        endsWith('blob_frame_$last.svg'),
      );
      expect(
        Directory('assets/images/blob').listSync().whereType<File>().length,
        TasukeArt.blobFrameCount,
        reason: 'a frame on disk that TasukeArt does not name never renders',
      );
    });

    test('each frame is valid XML with a 512 square viewBox', () {
      for (int i = 0; i < TasukeArt.blobFrameCount; i++) {
        final String source = File(TasukeArt.blobFrame(i)).readAsStringSync();
        expect(source, contains('viewBox="0 0 512 512"'));
        expect(utf8.encode(source).length, lessThan(8 * 1024));
      }
    });
  });

  group('SvgIllustration', () {
    testWidgets('renders at the size it is given', (WidgetTester tester) async {
      // ⚠️ `Align`, because a vertical `SingleChildScrollView` constrains its
      // child's width TIGHTLY to the viewport. Measured inside one, a 160pt
      // box reports the phone's 375 and the assertion tests the scroll view.
      await pumpWidgetUnderTest(
        tester,
        const Align(
          child: SvgIllustration(asset: TasukeArt.guideVoice, size: 160),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(SvgIllustration)).width, 160);
      expect(
        tester.getSize(find.byType(SvgIllustration)).height,
        160,
        reason: 'the box is pinned before the picture parses, so nothing jumps',
      );
    });

    testWidgets('announces nothing and swallows no taps', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const SvgIllustration(asset: TasukeArt.guidePrivacy, size: 120),
      );
      await tester.pump();

      // Decoration: it is neither a hit-test target nor a semantics node.
      expect(
        find.descendant(
          of: find.byType(SvgIllustration),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );

      final SemanticsHandle handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(SvgIllustration)).label,
        isEmpty,
        reason: 'the headline under the art already says what the page is',
      );
      handle.dispose();
    });
  });

  group('BlobOrb', () {
    Future<List<String>> framesOnScreen(WidgetTester tester) async {
      return tester.widgetList<SvgPicture>(find.byType(SvgPicture)).map((
        SvgPicture picture,
      ) {
        final BytesLoader loader = picture.bytesLoader;
        return loader is SvgAssetLoader ? loader.assetName : '';
      }).toList();
    }

    testWidgets('cross-fades two frames at a time, never eight', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(tester, const Align(child: BlobOrb(size: 180)));
      await tester.pump();

      // Exactly on a frame boundary the incoming layer is fully transparent
      // and is not built at all — a fully-invisible Opacity still costs a
      // saveLayer.
      expect(find.byType(SvgPicture), findsOneWidget);

      await tester.pump(
        TasukeDurations.blobCycle ~/ (TasukeArt.blobFrameCount * 2),
      );
      expect(
        find.byType(SvgPicture),
        findsNWidgets(2),
        reason: 'mid-fade there are two layers, and never more than two',
      );
      expect(tester.getSize(find.byType(BlobOrb)).width, 180);

      await tearDownTree(tester);
    });

    testWidgets('advances through the loop and comes back round', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(tester, const BlobOrb());
      await tester.pump();

      final String first = (await framesOnScreen(tester)).first;
      expect(first, TasukeArt.blobFrame(0));

      // Half a cycle in — deliberately the MIDDLE of a slot, not its edge.
      // `blobCycle ~/ frameCount * n` lands a millisecond short of the
      // boundary and the assertion then tests integer rounding rather than the
      // loop. Half of seven slots is slot 3 with room on both sides.
      await tester.pump(TasukeDurations.blobCycle ~/ 2);
      final int midway = TasukeArt.blobFrameCount ~/ 2;
      expect((await framesOnScreen(tester)).first, TasukeArt.blobFrame(midway));

      // A whole cycle from there returns to where it started.
      await tester.pump(TasukeDurations.blobCycle);
      expect((await framesOnScreen(tester)).first, TasukeArt.blobFrame(midway));

      await tearDownTree(tester);
    });

    testWidgets('holds still when the platform asks for reduced motion', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Material(child: Center(child: const BlobOrb())),
          ),
        ),
      );
      await tester.pump();

      expect((await framesOnScreen(tester)).first, TasukeArt.blobFrame(0));
      await tester.pump(TasukeDurations.blobCycle * 2);
      expect(
        (await framesOnScreen(tester)).first,
        TasukeArt.blobFrame(0),
        reason: 'an ambient loop is exactly what reduce-motion turns off',
      );

      await tearDownTree(tester);
    });

    testWidgets('leaves no ticker behind when it goes away', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(tester, const BlobOrb());
      await tester.pump(TasukeDurations.blobCycle ~/ 2);
      await tearDownTree(tester);
      // The test framework asserts on a live ticker at teardown; reaching here
      // is the assertion.
      expect(find.byType(BlobOrb), findsNothing);
    });
  });
}
