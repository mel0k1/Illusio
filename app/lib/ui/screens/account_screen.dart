import 'package:flutter/material.dart';

import '../../ffi/bindings.dart';
import '../../models/login_info.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  bool _loginMode = false;
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _tfa = TextEditingController();
  bool _needsTfa = false;
  bool _obscured = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _tfa.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(illusioSnackBar('Введите логин и пароль'));
      return;
    }
    final result = await widget.controller.authenticate(
      username,
      password,
      _tfa.text.trim(),
    );
    if (!mounted) {
      return;
    }
    if (result['ok'] == true) {
      Navigator.of(context).pop();
      return;
    }
    final code = result['code']?.toString().toLowerCase() ?? '';
    if (code == 'tfarequired' && !_needsTfa) {
      setState(() => _needsTfa = true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      illusioSnackBar(result['error']?.toString() ?? 'вход не удался'),
    );
  }

  Future<void> _openRegister() async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.controller.openUrl(Core.registerUrl);
    messenger.showSnackBar(
      illusioSnackBar('Открываем страницу регистрации'),
    );
  }

  Future<void> _openLink(String url) async {
    await widget.controller.openUrl(url);
  }

  Future<void> _loginGuest() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await widget.controller.loginAsGuest();
    navigator.pop();
    messenger.showSnackBar(illusioSnackBar('Вошли как гость'));
  }

  Future<void> _switch(LoginInfo account) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await widget.controller.switchAccount(account);
    navigator.pop();
    messenger.showSnackBar(
      illusioSnackBar('Аккаунт: ${account.username}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) =>
            _loginMode ? _buildLogin(context) : _buildAccounts(context),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _buildAccounts(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = widget.controller;
    final current = controller.login;
    final others = controller.accounts
        .where((account) => account.username != current?.username)
        .toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (current != null) ...[
              Center(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    current.username.isEmpty
                        ? '?'
                        : current.username[0].toUpperCase(),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child:
                    Text(current.username, style: theme.textTheme.titleLarge),
              ),
              if (current.expireTime.isNotEmpty)
                Center(
                  child: Text(
                    'Сессия до ${_formatExpiry(current.expireTime)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],
            if (others.isNotEmpty) ...[
              _sectionTitle(context, 'Сменить аккаунт'),
              const SizedBox(height: 8),
              for (final account in others)
                _AccountTile(
                  account: account,
                  onTap: () => _switch(account),
                ),
              const SizedBox(height: 20),
            ],
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _loginMode = true),
              icon: const Icon(Icons.person_add_alt_1, size: 20),
              label: const Text('Добавить аккаунт'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loginGuest,
              icon: const Icon(Icons.person_off_outlined, size: 20),
              label: const Text('Войти как гость'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openRegister,
              icon: const Icon(Icons.open_in_new, size: 20),
              label: const Text('Создать аккаунт'),
            ),
            const SizedBox(height: 10),
            if (current != null)
              TextButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  await widget.controller.logout();
                  if (!mounted) {
                    return;
                  }
                  navigator.pop();
                  messenger.showSnackBar(
                    illusioSnackBar('Вы вышли из аккаунта'),
                  );
                },
                icon: const Icon(Icons.logout, size: 20),
                label: const Text('Выйти'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogin(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = widget.controller;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Вход в аккаунт SS14',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Тот же аккаунт, что и на сайте spacestation14.io',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _username,
              autofillHints: const [AutofillHints.username],
              enableSuggestions: false,
              autocorrect: false,
              decoration: illusioInput('Логин',
                  prefixIcon: const Icon(Icons.person_outline, size: 20)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscured,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: illusioInput(
                'Пароль',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffix: IconButton(
                  onPressed: () => setState(() => _obscured = !_obscured),
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
              ),
            ),
            if (_needsTfa) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _tfa,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _submit(),
                decoration: illusioInput(
                  'Код двухфакторной аутентификации',
                  prefixIcon: const Icon(Icons.shield_outlined, size: 20),
                ),
              ),
            ],
            if (controller.loginError.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                controller.loginError,
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: controller.loginBusy ? null : _submit,
              child: controller.loginBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Войти'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() => _loginMode = false),
              child: const Text('Назад'),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => _openLink(Core.forgotPasswordUrl),
                  child: const Text('Забыли пароль?'),
                ),
                TextButton(
                  onPressed: () => _openLink(Core.resendConfirmationUrl),
                  child: const Text('Повторить письмо'),
                ),
              ],
            ),
            TextButton(
              onPressed: () => _openLink(Core.manageAccountUrl),
              child: const Text('Управление аккаунтом на сайте'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatExpiry(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.${local.year} $hour:$minute';
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.onTap});

  final LoginInfo account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurface,
        child: Text(
          account.username.isEmpty ? '?' : account.username[0].toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      title: Text(account.username,
          style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(
        'сохранённый аккаунт',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      tileColor: scheme.surfaceContainerLow,
    );
  }
}
