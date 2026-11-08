import 'package:flutter/material.dart';

import '../../models/server.dart';
import '../../models/server_info.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.controller,
    required this.onConnect,
  });

  final GameServer server;
  final AppController controller;
  final VoidCallback onConnect;

  bool get _isCurrent => controller.selectedServer?.url == server.url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _isCurrent;
    final connecting = selected && controller.connecting;
    final radius = BorderRadius.circular(28);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? hullRaised : hullSurface,
        borderRadius: radius,
        border: Border.all(color: selected ? signalAmber : edgeColor),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: controller.connecting
              ? null
              : () => controller.select(server),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Monogram(server: server),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            server.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            server.url,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: mutedFog),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TrailingStatus(
                      selected: selected,
                      connecting: connecting,
                      controller: controller,
                    ),
                    IconButton(
                      onPressed: controller.connecting
                          ? null
                          : () => controller.removeServer(server),
                      icon: const Icon(Icons.close, size: 18),
                      color: mutedFog,
                      tooltip: 'Убрать из списка',
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: selected
                      ? _StatusBody(
                          controller: controller,
                          onConnect: onConnect,
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.server});

  final GameServer server;

  @override
  Widget build(BuildContext context) {
    final letter = server.name.isEmpty ? '?' : server.name[0].toUpperCase();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: signalAmber.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: signalAmber.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: signalAmber,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _TrailingStatus extends StatelessWidget {
  const _TrailingStatus({
    required this.selected,
    required this.connecting,
    required this.controller,
  });

  final bool selected;
  final bool connecting;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (connecting) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (!selected) {
      return const Icon(Icons.chevron_right, size: 20, color: mutedFog);
    }
    final info = controller.statusInfo;
    if (info != null) {
      return Text(
        '${info.playerCount} онлайн',
        style: theme.textTheme.bodySmall?.copyWith(color: calmGreen),
      );
    }
    if (controller.loadError.isNotEmpty) {
      return const Icon(Icons.error_outline, size: 20, color: errorClay);
    }
    return const SizedBox(width: 16);
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({
    required this.controller,
    required this.onConnect,
  });

  final AppController controller;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connecting = controller.connecting;
    if (connecting) {
      return _DownloadBody(state: controller.downloadState);
    }
    final info = controller.statusInfo;
    if (info == null) {
      if (controller.loadError.isEmpty) {
        return const SizedBox(height: 4);
      }
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          'Сервер не ответил: ${controller.loadError}. Проверьте адрес и повторите попытку.',
          style: theme.textTheme.bodyMedium?.copyWith(color: errorClay),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors, size: 16, color: calmGreen),
              const SizedBox(width: 8),
              Text(info.playersLabel, style: theme.textTheme.bodyMedium),
            ],
          ),
          if (info.cleanMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              info.cleanMessage,
              style: theme.textTheme.bodySmall?.copyWith(color: mutedFog),
            ),
          ],
          if (info.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in info.tags) Chip(label: Text(tag)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Играть'),
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
    final failed = state.isError;
    final color = failed ? errorClay : mutedFog;
    final showBar = state.phase == 'download' || state.phase == 'extract';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!failed && !state.isDone)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  failed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 18,
                  color: failed ? errorClay : calmGreen,
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
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedFog),
                ),
            ],
          ),
          if (showBar) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 6,
                backgroundColor: edgeColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
