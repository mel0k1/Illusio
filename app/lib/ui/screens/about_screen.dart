import 'package:flutter/material.dart';

import '../../version.dart';
import '../theme.dart';
import '../widgets/illusio_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.version = appVersion});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                const IllusioLogo(size: 120),
                const SizedBox(height: 24),
                Text(
                  'Illusio',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Chip(
                  label: Text('v$version'),
                  avatar: const Icon(Icons.tag, size: 16),
                ),
                const SizedBox(height: 20),
                Text(
                  'Лаунчер для Space Station 14. Ядро на Rust получает статус серверов, скачивает и обновляет клиент, хранит настройки и запускает игру. Интерфейс собран на Flutter.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),
                const _LinkRow(icon: Icons.code, label: repoUrl),
                const SizedBox(height: 8),
                const _LinkRow(icon: Icons.public, label: 'spacestation14.io'),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'Illusio',
                      applicationVersion: version,
                    );
                  },
                  child: const Text('Лицензии и компоненты'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Код распространяется по лицензии MIT.',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedFog),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: mutedFog),
        const SizedBox(width: 8),
        SelectableText(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(color: fogWhite),
        ),
      ],
    );
  }
}
