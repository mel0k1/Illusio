import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'theme.dart';
import 'screens/account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mods_screen.dart';
import 'screens/servers_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/illusio_logo.dart';

class DockItem {
  const DockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const List<DockItem> dockItems = [
  DockItem(icon: Icons.star_outline, selectedIcon: Icons.star, label: 'Главная'),
  DockItem(
    icon: Icons.travel_explore_outlined,
    selectedIcon: Icons.travel_explore,
    label: 'Сервера',
  ),
  DockItem(icon: Icons.tune, selectedIcon: Icons.tune, label: 'Настройки'),
  DockItem(
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
    label: 'Моды',
  ),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _openAccount() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AccountSheet(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SlimBar(
              controller: widget.controller,
              onAccount: _openAccount,
            ),
            Expanded(
              child: _PageStack(
                controller: widget.controller,
                index: _index,
              ),
            ),
          ],
        ),
      ),
      extendBody: true,
      bottomNavigationBar: IllusioDock(
        index: _index,
        scheme: scheme,
        onSelect: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _SlimBar extends StatelessWidget {
  const _SlimBar({required this.controller, required this.onAccount});

  final AppController controller;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const IllusioLogo(size: 24),
            const SizedBox(width: 10),
            Text(
              'Illusio',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final name = controller.login?.username;
                return _AccountChip(name: name, onTap: onAccount);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.name, required this.onTap});

  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = name ?? 'Войти';
    return Material(
      color: scheme.surfaceContainer,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor:
                    name == null ? scheme.outlineVariant : scheme.primaryContainer,
                foregroundColor: name == null
                    ? scheme.onSurfaceVariant
                    : scheme.onPrimaryContainer,
                child: Text(
                  name == null ? '?' : name![0].toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 10),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurface,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageStack extends StatelessWidget {
  const _PageStack({required this.controller, required this.index});

  final AppController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(controller: controller),
      ServersScreen(controller: controller),
      SettingsScreen(controller: controller),
      ModsScreen(controller: controller),
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < pages.length; i++)
          Offstage(
            offstage: i != index,
            child: TickerMode(
              enabled: i == index,
              child: AnimatedSlide(
                duration: spatialDefault,
                curve: expressCurve,
                offset: i == index ? Offset.zero : const Offset(0, 0.015),
                child: AnimatedOpacity(
                  duration: spatialFast,
                  curve: expressCurve,
                  opacity: i == index ? 1 : 0,
                  child: pages[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class IllusioDock extends StatelessWidget {
  const IllusioDock({
    super.key,
    required this.index,
    required this.scheme,
    required this.onSelect,
  });

  final int index;
  final ColorScheme scheme;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final shadowAlpha =
        scheme.brightness == Brightness.dark ? 0.35 : 0.12;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: shadowAlpha),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < dockItems.length; i++)
              Expanded(
                child: _DockButton(
                  item: dockItems[i],
                  selected: i == index,
                  scheme: scheme,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final DockItem item;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          onTap: onTap,
          child: AnimatedSwitcher(
            duration: spatialFast,
            switchInCurve: expressCurve,
            switchOutCurve: expressCurve,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: selected
                ? Row(
                    key: const ValueKey(true),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedRotation(
                        turns: 0.125,
                        duration: spatialDefault,
                        curve: springCurve,
                        child: Icon(
                          item.selectedIcon,
                          size: 22,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          item.label,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: foreground),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  )
                : Icon(
                    item.icon,
                    key: const ValueKey(false),
                    size: 24,
                    color: foreground,
                  ),
          ),
        ),
      ),
    );
  }
}
