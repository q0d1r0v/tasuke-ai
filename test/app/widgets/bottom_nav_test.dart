import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';

import '_harness.dart';

/// The bar as a screen hosts it: floating over a full-bleed body.
///
/// The body is what proves trap 1 — if anything in the 88pt band hit-tests
/// where it should not, [onBehind] stops firing and every navigation
/// assertion in this file still passes.
Widget hostedNav({
  required ValueChanged<int> onSelected,
  required VoidCallback onMicTap,
  required VoidCallback onBehind,
  bool micEnabled = true,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return Stack(
    children: <Widget>[
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBehind,
          child: const SizedBox.expand(),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Builder(
          builder: (BuildContext context) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: padding),
              child: TasukeBottomNav(
                currentIndex: 0,
                onSelected: onSelected,
                onMicTap: onMicTap,
                micEnabled: micEnabled,
              ),
            );
          },
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('maps its four destinations onto shell branch indices', (
    WidgetTester tester,
  ) async {
    final List<int> selected = <int>[];
    await pumpWidgetUnderTest(
      tester,
      hostedNav(onSelected: selected.add, onMicTap: () {}, onBehind: () {}),
      scrollable: false,
    );

    for (final IconData icon in <IconData>[
      Icons.home_rounded,
      Icons.search_rounded,
      Icons.bar_chart_rounded,
      Icons.settings_rounded,
    ]) {
      await tester.tap(find.byIcon(icon));
    }

    // 0..3, in bar order — the mic's slot is not a destination and shifts
    // nothing.
    expect(selected, <int>[0, 1, 2, 3]);
  });

  testWidgets('the mic reports separately, and not at all when disabled', (
    WidgetTester tester,
  ) async {
    int mics = 0;
    await pumpWidgetUnderTest(
      tester,
      hostedNav(
        onSelected: (int _) {},
        onMicTap: () => mics++,
        onBehind: () {},
      ),
      scrollable: false,
    );
    await tester.tap(find.byType(MicFab));
    expect(mics, 1);

    await pumpWidgetUnderTest(
      tester,
      hostedNav(
        onSelected: (int _) {},
        onMicTap: () => mics++,
        onBehind: () {},
        micEnabled: false,
      ),
      scrollable: false,
    );
    await tester.tap(find.byType(MicFab));
    expect(mics, 1);
  });

  testWidgets('the band above the bar does not eat taps on the body', (
    WidgetTester tester,
  ) async {
    int behind = 0;
    int selected = -1;
    int mics = 0;
    await pumpWidgetUnderTest(
      tester,
      hostedNav(
        onSelected: (int index) => selected = index,
        onMicTap: () => mics++,
        onBehind: () => behind++,
      ),
      scrollable: false,
    );

    final Rect band = tester.getRect(find.byType(TasukeBottomNav));
    expect(band.height, TasukeMetrics.navBandHeight);

    // Inside the band, above the bar, well clear of the button: the overhang
    // strip. One opaque Container across the whole band would swallow this.
    await tester.tapAt(Offset(band.left + 40, band.top + 6));
    expect(behind, 1, reason: 'the overhang strip must be transparent');
    expect(selected, -1);
    expect(mics, 0);

    // The bar itself is opaque, or a tap between two glyphs falls through to
    // whatever is scrolling underneath.
    await tester.tapAt(Offset(band.left + 40, band.bottom - 8));
    expect(behind, 1);
  });

  testWidgets('the button overhangs the bar and still takes its taps', (
    WidgetTester tester,
  ) async {
    int mics = 0;
    await pumpWidgetUnderTest(
      tester,
      hostedNav(
        onSelected: (int _) {},
        onMicTap: () => mics++,
        onBehind: () {},
      ),
      scrollable: false,
    );

    final Rect band = tester.getRect(find.byType(TasukeBottomNav));
    final Rect fab = tester.getRect(find.byType(MicFab));

    expect(fab.top, band.top);
    expect(
      fab.bottom,
      lessThan(band.bottom - TasukeMetrics.navBarHeight + TasukeMetrics.micFab),
    );

    // The overhanging top edge of the button — outside the bar's own bounds,
    // which is exactly where a Stack child of the bar would stop responding.
    await tester.tapAt(Offset(fab.center.dx, fab.top + 4));
    expect(mics, 1);
  });

  testWidgets('the band grows by the system inset, never the bare constant', (
    WidgetTester tester,
  ) async {
    await pumpWidgetUnderTest(
      tester,
      hostedNav(
        onSelected: (int _) {},
        onMicTap: () {},
        onBehind: () {},
        padding: const EdgeInsets.only(bottom: 34),
      ),
      scrollable: false,
    );

    // Android 15 is edge-to-edge with no opt-out; the design sheet has no
    // system chrome in it, so the inset can only come from MediaQuery.
    expect(
      tester.getSize(find.byType(TasukeBottomNav)).height,
      TasukeMetrics.navBandHeight + 34,
    );
  });

  testWidgets('every destination is announced', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await pumpWidgetUnderTest(
      tester,
      hostedNav(onSelected: (int _) {}, onMicTap: () {}, onBehind: () {}),
      scrollable: false,
    );

    expect(
      tester.getSemantics(find.byIcon(Icons.search_rounded)),
      isSemantics(label: 'Search', isButton: true),
    );
    expect(
      tester.getSemantics(find.byIcon(Icons.home_rounded)),
      isSemantics(isSelected: true),
    );
    handle.dispose();
  });
}
