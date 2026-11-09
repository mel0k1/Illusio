import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../../ffi/bindings.dart';
import '../../l10n/strings.dart';
import '../../models/proxy_profile.dart';
import '../../state/app_controller.dart';
import '../../version.dart';
import '../theme.dart';
import 'account_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _installDir = TextEditingController();
  final TextEditingController _launchArgs = TextEditingController();
  final TextEditingController _guest = TextEditingController();
  final TextEditingController _override = TextEditingController();
  final TextEditingController _engineOverride = TextEditingController();
  final TextEditingController _hwid = TextEditingController();
  bool _proxyBusy = false;
  String _proxyResult = '';
  Color _proxyResultColor = Colors.transparent;
  String _configPath = '';
  bool _pathsLoaded = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await widget.controller.ready;
    if (!mounted) {
      return;
    }
    final controller = widget.controller;
    setState(() {
      _installDir.text = controller.installDir;
      _launchArgs.text = controller.launchArgs.join(' ');
      _guest.text = controller.guestUsername;
      _override.text = controller.usernameOverride;
      _engineOverride.text = controller.engineOverride;
      _hwid.text = controller.hwidValue;
    });
    final path = await controller.configDirPath();
    if (!mounted) {
      return;
    }
    setState(() {
      _configPath = path.isEmpty ? S.of(context).pathUndefined : path;
      _pathsLoaded = true;
    });
  }

  @override
  void dispose() {
    _installDir.dispose();
    _launchArgs.dispose();
    _guest.dispose();
    _override.dispose();
    _engineOverride.dispose();
    _hwid.dispose();
    super.dispose();
  }

  Future<void> _saveClient() async {
    final s = S.of(context);
    widget.controller.installDir = _installDir.text.trim();
    widget.controller.launchArgs = _launchArgs.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList();
    widget.controller.setEngineOverride(_engineOverride.text.trim());
    await widget.controller.saveConfig();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(illusioSnackBar(s.clientSaved));
  }

  Future<void> _probeProxy() async {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    if (!widget.controller.proxyConfigured) {
      messenger.showSnackBar(illusioSnackBar(s.proxyNoProfiles));
      return;
    }
    setState(() {
      _proxyBusy = true;
      _proxyResult = s.proxyTesting;
      _proxyResultColor = Theme.of(context).colorScheme.onSurfaceVariant;
    });
    final controller = widget.controller;
    final result = await controller.proxyProbe(controller.proxyUdpRelay);
    if (!mounted) {
      return;
    }
    setState(() {
      _proxyBusy = false;
      if (result['ok'] != true) {
        _proxyResult = result['error']?.toString() ?? '';
        _proxyResultColor = Theme.of(context).colorScheme.error;
        return;
      }
      final rtt = (result['rtt_ms'] as num?)?.toInt() ?? 0;
      final udpOk = result['udp_ok'] == true;
      if (controller.proxyUdpRelay && !udpOk) {
        _proxyResult = [
          s.proxyOk(rtt),
          s.proxyNoUdp,
          result['udp_error']?.toString() ?? '',
        ].where((value) => value.isNotEmpty).join(' · ');
        _proxyResultColor = Theme.of(context).colorScheme.error;
      } else {
        _proxyResult =
            controller.proxyUdpRelay ? s.proxyOkUdp(rtt) : s.proxyOk(rtt);
        _proxyResultColor = Theme.of(context).colorScheme.primary;
      }
    });
    messenger.showSnackBar(illusioSnackBar(
      _proxyResult,
      error: _proxyResultColor == scheme.error,
      errorColor: scheme.error,
    ));
  }

  Future<void> _editProxyProfile(ProxyProfileInfo? existing) async {
    final s = S.of(context);
    final name = TextEditingController(text: existing?.name ?? '');
    final host = TextEditingController(text: existing?.host ?? '');
    final port = TextEditingController(
        text: existing != null && existing.port > 0
            ? existing.port.toString()
            : '1080');
    final user = TextEditingController(text: existing?.username ?? '');
    final pass = TextEditingController(text: existing?.password ?? '');
    bool obscured = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
              existing == null ? s.addProxyProfile : s.editProxyProfile),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: existing == null,
                  decoration: illusioInput(
                    s.proxyProfileName,
                    hint: s.proxyProfileNameHint,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: host,
                        decoration: illusioInput(
                            s.proxyHost, hint: '127.0.0.1'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: port,
                        keyboardType: TextInputType.number,
                        decoration: illusioInput(s.proxyPort, hint: '1080'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: user,
                  decoration: illusioInput(
                    s.proxyUser,
                    hint: s.proxyUserHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pass,
                  obscureText: obscured,
                  decoration: illusioInput(
                    s.proxyPassword,
                    suffix: IconButton(
                      onPressed: () => setDialogState(
                          () => obscured = !obscured),
                      icon: Icon(
                        obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (host.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    host.dispose();
    port.dispose();
    user.dispose();
    pass.dispose();
    if (saved != true || !mounted) {
      return;
    }
    final id = existing?.id ??
        'p${DateTime.now().millisecondsSinceEpoch}';
    widget.controller.upsertProxyProfile(
      ProxyProfileInfo(
        id: id,
        name: name.text.trim().isEmpty
            ? host.text.trim()
            : name.text.trim(),
        host: host.text.trim(),
        port: int.tryParse(port.text.trim())?.clamp(1, 65535) ?? 1080,
        username: user.text.trim(),
        password: pass.text,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(illusioSnackBar(S.of(context).proxySaved));
    }
  }

  Future<void> _saveAccount() async {
    final s = S.of(context);
    widget.controller.setGuestUsername(_guest.text.trim());
    widget.controller.setUsernameOverride(_override.text.trim());
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(illusioSnackBar(s.accountSaved));
  }

  Future<void> _addHub() async {
    final s = S.of(context);
    final urlController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.addHub),
        content: TextField(
          controller: urlController,
          autofocus: true,
          decoration: illusioInput(
            s.hubAddress,
            hint: 'https://hub.example.com',
          ),
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
              final hubs = List<String>.from(widget.controller.hubs);
              if (!hubs.contains(url)) {
                hubs.add(url);
                widget.controller.setHubs(hubs);
              }
              Navigator.of(dialogContext).pop();
            },
            child: Text(s.add),
          ),
        ],
      ),
    );
    urlController.dispose();
  }

  void _openAccount() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AccountSheet(controller: widget.controller),
    );
  }

  List<(String, String, Color)> _themeChips(AppController controller) {
    final s = S.of(context);
    return [
      (s.themeDark, 'dark', const Color(0xFFFFD65C)),
      (s.themeDarkRed, 'darkRed', const Color(0xFFFFB4A0)),
      (s.themeDarkPurple, 'darkPurple', const Color(0xFFD0B4FF)),
      (s.themeMidnightBlue, 'midnightBlue', const Color(0xFFAAC7FF)),
      (s.themeEmeraldDusk, 'emeraldDusk', const Color(0xFF93D69B)),
      (s.themeCopperNight, 'copperNight', const Color(0xFFFFB77E)),
      (s.themeLight, 'light', const Color(0xFFF4ECDF)),
    ];
  }

  Future<void> _clearCache() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await Isolate.run(Core.cullContent);
    if (result['ok'] != true) {
      messenger.showSnackBar(illusioSnackBar(s.cacheFailed));
      return;
    }
    final files = (result['files'] as num?)?.toInt() ?? 0;
    final bytes = (result['bytes'] as num?)?.toInt() ?? 0;
    messenger.showSnackBar(
      illusioSnackBar(
        files > 0
            ? '${s.cacheCleared}: $files · ${s.formatBytes(bytes)}'
            : s.cacheCleared,
      ),
    );
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
          children: [
            _PageTitle(
              title: s.settingsTitle,
              subtitle: s.settingsSubtitle,
            ),
            const SizedBox(height: 24),
            _SectionLabel(s.appearance),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.theme, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    s.themeHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final preset in _themeChips(controller))
                        ChoiceChip(
                          label: Text(preset.$1),
                          selected: controller.theme == preset.$2,
                          onSelected: (_) => controller.setTheme(preset.$2),
                          avatar: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: preset.$3,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(s.language, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    s.languageHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'ru',
                        icon: Icon(Icons.language, size: 18),
                        label: Text('RU'),
                      ),
                      ButtonSegment(
                        value: 'en',
                        icon: Icon(Icons.language, size: 18),
                        label: Text('EN'),
                      ),
                    ],
                    selected: {
                      controller.language == 'en' ? 'en' : 'ru'
                    },
                    onSelectionChanged: (selection) =>
                        controller.setLanguage(selection.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(s.gameSection),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                children: [
                  _SwitchRow(
                    title: s.fullscreen,
                    subtitle: 'display.windowmode',
                    value: controller.fullscreen,
                    onChanged: controller.setFullscreen,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'vsync',
                    subtitle: 'display.vsync',
                    value: controller.vsync,
                    onChanged: controller.setVsync,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(s.serverListSection),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SwitchRow(
                    title: s.hideEmptyServers,
                    subtitle: s.hideEmptyHint,
                    value: controller.hideEmpty,
                    onChanged: controller.setHideEmpty,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.hideFullServers,
                    subtitle: s.hideFullHint,
                    value: controller.hideFull,
                    onChanged: controller.setHideFull,
                  ),
                  const SizedBox(height: 14),
                  Text(s.hubs, style: theme.textTheme.titleMedium),
                  Text(
                    s.hubsHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  for (final hub in controller.hubs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              hub,
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => controller.setHubs(
                              controller.hubs
                                  .where((value) => value != hub)
                                  .toList(),
                            ),
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: s.removeHub,
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addHub,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.addHub),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(s.clientSection),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _installDir,
                    decoration: illusioInput(
                      s.installDir,
                      hint: s.installDirHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _launchArgs,
                    decoration: illusioInput(
                      s.launchArgs,
                      hint: '--profile server',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _engineOverride,
                    decoration: illusioInput(
                      s.engineOverride,
                      hint: s.engineOverrideHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SwitchRow(
                    title: s.clientLogs,
                    subtitle: s.clientLogsHint,
                    value: controller.clientLogs,
                    onChanged: controller.setClientLogs,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: _saveClient,
                      child: Text(s.save),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(s.proxySection),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.proxyProfiles, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    s.proxyProfilesHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (controller.proxyProfiles.isEmpty)
                    Text(
                      s.proxyNoProfiles,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final profile in controller.proxyProfiles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          onTap: () =>
                              controller.selectProxyProfile(profile.id),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          tileColor: scheme.surfaceContainerLow,
                          leading: Icon(
                            controller.selectedProxyProfile?.id == profile.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 20,
                            color: controller.selectedProxyProfile?.id ==
                                    profile.id
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          title: Text(
                            profile.name,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${profile.host}:${profile.port}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _editProxyProfile(profile),
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18),
                                tooltip: s.editProxyProfile,
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    controller.removeProxyProfile(profile.id),
                                icon: const Icon(Icons.delete_outline,
                                    size: 18),
                                tooltip: s.deleteProxyProfile,
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () => _editProxyProfile(null),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.addProxyProfile),
                  ),
                  const SizedBox(height: 14),
                  _SwitchRow(
                    title: s.proxyEnable,
                    subtitle: s.proxyEnableHint,
                    value: controller.proxyEnabled,
                    onChanged: controller.setProxyEnabled,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.proxyUpdatesEnable,
                    subtitle: s.proxyUpdatesHint,
                    value: controller.proxyUpdates,
                    onChanged: controller.setProxyUpdates,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.proxyRegionEnable,
                    subtitle: s.proxyRegionHint,
                    value: controller.proxyRegionBypass,
                    onChanged: controller.setProxyRegionBypass,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.proxyUdp,
                    subtitle: s.proxyUdpHint,
                    value: controller.proxyUdpRelay,
                    onChanged: controller.setProxyUdpRelay,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.proxyApply,
                    subtitle: s.proxyApplyHint,
                    value: controller.proxyApplyToGame,
                    onChanged: controller.setProxyApplyToGame,
                  ),
                  if (_proxyResult.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _proxyResult,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: _proxyResultColor),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _proxyBusy ? null : _probeProxy,
                      icon: const Icon(Icons.network_check, size: 20),
                      label: Text(s.proxyTest),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(s.updatesSection),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.currentVersion(appVersion),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.autoUpdateLabel,
                    subtitle: s.autoUpdateHint,
                    value: controller.autoUpdate,
                    onChanged: controller.setAutoUpdate,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.prefetchLabel,
                    subtitle: s.prefetchHint,
                    value: controller.prefetchFavorites,
                    onChanged: controller.setPrefetchFavorites,
                  ),
                  if (controller.updateVersion.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      s.updateAvailable(controller.updateVersion),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                  if (controller.updateError.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      s.updateFailed(controller.updateError),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                  if (controller.updateApplied) ...[
                    const SizedBox(height: 12),
                    Text(
                      s.updateAppliedText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    children: [
                      if (controller.updateApplied)
                        FilledButton(
                          onPressed: () => exit(0),
                          child: Text(s.restartNow),
                        )
                      else if (controller.updateVersion.isNotEmpty)
                        FilledButton(
                          onPressed: controller.updateBusy
                              ? null
                              : () => controller.applyUpdate(),
                          child: Text(
                            controller.updateBusy
                                ? s.updateDownloading
                                : s.updateDownload,
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: controller.updateBusy
                              ? null
                              : () => controller.checkForUpdates(),
                          icon: const Icon(Icons.update, size: 20),
                          label: Text(
                            controller.updateBusy
                                ? s.checkingUpdates
                                : s.checkUpdates,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(s.safetySection),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                children: [
                  _SwitchRow(
                    title: s.patchRpcLabel,
                    subtitle: s.patchRpcHint,
                    value: controller.patchRpc,
                    onChanged: controller.setPatchRpc,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.patchJamLabel,
                    subtitle: s.patchJamHint,
                    value: controller.patchJamDials,
                    onChanged: controller.setPatchJamDials,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.patchBlackholeLabel,
                    subtitle: s.patchBlackholeHint,
                    value: controller.patchBlackhole,
                    onChanged: controller.setPatchBlackhole,
                  ),
                  const SizedBox(height: 14),
                  Text(s.hideLevelLabel, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    s.hideLevelHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: controller.hideLevel.clamp(0, 4),
                        isExpanded: true,
                        items: [
                          for (var level = 0; level <= 4; level++)
                            DropdownMenuItem(
                              value: level,
                              child: Text(s.hideLevelName(level)),
                            ),
                        ],
                        onChanged: (value) => controller.setHideLevel(value ?? 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(s.hwidModeLabel, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    s.hwidModeHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: const ['off', 'random', 'fixed', 'account']
                                .contains(controller.hwidMode)
                            ? controller.hwidMode
                            : 'off',
                        isExpanded: true,
                        items: [
                          for (final mode in ['off', 'random', 'fixed', 'account'])
                            DropdownMenuItem(
                              value: mode,
                              child: Text(s.hwidModeName(mode)),
                            ),
                        ],
                        onChanged: (value) {
                          controller.setHwidMode(value ?? 'off');
                          setState(() => _hwid.text = controller.hwidValue);
                        },
                      ),
                    ),
                  ),
                  if (controller.hwidMode == 'fixed') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _hwid,
                      decoration: illusioInput(
                        s.hwidValueLabel,
                        hint: s.hwidValueHint,
                      ).copyWith(
                        errorText: controller.hwidValueValid
                            ? null
                            : s.hwidInvalid,
                        suffixIcon: IconButton(
                          tooltip: s.hwidGenerate,
                          onPressed: () {
                            controller.setHwidValue(
                              widget.controller.generateHwid(),
                            );
                            setState(
                              () => _hwid.text = controller.hwidValue,
                            );
                          },
                          icon: const Icon(Icons.casino_outlined, size: 20),
                        ),
                      ),
                      onChanged: (value) => controller.setHwidValue(value),
                    ),
                  ],
                  if (controller.hwidMode != 'off') ...[
                    const SizedBox(height: 8),
                    _SwitchRow(
                      title: s.hwidOptoutLabel,
                      subtitle: s.hwidOptoutHint,
                      value: controller.hwidOptout,
                      onChanged: controller.setHwidOptout,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: s.pgoLabel,
                    subtitle: s.pgoHint,
                    value: controller.dynamicPgo,
                    onChanged: controller.setDynamicPgo,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(s.accountSection),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.login?.username ?? s.guest,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    controller.login == null
                        ? s.accountHintGuest
                        : s.accountsHintSignedInOf(controller.accounts.length),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _guest,
                    decoration: illusioInput(
                      s.guestName,
                      hint: s.guestNameHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _override,
                    decoration: illusioInput(
                      s.overrideName,
                      hint: s.overrideNameHint,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _saveAccount,
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: Text(s.save),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _openAccount,
                    icon: const Icon(Icons.person_outline, size: 20),
                    label: Text(
                      controller.login == null
                          ? s.signIn
                          : s.manageAccounts,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(s.diagnostics),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.configStored, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  SelectableText(
                    _pathsLoaded ? _configPath : s.loadingDots,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: controller.openModsDir,
                        icon: const Icon(Icons.folder_open, size: 20),
                        label: Text(s.modsDirOpen),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.openLogsDir,
                        icon: const Icon(Icons.receipt_long_outlined, size: 20),
                        label: Text(s.logsDirOpen),
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearCache,
                        icon: const Icon(Icons.cleaning_services_outlined,
                            size: 20),
                        label: Text(s.clearCache),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Illusio $appVersion · ${s.coreLabel} ${Core.version()}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  BoxDecoration _card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: scheme.outlineVariant),
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
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
