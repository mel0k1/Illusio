import 'package:flutter/material.dart';

import '../../ffi/bindings.dart';
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
    setState(() {
      _installDir.text = widget.controller.installDir;
      _launchArgs.text = widget.controller.launchArgs.join(' ');
      _guest.text = widget.controller.guestUsername;
      _override.text = widget.controller.usernameOverride;
      _engineOverride.text = widget.controller.engineOverride;
    });
    final path = await widget.controller.configDirPath();
    if (!mounted) {
      return;
    }
    setState(() {
      _configPath = path.isEmpty ? 'каталог не определён' : path;
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
    super.dispose();
  }

  Future<void> _saveClient() async {
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
        .showSnackBar(illusioSnackBar('Настройки клиента сохранены'));
  }

  Future<void> _clearCache() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await widget.controller.clearCache();
    messenger.showSnackBar(
      illusioSnackBar(ok ? 'Кэш загрузок очищен' : 'Не удалось очистить кэш'),
    );
  }

  Future<void> _saveAccount() async {
    widget.controller.setGuestUsername(_guest.text.trim());
    widget.controller.setUsernameOverride(_override.text.trim());
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(illusioSnackBar('Настройки аккаунта сохранены'));
  }

  Future<void> _addHub() async {
    final urlController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Добавить хаб'),
        content: TextField(
          controller: urlController,
          autofocus: true,
          decoration: illusioInput(
            'Адрес хаба',
            hint: 'https://hub.example.com',
          ),
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
              final hubs = List<String>.from(widget.controller.hubs);
              if (!hubs.contains(url)) {
                hubs.add(url);
                widget.controller.setHubs(hubs);
              }
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Добавить'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
          children: [
            _PageTitle(
              title: 'Настройки',
              subtitle: 'внешний вид, поведение и клиент игры',
            ),
            const SizedBox(height: 24),
            _SectionLabel('Внешний вид'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Тема', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'тёмная включена по умолчанию',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'dark',
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                        label: Text('Тёмная'),
                      ),
                      ButtonSegment(
                        value: 'light',
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                        label: Text('Светлая'),
                      ),
                    ],
                    selected: {controller.theme == 'light' ? 'light' : 'dark'},
                    onSelectionChanged: (selection) =>
                        controller.setTheme(selection.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel('Игра'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                children: [
                  _SwitchRow(
                    title: 'Полноэкранный режим',
                    subtitle: 'display.windowmode',
                    value: controller.fullscreen,
                    onChanged: controller.setFullscreen,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Вертикальная синхронизация',
                    subtitle: 'display.vsync',
                    value: controller.vsync,
                    onChanged: controller.setVsync,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel('Список серверов'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SwitchRow(
                    title: 'Скрывать пустые сервера',
                    subtitle: 'сервера без игроков не отображаются',
                    value: controller.hideEmpty,
                    onChanged: controller.setHideEmpty,
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Скрывать полные сервера',
                    subtitle: 'у них заняты все слоты',
                    value: controller.hideFull,
                    onChanged: controller.setHideFull,
                  ),
                  const SizedBox(height: 14),
                  Text('Хабы', style: theme.textTheme.titleMedium),
                  Text(
                    'основной хаб SS14 подключён всегда, ниже — дополнительные',
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
                            tooltip: 'Убрать хаб',
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addHub,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить хаб'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel('Клиент'),
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
                      'Каталог для клиента',
                      hint: 'по умолчанию — системный каталог данных',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _launchArgs,
                    decoration: illusioInput(
                      'Аргументы запуска',
                      hint: '--profile server',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _engineOverride,
                    decoration: illusioInput(
                      'Свой движок (zip)',
                      hint: 'путь к архиву движка вместо CDN',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SwitchRow(
                    title: 'Логи клиента',
                    subtitle: 'stdout и stderr пишутся в каталог logs',
                    value: controller.clientLogs,
                    onChanged: controller.setClientLogs,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: _saveClient,
                      child: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel('Аккаунт'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.login?.username ?? 'Гость',
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    controller.login == null
                        ? 'войдите, чтобы играть на серверах с аутентификацией'
                        : '${controller.accounts.length} сохранённых аккаунтов',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _guest,
                    decoration: illusioInput(
                      'Имя гостя',
                      hint: 'под каким именем заходить без аккаунта',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _override,
                    decoration: illusioInput(
                      'Подменить имя',
                      hint: 'имя вместо логина аккаунта',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _saveAccount,
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: const Text('Сохранить'),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _openAccount,
                    icon: const Icon(Icons.person_outline, size: 20),
                    label: Text(
                      controller.login == null
                          ? 'Войти'
                          : 'Управление аккаунтами',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel('Диагностика'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _card(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Конфиг хранится в:', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  SelectableText(
                    _pathsLoaded ? _configPath : 'загружаем…',
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
                        label: const Text('Каталог модов'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.openLogsDir,
                        icon: const Icon(Icons.receipt_long_outlined, size: 20),
                        label: const Text('Каталог логов'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearCache,
                        icon: const Icon(Icons.cleaning_services_outlined,
                            size: 20),
                        label: const Text('Очистить кэш'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Illusio $appVersion · ядро ${Core.version()}',
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
