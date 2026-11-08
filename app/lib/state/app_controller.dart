import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../ffi/bindings.dart';
import '../models/hub_server.dart';
import '../models/login_info.dart';
import '../models/server.dart';
import '../models/server_info.dart';
import '../models/server_status.dart';

class AppController extends ChangeNotifier {
  AppController() : favorites = [], accounts = [] {
    ready = _loadConfig();
  }

  late final Future<void> ready;

  String installDir = '';
  List<String> launchArgs = [];
  String configError = '';

  final List<GameServer> favorites;
  final List<LoginInfo> accounts;
  LoginInfo? login;

  String theme = 'system';
  bool hideEmpty = false;
  bool fullscreen = false;
  bool vsync = true;
  final List<String> modsEnabled = [];
  List<ModEntry> mods = [];
  String modsPath = '';

  List<HubServer> hubServers = [];
  bool hubLoading = false;
  String hubError = '';

  bool loginBusy = false;
  String loginError = '';

  DownloadStateInfo downloadState = DownloadStateInfo.empty;
  bool connecting = false;

  Future<void> _loadConfig() async {
    final result = await Isolate.run(Core.loadConfig);
    if (result['ok'] == true) {
      final config = (result['config'] as Map?) ?? const {};
      installDir = config['install_dir']?.toString() ?? '';
      launchArgs = ((config['launch_args'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList();
      login = LoginInfo.fromMap(config['login']);
      accounts
        ..clear()
        ..addAll(
          ((config['accounts'] as List?) ?? const [])
              .map(LoginInfo.fromMap)
              .whereType<LoginInfo>(),
        );
      favorites
        ..clear()
        ..addAll(
          ((config['favorites'] as List?) ?? const []).map(
            (value) => GameServer.fromJson((value as Map).cast<String, dynamic>()),
          ),
        );
      theme = config['theme']?.toString() ?? 'system';
      hideEmpty = config['hide_empty'] == true;
      fullscreen = config['fullscreen'] == true;
      vsync = config['vsync'] != false;
      modsEnabled
        ..clear()
        ..addAll(
          ((config['mods_enabled'] as List?) ?? const [])
              .map((value) => value.toString()),
        );
      if (login != null && !_accountsContain(login!)) {
        accounts.insert(0, login!);
      }
    } else {
      configError = result['error']?.toString() ?? '';
    }
    notifyListeners();
    await _loadModsDir();
    _refreshSession();
  }

  bool _accountsContain(LoginInfo info) {
    return accounts.any((account) => account.username == info.username);
  }

  Future<void> _loadModsDir() async {
    final result = await Isolate.run(Core.modsDir);
    if (result['ok'] == true) {
      modsPath = result['path']?.toString() ?? '';
    }
  }

  Future<void> saveConfig() async {
    final payload = jsonEncode({
      'install_dir': installDir,
      'launch_args': launchArgs,
      'last_server': selectedServer?.url ?? '',
      'login': login?.toJson(),
      'favorites': favorites.map((value) => value.toJson()).toList(),
      'accounts': accounts.map((value) => value.toJson()).toList(),
      'theme': theme,
      'hide_empty': hideEmpty,
      'fullscreen': fullscreen,
      'vsync': vsync,
      'mods_enabled': modsEnabled,
    });
    await Isolate.run(() => Core.saveConfig(payload));
  }

  Future<void> _refreshSession() async {
    final current = login;
    if (current == null) {
      return;
    }
    final payload = jsonEncode({
      'auth_url': current.authServer.isEmpty
          ? Core.defaultAuthUrl
          : current.authServer,
      'username': current.username,
      'user_id': current.userId,
      'token': current.token,
    });
    final result = await Isolate.run(() => Core.refreshLogin(payload));
    if (result['ok'] == true) {
      final updated = LoginInfo.fromMap(result['login']);
      if (updated != null) {
        login = updated;
        final index = accounts.indexWhere(
          (account) => account.username == updated.username,
        );
        if (index >= 0) {
          accounts[index] = updated;
        }
        await saveConfig();
        notifyListeners();
      }
    } else {
      login = null;
      await saveConfig();
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> authenticate(
    String username,
    String password,
    String tfaCode,
  ) async {
    if (loginBusy) {
      return {'ok': false, 'error': 'запрос уже выполняется'};
    }
    loginBusy = true;
    loginError = '';
    notifyListeners();
    final payload = jsonEncode({
      'auth_url': Core.defaultAuthUrl,
      'username': username,
      'password': password,
      'tfa_code': tfaCode,
    });
    final result = await Isolate.run(() => Core.authenticate(payload));
    loginBusy = false;
    if (result['ok'] == true) {
      final updated = LoginInfo.fromMap(result['login']);
      if (updated == null) {
        loginError = 'сервер авторизации вернул неполный ответ';
      } else {
        login = updated;
        loginError = '';
        final index = accounts.indexWhere(
          (account) => account.username == updated.username,
        );
        if (index >= 0) {
          accounts[index] = updated;
        } else {
          accounts.add(updated);
        }
        await saveConfig();
      }
    } else {
      loginError = result['error']?.toString() ?? 'авторизация не удалась';
    }
    notifyListeners();
    return result;
  }

  Future<void> switchAccount(LoginInfo account) async {
    if (login?.username == account.username) {
      return;
    }
    final payload = jsonEncode({
      'auth_url': account.authServer.isEmpty
          ? Core.defaultAuthUrl
          : account.authServer,
      'username': account.username,
      'user_id': account.userId,
      'token': account.token,
    });
    final result = await Isolate.run(() => Core.refreshLogin(payload));
    if (result['ok'] == true) {
      final updated = LoginInfo.fromMap(result['login']) ?? account;
      login = updated;
      final index = accounts.indexWhere(
        (element) => element.username == updated.username,
      );
      if (index >= 0) {
        accounts[index] = updated;
      }
    } else {
      login = account;
    }
    await saveConfig();
    notifyListeners();
    _refreshSession();
  }

  Future<void> logout() async {
    final current = login;
    if (current == null) {
      return;
    }
    final payload = jsonEncode({
      'auth_url': current.authServer.isEmpty
          ? Core.defaultAuthUrl
          : current.authServer,
      'token': current.token,
    });
    login = null;
    accounts.removeWhere((account) => account.username == current.username);
    notifyListeners();
    await saveConfig();
    await Isolate.run(() => Core.logout(payload));
  }

  Future<void> removeAccount(LoginInfo account) async {
    accounts.removeWhere((element) => element.username == account.username);
    if (login?.username == account.username) {
      login = null;
    }
    notifyListeners();
    await saveConfig();
  }

  bool isFavorite(String url) {
    return favorites.any((server) => server.url == url);
  }

  void addFavorite(String name, String url) {
    if (url.isEmpty || isFavorite(url)) {
      return;
    }
    favorites.add(GameServer(name: name.isEmpty ? url : name, url: url));
    notifyListeners();
    saveConfig();
  }

  void removeFavorite(String url) {
    favorites.removeWhere((server) => server.url == url);
    notifyListeners();
    saveConfig();
  }

  void toggleFavorite(String name, String url) {
    if (isFavorite(url)) {
      removeFavorite(url);
    } else {
      addFavorite(name, url);
    }
  }

  Future<void> loadHub() async {
    if (hubLoading) {
      return;
    }
    hubLoading = true;
    hubError = '';
    notifyListeners();
    final result = await Isolate.run(() => Core.fetchServers(''));
    hubLoading = false;
    if (result['ok'] == true) {
      hubServers = ((result['servers'] as List?) ?? const [])
          .map(HubServer.fromMap)
          .where((server) => !server.empty)
          .toList();
      hubServers.sort((left, right) => right.players.compareTo(left.players));
    } else {
      hubError = result['error']?.toString() ?? 'хаб недоступен';
    }
    notifyListeners();
  }

  void setTheme(String value) {
    theme = value;
    notifyListeners();
    saveConfig();
  }

  void setHideEmpty(bool value) {
    hideEmpty = value;
    notifyListeners();
    saveConfig();
  }

  void setFullscreen(bool value) {
    fullscreen = value;
    notifyListeners();
    saveConfig();
  }

  void setVsync(bool value) {
    vsync = value;
    notifyListeners();
    saveConfig();
  }

  Future<void> loadMods() async {
    if (modsPath.isEmpty) {
      return;
    }
    final result = await Isolate.run(() => Core.scanMods(modsPath));
    if (result['ok'] == true) {
      mods = ((result['mods'] as List?) ?? const [])
          .map(ModEntry.fromMap)
          .toList();
      modsEnabled.removeWhere(
        (name) => !mods.any((entry) => entry.fileName == name),
      );
      notifyListeners();
    }
  }

  void toggleMod(String fileName) {
    if (modsEnabled.contains(fileName)) {
      modsEnabled.remove(fileName);
    } else {
      modsEnabled.add(fileName);
    }
    notifyListeners();
    saveConfig();
  }

  Future<void> openUrl(String url) async {
    await Isolate.run(() => Core.openUrl(url));
  }

  Future<void> openModsDir() async {
    if (modsPath.isEmpty) {
      return;
    }
    await Isolate.run(() => Core.openPath(modsPath));
  }

  Future<String> configDirPath() async {
    final result = await Isolate.run(Core.configDir);
    return result['path']?.toString() ?? '';
  }

  Future<bool> clearCache() async {
    final result = await Isolate.run(Core.clearCache);
    return result['ok'] == true;
  }

  GameServer? selectedServer;
  ServerStatusInfo? statusInfo;
  bool loading = false;
  String loadError = '';

  Future<void> select(GameServer server) async {
    selectedServer = server;
    statusInfo = null;
    loadError = '';
    loading = true;
    notifyListeners();
    final result = await Isolate.run(() => Core.fetchStatus(server.url));
    if (!identical(selectedServer, server)) {
      return;
    }
    loading = false;
    if (result['ok'] == true) {
      statusInfo = ServerStatusInfo.fromMap(result['status']);
    } else {
      loadError = result['error']?.toString() ?? 'сервер не отвечает';
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> fetchStatus(String url) async {
    return Isolate.run(() => Core.fetchStatus(url));
  }

  List<String> _launchArgList() {
    final args = List<String>.from(launchArgs);
    if (fullscreen) {
      args.addAll(['--cvar', 'display.windowmode=1']);
    }
    if (!vsync) {
      args.addAll(['--cvar', 'display.vsync=false']);
    }
    return args;
  }

  List<String> enabledModPaths() {
    if (modsPath.isEmpty) {
      return const [];
    }
    final separator = Platform.isWindows ? '\\' : '/';
    return modsEnabled
        .map((name) => '$modsPath$separator$name')
        .toList();
  }

  Future<Map<String, dynamic>> connect(GameServer server) async {
    if (connecting) {
      return {'ok': false, 'error': 'подключение уже идёт'};
    }
    connecting = true;
    selectedServer = server;
    downloadState = DownloadStateInfo.empty;
    notifyListeners();

    final payload = jsonEncode({
      'server_url': server.url,
      'install_dir': installDir,
    });
    final started = await Isolate.run(() => Core.startDownload(payload));
    if (started['ok'] != true) {
      connecting = false;
      downloadState = DownloadStateInfo(
        phase: 'error',
        downloaded: 0,
        total: 0,
        message: '',
        error: started['error']?.toString() ?? 'не удалось начать загрузку',
        running: false,
        installDir: '',
        mode: '',
        engineZip: '',
        contentZip: '',
        engineSig: '',
        info: null,
      );
      notifyListeners();
      return started;
    }
    return _pollDownload(server);
  }

  Future<Map<String, dynamic>> _pollDownload(GameServer server) async {
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final result = await Isolate.run(Core.downloadState);
      if (result['ok'] != true) {
        continue;
      }
      downloadState = DownloadStateInfo.fromMap(result['state']);
      notifyListeners();
      if (downloadState.isDone) {
        connecting = false;
        notifyListeners();
        return _launchAfterDownload(server);
      }
      if (downloadState.isError) {
        connecting = false;
        notifyListeners();
        return {'ok': false, 'error': downloadState.error};
      }
    }
  }

  String get loaderDir {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final separator = Platform.isWindows ? '\\' : '/';
    return '$exeDir${separator}loader';
  }

  Future<Map<String, dynamic>> _launchAfterDownload(GameServer server) async {
    final info = downloadState.info;
    final current = login;
    final authAllowed = info?.authUsable == true;
    final acz = downloadState.isAcz;
    final spec = jsonEncode({
      'install_dir': downloadState.installDir,
      'args': _launchArgList(),
      'username': current?.username ?? '',
      'server_url': server.url,
      'connect_address': info?.connectAddress ?? '',
      'auth_token': authAllowed ? (current?.token ?? '') : '',
      'auth_user_id': authAllowed ? (current?.userId ?? '') : '',
      'auth_pubkey': authAllowed ? (info?.authPublicKey ?? '') : '',
      'auth_server': authAllowed ? (current?.authServer ?? '') : '',
      'build_download_url': info?.build.downloadUrl ?? '',
      'build_version': info?.build.version ?? '',
      'build_fork_id': info?.build.forkId ?? '',
      'build_hash': info?.build.hash ?? '',
      'build_engine_version': info?.build.engineVersion ?? '',
      'mode': acz ? 'acz' : 'zip',
      'loader_dir': acz ? loaderDir : '',
      'engine_zip': acz ? downloadState.engineZip : '',
      'content_zip': acz ? downloadState.contentZip : '',
      'engine_sig': acz ? downloadState.engineSig : '',
      'mods': acz ? enabledModPaths() : [],
    });
    final result = await Isolate.run(() => Core.launch(spec));
    if (result['ok'] != true) {
      return result;
    }
    selectedServer = server;
    await saveConfig();
    return result;
  }

  Future<void> launchFromDirectory() async {
    final spec = jsonEncode({
      'install_dir': installDir,
      'args': _launchArgList(),
    });
    await Isolate.run(() => Core.launch(spec));
  }
}
