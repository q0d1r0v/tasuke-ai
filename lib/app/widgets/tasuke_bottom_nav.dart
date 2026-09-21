import 'package:flutter/material.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/widgets/capture/mic_fab.dart';

/// The scoop the bar's top edge makes under the mic button.
///
/// Wider than the button and only [TasukeSpacing.md] deep: the design hints at
/// the button rather than cutting a socket for it.
const double _notchWidth = TasukeMetrics.micFab + (TasukeSpacing.lg * 2);
const double _notchDepth = TasukeSpacing.md;

/// The notched bottom bar and its mic button.
///
/// Four destinations in bar order — Home, Search, Stats, Settings — around a
/// fifth, empty slot. [currentIndex] and [onSelected] are indices into
/// `kShellBranches`; the mic is not a destination and reports through
/// [onMicTap].
///
/// ⚠️ Three hit-testing traps are designed around here, and all three have
/// shipped as bugs before:
///
/// 1. `Scaffold` hit-tests its `bottomNavigationBar` slot **before** its body.
///    One opaque box spanning the whole 88pt band therefore eats every tap on
///    the bottom of the task list while every navigation test still passes.
///    Only the bar itself and the button are allowed to hit-test: the band
///    around them is a bare [Stack], whose own `hitTestSelf` is false, holding
///    an [Align] that hits nothing but its child.
/// 2. The button overhangs the bar, and a [Stack] child painted outside its
///    parent's bounds receives no taps at all. So it is a **sibling** of the
///    bar inside a Stack sized to the whole band, not a child of the bar.
/// 3. `BottomAppBar(shape: CircularNotchedRectangle())` with
///    `centerDocked` cannot draw this notch: that geometry is derived from the
///    button's bounding rect plus a fixed `notchMargin`, which always produces a
///    deep circular socket. The scoop here is one quadratic curve.
class TasukeBottomNav extends StatelessWidget {
  const TasukeBottomNav({
    required this.currentIndex,
    required this.onSelected,
    required this.onMicTap,
    this.micEnabled = true,
    this.micProgressLabel,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onMicTap;
  final bool micEnabled;
  final String? micProgressLabel;

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final List<String> labels = <String>[
      // ⚠️ The ARB has no `navHome`: it carries searchTitle, statsTitle and
      // settingsTitle but nothing for Home, so the app's own name stands in as
      // the first tab's accessibility label until that key exists.
      context.l10n.appTitle,
      context.l10n.searchTitle,
      context.l10n.statsTitle,
      context.l10n.settingsTitle,
    ];

    return SizedBox(
      // Never the bare constant: Android 15 forces edge-to-edge with no opt-out
      // and the design sheet contains no system chrome, so the band has to be
      // told how much of it the device is already using.
      height: TasukeMetrics.navBandHeightOf(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: TasukeMetrics.navBarHeight + bottomInset,
            child: _NavSurface(
              bottomInset: bottomInset,
              currentIndex: currentIndex,
              onSelected: onSelected,
              labels: labels,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: TasukeMetrics.micFab,
            // Align hits only its child, so the band either side of the button
            // stays transparent to taps — see trap 1.
            child: Align(
              alignment: Alignment.topCenter,
              child: MicFab(
                onTap: onMicTap,
                enabled: micEnabled,
                progressLabel: micProgressLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavSurface extends StatelessWidget {
  const _NavSurface({
    required this.bottomInset,
    required this.currentIndex,
    required this.onSelected,
    required this.labels,
  });

  final double bottomInset;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<String> labels;

  static const List<IconData> _icons = <IconData>[
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.bar_chart_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Listener(
      // The bar is opaque to taps over its own rect, and only over its own
      // rect. Without this a tap landing in the gap between two glyphs falls
      // through to the list scrolling underneath.
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: const _NavBarPainter(),
        child: Padding(
          // The bar's surface runs under the system gesture handle; its content
          // does not.
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NavSlot(
                icon: _icons[0],
                label: labels[0],
                selected: currentIndex == 0,
                onTap: () => onSelected(0),
              ),
              _NavSlot(
                icon: _icons[1],
                label: labels[1],
                selected: currentIndex == 1,
                onTap: () => onSelected(1),
              ),
              // The mic's slot. Empty: the button is a sibling of this whole
              // surface, not a child of it — see trap 2.
              const Expanded(child: SizedBox.shrink()),
              _NavSlot(
                icon: _icons[2],
                label: labels[2],
                selected: currentIndex == 2,
                onTap: () => onSelected(2),
              ),
              _NavSlot(
                icon: _icons[3],
                label: labels[3],
                selected: currentIndex == 3,
                onTap: () => onSelected(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          // ⚠️ InkResponse with a circular shape, not a plain InkWell.
          //
          // An InkWell fills its Expanded cell, so the splash and the lingering
          // highlight are a full-bleed RECTANGLE inside a bar with rounded
          // corners and a scooped notch. It reads as a rendering fault, and it
          // is plainly visible in a store screenshot taken right after a tap.
          child: InkResponse(
            onTap: onTap,
            radius: TasukeMetrics.minTapTarget / 2,
            highlightShape: BoxShape.circle,
            containedInkWell: false,
            child: Center(
              // ⚠️ No text label. The band's height is pinned to the device's
              // system inset rather than to its content, so a label inside it
              // cannot honour the type scale — it would clip at 2×. The
              // destination's name lives in the screen header and in the
              // Semantics label above.
              child: Icon(
                icon,
                size: TasukeSpacing.xxl,
                color: selected ? TasukeColors.primary : TasukeColors.inkFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarPainter extends CustomPainter {
  const _NavBarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = _barPath(size);

    // Painted by hand because a ClipPath would cut the shadow off at exactly
    // the edge it is supposed to fall outside of, and PhysicalShape only draws
    // Material's own downward elevation — this one is blue and points up.
    for (final BoxShadow shadow in TasukeShadows.nav) {
      canvas.drawPath(path.shift(shadow.offset), shadow.toPaint());
    }
    canvas.drawPath(path, Paint()..color = TasukeColors.surface);
  }

  Path _barPath(Size size) {
    final double radius = TasukeRadii.cardLg;
    final double centreX = size.width / 2;
    final double half = _notchWidth / 2;

    return Path()
      ..moveTo(0, size.height)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..lineTo(centreX - half, 0)
      // A quadratic reaches half its control point's offset at its midpoint,
      // so the control sits at twice the depth the scoop should have.
      ..quadraticBezierTo(centreX, _notchDepth * 2, centreX + half, 0)
      ..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  bool shouldRepaint(_NavBarPainter oldDelegate) => false;
}
