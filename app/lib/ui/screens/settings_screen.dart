import 'dart:isolate';

import 'package:flutter/material.dart';

import '../../ffi/bindings.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _installDir = TextEditingController();
  final TextEditingController _launchArgs = TextEditingController();
  String _configPath = '';

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
    });
    final result = await Isolate.run(Core.configDir);
    if (!mounted) {
      return;
    }
    setState(() {
      _configPath = result['path']?.toString() ?? 'каталог не определён';
    });
  }

  @override
  void dispose() {
    _installDir.dispose();
    _launchArgs.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
        .showSnackBar(illusioSnackBar('Настройки сохранены'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Клиент', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
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
            decoration:
                illusioInput('Аргументы запуска', hint: '--profile server'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
          const SizedBox(height: 32),
          Text('Файлы', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            'Конфиг хранится в:',
            style: theme.textTheme.bodyMedium?.copyWith(color: mutedFog),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _configPath.isEmpty ? 'загружаем…' : _configPath,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
