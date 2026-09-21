import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

import '_harness.dart';

void main() {
  group('MicFab', () {
    testWidgets('reports taps, and refuses them when disabled', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(tester, MicFab(onTap: () => taps++));
      await tester.tap(find.byType(MicFab));
      expect(taps, 1);

      await pumpWidgetUnderTest(
        tester,
        MicFab(onTap: () => taps++, enabled: false),
      );
      await tester.tap(find.byType(MicFab));
      expect(taps, 1);
    });

    testWidgets('announces "Speak" by default and the progress when busy', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWidgetUnderTest(tester, MicFab(onTap: () {}));
      expect(
        tester.getSemantics(find.byType(MicFab)),
        isSemantics(label: 'Speak', isButton: true),
      );

      await pumpWidgetUnderTest(
        tester,
        MicFab(
          onTap: () {},
          enabled: false,
          progressLabel: 'Preparing AI — 42%',
        ),
      );
      // A ring, not text: a 64pt circle cannot lay a label out at 2× scale.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Preparing AI — 42%'), findsNothing);
      expect(
        tester.getSemantics(find.byType(MicFab)),
        isSemantics(label: 'Preparing AI — 42%'),
      );
      handle.dispose();
    });

    testWidgets('is the design size', (WidgetTester tester) async {
      await pumpWidgetUnderTest(
        tester,
        Align(
          alignment: Alignment.centerLeft,
          child: MicFab(onTap: () {}),
        ),
      );

      expect(
        tester.getSize(find.byType(MicFab)),
        const Size.square(TasukeMetrics.micFab),
      );
    });
  });

  group('MicOrb', () {
    testWidgets('re-reads the level every time the amplitude ticks', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<double> amplitude = ValueNotifier<double>(0);
      addTearDown(amplitude.dispose);
      int reads = 0;

      await pumpWidgetUnderTest(
        tester,
        MicOrb(
          amplitude: amplitude,
          levelOf: () {
            reads++;
            return amplitude.value;
          },
        ),
      );
      final int afterFirstFrame = reads;

      amplitude.value = 0.9;
      await tester.pump();
      expect(reads, greaterThan(afterFirstFrame));

      await tearDownTree(tester);
    });

    testWidgets('clamps a level the recorder reports out of range', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<double> amplitude = ValueNotifier<double>(-160);
      addTearDown(amplitude.dispose);

      await pumpWidgetUnderTest(
        tester,
        MicOrb(amplitude: amplitude, levelOf: () => amplitude.value),
      );

      expect(tester.takeException(), isNull);
      await tearDownTree(tester);
    });
  });

  group('WaveformView', () {
    testWidgets('repaints from the Listenable without rebuilding', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> amplitude = ValueNotifier<int>(0);
      addTearDown(amplitude.dispose);
      int paints = 0;

      List<double> samples() {
        paints++;
        return <double>[0.2, 0.4, 0.9];
      }

      await pumpWidgetUnderTest(
        tester,
        WaveformView(amplitude: amplitude, samplesOf: samples),
      );

      final Finder painter = find.descendant(
        of: find.byType(WaveformView),
        matching: find.byType(CustomPaint),
      );
      final CustomPaint before = tester.widget<CustomPaint>(painter);
      final int paintsAfterFirstFrame = paints;

      amplitude.value = 1;
      await tester.pump();

      // ⚠️ This is the whole point of the widget: the samples reached the
      // canvas, and the widget tree was never rebuilt to get them there.
      expect(paints, greaterThan(paintsAfterFirstFrame));
      expect(
        identical(tester.widget<CustomPaint>(painter), before),
        isTrue,
        reason: 'a rebuild here costs the Recording screen its frame rate',
      );
    });

    testWidgets('survives having fewer samples than bars', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> amplitude = ValueNotifier<int>(0);
      addTearDown(amplitude.dispose);

      await pumpWidgetUnderTest(
        tester,
        WaveformView(
          amplitude: amplitude,
          samplesOf: () => const <double>[0.5],
          barCount: 32,
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('RecordingTimer', () {
    testWidgets('formats mm:ss and follows the Listenable', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<Duration> elapsed = ValueNotifier<Duration>(
        const Duration(seconds: 65),
      );
      addTearDown(elapsed.dispose);

      await pumpWidgetUnderTest(
        tester,
        RecordingTimer(elapsed: elapsed, valueOf: () => elapsed.value),
      );
      expect(find.text('01:05'), findsOneWidget);

      elapsed.value = const Duration(seconds: 9);
      await tester.pump();
      expect(find.text('00:09'), findsOneWidget);
    });

    test('never prints a negative or a fractional second', () {
      expect(RecordingTimer.format(const Duration(seconds: -3)), '00:00');
      expect(
        RecordingTimer.format(const Duration(seconds: 59, milliseconds: 900)),
        '00:59',
      );
      expect(RecordingTimer.format(const Duration(minutes: 12)), '12:00');
    });
  });

  group('GradientOrb', () {
    testWidgets('is decoration: it takes no taps and says nothing', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      int behind = 0;

      await pumpWidgetUnderTest(
        tester,
        Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => behind++,
                child: const SizedBox.expand(),
              ),
            ),
            const Center(child: GradientOrb()),
          ],
        ),
        scrollable: false,
      );

      await tester.tapAt(tester.getCenter(find.byType(GradientOrb)));
      expect(behind, 1);
      handle.dispose();
    });
  });

  group('ProcessingChecklist', () {
    testWidgets('draws each step in its own state', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const ProcessingChecklist(
          steps: <ProcessingStepView>[
            ProcessingStepView(
              label: 'Transcribing your voice',
              state: ProcessingStepState.done,
            ),
            ProcessingStepView(
              label: 'Understanding with AI',
              state: ProcessingStepState.active,
            ),
            ProcessingStepView(
              label: 'Finding tasks and dates',
              state: ProcessingStepState.pending,
            ),
          ],
        ),
      );

      expect(find.text('Transcribing your voice'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tearDownTree(tester);
    });

    test('a step view compares by value, so a rebuild is cheap', () {
      const ProcessingStepView a = ProcessingStepView(
        label: 'Almost done...',
        state: ProcessingStepState.pending,
      );
      const ProcessingStepView b = ProcessingStepView(
        label: 'Almost done...',
        state: ProcessingStepState.pending,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
