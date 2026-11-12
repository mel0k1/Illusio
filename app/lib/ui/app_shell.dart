import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/server.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/account_avatar.dart';
import 'screens/account_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mods_screen.dart';
import 'screens/servers_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/connect_flow.dart';
import 'widgets/illusio_logo.dart';

class DockItem {
  const DockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String Function(S s) label;
}

final List<DockItem> dockItems = [
  DockItem(
      icon: Icons.star_outline, selectedIcon: Icons.star, label: (s) => s.home),
  DockItem(
    icon: Icons.travel_explore_outlined,
    selectedIcon: Icons.travel_explore,
    label: (s) => s.servers,
  ),
  DockItem(
      icon: Icons.tune, selectedIcon: Icons.tune, label: (s) => s.settings),
  DockItem(
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
    label: (s) => s.mods,
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
  bool _proxyDialogShown = false;
  bool _guardDialogShown = false;
  bool _crashDialogShown = false;
  bool _connectConsuming = false;

  @override
  void initState() {
    super.initState();
    _consumePendingConnect();
    widget.controller.addListener(_watchProxy);
    widget.controller.addListener(_watchCrash);
    widget.controller.addListener(_watchPendingConnect);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_watchProxy);
    widget.controller.removeListener(_watchCrash);
    widget.controller.removeListener(_watchPendingConnect);
    super.dispose();
  }

  void _watchPendingConnect() {
    if (_connectConsuming || !mounted) {
      return;
    }
    final url = widget.controller.pendingConnect;
    if (url == null || url.isEmpty) {
      return;
    }
    _consumePendingConnect();
  }

  void _watchCrash() {
    if (_crashDialogShown || widget.controller.crashDiag == null || !mounted) {
      return;
    }
    _crashDialogShown = true;
    _showCrashDialog().whenComplete(() => _crashDialogShown = false);
  }

  Future<void> _showCrashDialog() async {
    final crash = widget.controller.crashDiag;
    if (crash == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.bug_report_outlined),
        title: Text(S.of(dialogContext).crashTitle),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.of(dialogContext).crashBody(crash.exitCode)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    crash.logTail.isEmpty
                        ? S.of(dialogContext).crashLogEmpty
                        : crash.logTail,
                    style: Theme.of(dialogContext)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.of(dialogContext).crashClose),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    widget.controller.dismissCrash();
  }

  void _watchProxy() {
    if (!_guardDialogShown && widget.controller.launchGuardActive && mounted) {
      _guardDialogShown = true;
      _showLaunchGuardDialog()
          .whenComplete(() => _guardDialogShown = false);
      return;
    }
    if (_proxyDialogShown || !widget.controller.proxyUnavailable) {
      return;
    }
    if (!mounted) {
      return;
    }
    _proxyDialogShown = true;
    _showProxyDialog();
  }

  Future<void> _showLaunchGuardDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final error = widget.controller.launchGuardError;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.network_check_outlined),
        title: Text(S.of(dialogContext).proxyGuardTitle),
        content: Text(
          S.of(dialogContext).proxyGuardBody(
                error.isEmpty
                    ? S.of(dialogContext).probeTimeout
                    : error,
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.of(dialogContext).proxyGuardCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.of(dialogContext).proxyGuardContinue),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    if (proceed == true) {
      final result = await widget.controller.launchGuardContinue();
      if (!mounted) {
        return;
      }
      if (result['ok'] == true) {
        messenger.showSnackBar(
          illusioSnackBar(s.proxySessionOffNotice),
        );
      } else {
        messenger.showSnackBar(
          illusioSnackBar(
            result['error']?.toString() ?? s.connectFailed,
          ),
        );
      }
    } else {
      await widget.controller.launchGuardCancel();
    }
  }

  Future<void> _showProxyDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final error = widget.controller.proxyProbeError;
    final disable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.report_outlined),
        title: Text(S.of(dialogContext).proxyUnavailableTitle),
        content: Text(
          S.of(dialogContext).proxyUnavailableBody(
                error.isEmpty
                    ? S.of(dialogContext).probeTimeout
                    : error,
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.of(dialogContext).proxyKeepTrying),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.of(dialogContext).proxyContinueNoProxy),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    _proxyDialogShown = false;
    if (disable == true) {
      await widget.controller.continueWithoutProxy();
      messenger.showSnackBar(
        illusioSnackBar(s.proxySessionOffNotice),
      );
    } else {
      widget.controller.dismissProxyWarning();
    }
  }

  Future<void> _consumePendingConnect() async {
    if (_connectConsuming) {
      return;
    }
    _connectConsuming = true;
    try {
      await widget.controller.ready;
      if (!mounted) {
        return;
      }
      final url = widget.controller.pendingConnect;
      if (url == null || url.isEmpty) {
        return;
      }
      widget.controller.pendingConnect = null;
      await connectFlow(
          context, widget.controller, GameServer(name: url, url: url));
    } finally {
      _connectConsuming = false;
    }
  }

  void _openAccount() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AccountSheet(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final labels = dockItems.map((item) => item.label(s)).toList();
        final side = widget.controller.dockSide;
        final busy = widget.controller.connecting ||
            widget.controller.downloadState.running;
        final content = Column(
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
        );
        void select(int value) => setState(() => _index = value);
        final chip = _BusyChip(controller: widget.controller);
        final body = switch (side) {
          'left' => Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                  child: Column(
                    children: [
                      _Rail(
                        index: _index,
                        labels: labels,
                        corners: widget.controller.corners,
                        onSelect: select,
                      ),
                      AnimatedSwitcher(
                        duration: spatialFast,
                        switchInCurve: expressCurve,
                        switchOutCurve: exitCurve,
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                              opacity: animation, child: child),
                        ),
                        child: busy
                            ? Padding(
                                key: const ValueKey('rail-chip'),
                                padding: const EdgeInsets.only(top: 10),
                                child: chip,
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('rail-empty'),
                              ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            ),
          'right' => Row(
              children: [
                Expanded(child: content),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                  child: Column(
                    children: [
                      _Rail(
                        index: _index,
                        labels: labels,
                        corners: widget.controller.corners,
                        onSelect: select,
                      ),
                      AnimatedSwitcher(
                        duration: spatialFast,
                        switchInCurve: expressCurve,
                        switchOutCurve: exitCurve,
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                              opacity: animation, child: child),
                        ),
                        child: busy
                            ? Padding(
                                key: const ValueKey('rail-chip'),
                                padding: const EdgeInsets.only(top: 10),
                                child: chip,
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('rail-empty'),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          _ => content,
        };
        return Scaffold(
          body: SafeArea(
            bottom: side != 'bottom',
            child: body,
          ),
          extendBody: side == 'bottom',
          bottomNavigationBar: side == 'bottom'
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: spatialFast,
                      switchInCurve: expressCurve,
                      switchOutCurve: exitCurve,
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(
                        scale: animation,
                        child: FadeTransition(
                            opacity: animation, child: child),
                      ),
                      child: busy
                          ? Padding(
                              key: const ValueKey('dock-chip'),
                              padding:
                                  const EdgeInsets.fromLTRB(20, 0, 20, 6),
                              child: Center(child: chip),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('dock-empty'),
                            ),
                    ),
                    _BottomDock(
                      index: _index,
                      labels: labels,
                      corners: widget.controller.corners,
                      onSelect: select,
                    ),
                  ],
                )
              : null,
        );
      },
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
                return _AccountChip(
                  controller: controller,
                  name: name,
                  onTap: onAccount,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.controller,
    required this.name,
    required this.onTap,
  });

  final AppController controller;
  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = name ?? S.of(context).signIn;
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
              AccountAvatar(
                controller: controller,
                name: name ?? '',
                radius: 14,
                idleColor:
                    name == null ? scheme.outlineVariant : null,
                onIdleColor:
                    name == null ? scheme.onSurfaceVariant : null,
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

class _BusyChip extends StatelessWidget {
  const _BusyChip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = controller.downloadState;
    final progress = state.total > 0 ? state.progress : null;
    return Material(
      color: scheme.surfaceContainer,
      shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => showDownloadStatus(context, controller),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 16, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  value: progress,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  state.phaseLabel(S.of(context)),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (progress != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
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
                curve: i == index ? expressCurve : exitCurve,
                offset: i == index
                    ? Offset.zero
                    : Offset(i < index ? -0.025 : 0.025, 0.01),
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

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.index,
    required this.labels,
    required this.corners,
    required this.onSelect,
  });

  final int index;
  final List<String> labels;
  final String corners;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sc = cornerScale(corners);
    final shadowAlpha = scheme.brightness == Brightness.dark ? 0.35 : 0.12;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(32 * sc),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < dockItems.length; i++)
                    _DockButton(
                      item: dockItems[i],
                      label: labels[i],
                      selected: i == index,
                      scheme: scheme,
                      scale: sc,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.label,
    required this.selected,
    required this.scheme,
    required this.scale,
    required this.onTap,
  });

  final DockItem item;
  final String label;
  final bool selected;
  final ColorScheme scheme;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
      child: AnimatedContainer(
        duration: spatialDefault,
        curve: springCurve,
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(24 * scale),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24 * scale),
            ),
            onTap: onTap,
            child: AnimatedSwitcher(
              duration: spatialFast,
              switchInCurve: expressCurve,
              switchOutCurve: exitCurve,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: selected
                  ? Row(
                      key: const ValueKey(true),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedRotation(
                          turns: 0.125,
                          duration: spatialDefault,
                          curve: springCurve,
                          child: Icon(
                            item.selectedIcon,
                            size: 20,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: foreground),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Tooltip(
                      key: const ValueKey(false),
                      message: label,
                      child:
                          Icon(item.icon, size: 24, color: foreground),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.index,
    required this.labels,
    required this.corners,
    required this.onSelect,
  });

  final int index;
  final List<String> labels;
  final String corners;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sc = cornerScale(corners);
    final shadowAlpha = scheme.brightness == Brightness.dark ? 0.35 : 0.12;
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(28 * sc),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowAlpha),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const IllusioLogo(size: 26),
          const SizedBox(height: 18),
          for (var i = 0; i < dockItems.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: _RailButton(
                item: dockItems[i],
                label: labels[i],
                selected: i == index,
                scheme: scheme,
                scale: sc,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.item,
    required this.label,
    required this.selected,
    required this.scheme,
    required this.scale,
    required this.onTap,
  });

  final DockItem item;
  final String label;
  final bool selected;
  final ColorScheme scheme;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: spatialDefault,
      curve: springCurve,
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(18 * scale),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18 * scale),
          ),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.0 : 0.94,
                duration: spatialDefault,
                curve: springCurve,
                child: AnimatedRotation(
                  turns: selected ? 0.125 : 0,
                  duration: spatialDefault,
                  curve: springCurve,
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 22,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
