import 'package:flutter/material.dart';

import '../../ffi/bindings.dart';
import '../../l10n/strings.dart';
import '../../models/login_info.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/account_avatar.dart';

class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  bool _loginMode = false;
  String _busyAction = '';
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _tfa = TextEditingController();
  bool _needsTfa = false;
  bool _obscured = true;

  bool get _busy => _busyAction.isNotEmpty;

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
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    if (username.isEmpty || password.isEmpty) {
      messenger.showSnackBar(illusioSnackBar(s.enterCredentials));
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
    messenger.showSnackBar(
      illusioSnackBar(result['error']?.toString() ?? s.loginFailed),
    );
  }

  Future<void> _openRegister() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    await widget.controller.openUrl(Core.registerUrl);
    messenger.showSnackBar(
      illusioSnackBar(s.openRegisterPage),
    );
  }

  Future<void> _openLink(String url) async {
    await widget.controller.openUrl(url);
  }

  Future<void> _loginGuest() async {
    if (_busy) {
      return;
    }
    setState(() => _busyAction = 'guest');
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    try {
      await widget.controller.loginAsGuest();
    } finally {
      if (mounted) {
        setState(() => _busyAction = '');
      }
    }
    if (!mounted) {
      return;
    }
    navigator.pop();
    messenger.showSnackBar(illusioSnackBar(s.guestSignedIn));
  }

  Future<void> _switch(LoginInfo account) async {
    if (_busy) {
      return;
    }
    setState(() => _busyAction = 'switch:${account.username}');
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final s = S.of(context);
    try {
      await widget.controller.switchAccount(account);
    } finally {
      if (mounted) {
        setState(() => _busyAction = '');
      }
    }
    if (!mounted) {
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      illusioSnackBar(s.accountSwitched(account.username)),
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
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AccountAvatar(
                      controller: controller,
                      name: current.username,
                      radius: 32,
                      letterStyle: theme.textTheme.headlineSmall,
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: _AvatarEditButton(controller: controller),
                    ),
                  ],
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
                    S.of(context).sessionUntil(_formatExpiry(current.expireTime)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],
            if (others.isNotEmpty) ...[
              _sectionTitle(context, S.of(context).switchAccount),
              const SizedBox(height: 8),
              for (final account in others)
                _AccountTile(
                  account: account,
                  busy: _busyAction == 'switch:${account.username}',
                  disabled: _busy,
                  onTap: _busy ? null : () => _switch(account),
                ),
              const SizedBox(height: 20),
            ],
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _loginMode = true),
              icon: const Icon(Icons.person_add_alt_1, size: 20),
              label: Text(S.of(context).addAccount),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _loginGuest,
              icon: _busyAction == 'guest'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_off_outlined, size: 20),
              label: Text(S.of(context).loginAsGuest),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openRegister,
              icon: const Icon(Icons.open_in_new, size: 20),
              label: Text(S.of(context).createAccount),
            ),
            const SizedBox(height: 10),
            if (current != null)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        final s = S.of(context);
                        setState(() => _busyAction = 'logout');
                        try {
                          await widget.controller.logout();
                        } finally {
                          if (mounted) {
                            setState(() => _busyAction = '');
                          }
                        }
                        if (!mounted) {
                          return;
                        }
                        navigator.pop();
                        messenger.showSnackBar(
                          illusioSnackBar(s.loggedOut),
                        );
                      },
                icon: _busyAction == 'logout'
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout, size: 20),
                label: Text(S.of(context).logout),
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
              S.of(context).loginTitle,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              S.of(context).loginHint,
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
              decoration: illusioInput(S.of(context).username,
                  prefixIcon: const Icon(Icons.person_outline, size: 20)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscured,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: illusioInput(
                S.of(context).password,
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
                  S.of(context).tfaCode,
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
                  : Text(S.of(context).login),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() => _loginMode = false),
              child: Text(S.of(context).back),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => _openLink(Core.forgotPasswordUrl),
                  child: Text(S.of(context).forgotPassword),
                ),
                TextButton(
                  onPressed: () => _openLink(Core.resendConfirmationUrl),
                  child: Text(S.of(context).resendEmail),
                ),
              ],
            ),
            TextButton(
              onPressed: () => _openLink(Core.manageAccountUrl),
              child: Text(S.of(context).manageOnSite),
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

class _AvatarEditButton extends StatefulWidget {
  const _AvatarEditButton({required this.controller});

  final AppController controller;

  @override
  State<_AvatarEditButton> createState() => _AvatarEditButtonState();
}

class _AvatarEditButtonState extends State<_AvatarEditButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) {
      return;
    }
    if (widget.controller.avatarFile == null) {
      await _pick();
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop('choose'),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                label: Text(S.of(sheetContext).chooseAvatar),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop('remove'),
                icon: const Icon(Icons.no_photography_outlined, size: 20),
                label: Text(S.of(sheetContext).removeAvatar),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (action == 'choose') {
      await _pick();
    } else if (action == 'remove') {
      await widget.controller.removeAvatar();
    }
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final result = await widget.controller.chooseAvatar();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (result == AvatarPick.invalid) {
      messenger.showSnackBar(illusioSnackBar(s.avatarNotImage));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _tap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: _busy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 15,
                  color: scheme.onPrimary,
                ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.onTap,
    this.busy = false,
    this.disabled = false,
  });

  final LoginInfo account;
  final VoidCallback? onTap;
  final bool busy;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      enabled: !disabled,
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
        S.of(context).savedAccount,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right, size: 20),
      tileColor: scheme.surfaceContainerLow,
    );
  }
}
