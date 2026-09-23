import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/permissions/required_permissions.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';

/// The permissions primer, and — with [fixing] — the screen the Home warning
/// banner opens when a required permission is still off.
///
/// The main button asks for everything that is missing, in
/// [kRequiredPermissions] order, and moves on by itself once all of it is
/// granted. That makes granting the path of least resistance.
///
/// ⚠️ Still a primer, not a gate: "Not now" always works. If this blocked on
/// the OS grant, a user who tapped "Don't Allow" would be stuck forever — iOS
/// never re-prompts, so there would be no way forward — and App Review
/// rejects apps that withhold themselves until a permission is granted. What
/// replaces the gate is the Home banner: it stays until the gap is closed.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({this.fixing = false, super.key});

  /// True when opened from the Home banner. It then leaves by popping back to
  /// where the user was, and never touches the first-run flag.
  final bool fixing;

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool _busy = false;

  /// One card: the OS prompt when there is one, the Settings app when there is
  /// not.
  Future<void> _request(AppPermission permission) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _ask(permission);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns whether the answer lives in the Settings app instead.
  Future<bool> _ask(
    AppPermission permission, {
    bool openSettings = true,
  }) async {
    final PermissionService service = ref.read(permissionServiceProvider);
    final PermissionState current = await service.status(permission);
    bool needsSettings = false;
    if (current.needsSettings) {
      // ⚠️ Re-requesting a permanently denied permission silently no-ops, and
      // a button that does nothing reads as a broken app. Send them to Settings.
      needsSettings = true;
      if (openSettings) await service.openSettings();
    } else if (!current.isGranted) {
      // For exact alarms this opens the "Alarms & reminders" page: Android has
      // no dialog for that one.
      await service.request(permission);
    }
    ref.invalidate(permissionStatusProvider(permission));
    return needsSettings;
  }

  Future<void> _allowAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final PermissionService service = ref.read(permissionServiceProvider);
      bool settingsNeeded = false;
      for (final AppPermission permission in kRequiredPermissions) {
        if (!isFixableGap(await service.status(permission))) continue;
        // Settings is opened once, at the end, not once per permission: every
        // trip there leaves the app, and three in a row lose the user.
        if (await _ask(permission, openSettings: false)) settingsNeeded = true;
      }
      if (settingsNeeded) {
        await service.openSettings();
        return;
      }

      // Asked from the service, not from the providers: the providers were
      // just invalidated and may not have re-read yet.
      for (final AppPermission permission in kRequiredPermissions) {
        if (isFixableGap(await service.status(permission))) return;
      }
      if (mounted) _leave();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() {
    if (widget.fixing) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoute.home.path);
      }
      return;
    }
    ref.read(permissionsPrimerSeenProvider.notifier).complete();
    context.go(AppRoute.home.path);
  }

  @override
  Widget build(BuildContext context) {
    PermissionState? stateOf(AppPermission permission) =>
        ref.watch(permissionStatusProvider(permission)).value;

    final PermissionState? exactAlarm = stateOf(AppPermission.exactAlarm);
    final List<AppPermission>? missing = ref
        .watch(missingPermissionsProvider)
        .value;
    final bool allSet = missing != null && missing.isEmpty;

    return Scaffold(
      backgroundColor: TasukeColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: TasukeSpacing.gutter,
              ),
              child: ConstrainedBox(
                // Centred on a roomy phone, scrollable on a small one or at a
                // large text size — three cards at 2× type do not fit a 320pt
                // screen.
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(height: TasukeSpacing.xxl),
                    Text(
                      widget.fixing
                          ? context.l10n.permissionsFixTitle
                          : context.l10n.permissionsTitle,
                      style: TasukeTypography.displayMd,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: TasukeSpacing.md),
                    Text(
                      widget.fixing
                          ? context.l10n.permissionsFixSubtitle
                          : context.l10n.permissionsSubtitle,
                      style: TasukeTypography.bodyMd,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: TasukeSpacing.xxxl),
                    PermissionCard(
                      title: context.l10n.permissionsMicrophoneTitle,
                      subtitle: context.l10n.permissionsMicrophoneSubtitle,
                      icon: const Icon(Icons.mic_none_rounded),
                      state:
                          stateOf(AppPermission.microphone) ??
                          PermissionState.notDetermined,
                      onTap: () => _request(AppPermission.microphone),
                    ),
                    const SizedBox(height: TasukeSpacing.cardGap),
                    PermissionCard(
                      title: context.l10n.permissionsNotificationsTitle,
                      subtitle: context.l10n.permissionsNotificationsSubtitle,
                      icon: const Icon(Icons.notifications_none_rounded),
                      state:
                          stateOf(AppPermission.notifications) ??
                          PermissionState.notDetermined,
                      onTap: () => _request(AppPermission.notifications),
                    ),
                    // Android only: iOS has no such permission and reports
                    // notApplicable, and a card for it would read "Allowed"
                    // for something the user was never asked.
                    if (exactAlarm != null &&
                        exactAlarm !=
                            PermissionState.notApplicable) ...<Widget>[
                      const SizedBox(height: TasukeSpacing.cardGap),
                      PermissionCard(
                        title: context.l10n.permissionsExactAlarmTitle,
                        subtitle: context.l10n.permissionsExactAlarmSubtitle,
                        icon: const Icon(Icons.alarm_rounded),
                        state: exactAlarm,
                        onTap: () => _request(AppPermission.exactAlarm),
                      ),
                    ],
                    const SizedBox(height: TasukeSpacing.xxxl),
                    PrimaryButton(
                      label: allSet
                          ? (widget.fixing
                                ? context.l10n.actionDone
                                : context.l10n.actionContinue)
                          : context.l10n.permissionsAllowAll,
                      onPressed: _busy ? null : (allSet ? _leave : _allowAll),
                    ),
                    if (!allSet) ...<Widget>[
                      const SizedBox(height: TasukeSpacing.sm),
                      TextLinkButton(
                        label: context.l10n.permissionsNotNow,
                        onPressed: _busy ? null : _leave,
                      ),
                    ],
                    const SizedBox(height: TasukeSpacing.lg),
                    Text(
                      context.l10n.permissionsPrivacyNote,
                      style: TasukeTypography.caption,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: TasukeSpacing.xxl),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
