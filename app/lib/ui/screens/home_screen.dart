import 'package:flutter/material.dart';

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
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить сервер'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              autofocus: true,
              decoration: illusioInput(
                'Адрес сервера',
                hint: 'ss14://example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: illusioInput(
                'Название',
                hint: 'как отобразить в избранном',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
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
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    nameController.dispose();
    urlController.dispose();
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
        final favorites = widget.controller.favorites;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
          children: [
            _PageTitle(
              title: 'Главная',
              subtitle: 'избранные сервера и прямое подключение',
            ),
            const SizedBox(height: 20),
            _DirectConnectCard(
              controller: _direct,
              onConnect: _connectDirect,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Text('Избранное', style: Theme.of(context).textTheme.titleMedium),
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
                  label: const Text('Добавить'),
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
                ),
                const SizedBox(height: 10),
              ],
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Прямое подключение',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Вставьте адрес сервера — клиент скачается сам при первом подключении.',
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
                      'Адрес',
                      hint: 'ss14://play.example.com',
                      prefixIcon: const Icon(Icons.link, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : onConnect,
                  child: const Text('Играть'),
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
          Text('Здесь пока пусто', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Добавьте первый сервер или найдите его на вкладке «Сервера».',
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
  });

  final GameServer server;
  final AppController controller;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connecting =
        controller.connecting && controller.selectedServer?.url == server.url;
    return Container(
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
                onPressed: () => controller.removeFavorite(server.url),
                icon: const Icon(Icons.star, size: 20),
                color: scheme.primary,
                tooltip: 'Убрать из избранного',
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
          if (connecting) DownloadInline(state: controller.downloadState),
        ],
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
