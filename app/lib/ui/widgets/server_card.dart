import 'package:flutter/material.dart';

import '../../models/server.dart';
import '../../models/server_status.dart';
import '../theme.dart';

class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.selected,
    required this.loading,
    required this.status,
    required this.loadError,
    required this.onSelect,
    required this.onLaunch,
    required this.onDelete,
  });

  final GameServer server;
  final bool selected;
  final bool loading;
  final ServerStatusInfo? status;
  final String loadError;
  final VoidCallback onSelect;
  final VoidCallback onLaunch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          onTap: onSelect,
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
                      loading: loading,
                      status: status,
                      loadError: loadError,
                    ),
                    IconButton(
                      onPressed: onDelete,
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
                          loading: loading,
                          status: status,
                          loadError: loadError,
                          onLaunch: onLaunch,
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
    required this.loading,
    required this.status,
    required this.loadError,
  });

  final bool selected;
  final bool loading;
  final ServerStatusInfo? status;
  final String loadError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (!selected) {
      return const Icon(Icons.chevron_right, size: 20, color: mutedFog);
    }
    final info = status;
    if (info != null) {
      return Text(
        '${info.playerCount} онлайн',
        style: theme.textTheme.bodySmall?.copyWith(color: calmGreen),
      );
    }
    if (loadError.isNotEmpty) {
      return const Icon(Icons.error_outline, size: 20, color: errorClay);
    }
    return const SizedBox(width: 16);
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({
    required this.loading,
    required this.status,
    required this.loadError,
    required this.onLaunch,
  });

  final bool loading;
  final ServerStatusInfo? status;
  final String loadError;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Запрашиваем статус',
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: mutedFog),
            ),
          ],
        ),
      );
    }
    final info = status;
    if (info == null) {
      if (loadError.isEmpty) {
        return const SizedBox(height: 4);
      }
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          'Сервер не ответил: $loadError. Проверьте адрес и повторите попытку.',
          style:
              theme.textTheme.bodyMedium?.copyWith(color: errorClay),
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
            onPressed: onLaunch,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Играть'),
          ),
        ],
      ),
    );
  }
}
