import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../ffi/bindings.dart';
import '../models/server.dart';
import '../models/server_status.dart';

class AppController extends ChangeNotifier {
  AppController() {
    ready = _loadConfig();
  }

  late final Future<void> ready;

  final List<GameServer> servers = [];
  GameServer? selectedServer;
  ServerStatusInfo? statusInfo;
  bool loading = false;
  String loadError = '';
  String installDir = '';
  List<String> launchArgs = [];
  String configError = '';

  Future<void> _loadConfig() async {
    final result = await Isolate.run(Core.loadConfig);
    if (result['ok'] == true) {
      final config = (result['config'] as Map?) ?? const {};
      installDir = config['install_dir']?.toString() ?? '';
      launchArgs = ((config['launch_args'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList();
    } else {
      configError = result['error']?.toString() ?? '';
    }
    notifyListeners();
  }

  Future<void> saveConfig() async {
    final payload = jsonEncode({
      'install_dir': installDir,
      'launch_args': launchArgs,
      'last_server': selectedServer?.url ?? '',
    });
    await Isolate.run(() => Core.saveConfig(payload));
  }

  void addServer(String name, String url) {
    servers.add(GameServer(name: name, url: url));
    notifyListeners();
  }

  void removeServer(GameServer server) {
    servers.remove(server);
    if (identical(selectedServer, server)) {
      selectedServer = null;
      statusInfo = null;
      loadError = '';
    }
    notifyListeners();
  }

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

  Future<Map<String, dynamic>> launch() async {
    final spec = jsonEncode({'install_dir': installDir, 'args': launchArgs});
    return Isolate.run(() => Core.launch(spec));
  }
}
