import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../widgets/press_scale.dart';

import '../../l10n/strings.dart';
import '../../models/server.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/connect_flow.dart';
import '../widgets/illusio_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _direct = TextEditingController();

  @override
  void dispose() {
    _direct.dispose();
    super.dispose();
  }

  Future<void> _openAddDialog() async {
    final s = S.of(context);
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.addServer),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              autofocus: true,
              decoration: illusioInput(
                s.serverAddress,
                hint: 'ss14://example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: illusioInput(
                s.serverName,
                hint: s.serverNameHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isEmpty) {
                return;
              }
              widget.controller.addFavorite(
                nameController.text.trim(),
                url,
              );
              Navigator.of(dialogContext).pop();
            },
            child: Text(s.add),
          ),
        ],
      ),
    );
    nameController.dispose();
    urlController.dispose();
  }

  Future<void> _openEditDialog(GameServer server) async {
    final s = S.of(context);
    final nameController = TextEditingController(text: server.name);
    final urlController = TextEditingController(text: server.url);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.editServer),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: illusioInput(s.serverName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: illusioInput(s.serverAddress),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              widget.controller.editFavorite(
                server.url,
                nameController.text.trim(),
                urlController.text.trim(),
              );
              Navigator.of(dialogContext).pop();
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
    nameController.dispose();
    urlController.dispose();
  }

  Future<void> _pickBundle() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final type = XTypeGroup(label: s.replayTypeLabel, extensions: ['zip']);
    final files = await openFiles(acceptedTypeGroups: [type]);
    if (files.isEmpty) {
      return;
    }
    final path = files.first.path;
    if (!path.toLowerCase().endsWith('.zip')) {
      messenger.showSnackBar(
        illusioSnackBar(s.needZipBundle),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    await bundleFlow(context, widget.controller, path);
  }

  void _connectDirect() {
    final url = _direct.text.trim();
    if (url.isEmpty) {
      return;
    }
    connectFlow(context, widget.controller, GameServer(name: url, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final s = S.of(context);
        final favorites = widget.controller.sortedFavorites;
        return ListView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, widget.controller.listBottomPad),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PageTitle(
                      title: s.homeTitle,
                      subtitle: s.homeSubtitle,
                    ),
                    const SizedBox(height: 20),
                    _DirectConnectCard(
                      controller: _direct,
                      onConnect: _connectDirect,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _pickBundle,
                        icon: const Icon(Icons.movie_outlined, size: 20),
                        label: Text(s.launchReplay),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text(s.favorites,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(width: 8),
                        Text(
                          '${favorites.length}',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: _openAddDialog,
                          icon: const Icon(Icons.add, size: 20),
                          label: Text(s.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (favorites.isEmpty)
                      _EmptyFavorites(onAdd: _openAddDialog)
                    else
                      for (final server in favorites) ...[
                        _FavoriteTile(
                          server: server,
                          controller: widget.controller,
                          onConnect: () =>
                              connectFlow(context, widget.controller, server),
                          onEdit: () => _openEditDialog(server),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _DirectConnectCard extends StatelessWidget {
  const _DirectConnectCard({required this.controller, required this.onConnect});

  final TextEditingController controller;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings_ethernet_rounded,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                s.directTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.directHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onSubmitted: (_) => onConnect(),
                    decoration: illusioInput(
                      s.address,
                      hint: 'ss14://play.example.com',
                      prefixIcon: const Icon(Icons.link, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: value.text.trim().isEmpty ? null : onConnect,
                  icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                  label: Text(S.of(context).play),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          const IllusioLogo(size: 72),
          const SizedBox(height: 16),
          Text(S.of(context).emptyFavoritesTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            S.of(context).emptyFavoritesHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.server,
    required this.controller,
    required this.onConnect,
    required this.onEdit,
  });

  final GameServer server;
  final AppController controller;
  final VoidCallback onConnect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connecting =
        controller.connecting && controller.selectedServer?.url == server.url;
    return PressScale(
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
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
                      Text(
                        server.url,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => controller.raiseFavorite(server.url),
                  icon: const Icon(Icons.vertical_align_top, size: 20),
                  color: scheme.onSurfaceVariant,
                  tooltip: S.of(context).raiseTop,
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: scheme.onSurfaceVariant,
                  tooltip: S.of(context).edit,
                ),
                IconButton(
                  onPressed: () => controller.removeFavorite(server.url),
                  icon: const Icon(Icons.star, size: 20),
                  color: scheme.primary,
                  tooltip: S.of(context).removeFavorite,
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
            if (connecting) DownloadInline(state: controller.downloadState),
          ],
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
    final scheme = Theme.of(context).colorScheme;
    final letter = server.name.isEmpty ? '?' : server.name[0].toUpperCase();
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
      ),
    );
  }
}
