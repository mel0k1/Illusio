import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef VersionNative = Pointer<Utf8> Function();
typedef TakeStringNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef FreeNative = Void Function(Pointer<Utf8>);

class Core {
  Core._();

  static const String defaultAuthUrl = 'https://auth.spacestation14.com/';

  static DynamicLibrary _open() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('illusio.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libillusio.dylib');
    }
    return DynamicLibrary.open('libillusio.so');
  }

  static final DynamicLibrary _lib = _open();
  static final Pointer<Utf8> Function() _version = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_version')
      .asFunction();
  static final Pointer<Utf8> Function() _configDir = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_config_dir')
      .asFunction();
  static final Pointer<Utf8> Function() _loadConfig = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_load_config')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _saveConfig = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_save_config')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _fetchStatus = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_fetch_status')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _launch = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_launch')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _fetchInfo = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_fetch_info')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _startDownload = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_start_download')
      .asFunction();
  static final Pointer<Utf8> Function() _downloadState = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_download_state')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _authenticate = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_authenticate')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _refreshLogin = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_refresh_login')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _checkToken = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_check_token')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _logout = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_logout')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _fetchServers = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_fetch_servers')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _openUrl = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_open_url')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _openPath = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_open_path')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _scanMods = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_scan_mods')
      .asFunction();
  static final Pointer<Utf8> Function() _modsDir = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_mods_dir')
      .asFunction();
  static final Pointer<Utf8> Function() _resPacksDir = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_res_packs_dir')
      .asFunction();
  static final Pointer<Utf8> Function() _dumpsDir = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_dumps_dir')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _listPacks = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_list_packs')
      .asFunction();
  static final Pointer<Utf8> Function() _clearCache = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_clear_cache')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _pingServers = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_ping_servers')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _checkUpdate = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_check_update')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _proxyProbe = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_proxy_probe')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _proxySession = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_proxy_session')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _contentState = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_content_state')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _updateCheck = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_update_check')
      .asFunction();
  static final Pointer<Utf8> Function(Pointer<Utf8>) _selfUpdate = _lib
      .lookup<NativeFunction<TakeStringNative>>('illusio_self_update')
      .asFunction();
  static final Pointer<Utf8> Function() _cullContent = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_cull_content')
      .asFunction();
  static final Pointer<Utf8> Function() _logsDir = _lib
      .lookup<NativeFunction<VersionNative>>('illusio_logs_dir')
      .asFunction();
  static final void Function(Pointer<Utf8>) _free = _lib
      .lookup<NativeFunction<FreeNative>>('illusio_free')
      .asFunction();

  static String version() {
    final result = _run(_version);
    final value = result['version'];
    return value is String ? value : '0.0.0';
  }

  static Map<String, dynamic> configDir() => _run(_configDir);

  static Map<String, dynamic> loadConfig() => _run(_loadConfig);

  static Map<String, dynamic> saveConfig(String json) =>
      _withString(json, _saveConfig);

  static Map<String, dynamic> fetchStatus(String url) =>
      _withString(url, _fetchStatus);

  static Map<String, dynamic> launch(String spec) => _withString(spec, _launch);

  static Map<String, dynamic> fetchInfo(String url) =>
      _withString(url, _fetchInfo);

  static Map<String, dynamic> startDownload(String spec) =>
      _withString(spec, _startDownload);

  static Map<String, dynamic> downloadState() => _run(_downloadState);

  static Map<String, dynamic> authenticate(String json) =>
      _withString(json, _authenticate);

  static Map<String, dynamic> refreshLogin(String json) =>
      _withString(json, _refreshLogin);

  static Map<String, dynamic> checkToken(String json) =>
      _withString(json, _checkToken);

  static Map<String, dynamic> logout(String json) => _withString(json, _logout);

  static Map<String, dynamic> fetchServers(String url) =>
      _withString(url, _fetchServers);

  static Map<String, dynamic> openUrl(String url) => _withString(url, _openUrl);

  static Map<String, dynamic> openPath(String path) =>
      _withString(path, _openPath);

  static Map<String, dynamic> scanMods(String dir) =>
      _withString(dir, _scanMods);

  static Map<String, dynamic> modsDir() => _run(_modsDir);

  static Map<String, dynamic> resPacksDir() => _run(_resPacksDir);

  static Map<String, dynamic> dumpsDir() => _run(_dumpsDir);

  static Map<String, dynamic> listPacks(String dir) =>
      _withString(dir, _listPacks);

  static Map<String, dynamic> clearCache() => _run(_clearCache);

  static Map<String, dynamic> pingServers(String json) =>
      _withString(json, _pingServers);

  static Map<String, dynamic> checkUpdate(String version) =>
      _withString(version, _checkUpdate);

  static Map<String, dynamic> logsDir() => _run(_logsDir);

  static Map<String, dynamic> proxyProbe(String json) =>
      _withString(json, _proxyProbe);

  static Map<String, dynamic> proxySession(String json) =>
      _withString(json, _proxySession);

  static Map<String, dynamic> contentState(String json) =>
      _withString(json, _contentState);

  static Map<String, dynamic> updateCheck(String json) =>
      _withString(json, _updateCheck);

  static Map<String, dynamic> selfUpdate(String json) =>
      _withString(json, _selfUpdate);

  static Map<String, dynamic> cullContent() => _run(_cullContent);

  static const String registerUrl =
      'https://account.spacestation14.com/Register';
  static const String forgotPasswordUrl =
      'https://account.spacestation14.com/ForgotPassword';
  static const String resendConfirmationUrl =
      'https://account.spacestation14.com/ResendEmailConfirmation';
  static const String manageAccountUrl =
      'https://account.spacestation14.com/Manage';

  static Map<String, dynamic> _withString(
    String value,
    Pointer<Utf8> Function(Pointer<Utf8>) call,
  ) {
    final native = value.toNativeUtf8(allocator: malloc);
    try {
      return _run(() => call(native));
    } finally {
      malloc.free(native);
    }
  }

  static Map<String, dynamic> _run(Pointer<Utf8> Function() call) {
    try {
      final pointer = call();
      if (pointer == nullptr) {
        return {'ok': false, 'error': 'core empty reply'};
      }
      final raw = pointer.toDartString();
      _free(pointer);
      return _decode(raw);
    } catch (error) {
      return {'ok': false, 'error': error.toString()};
    }
  }

  static Map<String, dynamic> _decode(String raw) {
    final decoded = _tryDecode(raw);
    return decoded ?? {'ok': false, 'error': 'core invalid reply'};
  }

  static Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
