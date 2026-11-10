import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/server.dart';
import '../../models/server_info.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

Future<void> connectFlow(
  BuildContext context,
  AppController controller,
  GameServer server,
) async {
  if (controller.connecting) {
    return;
  }
  final info = await controller.fetchInfo(server.url);
  ServerFullInfo? full;
  if (info['ok'] == true) {
    full = ServerFullInfo.fromMap(info['info']);
  }
  final policy = full?.privacyPolicy;
  if (!controller.skipPrivacy &&
      policy != null &&
      !controller.privacyAccepted(policy)) {
    if (!context.mounted) {
      return;
    }
    final accepted =
        await _askPrivacy(context, controller, server.name, policy);
    if (!accepted) {
      return;
    }
  }
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ConnectDialog(
      controller: controller,
      server: server,
      title: server.name.isEmpty ? S.of(context).connecting : server.name,
    ),
  );
}

Future<void> bundleFlow(
  BuildContext context,
  AppController controller,
  String zipPath,
) async {
  if (controller.connecting) {
    return;
  }
  final fileName = zipPath.split(Platform.pathSeparator).last;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ConnectDialog(
      controller: controller,
      server: GameServer(name: fileName, url: ''),
      title: S.of(context).launchingReplay,
      isBundle: true,
      bundlePath: zipPath,
    ),
  );
}

Future<bool> _askPrivacy(
  BuildContext context,
  AppController controller,
  String serverName,
  ServerPrivacyInfo policy,
) async {
  final s = S.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.privacyTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.privacyBody(serverName)),
          const SizedBox(height: 12),
          Text(
            s.privacyVersion(policy.version),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(s.reject),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(s.accept),
        ),
      ],
    ),
  );
  if (result != true) {
    return false;
  }
  controller.acceptPrivacy(policy);
  return true;
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({
    required this.controller,
    required this.server,
    required this.title,
    this.isBundle = false,
    this.bundlePath = '',
  });

  final AppController controller;
  final GameServer server;
  final String title;
  final bool isBundle;
  final String bundlePath;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final s = S.of(context);
    final result = widget.isBundle
        ? await widget.controller.connectBundle(widget.bundlePath)
        : await widget.controller.connect(widget.server);
    if (!_visible || !mounted) {
      return;
    }
    navigator.pop();
    if (result['ok'] == true) {
      messenger.showSnackBar(illusioSnackBar(s.clientStarted));
    } else {
      messenger.showSnackBar(
        illusioSnackBar(result['error']?.toString() ?? s.connectFailed),
      );
    }
  }

  void _hide() {
    _visible = false;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => AlertDialog(
        title: Text(widget.title),
        content: _DownloadBody(state: widget.controller.downloadState),
        actions: [
          TextButton(
            onPressed: _hide,
            child: Text(S.of(context).hide),
          ),
        ],
      ),
    );
  }
}

class _DownloadBody extends StatelessWidget {
  const _DownloadBody({required this.state});

  final DownloadStateInfo state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = state.isError;
    final done = state.isDone;
    final color = failed ? scheme.error : scheme.onSurfaceVariant;
    final showBar = state.phase == 'engine' ||
        state.phase == 'download' ||
        state.phase == 'extract';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (!failed && !done)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            else
              AnimatedSwitcher(
                duration: spatialFast,
                switchInCurve: expressCurve,
                switchOutCurve: exitCurve,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  key: ValueKey(failed),
                  failed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 20,
                  color: failed ? scheme.error : scheme.secondary,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.phaseLabel(S.of(context)),
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
            if (showBar && state.total > 0)
              Text(
                '${state.sizeLabel(S.of(context))} / ${state.totalLabel(S.of(context))}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (showBar) ...[
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(
              end: (state.progress ?? 0).clamp(0.0, 1.0).toDouble(),
            ),
            duration: spatialDefault,
            curve: expressCurve,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ],
    );
  }
}

class DownloadInline extends StatelessWidget {
  const DownloadInline({super.key, required this.state});

  final DownloadStateInfo state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showBar = state.phase == 'engine' ||
        state.phase == 'download' ||
        state.phase == 'extract';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.phaseLabel(S.of(context)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (showBar) ...[
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(
                end: (state.progress ?? 0).clamp(0.0, 1.0).toDouble(),
              ),
              duration: spatialDefault,
              curve: expressCurve,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
