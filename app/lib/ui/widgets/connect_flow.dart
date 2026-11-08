import 'dart:io';

import 'package:flutter/material.dart';

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
  if (policy != null && !controller.privacyAccepted(policy)) {
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
      title: server.name.isEmpty ? 'Подключение' : server.name,
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
      title: 'Запуск реплея',
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
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Политика конфиденциальности'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Сервер «$serverName» требует принять свою политику конфиденциальности перед подключением.',
          ),
          const SizedBox(height: 12),
          Text(
            'Версия: ${policy.version}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отклонить'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Принять'),
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
    final result = widget.isBundle
        ? await widget.controller.connectBundle(widget.bundlePath)
        : await widget.controller.connect(widget.server);
    if (!_visible || !mounted) {
      return;
    }
    navigator.pop();
    if (result['ok'] == true) {
      messenger.showSnackBar(illusioSnackBar('Клиент запущен'));
    } else {
      messenger.showSnackBar(
        illusioSnackBar(
            result['error']?.toString() ?? 'не удалось подключиться'),
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
            child: const Text('Скрыть'),
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
              Icon(
                failed ? Icons.error_outline : Icons.check_circle_outline,
                size: 20,
                color: failed ? scheme.error : scheme.secondary,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.phaseLabel,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
            if (showBar && state.total > 0)
              Text(
                '${state.sizeLabel} / ${state.totalLabel}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (showBar) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 8,
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
                  state.phaseLabel,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
