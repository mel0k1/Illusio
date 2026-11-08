import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/illusio_logo.dart';
import '../widgets/server_card.dart';
import 'about_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AppController _controller = AppController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(controller: _controller),
      ),
    );
  }

  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
    );
  }

  Future<void> _openAddDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Новый сервер'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: illusioInput('Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: illusioInput(
                'Адрес',
                hint: 'example.spacestation14.io',
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
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (url.isEmpty) {
                return;
              }
              _controller.addServer(name.isEmpty ? url : name, url);
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

  Future<void> _launchGame() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await _controller.launch();
    if (result['ok'] == true) {
      messenger.showSnackBar(illusioSnackBar('Игра запущена'));
    } else {
      messenger.showSnackBar(
        illusioSnackBar(
          result['error']?.toString() ?? 'не удалось запустить игру',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            IllusioLogo(size: 32),
            SizedBox(width: 12),
            Text('Illusio'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.tune),
            tooltip: 'Настройки',
          ),
          IconButton(
            onPressed: _openAbout,
            icon: const Icon(Icons.info_outline),
            tooltip: 'О приложении',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Добавить сервер'),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_controller.servers.isEmpty) {
      return _buildEmpty(context);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      itemCount: _controller.servers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final server = _controller.servers[index];
        final selected = _controller.selectedServer?.url == server.url;
        return ServerCard(
          server: server,
          selected: selected,
          loading: selected && _controller.loading,
          status: selected ? _controller.statusInfo : null,
          loadError: selected ? _controller.loadError : '',
          onSelect: () => _controller.select(server),
          onLaunch: _launchGame,
          onDelete: () => _controller.removeServer(server),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IllusioLogo(size: 96),
            const SizedBox(height: 24),
            Text('Здесь пока пусто', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Добавьте первый сервер: адрес можно скопировать из любого списка серверов SS14.',
              style: theme.textTheme.bodyMedium?.copyWith(color: mutedFog),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
