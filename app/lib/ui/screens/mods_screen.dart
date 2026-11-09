import 'package:flutter/material.dart';

import '../widgets/press_scale.dart';

import '../../l10n/strings.dart';
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
        final s = S.of(context);
        final zips = controller.mods.where((mod) => !mod.isDll).toList();
        final patchDlls = controller.mods
            .where((mod) => mod.isDll && !mod.isGameMod)
            .toList();
        final gameDlls = controller.mods.where((mod) => mod.isGameMod).toList();
        final packs = controller.resPacks;
        final enabled = controller.modsEnabled.length +
            controller.dllModsEnabled.length +
            controller.subverterEnabled.length +
            controller.resPacksEnabled.length;
        final empty = controller.mods.isEmpty && packs.isEmpty;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.modsTitle, style: theme.textTheme.headlineLarge),
                const SizedBox(height: 4),
                Text(
                  empty
                      ? s.modsSubtitle
                      : s.modsCountLine(
                          controller.mods.length + packs.length,
                          enabled,
                        ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _HowItWorksCard(controller: controller),
            const SizedBox(height: 20),
            if (empty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.category_outlined,
                      size: 44,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(s.modsEmptyTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      s.modsEmptyHint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else ...[
              if (zips.isNotEmpty) ...[
                _KindLabel(s.zipSection),
                const SizedBox(height: 10),
                for (final mod in zips) ...[
                  _ModTile(
                    mod: mod,
                    title: mod.fileName,
                    subtitle:
                        '${mod.sizeLabel(s)} · ${controller.modsEnabled.contains(mod.fileName) ? s.modEnabled : s.modDisabled}',
                    enabled: controller.modsEnabled.contains(mod.fileName),
                    controller: controller,
                    onToggle: () => controller.toggleMod(mod.fileName),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (patchDlls.isNotEmpty) ...[
                _KindLabel(s.dllSection),
                const SizedBox(height: 10),
                for (final mod in patchDlls) ...[
                  _ModTile(
                    mod: mod,
                    title: mod.name.isEmpty ? mod.fileName : mod.name,
                    subtitle: _dllSubtitle(
                      s,
                      mod,
                      controller.dllModsEnabled.contains(mod.path),
                    ),
                    enabled: controller.dllModsEnabled.contains(mod.path),
                    controller: controller,
                    onToggle: () => controller.toggleDllMod(mod.path),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (gameDlls.isNotEmpty) ...[
                _KindLabel(s.subverterSection),
                const SizedBox(height: 10),
                for (final mod in gameDlls) ...[
                  _ModTile(
                    mod: mod,
                    title: mod.name.isEmpty ? mod.fileName : mod.name,
                    subtitle: _gameSubtitle(
                      s,
                      mod,
                      controller.subverterEnabled.contains(mod.path),
                    ),
                    enabled: controller.subverterEnabled.contains(mod.path),
                    controller: controller,
                    onToggle: () => controller.toggleSubverter(mod.path),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
            if (packs.isNotEmpty) ...[
              _KindLabel(s.resPacksSection),
              const SizedBox(height: 10),
              for (final pack in packs) ...[
                _ResPackTile(
                  pack: pack,
                  enabled: controller.resPacksEnabled.contains(pack.dirName),
                  onToggle: () => controller.toggleResPack(pack.dirName),
                ),
                const SizedBox(height: 10),
              ],
            ],
            _DumperCard(controller: controller),
          ],
        );
      },
    );
  }

  String _dllSubtitle(S s, ModEntry mod, bool enabled) {
    final parts = <String?>[];
    if (mod.preload) {
      parts.add(s.preloadBadge);
    }
    if (mod.version.isNotEmpty) {
      parts.add('v${mod.version}');
    }
    parts.add(mod.sizeLabel(s));
    parts.add(mod.name.isEmpty ? s.dllNoMarker : null);
    parts.add(enabled ? s.modEnabled : s.modDisabled);
    return parts
        .where((value) => value != null && value.isNotEmpty)
        .join(' · ');
  }

  String _gameSubtitle(S s, ModEntry mod, bool enabled) {
    final parts = <String?>[
      s.gameModLabel,
      if (mod.version.isNotEmpty) 'v${mod.version}',
      mod.sizeLabel(s),
      enabled ? s.modEnabled : s.modDisabled,
    ];
    return parts
        .where((value) => value != null && value.isNotEmpty)
        .join(' · ');
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
              Icon(Icons.extension, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(s.howItWorks, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.zipHowText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.dllHowText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.subverterHowText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.respackHowText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.dumperHowText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            controller.modsPath.isEmpty ? '…' : controller.modsPath,
            style: theme.textTheme.bodySmall,
          ),
          if (controller.resPacksPath.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              controller.resPacksPath,
              style: theme.textTheme.bodySmall,
            ),
          ],
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
                        messenger.showSnackBar(illusioSnackBar(s.folderOpened));
                      },
                icon: const Icon(Icons.folder_open, size: 20),
                label: Text(s.openFolder),
              ),
              OutlinedButton.icon(
                onPressed: controller.resPacksPath.isEmpty
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await controller.openResPacksDir();
                        messenger.showSnackBar(illusioSnackBar(s.folderOpened));
                      },
                icon: const Icon(Icons.palette_outlined, size: 20),
                label: Text(s.openResPacks),
              ),
              OutlinedButton.icon(
                onPressed: () => controller.loadMods(),
                icon: const Icon(Icons.refresh, size: 20),
                label: Text(s.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KindLabel extends StatelessWidget {
  const _KindLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.4,
          ),
    );
  }
}

class _ModTile extends StatelessWidget {
  const _ModTile({
    required this.mod,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.controller,
    required this.onToggle,
  });

  final ModEntry mod;
  final String title;
  final String subtitle;
  final bool enabled;
  final AppController controller;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PressScale(
      child: Container(
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
                mod.isGameMod
                    ? Icons.sports_esports_outlined
                    : mod.isDll
                        ? Icons.memory_outlined
                        : Icons.inventory_2_outlined,
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
                    title,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: enabled, onChanged: (_) => onToggle()),
          ],
        ),
      ),
    );
  }
}

class _ResPackTile extends StatelessWidget {
  const _ResPackTile({
    required this.pack,
    required this.enabled,
    required this.onToggle,
  });

  final ResPackEntry pack;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = S.of(context);
    final subtitle = <String>[
      if (pack.valid && pack.target.isNotEmpty) s.resPackTarget(pack.target),
      if (pack.valid) s.resPackFiles(pack.files),
      pack.sizeLabel(s),
      if (!pack.valid) s.resPackInvalid,
      enabled ? s.modEnabled : s.modDisabled,
    ].join(' · ');
    return PressScale(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: enabled
              ? scheme.tertiaryContainer.withValues(alpha: 0.45)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enabled ? scheme.tertiary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: enabled
                    ? scheme.tertiaryContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                pack.valid
                    ? Icons.texture_outlined
                    : Icons.warning_amber_outlined,
                size: 20,
                color: enabled
                    ? scheme.onTertiaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.valid && pack.name.isNotEmpty
                        ? pack.name
                        : pack.dirName,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pack.description.isNotEmpty)
                    Text(
                      pack.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: pack.valid ? (_) => onToggle() : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DumperCard extends StatelessWidget {
  const _DumperCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: controller.dumpResources
            ? scheme.errorContainer.withValues(alpha: 0.4)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              controller.dumpResources ? scheme.error : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: controller.dumpResources
                  ? scheme.errorContainer
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.unarchive_outlined,
              size: 20,
              color: controller.dumpResources
                  ? scheme.onErrorContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.dumperSection, style: theme.textTheme.titleMedium),
                Text(
                  controller.dumpResources ? s.dumperOn : s.dumperOff,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.openDumps,
            onPressed: controller.dumpsPath.isEmpty
                ? null
                : () => controller.openDumpsDir(),
            icon: const Icon(Icons.folder_open, size: 20),
          ),
          Switch(
            value: controller.dumpResources,
            onChanged: (value) => controller.setDumpResources(value),
          ),
        ],
      ),
    );
  }
}
