import 'package:flutter/material.dart';

import '../../models/hub_server.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class ModsScreen extends StatefulWidget {
  const ModsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ModsScreen> createState() => _ModsScreenState();
}

class _ModsScreenState extends State<ModsScreen> {
  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    await widget.controller.ready;
    if (!mounted) {
      return;
    }
    await widget.controller.loadMods();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final mods = controller.mods;
        final enabled = controller.modsEnabled;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Моды', style: theme.textTheme.headlineLarge),
                const SizedBox(height: 4),
                Text(
                  mods.isEmpty
                      ? 'ZIP-моды из каталога модов'
                      : '${mods.length} файлов · ${enabled.length} включено',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
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
                      Icon(Icons.extension, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text('Как это работает',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Положите ZIP-архивы в каталог модов и включите нужные. Они монтируются в клиент как оверлей при запуске. Отключение вернёт оригинальные ресурсы.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    controller.modsPath.isEmpty ? '…' : controller.modsPath,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: controller.modsPath.isEmpty
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await controller.openModsDir();
                                messenger.showSnackBar(
                                  illusioSnackBar(
                                    'Каталог открыт — положите ZIP-архивы туда',
                                  ),
                                );
                              },
                        icon: const Icon(Icons.folder_open, size: 20),
                        label: const Text('Открыть папку'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => controller.loadMods(),
                        icon: const Icon(Icons.refresh, size: 20),
                        label: const Text('Обновить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (mods.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(Icons.category_outlined,
                        size: 44, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text('Модов пока нет', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Скачайте ZIP-мод, откройте папку модов и положите файл туда, затем нажмите «Обновить».',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              for (final mod in mods) ...[
                _ModTile(
                  mod: mod,
                  enabled: enabled.contains(mod.fileName),
                  controller: controller,
                ),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }
}

class _ModTile extends StatelessWidget {
  const _ModTile({
    required this.mod,
    required this.enabled,
    required this.controller,
  });

  final ModEntry mod;
  final bool enabled;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: enabled
            ? scheme.secondaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled ? scheme.secondary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: enabled
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: enabled
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mod.fileName,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${mod.sizeLabel} · ${enabled ? 'включён' : 'выключен'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (_) => controller.toggleMod(mod.fileName),
          ),
        ],
      ),
    );
  }
}
