import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ffi/bindings.dart';
import '../l10n/strings.dart';
import '../models/engine_entry.dart';
import '../models/hub_server.dart';
import '../models/login_info.dart';
import '../models/proxy_profile.dart';
import '../models/server.dart';
import '../models/server_info.dart';
import '../models/server_status.dart';
import '../version.dart';

class CrashInfo {
  const CrashInfo({required this.exitCode, required this.logTail});

  final int exitCode;
  final String logTail;
}

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

  String theme = 'dark';
  String language = 'ru';
  bool hideEmpty = false;
  bool hideFull = false;
  bool fullscreen = false;
  bool vsync = true;
  String dockSide = 'bottom';
  String corners = 'normal';
  String font = 'default';
  int customColor = 0;
  List<String> hubs = [];
  String guestUsername = '';
  String usernameOverride = '';
  String engineOverride = '';
  bool clientLogs = false;
  List<String> filterTags = [];
  int filterMinPlayers = 0;
  int filterMaxPlayers = 0;
  List<Map<String, String>> acceptedPrivacy = [];

  bool proxyEnabled = false;
  bool proxyUpdates = false;
  bool proxyRegionBypass = false;
  bool proxyUdpRelay = false;
  bool proxyApplyToGame = false;
  final List<ProxyProfileInfo> proxyProfiles = [];
  String proxySelected = '';
  bool proxyUnavailable = false;
  bool proxySessionOff = false;
  String proxyProbeError = '';

  bool autoUpdate = false;
  bool prefetchFavorites = false;
  bool patchHwid = false;
  bool patchRpc = false;
  bool patchJamDials = false;
  bool patchBlackhole = false;
  int hideLevel = 2;
  String hwidMode = 'off';
  String hwidValue = '';
  bool hwidOptout = false;
  bool dynamicPgo = true;
  bool backports = true;
  bool backportsNoAny = false;
  bool rpcFake = false;
  String rpcFakeName = 'Illusio';
  bool proxyGuardLaunch = true;
  bool patchless = false;
  bool stealthRegistries = false;
  bool skipPrivacy = false;
  bool throwPatchFail = false;
  bool noAutologin = false;
  bool patchFlyi = false;
  bool psDebug = false;
  bool adminGuid = false;
  String adminGuidValue = '';
  bool modLogs = false;
  List<String> filterHubs = [];
  bool updatePrerelease = false;
  bool cardMap = true;
  bool cardPreset = true;
  bool cardRound = true;
  int blobKeepDays = 7;
  int bundleKeep = 10;
  int engineKeep = 2;

  CrashInfo? crashDiag;

  String updateVersion = '';
  String updateNotes = '';
  bool updateBusy = false;
  bool updateCheckBusy = false;
  bool updateApplied = false;
  String updateError = '';
  List<Map<String, dynamic>> releases = [];
  bool releasesLoading = false;
  bool releasesBusy = false;
  bool releasesLoaded = false;
  bool releaseApplied = false;
  String releasesError = '';
  int installingRelease = -1;
  double releaseProgressValue = 0;
  String releaseProgressLabel = '';
  bool verifying = false;
  String verifyResult = '';
  String verifyError = '';
  Timer? _refreshTimer;
  Timer? _prefetchTimer;
  Timer? _ipcTimer;
  Timer? _crashTimer;
  bool _prefetchRunning = false;
  Future<void> _saveChain = Future.value();

  bool get ru => language != 'en';

  S get s => S(language);

  final List<String> modsEnabled = [];
  final List<String> dllModsEnabled = [];
  final List<String> subverterEnabled = [];
  final List<String> resPacksEnabled = [];
  List<ModEntry> mods = [];
  List<ResPackEntry> resPacks = [];
  List<EngineEntry> customEngines = [];
  String modsPath = '';
  String resPacksPath = '';
  String dumpsPath = '';
  String logsPath = '';
  String enginesPath = '';
  bool enginesBusy = false;
  String enginesError = '';
  bool dumpResources = false;

  List<HubServer> hubServers = [];
  bool hubLoading = false;
  String hubError = '';
  Map<String, ServerPing> pings = {};

  bool loginBusy = false;
  String loginError = '';

  DownloadStateInfo downloadState = DownloadStateInfo.empty;
  bool connecting = false;

  String? pendingConnect;

  bool launchGuardActive = false;
  String launchGuardError = '';
  GameServer? _launchGuardServer;

  bool get isGuest => login != null && login!.token.isEmpty;

  bool get dockIsBottom => dockSide == 'bottom';

  double get listBottomPad => dockIsBottom ? 110.0 : 28.0;

  String get effectiveUsername {
    if (isGuest) {
      final guest = guestUsername.trim();
      return guest.isEmpty ? (ru ? 'Гость' : 'Guest') : guest;
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
      theme = config['theme']?.toString() ?? 'dark';
      if (theme == 'system' || theme.isEmpty) {
        theme = 'dark';
      }
      dockSide = ['bottom', 'left', 'right']
              .contains(config['dock_side']?.toString())
          ? config['dock_side'].toString()
          : 'bottom';
      corners = ['compact', 'normal', 'round']
              .contains(config['corners']?.toString())
          ? config['corners'].toString()
          : 'normal';
      font = [
        'default',
        'system',
        'inter',
        'manrope',
        'nunito',
        'jetbrains',
      ].contains(config['font']?.toString())
          ? config['font'].toString()
          : 'default';
      customColor = (config['custom_color'] as num?)?.toInt() ?? 0;
      language = config['language']?.toString() ?? 'ru';
      hideEmpty = config['hide_empty'] == true;
      hideFull = config['hide_full'] == true;
      fullscreen = config['fullscreen'] == true;
      vsync = config['vsync'] != false;
      modsEnabled
        ..clear()
        ..addAll(
          ((config['mods_enabled'] as List?) ?? const []).map(
            (value) => value.toString(),
          ),
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
          .map(
            (entry) => {
              'identifier': entry['identifier']?.toString() ?? '',
              'version': entry['version']?.toString() ?? '',
            },
          )
          .toList();
      proxyEnabled = config['proxy_enabled'] == true;
      proxyUpdates = config['proxy_updates'] == true;
      proxyRegionBypass = config['proxy_region_bypass'] == true;
      proxyUdpRelay = config['proxy_udp_relay'] == true;
      proxyApplyToGame = config['proxy_apply_to_game'] == true;
      proxyProfiles
        ..clear()
        ..addAll(
          ((config['proxy_profiles'] as List?) ?? const [])
              .map((value) => ProxyProfileInfo.fromMap(value as Map?))
              .toList(),
        );
      proxySelected = config['proxy_selected']?.toString() ?? '';
      autoUpdate = config['auto_update'] == true;
      prefetchFavorites = config['prefetch_favorites'] == true;
      patchHwid = config['patch_hwid'] == true;
      patchRpc = config['patch_rpc'] == true;
      patchJamDials = config['patch_jam_dials'] == true;
      patchBlackhole = config['patch_blackhole'] == true;
      hideLevel = (config['hide_level'] as num?)?.toInt() ?? 2;
      hwidMode = config['hwid_mode']?.toString() ?? 'off';
      hwidValue = config['hwid_value']?.toString() ?? '';
      hwidOptout = config['hwid_optout'] == true;
      dynamicPgo = config['dynamic_pgo'] != false;
      backports = config['backports'] != false;
      backportsNoAny = config['backports_no_any'] == true;
      rpcFake = config['rpc_fake'] == true;
      rpcFakeName = config['rpc_fake_name']?.toString() ?? 'Illusio';
      proxyGuardLaunch = config['proxy_guard_launch'] != false;
      patchless = config['patchless'] == true;
      stealthRegistries = config['stealth_registries'] == true;
      skipPrivacy = config['skip_privacy'] == true;
      throwPatchFail = config['throw_patch_fail'] == true;
      noAutologin = config['no_autologin'] == true;
      patchFlyi = config['patch_flyi'] == true;
      psDebug = config['ps_debug'] == true;
      adminGuid = config['admin_guid'] == true;
      adminGuidValue = config['admin_guid_value']?.toString() ?? '';
      modLogs = config['mod_logs'] == true;
      filterHubs = ((config['filter_hubs'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList();
      updatePrerelease = config['update_prerelease'] == true;
      cardMap = config['card_map'] != false;
      cardPreset = config['card_preset'] != false;
      cardRound = config['card_round'] != false;
      blobKeepDays = (config['blob_keep_days'] as num?)?.toInt() ?? 7;
      bundleKeep = (config['bundle_keep'] as num?)?.toInt() ?? 10;
      engineKeep = (config['engine_keep'] as num?)?.toInt() ?? 2;
      dllModsEnabled
        ..clear()
        ..addAll(
          ((config['dll_mods_enabled'] as List?) ?? const []).map(
            (value) => value.toString(),
          ),
        );
      subverterEnabled
        ..clear()
        ..addAll(
          ((config['subverter_enabled'] as List?) ?? const []).map(
            (value) => value.toString(),
          ),
        );
      resPacksEnabled
        ..clear()
        ..addAll(
          ((config['res_packs_enabled'] as List?) ?? const []).map(
            (value) => value.toString(),
          ),
        );
      dumpResources = config['dump_resources'] == true;
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
    _startTimers();
    if (!noAutologin) {
      _refreshSession();
    }
    _checkProxyOnStartup();
    if (autoUpdate) {
      checkForUpdates(auto: true);
    }
  }

  void _startTimers() {
    _refreshTimer?.cancel();
    _prefetchTimer?.cancel();
    _ipcTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(hours: 12),
      (_) => _refreshSession(),
    );
    _prefetchTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => prefetchLoop(),
    );
    _ipcTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _pollIpc(),
    );
  }

  void _pollIpc() {
    if (connecting) {
      return;
    }
    final result = Core.ipcPoll();
    final url = result['url']?.toString() ?? '';
    if (url.isEmpty) {
      return;
    }
    pendingConnect = url;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _prefetchTimer?.cancel();
    _ipcTimer?.cancel();
    _crashTimer?.cancel();
    super.dispose();
  }

  void dismissCrash() {
    crashDiag = null;
    notifyListeners();
  }

  void _watchLaunch() {
    _crashTimer?.cancel();
    var checks = 0;
    _crashTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      checks++;
      final result = Core.launchStatus();
      final status = (result['status'] as Map?) ?? const {};
      if (status['crashed'] == true) {
        timer.cancel();
        crashDiag = CrashInfo(
          exitCode: (status['exitCode'] as num?)?.toInt() ?? -1,
          logTail: status['logTail']?.toString() ?? '',
        );
        notifyListeners();
      } else if (status['exited'] == true || checks >= 12) {
        timer.cancel();
      }
    });
  }

  DateTime? _expiry(String raw) {
    final parsed = DateTime.tryParse(raw.trim());
    return parsed?.toUtc();
  }

  bool _tokenExpiringSoon(LoginInfo account) {
    final expiry = _expiry(account.expireTime);
    if (expiry == null) {
      return true;
    }
    return expiry.difference(DateTime.now().toUtc()) <=
        const Duration(days: 15);
  }

  Future<bool> _refreshOne(LoginInfo account) async {
    final payload = jsonEncode({
      'auth_url': account.authServer.isEmpty
          ? Core.defaultAuthUrl
          : account.authServer,
      'username': account.username,
      'user_id': account.userId,
      'token': account.token,
      'hwid': account.hwid,
    });
    final result = await Isolate.run(() => Core.refreshLogin(payload));
    if (result['ok'] != true) {
      return false;
    }
    final updated = LoginInfo.fromMap(result['login']);
    if (updated == null) {
      return false;
    }
    final index = accounts.indexWhere(
      (value) => value.username == updated.username,
    );
    if (index >= 0) {
      accounts[index] = updated;
    }
    if (login?.username == updated.username) {
      login = updated;
    }
    return true;
  }

  Future<void> ensureFreshLogin() async {
    final current = login;
    if (current == null ||
        current.token.isEmpty ||
        !_tokenExpiringSoon(current)) {
      return;
    }
    await _refreshOne(current);
    await saveConfig();
    notifyListeners();
  }

  ProxyProfileInfo? get selectedProxyProfile {
    final id = proxySelected.trim();
    for (final profile in proxyProfiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return proxyProfiles.isEmpty ? null : proxyProfiles.first;
  }

  bool get proxyConfigured {
    final profile = selectedProxyProfile;
    if (profile == null || profile.host.trim().isEmpty || profile.port <= 0) {
      return false;
    }
    return proxyEnabled ||
        proxyUpdates ||
        proxyRegionBypass ||
        proxyUdpRelay ||
        proxyApplyToGame;
  }

  Future<void> _checkProxyOnStartup() async {
    if (!proxyConfigured) {
      return;
    }
    final result = await proxyProbe(proxyUdpRelay);
    if (result['ok'] == true) {
      return;
    }
    proxyProbeError = result['error']?.toString() ?? '';
    proxyUnavailable = true;
    notifyListeners();
  }

  void dismissProxyWarning() {
    proxyUnavailable = false;
    notifyListeners();
  }

  Future<void> continueWithoutProxy() async {
    proxyUnavailable = false;
    proxySessionOff = true;
    notifyListeners();
    await Isolate.run(() => Core.proxySession(jsonEncode({'enabled': false})));
  }

  Future<void> resumeProxySession() async {
    if (!proxySessionOff) {
      return;
    }
    proxySessionOff = false;
    notifyListeners();
    await Isolate.run(() => Core.proxySession(jsonEncode({'enabled': true})));
  }

  ProxyProfileInfo? proxyProbeTarget() {
    final profile = selectedProxyProfile;
    return profile;
  }

  bool _accountsContain(LoginInfo info) {
    return accounts.any((account) => account.username == info.username);
  }

  Future<void> _loadAuxDirs() async {
    final modsResult = await Isolate.run(Core.modsDir);
    if (modsResult['ok'] == true) {
      modsPath = modsResult['path']?.toString() ?? '';
    }
    final packsResult = await Isolate.run(Core.resPacksDir);
    if (packsResult['ok'] == true) {
      resPacksPath = packsResult['path']?.toString() ?? '';
    }
    final dumpsResult = await Isolate.run(Core.dumpsDir);
    if (dumpsResult['ok'] == true) {
      dumpsPath = dumpsResult['path']?.toString() ?? '';
    }
    final logsResult = await Isolate.run(Core.logsDir);
    if (logsResult['ok'] == true) {
      logsPath = logsResult['path']?.toString() ?? '';
    }
    await reloadEngines();
  }

  Future<void> reloadEngines() async {
    final result = await Isolate.run(Core.enginesList);
    if (result['ok'] == true) {
      enginesPath = result['dir']?.toString() ?? '';
      customEngines = ((result['engines'] as List?) ?? const [])
          .map(EngineEntry.fromMap)
          .toList();
    }
  }

  String engineZipPath(EngineEntry engine) {
    if (enginesPath.isEmpty) {
      return '';
    }
    final separator = Platform.isWindows ? '\\' : '/';
    return '$enginesPath$separator${engine.fileName}';
  }

  Future<void> importEngine(String path) async {
    if (enginesBusy || path.trim().isEmpty) {
      return;
    }
    enginesBusy = true;
    enginesError = '';
    notifyListeners();
    final result = await Isolate.run(
      () => Core.enginesImport(jsonEncode({'path': path.trim()})),
    );
    enginesBusy = false;
    if (result['ok'] == true) {
      await reloadEngines();
      final engine = result['engine'];
      if (engine is Map) {
        final id = engine['id']?.toString() ?? '';
        for (final entry in customEngines) {
          if (entry.id == id) {
            engineOverride = engineZipPath(entry);
          }
        }
      }
      await saveConfig();
    } else {
      enginesError = result['error']?.toString() ?? '';
    }
    notifyListeners();
  }

  Future<void> removeEngine(String id) async {
    if (enginesBusy || id.trim().isEmpty) {
      return;
    }
    enginesBusy = true;
    enginesError = '';
    notifyListeners();
    final removed = customEngines
        .where((engine) => engine.id == id.trim())
        .toList();
    final result = await Isolate.run(
      () => Core.enginesRemove(jsonEncode({'id': id.trim()})),
    );
    enginesBusy = false;
    if (result['ok'] == true) {
      final zip = removed.isEmpty ? '' : engineZipPath(removed.first);
      await reloadEngines();
      if (zip.isNotEmpty && engineOverride == zip) {
        engineOverride = '';
        await saveConfig();
      }
    } else {
      enginesError = result['error']?.toString() ?? '';
    }
    notifyListeners();
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
      'dock_side': dockSide,
      'corners': corners,
      'font': font,
      'custom_color': customColor,
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
      'language': language,
      'proxy_enabled': proxyEnabled,
      'proxy_updates': proxyUpdates,
      'proxy_region_bypass': proxyRegionBypass,
      'proxy_profiles': proxyProfiles.map((value) => value.toJson()).toList(),
      'proxy_selected': proxySelected,
      'proxy_udp_relay': proxyUdpRelay,
      'proxy_apply_to_game': proxyApplyToGame,
      'dll_mods_enabled': dllModsEnabled,
      'subverter_enabled': subverterEnabled,
      'res_packs_enabled': resPacksEnabled,
      'dump_resources': dumpResources,
      'auto_update': autoUpdate,
      'prefetch_favorites': prefetchFavorites,
      'patch_hwid': patchHwid,
      'patch_rpc': patchRpc,
      'patch_jam_dials': patchJamDials,
      'patch_blackhole': patchBlackhole,
      'hide_level': hideLevel,
      'hwid_mode': hwidMode,
      'hwid_value': hwidValue,
      'hwid_optout': hwidOptout,
      'dynamic_pgo': dynamicPgo,
      'backports': backports,
      'backports_no_any': backportsNoAny,
      'rpc_fake': rpcFake,
      'rpc_fake_name': rpcFakeName,
      'proxy_guard_launch': proxyGuardLaunch,
      'patchless': patchless,
      'stealth_registries': stealthRegistries,
      'admin_guid': adminGuid,
      'admin_guid_value': adminGuidValue,
      'mod_logs': modLogs,
      'skip_privacy': skipPrivacy,
      'throw_patch_fail': throwPatchFail,
      'no_autologin': noAutologin,
      'patch_flyi': patchFlyi,
      'ps_debug': psDebug,
      'filter_hubs': filterHubs,
      'update_prerelease': updatePrerelease,
      'card_map': cardMap,
      'card_preset': cardPreset,
      'card_round': cardRound,
      'blob_keep_days': blobKeepDays,
      'bundle_keep': bundleKeep,
      'engine_keep': engineKeep,
    });
    final task = _saveChain.then(
      (_) => Isolate.run(() => Core.saveConfig(payload)),
    );
    _saveChain = task.catchError((Object _) {});
    await task;
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
    final expiring = [
      if (login != null && login!.token.isNotEmpty) login!,
      ...accounts.where(
        (account) =>
            account.token.isNotEmpty &&
            account.username != login?.username &&
            _tokenExpiringSoon(account),
      ),
    ];
    var changed = false;
    for (final account in expiring) {
      final ok = await _refreshOne(account);
      changed = changed || ok;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (changed) {
      await saveConfig();
      notifyListeners();
    }
  }

  Future<void> prefetchLoop() async {
    if (_prefetchRunning || connecting || !prefetchFavorites) {
      return;
    }
    if (downloadState.running) {
      return;
    }
    _prefetchRunning = true;
    try {
      for (final server in List<GameServer>.from(sortedFavorites)) {
        if (!prefetchFavorites || connecting || downloadState.running) {
          break;
        }
        final state = await Isolate.run(
          () => Core.contentState(
            jsonEncode({'server_url': server.url, 'install_dir': installDir}),
          ),
        );
        if (state['ok'] != true || state['actual'] == true) {
          continue;
        }
        if (!await _favoritePrivacyAccepted(server.url)) {
          continue;
        }
        await _backgroundDownload(server);
      }
    } finally {
      _prefetchRunning = false;
    }
  }

  Future<bool> _favoritePrivacyAccepted(String url) async {
    final result = await Isolate.run(() => Core.fetchInfo(url));
    if (result['ok'] != true) {
      return false;
    }
    final info = ServerFullInfo.fromMap(result['info']);
    if (info == null) {
      return false;
    }
    return privacyAccepted(info.privacyPolicy);
  }

  Future<void> _backgroundDownload(GameServer server) async {
    final payload = jsonEncode({
      'server_url': server.url,
      'install_dir': installDir,
    });
    final started = await Isolate.run(() => Core.startDownload(payload));
    if (started['ok'] != true) {
      return;
    }
    var bad = 0;
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final result = await Isolate.run(Core.downloadState);
      if (result['ok'] != true) {
        bad++;
        if (bad >= 40) {
          return;
        }
        continue;
      }
      bad = 0;
      downloadState = DownloadStateInfo.fromMap(result['state']);
      notifyListeners();
      if (downloadState.isDone || downloadState.isError) {
        return;
      }
    }
  }

  Future<Map<String, dynamic>> authenticate(
    String username,
    String password,
    String tfaCode,
  ) async {
    if (loginBusy) {
      return {'ok': false, 'error': s.busyRequest};
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
        loginError = s.authIncomplete;
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
      loginError = result['error']?.toString() ?? s.authFailed;
    }
    notifyListeners();
    return result;
  }

  Future<void> loginAsGuest() async {
    final guest = guestUsername.trim();
    login = LoginInfo(
      token: '',
      username: guest.isEmpty ? (ru ? 'Гость' : 'Guest') : guest,
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
      'auth_url': account.authServer.isEmpty
          ? Core.defaultAuthUrl
          : account.authServer,
      'username': account.username,
      'user_id': account.userId,
      'token': account.token,
      'hwid': account.hwid,
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
      'auth_url': current.authServer.isEmpty
          ? Core.defaultAuthUrl
          : current.authServer,
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
      hubServers.sort((left, right) {
        final byPlayers = right.players.compareTo(left.players);
        if (byPlayers != 0) {
          return byPlayers;
        }
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
      notifyListeners();
      _pingVisible();
    } else {
      hubError = result['error']?.toString() ?? s.hubUnavailable;
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

  void setLanguage(String value) {
    language = value;
    notifyListeners();
    saveConfig();
  }

  void setDockSide(String value) {
    dockSide = ['bottom', 'left', 'right'].contains(value) ? value : 'bottom';
    notifyListeners();
    saveConfig();
  }

  void setCorners(String value) {
    corners = ['compact', 'normal', 'round'].contains(value) ? value : 'normal';
    notifyListeners();
    saveConfig();
  }

  void setFont(String value) {
    font = [
      'default',
      'system',
      'inter',
      'manrope',
      'nunito',
      'jetbrains',
    ].contains(value)
        ? value
        : 'default';
    notifyListeners();
    saveConfig();
  }

  void setCustomColor(int value) {
    customColor = value & 0xFFFFFF;
    notifyListeners();
    saveConfig();
  }

  void setProxyEnabled(bool value) {
    proxyEnabled = value;
    notifyListeners();
    resumeProxySession();
    saveConfig();
  }

  void setProxyUpdates(bool value) {
    proxyUpdates = value;
    notifyListeners();
    resumeProxySession();
    saveConfig();
  }

  void setProxyRegionBypass(bool value) {
    proxyRegionBypass = value;
    notifyListeners();
    resumeProxySession();
    saveConfig();
  }

  void setProxyUdpRelay(bool value) {
    proxyUdpRelay = value;
    notifyListeners();
    resumeProxySession();
    saveConfig();
  }

  void setProxyApplyToGame(bool value) {
    proxyApplyToGame = value;
    notifyListeners();
    resumeProxySession();
    saveConfig();
  }

  void selectProxyProfile(String id) {
    proxySelected = id;
    notifyListeners();
    resumeProxySession();
    saveConfig();
  }

  void upsertProxyProfile(ProxyProfileInfo profile) {
    final index = proxyProfiles.indexWhere((value) => value.id == profile.id);
    if (index >= 0) {
      proxyProfiles[index] = profile;
    } else {
      proxyProfiles.add(profile);
    }
    if (proxySelected.trim().isEmpty) {
      proxySelected = profile.id;
    }
    notifyListeners();
    resumeProxySession();
    saveConfig();
  }

  void removeProxyProfile(String id) {
    proxyProfiles.removeWhere((value) => value.id == id);
    if (proxySelected == id) {
      proxySelected = proxyProfiles.isEmpty ? '' : proxyProfiles.first.id;
    }
    notifyListeners();
    resumeProxySession();
    saveConfig();
  }

  void setAutoUpdate(bool value) {
    autoUpdate = value;
    notifyListeners();
    saveConfig();
  }

  void setPrefetchFavorites(bool value) {
    prefetchFavorites = value;
    notifyListeners();
    saveConfig();
  }

  void setPatchHwid(bool value) {
    patchHwid = value;
    notifyListeners();
    saveConfig();
  }

  void setPatchRpc(bool value) {
    patchRpc = value;
    notifyListeners();
    saveConfig();
  }

  void setPatchJamDials(bool value) {
    patchJamDials = value;
    notifyListeners();
    saveConfig();
  }

  void setPatchBlackhole(bool value) {
    patchBlackhole = value;
    notifyListeners();
    saveConfig();
  }

  void setHideLevel(int value) {
    hideLevel = value.clamp(0, 4);
    notifyListeners();
    saveConfig();
  }

  void setHwidMode(String value) {
    hwidMode = value;
    notifyListeners();
    saveConfig();
  }

  void setHwidValue(String value) {
    hwidValue = value.trim().toLowerCase();
    notifyListeners();
    saveConfig();
  }

  void setHwidOptout(bool value) {
    hwidOptout = value;
    notifyListeners();
    saveConfig();
  }

  void setDynamicPgo(bool value) {
    dynamicPgo = value;
    notifyListeners();
    saveConfig();
  }

  bool get hwidValueValid {
    final value = hwidValue.trim().toLowerCase().replaceFirst(RegExp('^0x'), '');
    if (value.isEmpty) {
      return true;
    }
    if (value.length.isOdd || value.length > 128) {
      return false;
    }
    return RegExp('^[0-9a-f]+\$').hasMatch(value);
  }

  String generateHwid() {
    final random = Random.secure();
    const digits = '0123456789abcdef';
    return List.generate(64, (_) => digits[random.nextInt(16)]).join();
  }

  Future<void> ensureAccountHwid() async {
    if (hwidMode != 'account' || isGuest || login == null) {
      return;
    }
    if (login!.hwid.trim().isNotEmpty) {
      return;
    }
    final hwid = generateHwid();
    final updated = LoginInfo(
      token: login!.token,
      username: login!.username,
      userId: login!.userId,
      expireTime: login!.expireTime,
      authServer: login!.authServer,
      hwid: hwid,
    );
    login = updated;
    final index = accounts.indexWhere(
      (element) => element.username == updated.username,
    );
    if (index >= 0) {
      accounts[index] = updated;
    }
    await saveConfig();
  }

  Future<void> checkForUpdates({bool auto = false}) async {
    if (updateBusy || updateCheckBusy) {
      return;
    }
    updateCheckBusy = true;
    if (!auto) {
      notifyListeners();
    }
    try {
      final payload = jsonEncode({'current': appVersion, 'prerelease': updatePrerelease});
      final result = await Isolate.run(() => Core.updateCheck(payload));
      if (result['ok'] != true) {
        if (!auto) {
          updateError = result['error']?.toString() ?? '';
        }
        return;
      }
      updateError = '';
      if (result['available'] == true) {
        updateVersion = result['version']?.toString() ?? '';
        updateNotes = result['notes']?.toString() ?? '';
        if (auto) {
          await applyUpdate();
          return;
        }
      } else {
        updateVersion = '';
        updateNotes = '';
      }
    } finally {
      updateCheckBusy = false;
      notifyListeners();
    }
  }

  Future<void> applyUpdate() async {
    if (updateBusy || updateVersion.isEmpty) {
      return;
    }
    updateBusy = true;
    updateError = '';
    notifyListeners();
    final payload = jsonEncode({'current': appVersion, 'prerelease': updatePrerelease});
    final result = await Isolate.run(() => Core.selfUpdate(payload));
    updateBusy = false;
    if (result['ok'] == true && result['updated'] == true) {
      updateApplied = true;
    } else if (result['ok'] != true) {
      updateError = result['error']?.toString() ?? '';
    }
    notifyListeners();
  }

  Future<void> loadReleases() async {
    if (releasesLoading || releasesBusy) {
      return;
    }
    releasesLoading = true;
    releasesError = '';
    notifyListeners();
    final payload = jsonEncode({'current': appVersion, 'prerelease': updatePrerelease});
    final result = await Isolate.run(() => Core.releasesList(payload));
    releasesLoading = false;
    if (result['ok'] == true) {
      final list = result['releases'];
      releases = list is List
          ? list
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
          : [];
      releasesLoaded = true;
      releaseApplied = false;
    } else {
      releasesError = result['error']?.toString() ?? '';
    }
    notifyListeners();
  }

  Future<void> installRelease(int index) async {
    if (releasesBusy || updateBusy || index < 0 || index >= releases.length) {
      return;
    }
    final release = releases[index];
    final url = release['assetUrl']?.toString() ?? '';
    final name = release['assetName']?.toString() ?? '';
    if (url.isEmpty || name.isEmpty) {
      return;
    }
    releasesBusy = true;
    installingRelease = index;
    releaseProgressValue = 0;
    releaseProgressLabel = '';
    releasesError = '';
    notifyListeners();
    final poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final snap = Core.releaseProgress();
      if (snap['ok'] != true) {
        return;
      }
      final state = snap['state'];
      if (state is! Map) {
        return;
      }
      final total = (state['total'] as num?)?.toInt() ?? 0;
      final downloaded = (state['downloaded'] as num?)?.toInt() ?? 0;
      releaseProgressValue = total > 0
          ? (downloaded / total).clamp(0.0, 1.0).toDouble()
          : 0;
      releaseProgressLabel = state['message']?.toString() ?? '';
      notifyListeners();
    });
    try {
      final payload = jsonEncode({'url': url, 'name': name});
      final result = await Isolate.run(() => Core.releaseInstall(payload));
      if (result['ok'] == true) {
        releaseApplied = true;
      } else {
        releasesError = result['error']?.toString() ?? '';
      }
    } finally {
      poll.cancel();
      releasesBusy = false;
      installingRelease = -1;
      releaseProgressLabel = '';
      notifyListeners();
    }
  }

  Future<void> verifyFiles() async {
    if (verifying || downloadState.running) {
      return;
    }
    verifying = true;
    verifyResult = '';
    verifyError = '';
    notifyListeners();
    final payload = jsonEncode({
      'server_url': selectedServer?.url ?? '',
      'install_dir': installDir,
    });
    try {
      final started = await Isolate.run(() => Core.startVerify(payload));
      if (started['ok'] != true) {
        verifyError = started['error']?.toString() ?? '';
        return;
      }
      var bad = 0;
      var polls = 0;
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        polls++;
        if (polls > 6750) {
          verifyError = s.verifyStuck;
          break;
        }
        final result = await Isolate.run(Core.downloadState);
        if (result['ok'] != true) {
          bad++;
          if (bad >= 25) {
            verifyError = s.verifyStuck;
            break;
          }
          continue;
        }
        bad = 0;
        downloadState = DownloadStateInfo.fromMap(result['state']);
        notifyListeners();
        if (downloadState.isDone || downloadState.isError) {
          break;
        }
      }
      if (downloadState.isDone) {
        verifyResult = downloadState.message;
      } else if (downloadState.isError && verifyError.isEmpty) {
        verifyError = downloadState.error;
      }
    } finally {
      verifying = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> proxyProbe(bool udp) async {
    final profile = selectedProxyProfile;
    final payload = jsonEncode({
      'host': profile?.host ?? '',
      'port': profile?.port ?? 0,
      'username': profile?.username ?? '',
      'password': profile?.password ?? '',
      'udp': udp,
    });
    return Isolate.run(() => Core.proxyProbe(payload));
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
        username: value.trim().isEmpty
            ? (ru ? 'Гость' : 'Guest')
            : value.trim(),
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
    final result = await Isolate.run(
      () => Core.scanMods(
        jsonEncode({'path': modsPath, 'loader_dir': loaderDir}),
      ),
    );
    if (result['ok'] == true) {
      mods = ((result['mods'] as List?) ?? const [])
          .map(ModEntry.fromMap)
          .toList();
      modsEnabled.removeWhere(
        (name) => !mods.any((entry) => entry.fileName == name),
      );
      dllModsEnabled.removeWhere(
        (name) => !mods.any((entry) => entry.path == name),
      );
      subverterEnabled.removeWhere(
        (name) => !mods.any((entry) => entry.path == name && entry.isGameMod),
      );
      notifyListeners();
    }
    await loadResPacks();
  }

  Future<void> loadResPacks() async {
    if (resPacksPath.isEmpty) {
      return;
    }
    final result = await Isolate.run(() => Core.listPacks(resPacksPath));
    if (result['ok'] == true) {
      resPacks = ((result['packs'] as List?) ?? const [])
          .map(ResPackEntry.fromMap)
          .toList();
      resPacksEnabled.removeWhere(
        (name) => !resPacks.any((pack) => pack.dirName == name),
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

  void toggleDllMod(String path) {
    if (dllModsEnabled.contains(path)) {
      dllModsEnabled.remove(path);
    } else {
      dllModsEnabled.add(path);
    }
    notifyListeners();
    saveConfig();
  }

  void toggleSubverter(String path) {
    if (subverterEnabled.contains(path)) {
      subverterEnabled.remove(path);
    } else {
      subverterEnabled.add(path);
    }
    notifyListeners();
    saveConfig();
  }

  void toggleResPack(String dirName) {
    if (resPacksEnabled.contains(dirName)) {
      resPacksEnabled.remove(dirName);
    } else {
      resPacksEnabled.add(dirName);
    }
    notifyListeners();
    saveConfig();
  }

  void setDumpResources(bool value) {
    dumpResources = value;
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

  Future<void> openResPacksDir() async {
    if (resPacksPath.isEmpty) {
      return;
    }
    await Isolate.run(() => Core.openPath(resPacksPath));
  }

  Future<void> openDumpsDir() async {
    if (dumpsPath.isEmpty) {
      return;
    }
    await Isolate.run(() => Core.openPath(dumpsPath));
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
      loadError = result['error']?.toString() ?? s.serverNotResponding;
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

  List<String> enabledDllPaths() {
    return dllModsEnabled.where((path) => File(path).existsSync()).toList();
  }

  List<String> enabledSubverterPaths() {
    return subverterEnabled.where((path) => File(path).existsSync()).toList();
  }

  List<String> enabledResPackPaths() {
    if (resPacksPath.isEmpty) {
      return const [];
    }
    final separator = Platform.isWindows ? '\\' : '/';
    return resPacksEnabled
        .map((name) => '$resPacksPath$separator$name')
        .where((path) => File('$path${separator}meta.json').existsSync())
        .toList();
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
    required List<String> modules,
  }) {
    final auth = _authFields(info);
    final logDir = clientLogs && logsPath.isNotEmpty ? logsPath : '';
    final overrideZip = engineOverride.trim();
    final overrideFile =
        overrideZip.isNotEmpty && File(overrideZip).existsSync();
    final useOverride = acz && overrideFile;
    final engineZip = useOverride
        ? overrideZip
        : (acz ? downloadState.engineZip : '');
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
      'mod_dlls': acz ? enabledDllPaths() : [],
      'subverters': acz ? enabledSubverterPaths() : [],
      'res_packs': acz ? enabledResPackPaths() : [],
      'dump_resources': acz && dumpResources,
      'log_dir': logDir,
      'allow_unsigned': useOverride,
      'patch_hwid': patchHwid,
      'patch_rpc': patchRpc,
      'patch_jam_dials': patchJamDials,
      'patch_blackhole': patchBlackhole,
      'hide_level': hideLevel,
      'hwid_mode': hwidMode,
      'hwid_value': hwidMode == 'account' ? (login?.hwid ?? '') : hwidValue,
      'hwid_optout': hwidOptout,
      'dynamic_pgo': dynamicPgo,
      'backports': backports,
      'backports_no_any': backportsNoAny,
      'rpc_fake': rpcFake,
      'rpc_fake_name': rpcFakeName,
      'patchless': patchless,
      'stealth_registries': stealthRegistries,
      'admin_guid': adminGuid,
      'admin_guid_value': adminGuidValue,
      'throw_patch_fail': throwPatchFail,
      'patch_flyi': patchFlyi,
      'ps_debug': psDebug,
      'mod_logs': modLogs,
      'modules': modules,
    };
  }

  Future<Map<String, dynamic>> connect(GameServer server) async {
    if (connecting || verifying || downloadState.running) {
      return {'ok': false, 'error': s.connectBusy};
    }
    connecting = true;
    selectedServer = server;
    downloadState = DownloadStateInfo.empty;
    notifyListeners();

    await ensureAccountHwid();
    await ensureFreshLogin();

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
        error: started['error']?.toString() ?? s.downloadStartFailed,
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
    if (connecting || verifying || downloadState.running) {
      return {'ok': false, 'error': s.connectBusy};
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
    var bad = 0;
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final result = await Isolate.run(Core.downloadState);
      if (result['ok'] != true) {
        bad++;
        if (bad >= 40) {
          connecting = false;
          notifyListeners();
          return {'ok': false, 'error': s.downloadLost};
        }
        continue;
      }
      bad = 0;
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

  Future<String?> _proxyGuardProbe() async {
    if (!proxyGuardLaunch || !proxyConfigured || proxySessionOff) {
      return null;
    }
    if (!proxyApplyToGame) {
      return null;
    }
    final probe = await proxyProbe(proxyUdpRelay);
    if (probe['ok'] == true) {
      return null;
    }
    return probe['error']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> _launchAfterDownload(GameServer? server) async {
    final guardError = await _proxyGuardProbe();
    if (guardError != null) {
      launchGuardError = guardError;
      launchGuardActive = true;
      _launchGuardServer = server;
      notifyListeners();
      return {'ok': false, 'error': s.proxyGuardBlocked};
    }
    final info = downloadState.info;
    final acz = downloadState.isAcz;
    final bundle = downloadState.bundleZip;
    final overlays = <String>[
      if (bundle.isNotEmpty) bundle,
      ...enabledModPaths(),
    ];
    var modules = downloadState.modules;
    final overrideZip = engineOverride.trim();
    if (acz && overrideZip.isNotEmpty && File(overrideZip).existsSync()) {
      final result = await Isolate.run(
        () => Core.engineModules(jsonEncode({'path': overrideZip})),
      );
      if (result['ok'] == true) {
        modules = ((result['modules'] as List?) ?? const [])
            .map((value) => value.toString())
            .toList();
      }
    }
    final spec = _launchSpec(
      installDir: downloadState.installDir,
      serverUrl: server?.url ?? '',
      info: info,
      acz: acz,
      overlays: overlays,
      connectAddress: info?.connectAddress ?? '',
      modules: modules,
    );
    final result = await Isolate.run(() => Core.launch(jsonEncode(spec)));
    if (result['ok'] != true) {
      return result;
    }
    selectedServer = server;
    _watchLaunch();
    await saveConfig();
    return result;
  }

  Future<Map<String, dynamic>> launchGuardContinue() async {
    final server = _launchGuardServer;
    launchGuardActive = false;
    launchGuardError = '';
    _launchGuardServer = null;
    notifyListeners();
    await continueWithoutProxy();
    return _launchAfterDownload(server);
  }

  Future<void> launchGuardCancel() async {
    launchGuardActive = false;
    launchGuardError = '';
    _launchGuardServer = null;
    connecting = false;
    downloadState = DownloadStateInfo.empty;
    notifyListeners();
  }

  Future<void> launchFromDirectory() async {
    final spec = _launchSpec(
      installDir: installDir,
      serverUrl: '',
      info: null,
      acz: false,
      overlays: const [],
      connectAddress: '',
      modules: const [],
    );
    final result = await Isolate.run(() => Core.launch(jsonEncode(spec)));
    if (result['ok'] == true) {
      _watchLaunch();
    }
  }

  void setBackports(bool value) {
    backports = value;
    notifyListeners();
    saveConfig();
  }

  void setBackportsNoAny(bool value) {
    backportsNoAny = value;
    notifyListeners();
    saveConfig();
  }

  void setRpcFake(bool value) {
    rpcFake = value;
    notifyListeners();
    saveConfig();
  }

  void setRpcFakeName(String value) {
    rpcFakeName = value;
    notifyListeners();
    saveConfig();
  }

  void setProxyGuardLaunch(bool value) {
    proxyGuardLaunch = value;
    notifyListeners();
    saveConfig();
  }

  void setPatchless(bool value) {
    patchless = value;
    notifyListeners();
    saveConfig();
  }

  void setSkipPrivacy(bool value) {
    skipPrivacy = value;
    notifyListeners();
    saveConfig();
  }

  void setThrowPatchFail(bool value) {
    throwPatchFail = value;
    notifyListeners();
    saveConfig();
  }

  void setNoAutologin(bool value) {
    noAutologin = value;
    notifyListeners();
    saveConfig();
  }

  void setPatchFlyi(bool value) {
    patchFlyi = value;
    notifyListeners();
    saveConfig();
  }

  void setPsDebug(bool value) {
    psDebug = value;
    notifyListeners();
    saveConfig();
  }

  void setStealthRegistries(bool value) {
    stealthRegistries = value;
    notifyListeners();
    saveConfig();
  }

  void setAdminGuid(bool value) {
    adminGuid = value;
    notifyListeners();
    saveConfig();
  }

  void setAdminGuidValue(String value) {
    adminGuidValue = value.trim();
    notifyListeners();
    saveConfig();
  }

  void setModLogs(bool value) {
    modLogs = value;
    notifyListeners();
    saveConfig();
  }

  void setFilterHubs(List<String> value) {
    filterHubs = value;
    notifyListeners();
    saveConfig();
  }

  void setUpdatePrerelease(bool value) {
    updatePrerelease = value;
    notifyListeners();
    saveConfig();
  }

  void setCardMap(bool value) {
    cardMap = value;
    notifyListeners();
    saveConfig();
  }

  void setCardPreset(bool value) {
    cardPreset = value;
    notifyListeners();
    saveConfig();
  }

  void setCardRound(bool value) {
    cardRound = value;
    notifyListeners();
    saveConfig();
  }

  Map<String, dynamic> themeProfile() {
    return {
      'version': 1,
      'app': 'illusio',
      'theme': theme,
      'custom_color': customColor,
      'corners': corners,
      'font': font,
      'dock_side': dockSide,
    };
  }

  Future<void> exportTheme(String path) async {
    final raw = const JsonEncoder.withIndent('  ').convert(themeProfile());
    await File(path).writeAsString('$raw\n');
  }

  Future<bool> importTheme(String path) async {
    final raw = await File(path).readAsString();
    final Object? data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return false;
    }
    if (data is! Map) {
      return false;
    }
    const presets = [
      'dark',
      'darkRed',
      'darkPurple',
      'midnightBlue',
      'emeraldDusk',
      'copperNight',
      'light',
      'custom',
    ];
    const cornerValues = ['compact', 'normal', 'round'];
    const fontValues = ['default', 'system', 'inter', 'manrope', 'nunito', 'jetbrains'];
    const dockValues = ['bottom', 'left', 'right'];
    final preset = data['theme']?.toString() ?? '';
    if (!presets.contains(preset)) {
      return false;
    }
    theme = preset;
    final color = (data['custom_color'] as num?)?.toInt();
    if (color != null) {
      customColor = color & 0xFFFFFF;
    }
    final cornerValue = data['corners']?.toString() ?? '';
    if (cornerValues.contains(cornerValue)) {
      corners = cornerValue;
    }
    final fontValue = data['font']?.toString() ?? '';
    if (fontValues.contains(fontValue)) {
      font = fontValue;
    }
    final dockValue = data['dock_side']?.toString() ?? '';
    if (dockValues.contains(dockValue)) {
      dockSide = dockValue;
    }
    notifyListeners();
    await saveConfig();
    return true;
  }
}
