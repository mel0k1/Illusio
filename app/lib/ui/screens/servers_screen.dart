import 'package:flutter/material.dart';

import '../../models/hub_server.dart';
import '../../models/server.dart';
import '../../models/server_status.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/connect_flow.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final TextEditingController _search = TextEditingController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    await widget.controller.ready;
    if (!mounted || _initialized) {
      return;
    }
    _initialized = true;
    if (widget.controller.hubServers.isEmpty) {
      widget.controller.loadHub();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openDetails(HubServer server) async {
    final screenContext = context;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ServerDetailsSheet(
        controller: widget.controller,
        server: server,
        onConnect: () => connectFlow(
          screenContext,
          widget.controller,
          GameServer(
            name: server.name.isEmpty ? server.address : server.name,
            url: server.address,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, _search]),
      builder: (context, _) {
        final controller = widget.controller;
        final query = _search.text.trim().toLowerCase();
        final servers = controller.hubServers.where((server) {
          if (query.isNotEmpty &&
              !server.name.toLowerCase().contains(query) &&
              !server.address.toLowerCase().contains(query)) {
            return false;
          }
          if (controller.hideEmpty && server.players <= 0) {
            return false;
          }
          return true;
        }).toList();
        final totalPlayers = controller.hubServers
            .fold<int>(0, (sum, server) => sum + server.players);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Сервера',
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              controller.hubError.isEmpty
                                  ? '${servers.length} серверов · $totalPlayers игроков онлайн'
                                  : 'список не обновлён',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: controller.hubLoading
                            ? null
                            : () => controller.loadHub(),
                        icon: controller.hubLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 22),
                        tooltip: 'Обновить',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    decoration: illusioInput(
                      'Поиск',
                      hint: 'имя или адрес сервера',
                      prefixIcon: const Icon(Icons.search, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildList(context, servers)),
          ],
        );
      },
    );
  }

  Widget _buildList(BuildContext context, List<HubServer> servers) {
    final controller = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    if (controller.hubError.isNotEmpty && controller.hubServers.isEmpty) {
      return _HubError(
        message: controller.hubError,
        onRetry: () => controller.loadHub(),
      );
    }
    if (controller.hubLoading && controller.hubServers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Получаем список серверов',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await controller.loadHub();
      },
      color: scheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        itemCount: servers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final server = servers[index];
          return _ServerTile(
            server: server,
            controller: controller,
            onOpen: () => _openDetails(server),
            onConnect: () => connectFlow(
              context,
              controller,
              GameServer(
                name: server.name.isEmpty ? server.address : server.name,
                url: server.address,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.controller,
    required this.onOpen,
    required this.onConnect,
  });

  final HubServer server;
  final AppController controller;
  final VoidCallback onOpen;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final favorite = controller.isFavorite(server.address);
    final connecting = controller.connecting &&
        controller.selectedServer?.url == server.address;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connecting ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                _Monogram(server: server),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name.isEmpty ? server.address : server.name,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              server.preset.isEmpty
                                  ? server.address
                                  : server.preset,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (server.map.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.map_outlined,
                                size: 13, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                server.map,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _PlayersBadge(server: server),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => controller.toggleFavorite(
                    server.name.isEmpty ? server.address : server.name,
                    server.address,
                  ),
                  icon: Icon(
                    favorite ? Icons.star : Icons.star_outline,
                    size: 20,
                  ),
                  color: favorite ? scheme.primary : scheme.onSurfaceVariant,
                  tooltip:
                      favorite ? 'Убрать из избранного' : 'В избранное',
                ),
                connecting
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FilledButton.tonal(
                        onPressed: onConnect,
                        child: const Text('Играть'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayersBadge extends StatelessWidget {
  const _PlayersBadge({required this.server});

  final HubServer server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final full = server.softMaxPlayers > 0 &&
        server.players >= server.softMaxPlayers;
    final color = server.players <= 0
        ? scheme.onSurfaceVariant
        : full
            ? scheme.tertiary
            : scheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            server.playersLabel,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.server});

  final HubServer server;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final source = server.name.isEmpty ? server.address : server.name;
    final letter =
        source.isEmpty ? '?' : source.replaceAll(RegExp(r'^\W+'), '')[0].toUpperCase();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter.isEmpty ? '?' : letter,
        style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

class _HubError extends StatelessWidget {
  const _HubError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Хаб недоступен',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerDetailsSheet extends StatefulWidget {
  const _ServerDetailsSheet({
    required this.controller,
    required this.server,
    required this.onConnect,
  });

  final AppController controller;
  final HubServer server;
  final VoidCallback onConnect;

  @override
  State<_ServerDetailsSheet> createState() => _ServerDetailsSheetState();
}

class _ServerDetailsSheetState extends State<_ServerDetailsSheet> {
  ServerStatusInfo? _status;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.controller.fetchStatus(widget.server.address);
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      if (result['ok'] == true) {
        _status = ServerStatusInfo.fromMap(result['status']);
      } else {
        _error = result['error']?.toString() ?? 'сервер не отвечает';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final server = widget.server;
    final controller = widget.controller;
    final favorite = controller.isFavorite(server.address);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    server.name.isEmpty ? server.address : server.name,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => controller.toggleFavorite(
                    server.name.isEmpty ? server.address : server.name,
                    server.address,
                  ),
                  icon: Icon(
                    favorite ? Icons.star : Icons.star_outline,
                    size: 22,
                  ),
                  color: favorite ? scheme.primary : scheme.onSurfaceVariant,
                  tooltip:
                      favorite ? 'Убрать из избранного' : 'В избранное',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              server.address,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.person,
                  label: server.playersLabel,
                  tone: _ChipTone.neutral,
                ),
                if (server.runLevelLabel.isNotEmpty)
                  _InfoChip(
                    icon: Icons.timelapse,
                    label: server.runLevelLabel,
                    tone: _ChipTone.neutral,
                  ),
                if (server.preset.isNotEmpty)
                  _InfoChip(icon: Icons.category_outlined, label: server.preset),
                if (server.map.isNotEmpty)
                  _InfoChip(icon: Icons.map_outlined, label: server.map),
                if (server.roundId > 0)
                  _InfoChip(
                    icon: Icons.tag,
                    label: 'Раунд ${server.roundId}',
                  ),
                for (final tag in server.tags)
                  _InfoChip(icon: Icons.label_outline, label: _tagLabel(tag)),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error.isNotEmpty)
              Text(
                'Не удалось получить описание: $_error',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
              )
            else if (_status != null && _status!.cleanMessage.isNotEmpty)
              Text(
                _status!.cleanMessage,
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onConnect();
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Подключиться'),
            ),
          ],
        ),
      ),
    );
  }

  String _tagLabel(String raw) {
    const regions = {
      'eu_e': 'Европа (восток)',
      'eu_w': 'Европа (запад)',
      'as_e': 'Азия (восток)',
      'as_n': 'Азия (север)',
      'as_se': 'Азия (юго-восток)',
      'am_n_e': 'Северная Америка (восток)',
      'am_n_w': 'Северная Америка (запад)',
      'am_n_c': 'Северная Америка (центр)',
      'am_c': 'Центральная Америка',
      'oce': 'Океания',
    };
    if (raw.startsWith('region:')) {
      return regions[raw.substring('region:'.length)] ?? raw;
    }
    if (raw.startsWith('lang:')) {
      return 'Язык: ${raw.substring('lang:'.length)}';
    }
    if (raw.startsWith('rp:')) {
      return 'RP: ${raw.substring('rp:'.length)}';
    }
    if (raw.startsWith('higher_perf:') ||
        raw.startsWith('luna') ||
        raw == 'no_tag_infer') {
      return raw;
    }
    return raw;
  }
}

enum _ChipTone { neutral, plain }

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.tone = _ChipTone.plain,
  });

  final IconData icon;
  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone == _ChipTone.neutral
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: tone == _ChipTone.neutral
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tone == _ChipTone.neutral
                      ? scheme.onSecondaryContainer
                      : scheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}
