import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
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

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _installDir = TextEditingController();
  final TextEditingController _launchArgs = TextEditingController();
  final TextEditingController _guest = TextEditingController();
  final TextEditingController _override = TextEditingController();
  final TextEditingController _hwid = TextEditingController();
  final TextEditingController _rpcFakeName = TextEditingController();
  final TextEditingController _hex = TextEditingController();
  final TextEditingController _adminGuid = TextEditingController();
  late final TabController _tabs = TabController(length: 5, vsync: this);
  bool _proxyBusy = false;
  String _proxyResult = '';
  Color _proxyResultColor = Colors.transparent;
  String _configPath = '';
  bool _pathsLoaded = false;
  Map<String, dynamic>? _health;

  static const List<int> _customSwatches = [
    0xFFF2F2F3,
    0xFFB4B4BA,
    0xFFFFB4A9,
    0xFFFFB77E,
    0xFFFFD65C,
    0xFF9CD69D,
    0xFF7FD1C3,
    0xFFAAC7FF,
    0xFF7986CB,
    0xFFD0B4FF,
    0xFFF3B4D6,
    0xFFE57373,
    0xFF4DB6AC,
    0xFFC9A86A,
  ];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _restore();
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    final result = await Isolate.run(Core.health);
    if (!mounted) {
      return;
    }
    setState(() {
      _health = result;
    });
  }

  Future<void> _exportTheme() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final location = await getSaveLocation(
      suggestedName: 'illusio-theme.json',
      acceptedTypeGroups: [const XTypeGroup(label: 'json', extensions: ['json'])],
    );
    if (location == null) {
      return;
    }
    await widget.controller.exportTheme(location.path);
    messenger.showSnackBar(illusioSnackBar(s.themeExported));
  }

  Future<void> _importTheme() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final typeGroup = XTypeGroup(label: s.themeFileLabel, extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) {
      return;
    }
    final ok = await widget.controller.importTheme(file.path);
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      illusioSnackBar(ok ? s.themeImportOk : s.themeImportBad),
    );
    if (ok) {
      setState(() {
        _adminGuid.text = widget.controller.adminGuidValue;
      });
    }
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
      _hwid.text = controller.hwidValue;
      _rpcFakeName.text = controller.rpcFakeName;
      _adminGuid.text = controller.adminGuidValue;
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
    _hwid.dispose();
    _rpcFakeName.dispose();
    _hex.dispose();
    _adminGuid.dispose();
    _tabs.dispose();
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

  Future<void> _importEngineZip() async {
    final controller = widget.controller;
    const typeGroup = XTypeGroup(label: 'engine zip', extensions: ['zip']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) {
      return;
    }
    await controller.importEngine(file.path);
  }

  Future<void> _importEngineFolder() async {
    final controller = widget.controller;
    final path = await getDirectoryPath();
    if (path == null || path.isEmpty || !mounted) {
      return;
    }
    await controller.importEngine(path);
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
      (s.themeDark, 'dark', themeDot('dark')),
      (s.themeDarkRed, 'darkRed', themeDot('darkRed')),
      (s.themeDarkPurple, 'darkPurple', themeDot('darkPurple')),
      (s.themeMidnightBlue, 'midnightBlue', themeDot('midnightBlue')),
      (s.themeEmeraldDusk, 'emeraldDusk', themeDot('emeraldDusk')),
      (s.themeCopperNight, 'copperNight', themeDot('copperNight')),
      (s.themeLight, 'light', themeDot('light')),
      (
        s.themeCustom,
        'custom',
        themeDot('custom', customColor: controller.customColor)
      ),
    ];
  }

  void _applyHex(String value) {
    final raw = value.trim().replaceAll('#', '');
    final parsed = raw.length == 6 ? int.tryParse(raw, radix: 16) : null;
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        illusioSnackBar(S.of(context).customColorInvalid),
      );
      return;
    }
    widget.controller.setCustomColor(parsed);
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
        final pad = controller.listBottomPad;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PageTitle(
                    title: s.settingsTitle,
                    subtitle: s.settingsSubtitle,
                  ),
                  const SizedBox(height: 16),
                  TabBar(
                    controller: _tabs,
                    indicatorColor: scheme.primary,
                    labelColor: scheme.primary,
                    unselectedLabelColor: scheme.onSurfaceVariant,
                    dividerColor: scheme.outlineVariant,
                    tabs: [
                      Tab(text: s.appearance),
                      Tab(text: s.gameSection),
                      Tab(text: s.tabNetwork),
                      Tab(text: s.accountSection),
                      Tab(text: s.tabSystem),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tabs.index,
                children: [
                  _lookTab(controller, s, pad),
                  _gameTab(controller, s, pad),
                  _networkTab(controller, s, pad),
                  _accountTab(controller, s, pad),
                  _systemTab(controller, s, pad),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _lookTab(AppController controller, S s, double pad) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad),
      children: [
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exportTheme,
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: Text(s.themeExport),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importTheme,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(s.themeImport),
                  ),
                ],
              ),
              if (controller.theme == 'custom') ...[
                const SizedBox(height: 18),
                Text(s.customColorLabel,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  s.customColorHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final swatch in _customSwatches)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () =>
                            controller.setCustomColor(swatch & 0xFFFFFF),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Color(0xFF000000 | swatch),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: controller.customColor ==
                                      (swatch & 0xFFFFFF)
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: controller.customColor ==
                                      (swatch & 0xFFFFFF)
                                  ? 2.5
                                  : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hex,
                  decoration: illusioInput(s.customColorLabel,
                      hint: '#7C5CFF'),
                  onSubmitted: _applyHex,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.dockLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                s.dockHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'bottom',
                    icon: const Icon(Icons.dock, size: 18),
                    label: Text(s.dockBottom),
                  ),
                  ButtonSegment(
                    value: 'left',
                    icon: const Icon(Icons.vertical_split, size: 18),
                    label: Text(s.dockLeft),
                  ),
                  ButtonSegment(
                    value: 'right',
                    icon: const Icon(Icons.vertical_split_outlined,
                        size: 18),
                    label: Text(s.dockRight),
                  ),
                ],
                selected: {
                  ['bottom', 'left', 'right'].contains(controller.dockSide)
                      ? controller.dockSide
                      : 'bottom'
                },
                onSelectionChanged: (selection) =>
                    controller.setDockSide(selection.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.cornersLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                s.cornersHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final variant in [
                    (s.cornersCompact, 'compact'),
                    (s.cornersNormal, 'normal'),
                    (s.cornersRound, 'round'),
                  ])
                    ChoiceChip(
                      label: Text(variant.$1),
                      selected: controller.corners == variant.$2,
                      onSelected: (_) => controller.setCorners(variant.$2),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.fontLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                s.fontHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final variant in [
                    (s.fontDefault, 'default'),
                    (s.fontSystem, 'system'),
                    ('Inter', 'inter'),
                    ('Manrope', 'manrope'),
                    ('Nunito', 'nunito'),
                    ('JetBrains Mono', 'jetbrains'),
                  ])
                    ChoiceChip(
                      label: Text(variant.$1),
                      selected: controller.font == variant.$2,
                      onSelected: (_) => controller.setFont(variant.$2),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
      ],
    );
  }

  Widget _gameTab(AppController controller, S s, double pad) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad),
      children: [
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
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.patchlessLabel,
                subtitle: s.patchlessHint,
                value: controller.patchless,
                onChanged: controller.setPatchless,
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.skipPrivacyLabel,
                subtitle: s.skipPrivacyHint,
                value: controller.skipPrivacy,
                onChanged: controller.setSkipPrivacy,
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.throwPatchFailLabel,
                subtitle: s.throwPatchFailHint,
                value: controller.throwPatchFail,
                onChanged: controller.setThrowPatchFail,
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.adminGuidLabel,
                subtitle: s.adminGuidHint,
                value: controller.adminGuid,
                onChanged: controller.setAdminGuid,
              ),
              if (controller.adminGuid || controller.patchFlyi) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _adminGuid,
                  decoration: illusioInput(s.adminGuidValueLabel).copyWith(
                    errorText: _adminGuidValid(controller.adminGuidValue)
                        ? null
                        : s.hwidInvalid,
                  ),
                  onChanged: controller.setAdminGuidValue,
                ),
              ],
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.patchFlyiLabel,
                subtitle: s.patchFlyiHint,
                value: controller.patchFlyi,
                onChanged: controller.setPatchFlyi,
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
              Text(s.enginesSection, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                s.enginesHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => controller.setEngineOverride(''),
                child: Row(
                  children: [
                    Icon(
                      controller.engineOverride.isEmpty
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: controller.engineOverride.isEmpty
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.enginesStandard,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              for (final engine in controller.customEngines)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => controller
                      .setEngineOverride(controller.engineZipPath(engine)),
                  child: Row(
                    children: [
                      Icon(
                        controller.engineOverride ==
                                controller.engineZipPath(engine)
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                        color: controller.engineOverride ==
                                controller.engineZipPath(engine)
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          engine.version.isEmpty
                              ? engine.name
                              : '${engine.name} · ${s.engineVersioned(engine.version)}',
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: s.enginesDelete,
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: controller.enginesBusy
                            ? null
                            : () => controller.removeEngine(engine.id),
                      ),
                    ],
                  ),
                ),
              if (controller.customEngines.isEmpty)
                Text(
                  s.enginesEmpty,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              if (controller.enginesError.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  s.enginesFailed(controller.enginesError),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.error),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.enginesBusy
                        ? null
                        : _importEngineZip,
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: Text(
                      controller.enginesBusy
                          ? s.enginesImporting
                          : s.enginesImportZip,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.enginesBusy
                        ? null
                        : _importEngineFolder,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: Text(s.enginesImportFolder),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SwitchRow(
                title: s.clientLogs,
                subtitle: s.clientLogsHint,
                value: controller.clientLogs,
                onChanged: controller.setClientLogs,
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.modLogsLabel,
                subtitle: s.modLogsHint,
                value: controller.modLogs,
                onChanged: controller.setModLogs,
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
      ],
    );
  }

  Widget _networkTab(AppController controller, S s, double pad) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad),
      children: [
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
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.proxyGuardLabel,
                subtitle: s.proxyGuardHint,
                value: controller.proxyGuardLaunch,
                onChanged: controller.setProxyGuardLaunch,
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.psDebugLabel,
                subtitle: s.psDebugHint,
                value: controller.psDebug,
                onChanged: controller.setPsDebug,
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
      ],
    );
  }

  Widget _accountTab(AppController controller, S s, double pad) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad),
      children: [
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
              _SwitchRow(
                title: s.noAutologinLabel,
                subtitle: s.noAutologinHint,
                value: controller.noAutologin,
                onChanged: controller.setNoAutologin,
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
      ],
    );
  }

  Future<void> _confirmInstall(
    AppController controller,
    S s,
    String version,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.installConfirmTitle(version)),
        content: Text(s.installConfirmBody(version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.versionInstall),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final index = controller.releases.indexWhere(
      (entry) => entry['version'] == version,
    );
    if (index >= 0) {
      await controller.installRelease(index);
    }
  }

  Widget _releaseRow(
    AppController controller,
    S s,
    Map<String, dynamic> release,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final version = release['version']?.toString() ?? '';
    final current = release['current'] == true;
    final prerelease = release['prerelease'] == true;
    final published = release['published']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'v$version',
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (prerelease) ...[
                      const SizedBox(width: 8),
                      Text(
                        s.versionPrerelease,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.tertiary,
                        ),
                      ),
                    ],
                    if (current) ...[
                      const SizedBox(width: 8),
                      Text(
                        s.versionCurrent,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (published.isNotEmpty)
                  Text(published, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (current)
            Icon(Icons.check_circle_outline, size: 20, color: scheme.primary)
          else
            OutlinedButton(
              onPressed: controller.releasesBusy
                  ? null
                  : () => _confirmInstall(controller, s, version),
              child: Text(
                controller.releasesBusy ? s.versionsLoading : s.versionInstall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _systemTab(AppController controller, S s, double pad) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad),
      children: [
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
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.updatePrereleaseLabel,
                subtitle: s.updatePrereleaseHint,
                value: controller.updatePrerelease,
                onChanged: controller.setUpdatePrerelease,
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
        _SectionLabel(s.versionsSection),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (controller.releaseApplied) ...[
                Text(
                  s.updateAppliedText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: () => exit(0),
                      child: Text(s.restartNow),
                    ),
                  ],
                ),
              ] else if (!controller.releasesLoaded) ...[
                OutlinedButton.icon(
                  onPressed:
                      controller.releasesLoading || controller.releasesBusy
                          ? null
                          : () => controller.loadReleases(),
                  icon: const Icon(Icons.history, size: 20),
                  label: Text(
                    controller.releasesLoading
                        ? s.versionsLoading
                        : s.showVersions,
                  ),
                ),
              ] else if (controller.releases.isEmpty) ...[
                Text(s.versionsEmpty, style: theme.textTheme.bodySmall),
              ] else ...[
                ...controller.releases.map(
                  (release) =>
                      _releaseRow(controller, s, release, theme, scheme),
                ),
              ],
              if (controller.releasesError.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  s.releasesFailed(controller.releasesError),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
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
              if (!controller.patchRpc) ...[
                const SizedBox(height: 8),
                _SwitchRow(
                  title: s.rpcFakeLabel,
                  subtitle: s.rpcFakeHint,
                  value: controller.rpcFake,
                  onChanged: controller.setRpcFake,
                ),
                if (controller.rpcFake) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rpcFakeName,
                    decoration: illusioInput(s.rpcFakeNameLabel),
                    onChanged: controller.setRpcFakeName,
                  ),
                ],
              ],
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
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.backportsLabel,
                subtitle: s.backportsHint,
                value: controller.backports,
                onChanged: controller.setBackports,
              ),
              if (controller.backports) ...[
                const SizedBox(height: 8),
                _SwitchRow(
                  title: s.backportsNoAnyLabel,
                  subtitle: s.backportsNoAnyHint,
                  value: controller.backportsNoAny,
                  onChanged: controller.setBackportsNoAny,
                ),
              ],
              const SizedBox(height: 8),
              _SwitchRow(
                title: s.stealthRegistriesLabel,
                subtitle: s.stealthRegistriesHint,
                value: controller.stealthRegistries,
                onChanged: controller.setStealthRegistries,
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
              const SizedBox(height: 16),
              _healthSection(context, controller, s),
            ],
          ),
        ),
      ],
    );
  }

  bool _adminGuidValid(String value) {
    final guid = value.trim().replaceAll(RegExp(r'^\{|\}$'), '');
    if (guid.isEmpty) {
      return true;
    }
    return guid.length == 32 &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(guid);
  }

  Widget _healthSection(BuildContext context, AppController controller, S s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _health;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.healthSection, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (result == null || result['ok'] != true)
          Text(
            result == null
                ? s.loadingDots
                : s.healthCheckFailed(
                    result['error']?.toString() ?? '',
                  ),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          ..._healthEntries(context, result, s),
      ],
    );
  }

  List<Widget> _healthEntries(
    BuildContext context,
    Map<String, dynamic> result,
    S s,
  ) {
    final health = (result['health'] as Map?) ?? const {};
    final entries = <(String, Object?, String, String)>[
      (
        s.healthVcRedist,
        health['vcRedistInstalled'],
        s.healthVcRedistMissing,
        s.healthVcRedistOk(
          (health['vcRedistVersion'] ?? '').toString(),
        ),
      ),
      (
        s.healthWine,
        health['wineInstalled'],
        s.healthWineMissing,
        s.healthWineOk,
      ),
      (
        s.healthRosetta,
        health['rosettaInstalled'],
        s.healthRosettaMissing,
        s.healthRosettaOk,
      ),
    ];
    return [
      for (final (title, installed, missing, ok) in entries)
        if (installed != null)
          _healthRow(
            context,
            title,
            installed == true ? ok : missing,
            bad: installed != true,
          ),
    ];
  }

  Widget _healthRow(
    BuildContext context,
    String title,
    String value, {
    required bool bad,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              title,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: bad ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
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
