import 'package:flutter/material.dart';

import '../../models/login_info.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/illusio_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(
        illusioSnackBar('Введите код из приложения-аутентификатора'),
      );
      return;
    }
    messenger.showSnackBar(
      illusioSnackBar(result['error']?.toString() ?? 'вход не удался'),
    );
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await widget.controller.logout();
    if (!mounted) {
      return;
    }
    navigator.pop();
    messenger.showSnackBar(illusioSnackBar('Вы вышли из аккаунта'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Аккаунт SS14')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final login = widget.controller.login;
          if (login != null) {
            return _buildAccount(context, login);
          }
          return _buildForm(context);
        },
      ),
    );
  }

  Widget _buildAccount(BuildContext context, LoginInfo login) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              const IllusioLogo(size: 80),
              const SizedBox(height: 24),
              Text(login.username, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Аккаунт центральных серверов SS14',
                style: theme.textTheme.bodyMedium?.copyWith(color: mutedFog),
              ),
              if (login.expireTime.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Сессия до ${_formatExpiry(login.expireTime)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedFog),
                ),
              ],
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: widget.controller.loginBusy ? null : _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Выйти'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const IllusioLogo(size: 80),
              const SizedBox(height: 24),
              Text(
                'Вход в аккаунт SS14',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Тот же аккаунт, что и на сайте spacestation14.io. Токен остаётся на этом компьютере.',
                style: theme.textTheme.bodyMedium?.copyWith(color: mutedFog),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _username,
                autofillHints: const [AutofillHints.username],
                enableSuggestions: false,
                autocorrect: false,
                decoration: illusioInput('Логин'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscured,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                decoration: illusioInput('Пароль').copyWith(
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
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
                  decoration: illusioInput('Код двухфакторной аутентификации'),
                ),
              ],
              if (widget.controller.loginError.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  widget.controller.loginError,
                  style: theme.textTheme.bodyMedium?.copyWith(color: errorClay),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: widget.controller.loginBusy ? null : _submit,
                child: widget.controller.loginBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Войти'),
              ),
              const SizedBox(height: 16),
              Text(
                'Нет аккаунта? Зарегистрируйтесь на spacestation14.io',
                style: theme.textTheme.bodySmall?.copyWith(color: mutedFog),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
