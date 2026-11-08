import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef VersionNative = Pointer<Utf8> Function();
typedef TakeStringNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef FreeNative = Void Function(Pointer<Utf8>);

class Core {
  Core._();

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
        return {'ok': false, 'error': 'ядро вернуло пустой ответ'};
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
    return decoded ?? {'ok': false, 'error': 'ядро вернуло некорректный ответ'};
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
