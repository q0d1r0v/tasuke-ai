import 'dart:async';

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
import 'package:tasuke_ai/core/storage/prefs.dart';

/// The permissions primer.
///
/// ⚠️ A primer, not a gate. Continue is always enabled. If this blocked on the
/// OS grant, a user who tapped "Don't Allow" would be stuck forever: iOS never
/// re-prompts, so the button could never become enabled and the app would have
/// no way forward. The Recording screen handles a still-denied microphone, at
/// the moment the user actually has a reason to grant it.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  PermissionState _mic = PermissionState.notDetermined;
  PermissionState _notifications = PermissionState.notDetermined;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final PermissionService service = ref.read(permissionServiceProvider);
    final PermissionState mic = await service.status(AppPermission.microphone);
    final PermissionState notify = await service.status(
      AppPermission.notifications,
    );
    if (!mounted) return;
    setState(() {
      _mic = mic;
      _notifications = notify;
    });
  }

  Future<void> _request(AppPermission permission) async {
    if (_busy) return;
    setState(() => _busy = true);
    final PermissionService service = ref.read(permissionServiceProvider);

    PermissionState next;
    final PermissionState current = await service.status(permission);
    if (current.needsSettings) {
      // ⚠️ Re-requesting a permanently denied permission silently no-ops, and
      // a button that does nothing reads as a broken app. Send them to Settings.
      await service.openSettings();
      next = current;
    } else {
      next = await service.request(permission);
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (permission == AppPermission.microphone) {
        _mic = next;
      } else {
        _notifications = next;
      }
    });
  }

  void _continue() {
    ref.read(permissionsPrimerSeenProvider.notifier).complete();
    context.go(AppRoute.home.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasukeColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TasukeSpacing.gutter),
          child: Column(
            children: <Widget>[
              const Spacer(),
              Text(
                context.l10n.permissionsTitle,
                style: TasukeTypography.displayMd,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TasukeSpacing.md),
              Text(
                context.l10n.permissionsSubtitle,
                style: TasukeTypography.bodyMd,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: TasukeSpacing.xxxl),
              PermissionCard(
                title: context.l10n.permissionsMicrophoneTitle,
                subtitle: context.l10n.permissionsMicrophoneSubtitle,
                icon: const Icon(Icons.mic_none_rounded),
                state: _mic,
                onTap: () => _request(AppPermission.microphone),
              ),
              const SizedBox(height: TasukeSpacing.cardGap),
              PermissionCard(
                title: context.l10n.permissionsNotificationsTitle,
                subtitle: context.l10n.permissionsNotificationsSubtitle,
                icon: const Icon(Icons.notifications_none_rounded),
                state: _notifications,
                onTap: () => _request(AppPermission.notifications),
              ),
              const Spacer(flex: 2),
              PrimaryButton(
                label: context.l10n.actionContinue,
                onPressed: _busy ? null : _continue,
              ),
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
      ),
    );
  }
}
