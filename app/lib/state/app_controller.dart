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
  AppController()
      : favorites = [],
        accounts = [] {
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
  bool hideFull = false;
  bool fullscreen = false;
  bool vsync = true;
  List<String> hubs = [];
  String guestUsername = '';
  String usernameOverride = '';
  String engineOverride = '';
  bool clientLogs = false;
  List<String> filterTags = [];
  int filterMinPlayers = 0;
  int filterMaxPlayers = 0;
  List<Map<String, String>> acceptedPrivacy = [];

  final List<String> modsEnabled = [];
  List<ModEntry> mods = [];
  String modsPath = '';
  String logsPath = '';

  List<HubServer> hubServers = [];
  bool hubLoading = false;
  String hubError = '';
  Map<String, ServerPing> pings = {};

  bool loginBusy = false;
  String loginError = '';

  DownloadStateInfo downloadState = DownloadStateInfo.empty;
  bool connecting = false;

  String? pendingConnect;

  bool get isGuest => login != null && login!.token.isEmpty;

  String get effectiveUsername {
    if (isGuest) {
      final guest = guestUsername.trim();
      return guest.isEmpty ? 'Гость' : guest;
    }
    final override = usernameOverride.trim();
    if (override.isNotEmpty) {
      return override;
    }
    return login?.username ?? '';
  }

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
              .whereType<LoginInfo>()
              .where((account) => account.token.isNotEmpty),
        );
      favorites
        ..clear()
        ..addAll(
          ((config['favorites'] as List?) ?? const []).map(
            (value) =>
                GameServer.fromJson((value as Map).cast<String, dynamic>()),
          ),
        );
      theme = config['theme']?.toString() ?? 'system';
      hideEmpty = config['hide_empty'] == true;
      hideFull = config['hide_full'] == true;
      fullscreen = config['fullscreen'] == true;
      vsync = config['vsync'] != false;
      modsEnabled
        ..clear()
        ..addAll(
          ((config['mods_enabled'] as List?) ?? const [])
              .map((value) => value.toString()),
        );
      hubs = ((config['hubs'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList();
      guestUsername = config['guest_username']?.toString() ?? '';
      usernameOverride = config['username_override']?.toString() ?? '';
      engineOverride = config['engine_override']?.toString() ?? '';
      clientLogs = config['client_logs'] == true;
      filterTags = ((config['filter_tags'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList();
      filterMinPlayers = (config['filter_min_players'] as num?)?.toInt() ?? 0;
      filterMaxPlayers = (config['filter_max_players'] as num?)?.toInt() ?? 0;
      acceptedPrivacy = ((config['accepted_privacy'] as List?) ?? const [])
          .whereType<Map>()
          .map((entry) => {
                'identifier': entry['identifier']?.toString() ?? '',
                'version': entry['version']?.toString() ?? '',
              })
          .toList();
      if (login != null &&
          login!.token.isNotEmpty &&
          !_accountsContain(login!)) {
        accounts.insert(0, login!);
      }
    } else {
      configError = result['error']?.toString() ?? '';
    }
    notifyListeners();
    await _loadAuxDirs();
    _refreshSession();
  }

  bool _accountsContain(LoginInfo info) {
    return accounts.any((account) => account.username == info.username);
  }

  Future<void> _loadAuxDirs() async {
    final modsResult = await Isolate.run(Core.modsDir);
    if (modsResult['ok'] == true) {
      modsPath = modsResult['path']?.toString() ?? '';
    }
    final logsResult = await Isolate.run(Core.logsDir);
    if (logsResult['ok'] == true) {
      logsPath = logsResult['path']?.toString() ?? '';
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
      'hide_full': hideFull,
      'fullscreen': fullscreen,
      'vsync': vsync,
      'mods_enabled': modsEnabled,
      'hubs': hubs,
      'guest_username': guestUsername,
      'username_override': usernameOverride,
      'engine_override': engineOverride,
      'client_logs': clientLogs,
      'filter_tags': filterTags,
      'filter_min_players': filterMinPlayers,
      'filter_max_players': filterMaxPlayers,
      'accepted_privacy': acceptedPrivacy,
    });
    await Isolate.run(() => Core.saveConfig(payload));
  }

  bool privacyAccepted(ServerPrivacyInfo? policy) {
    if (policy == null) {
      return true;
    }
    return acceptedPrivacy.any(
      (entry) =>
          entry['identifier'] == policy.identifier &&
          entry['version'] == policy.version,
    );
  }

  void acceptPrivacy(ServerPrivacyInfo policy) {
    acceptedPrivacy.removeWhere(
      (entry) => entry['identifier'] == policy.identifier,
    );
    acceptedPrivacy.add({
      'identifier': policy.identifier,
      'version': policy.version,
    });
    saveConfig();
  }

  Future<void> _refreshSession() async {
    final current = login;
    if (current == null || current.token.isEmpty) {
      return;
    }
    final payload = jsonEncode({
      'auth_url':
          current.authServer.isEmpty ? Core.defaultAuthUrl : current.authServer,
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

  Future<void> loginAsGuest() async {
    final guest = guestUsername.trim();
    login = LoginInfo(
      token: '',
      username: guest.isEmpty ? 'Гость' : guest,
      userId: '',
      expireTime: '',
      authServer: '',
    );
    loginError = '';
    notifyListeners();
    await saveConfig();
  }

  Future<void> switchAccount(LoginInfo account) async {
    if (account.token.isEmpty) {
      await loginAsGuest();
      return;
    }
    if (login?.username == account.username && !isGuest) {
      return;
    }
    final payload = jsonEncode({
      'auth_url':
          account.authServer.isEmpty ? Core.defaultAuthUrl : account.authServer,
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
    login = null;
    accounts.removeWhere((account) => account.username == current.username);
    notifyListeners();
    await saveConfig();
    if (current.token.isEmpty) {
      return;
    }
    final payload = jsonEncode({
      'auth_url':
          current.authServer.isEmpty ? Core.defaultAuthUrl : current.authServer,
      'token': current.token,
    });
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
    favorites.add(
      GameServer(
        name: name.isEmpty ? url : name,
        url: url,
        raised: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    notifyListeners();
    saveConfig();
  }

  void editFavorite(String url, String newName, String newUrl) {
    final index = favorites.indexWhere((server) => server.url == url);
    if (index < 0) {
      return;
    }
    favorites[index] = GameServer(
      name: newName.isEmpty ? url : newName,
      url: newUrl.isEmpty ? url : newUrl,
      raised: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    saveConfig();
  }

  void raiseFavorite(String url) {
    final index = favorites.indexWhere((server) => server.url == url);
    if (index < 0) {
      return;
    }
    favorites[index] = favorites[index].copyWith(
      raised: DateTime.now().millisecondsSinceEpoch,
    );
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

  List<GameServer> get sortedFavorites {
    final list = List<GameServer>.from(favorites);
    list.sort((left, right) {
      final byRaised = right.raised.compareTo(left.raised);
      if (byRaised != 0) {
        return byRaised;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return list;
  }

  Future<void> loadHub() async {
    if (hubLoading) {
      return;
    }
    hubLoading = true;
    hubError = '';
    notifyListeners();
    final payload = jsonEncode(hubs);
    final result = await Isolate.run(() => Core.fetchServers(payload));
    hubLoading = false;
    if (result['ok'] == true) {
      hubServers = ((result['servers'] as List?) ?? const [])
          .map(HubServer.fromMap)
          .where((server) => !server.empty)
          .toList();
      hubServers.sort((left, right) => right.players.compareTo(left.players));
      notifyListeners();
      _pingVisible();
    } else {
      hubError = result['error']?.toString() ?? 'хаб недоступен';
    }
    notifyListeners();
  }

  Future<void> _pingVisible() async {
    final urls = hubServers.take(80).map((server) => server.address).toList();
    if (urls.isEmpty) {
      return;
    }
    final payload = jsonEncode(urls);
    final result = await Isolate.run(() => Core.pingServers(payload));
    if (result['ok'] == true) {
      final updated = <String, ServerPing>{};
      for (final ping in ((result['pings'] as List?) ?? const [])) {
        final parsed = ServerPing.fromMap(ping);
        if (parsed != null) {
          updated[parsed.url] = parsed;
        }
      }
      pings = updated;
      notifyListeners();
    }
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

  void setHideFull(bool value) {
    hideFull = value;
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

  void setGuestUsername(String value) {
    guestUsername = value;
    if (isGuest) {
      login = LoginInfo(
        token: '',
        username: value.trim().isEmpty ? 'Гость' : value.trim(),
        userId: '',
        expireTime: '',
        authServer: '',
      );
    }
    notifyListeners();
    saveConfig();
  }

  void setUsernameOverride(String value) {
    usernameOverride = value;
    notifyListeners();
    saveConfig();
  }

  void setEngineOverride(String value) {
    engineOverride = value;
    notifyListeners();
    saveConfig();
  }

  void setClientLogs(bool value) {
    clientLogs = value;
    notifyListeners();
    saveConfig();
  }

  void setHubs(List<String> value) {
    hubs = value;
    notifyListeners();
    saveConfig();
  }

  void setFilterTags(List<String> value) {
    filterTags = value;
    notifyListeners();
    saveConfig();
  }

  void setFilterPlayers(int min, int max) {
    filterMinPlayers = min;
    filterMaxPlayers = max;
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

  Future<void> openLogsDir() async {
    if (logsPath.isEmpty) {
      return;
    }
    await Isolate.run(() => Core.openPath(logsPath));
  }

  Future<String> configDirPath() async {
    final result = await Isolate.run(Core.configDir);
    return result['path']?.toString() ?? '';
  }

  Future<bool> clearCache() async {
    final result = await Isolate.run(Core.clearCache);
    return result['ok'] == true;
  }

  Future<Map<String, dynamic>> checkLauncherUpdate(String version) async {
    return Isolate.run(() => Core.checkUpdate(version));
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

  Future<Map<String, dynamic>> fetchInfo(String url) async {
    return Isolate.run(() => Core.fetchInfo(url));
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
    return modsEnabled.map((name) => '$modsPath$separator$name').toList();
  }

  Map<String, String?> _authFields(ServerFullInfo? info) {
    final authAllowed = info?.authUsable == true && !isGuest && login != null;
    return {
      'token': authAllowed ? login?.token : '',
      'userId': authAllowed ? login?.userId : '',
      'pubkey': authAllowed ? info?.authPublicKey : '',
      'server': authAllowed ? login?.authServer : '',
    };
  }

  Map<String, dynamic> _launchSpec({
    required String installDir,
    required String serverUrl,
    required ServerFullInfo? info,
    required bool acz,
    required List<String> overlays,
    required String connectAddress,
  }) {
    final auth = _authFields(info);
    final logDir = clientLogs && logsPath.isNotEmpty ? logsPath : '';
    final overrideZip = engineOverride.trim();
    final overrideFile =
        overrideZip.isNotEmpty && File(overrideZip).existsSync();
    final useOverride = acz && overrideFile;
    final engineZip =
        useOverride ? overrideZip : (acz ? downloadState.engineZip : '');
    final engineSig = useOverride ? '00' : (acz ? downloadState.engineSig : '');
    return {
      'install_dir': installDir,
      'args': _launchArgList(),
      'username': effectiveUsername,
      'server_url': serverUrl,
      'connect_address': connectAddress,
      'auth_token': auth['token'] ?? '',
      'auth_user_id': auth['userId'] ?? '',
      'auth_pubkey': auth['pubkey'] ?? '',
      'auth_server': auth['server'] ?? '',
      'build_download_url': info?.build.downloadUrl ?? '',
      'build_version': info?.build.version ?? '',
      'build_fork_id': info?.build.forkId ?? '',
      'build_hash': info?.build.hash ?? '',
      'build_engine_version': info?.build.engineVersion ?? '',
      'mode': acz ? 'acz' : 'zip',
      'loader_dir': acz ? loaderDir : '',
      'engine_zip': engineZip,
      'content_zip': acz ? downloadState.contentZip : '',
      'engine_sig': engineSig,
      'mods': acz ? overlays : [],
      'log_dir': logDir,
      'allow_unsigned': useOverride,
    };
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

  Future<Map<String, dynamic>> connectBundle(String zipPath) async {
    if (connecting) {
      return {'ok': false, 'error': 'подключение уже идёт'};
    }
    connecting = true;
    selectedServer = null;
    statusInfo = null;
    downloadState = DownloadStateInfo.empty;
    notifyListeners();
    final payload = jsonEncode({
      'bundle_zip': zipPath,
      'install_dir': installDir,
    });
    final started = await Isolate.run(() => Core.startDownload(payload));
    if (started['ok'] != true) {
      connecting = false;
      notifyListeners();
      return started;
    }
    return _pollDownload(null);
  }

  Future<Map<String, dynamic>> _pollDownload(GameServer? server) async {
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

  Future<Map<String, dynamic>> _launchAfterDownload(GameServer? server) async {
    final info = downloadState.info;
    final acz = downloadState.isAcz;
    final bundle = downloadState.bundleZip;
    final overlays = <String>[
      if (bundle.isNotEmpty) bundle,
      ...enabledModPaths(),
    ];
    final spec = _launchSpec(
      installDir: downloadState.installDir,
      serverUrl: server?.url ?? '',
      info: info,
      acz: acz,
      overlays: overlays,
      connectAddress: info?.connectAddress ?? '',
    );
    final result = await Isolate.run(() => Core.launch(jsonEncode(spec)));
    if (result['ok'] != true) {
      return result;
    }
    selectedServer = server;
    await saveConfig();
    return result;
  }

  Future<void> launchFromDirectory() async {
    final spec = _launchSpec(
      installDir: installDir,
      serverUrl: '',
      info: null,
      acz: false,
      overlays: const [],
      connectAddress: '',
    );
    await Isolate.run(() => Core.launch(jsonEncode(spec)));
  }
}
