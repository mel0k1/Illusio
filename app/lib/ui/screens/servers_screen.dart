import 'package:flutter/material.dart';

import '../widgets/press_scale.dart';

import '../../l10n/strings.dart';
import '../../models/hub_server.dart';
import '../../models/server.dart';
import '../../models/server_info.dart';
import '../../models/server_status.dart';
import '../../models/tags.dart';
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
        final s = S.of(context);
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
          if (controller.hideFull && server.full) {
            return false;
          }
          final tags = ServerTagInfo.infer(server);
          final min = controller.filterMinPlayers;
          if (min > 0 && server.players < min) {
            return false;
          }
          final max = controller.filterMaxPlayers;
          if (max > 0 && server.players > max) {
            return false;
          }
          final active = controller.filterTags;
          if (active.isEmpty) {
            return true;
          }
          final categories = <String, List<String>>{};
          for (final filter in active) {
            final category = ServerTagInfo.categoryOf(filter);
            if (category.isEmpty) {
              continue;
            }
            categories.putIfAbsent(category, () => []).add(filter);
          }
          for (final filters in categories.values) {
            final matched = filters.any(tags.contains);
            if (!matched) {
              return false;
            }
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
                              s.serversTitle,
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              controller.hubError.isEmpty
                                  ? s.serversCount(
                                      servers.length,
                                      controller.hubServers.length,
                                      totalPlayers)
                                  : s.listNotUpdated,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _openFilters(context),
                        icon: Badge.count(
                          count: controller.filterTags.length,
                          isLabelVisible: controller.filterTags.isNotEmpty ||
                              controller.hideFull ||
                              controller.filterMinPlayers > 0 ||
                              controller.filterMaxPlayers > 0,
                          child: const Icon(Icons.tune, size: 22),
                        ),
                        tooltip: s.filters,
                      ),
                      const SizedBox(width: 8),
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
                        tooltip: s.refresh,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    decoration: illusioInput(
                      s.search,
                      hint: s.searchHint,
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

  Future<void> _openFilters(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _FilterSheet(controller: widget.controller),
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
              S.of(context).loadingList,
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
    return PressScale(
      child: Container(
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
                  _PingDot(ping: controller.pings[server.address]),
                  const SizedBox(width: 4),
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
                    tooltip: favorite
                        ? S.of(context).removeFavorite
                        : S.of(context).addFavorite,
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
                          child: Text(S.of(context).play),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PingDot extends StatelessWidget {
  const _PingDot({required this.ping});

  final ServerPing? ping;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = ping;
    const colors = [
      Color(0xFF43A047),
      Color(0xFFFB8C00),
      Color(0xFFE53935),
    ];
    final color = value == null
        ? scheme.outlineVariant
        : colors[value.quality.clamp(0, 2)];
    return Tooltip(
      message: value == null
          ? S.of(context).pingUnmeasured
          : S.of(context).pingLabel(value.label(S.of(context))),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
    final full =
        server.softMaxPlayers > 0 && server.players >= server.softMaxPlayers;
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
    final letter = source.isEmpty
        ? '?'
        : source.replaceAll(RegExp(r'^\W+'), '')[0].toUpperCase();
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
              S.of(context).hubUnavailable,
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
              label: Text(S.of(context).retry),
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
  ServerFullInfo? _info;
  String _error = '';
  String _infoError = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadInfo();
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
        _error =
            result['error']?.toString() ?? S.of(context).serverNotResponding;
      }
    });
  }

  Future<void> _loadInfo() async {
    final result = await widget.controller.fetchInfo(widget.server.address);
    if (!mounted) {
      return;
    }
    setState(() {
      if (result['ok'] == true) {
        _info = ServerFullInfo.fromMap(result['info']);
      } else {
        _infoError = result['error']?.toString() ?? '';
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
                  tooltip: favorite
                      ? S.of(context).removeFavorite
                      : S.of(context).addFavorite,
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
                if (server.runLevelLabel(S.of(context)).isNotEmpty)
                  _InfoChip(
                    icon: Icons.timelapse,
                    label: server.runLevelLabel(S.of(context)),
                    tone: _ChipTone.neutral,
                  ),
                if (server.preset.isNotEmpty)
                  _InfoChip(
                      icon: Icons.category_outlined, label: server.preset),
                if (server.map.isNotEmpty)
                  _InfoChip(icon: Icons.map_outlined, label: server.map),
                if (server.roundId > 0)
                  _InfoChip(
                    icon: Icons.tag,
                    label: '${S.of(context).round} ${server.roundId}',
                  ),
                for (final tag in server.tags)
                  _InfoChip(icon: Icons.label_outline, label: _tagLabel(tag)),
              ],
            ),
            const SizedBox(height: 20),
            if (_info != null && _info!.desc.isNotEmpty) ...[
              Text(
                _info!.desc,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
            ],
            if (_info != null && _info!.links.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final link in _info!.links)
                    ActionChip(
                      avatar: Icon(
                        _linkIcon(link.icon),
                        size: 16,
                        color: scheme.primary,
                      ),
                      label: Text(
                        link.name.isEmpty ? _linkLabel(link.url) : link.name,
                      ),
                      onPressed: () => controller.openUrl(link.url),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (_infoError.isNotEmpty && _info == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  S.of(context).infoFailed(_infoError),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error.isNotEmpty)
              Text(
                S.of(context).detailsFailed(_error),
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
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
              label: Text(S.of(context).connect),
            ),
          ],
        ),
      ),
    );
  }

  IconData _linkIcon(String icon) {
    switch (icon.toLowerCase()) {
      case 'discord':
        return Icons.forum_outlined;
      case 'wiki':
        return Icons.menu_book_outlined;
      case 'github':
        return Icons.code;
      case 'web':
        return Icons.language;
      case 'telegram':
        return Icons.send_outlined;
      case 'forum':
        return Icons.chat_bubble_outline;
      default:
        return Icons.link;
    }
  }

  String _linkLabel(String url) {
    return url.replaceFirst(RegExp(r'^https?://'), '').split('/').first;
  }

  String _tagLabel(String raw) {
    const regionKeys = {
      'eu_e': 'eu_east',
      'eu_w': 'eu_west',
      'as_e': 'asia_east',
      'as_n': 'asia_north',
      'as_se': 'asia_se',
      'am_n_e': 'na_east',
      'am_n_w': 'na_west',
      'am_n_c': 'na_central',
      'am_c': 'sa_central',
      'oce': 'oceania',
    };
    final s = S.of(context);
    if (raw.startsWith('region:')) {
      final value = raw.substring('region:'.length);
      return '${s.regionPrefix}${s.regionName(regionKeys[value] ?? value)}';
    }
    if (raw.startsWith('lang:')) {
      return '${s.langPrefix}${raw.substring('lang:'.length)}';
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

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.controller});

  final AppController controller;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final TextEditingController _min;
  late final TextEditingController _max;

  @override
  void initState() {
    super.initState();
    _min = TextEditingController(
      text: widget.controller.filterMinPlayers > 0
          ? '${widget.controller.filterMinPlayers}'
          : '',
    );
    _max = TextEditingController(
      text: widget.controller.filterMaxPlayers > 0
          ? '${widget.controller.filterMaxPlayers}'
          : '',
    );
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    final controller = widget.controller;
    final min = int.tryParse(_min.text.trim()) ?? 0;
    final max = int.tryParse(_max.text.trim()) ?? 0;
    controller.setFilterPlayers(min.clamp(0, 9999), max.clamp(0, 9999));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = S.of(context);
    final controller = widget.controller;
    final available = ServerTagInfo.availableFilters(controller.hubServers);
    final selected = List<String>.from(controller.filterTags);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.of(context).filtersTitle,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                s.filtersHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in available)
                    FilterChip(
                      selected: selected.contains(filter),
                      label: Text(
                          ServerTagInfo.filterLabel(filter, S.of(context))),
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            selected.add(filter);
                          } else {
                            selected.remove(filter);
                          }
                        });
                        controller.setFilterTags(selected);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      decoration:
                          illusioInput(S.of(context).playersFrom, hint: '0'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      decoration:
                          illusioInput(S.of(context).playersTo, hint: '∞'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      S.of(context).hideFullServers,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Switch(
                    value: controller.hideFull,
                    onChanged: controller.setHideFull,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        controller.setFilterTags([]);
                        controller.setFilterPlayers(0, 0);
                        controller.setHideFull(false);
                        Navigator.of(context).pop();
                      },
                      child: Text(S.of(context).reset),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: Text(s.done),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
