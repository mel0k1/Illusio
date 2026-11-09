import '../l10n/strings.dart';

class HubServer {
  const HubServer({
    required this.address,
    required this.name,
    required this.players,
    required this.softMaxPlayers,
    required this.tags,
    required this.preset,
    required this.map,
    required this.runLevel,
    required this.roundId,
    required this.statusMessage,
    this.hub = '',
  });

  final String address;
  final String name;
  final int players;
  final int softMaxPlayers;
  final List<String> tags;
  final String preset;
  final String map;
  final int runLevel;
  final int roundId;
  final String statusMessage;
  final String hub;

  static String _string(Object? value) => value?.toString() ?? '';

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _strings(Object? value) =>
      ((value as List?) ?? const []).map(_string).toList();

  static HubServer fromMap(Object? raw) {
    if (raw is! Map) {
      return const HubServer(
        address: '',
        name: '',
        players: 0,
        softMaxPlayers: 0,
        tags: [],
        preset: '',
        map: '',
        runLevel: 0,
        roundId: 0,
        statusMessage: '',
      );
    }
    return HubServer(
      address: _string(raw['address']),
      name: _string(raw['name']),
      players: _int(raw['players']),
      softMaxPlayers: _int(raw['soft_max_players']),
      tags: _strings(raw['tags']),
      preset: _string(raw['preset']),
      map: _string(raw['map']),
      runLevel: _int(raw['run_level']),
      roundId: _int(raw['round_id']),
      statusMessage: _string(raw['status_message']),
      hub: _string(raw['hub']),
    );
  }

  bool get empty => address.isEmpty;

  bool get full => softMaxPlayers > 0 && players >= softMaxPlayers;

  String hubLabel(S s) => hub.isEmpty ? '' : s.hubPrefix(hub);

  String get playersLabel {
    if (softMaxPlayers <= 0) {
      return '$players';
    }
    return '$players/$softMaxPlayers';
  }

  String runLevelLabel(S s) {
    switch (runLevel) {
      case 0:
        return s.lobby;
      case 1:
        return s.inRound;
      case 2:
        return s.afterRound;
      default:
        return '';
    }
  }
}

class ServerPing {
  const ServerPing({
    required this.url,
    required this.pingMs,
    required this.online,
  });

  final String url;
  final int pingMs;
  final bool online;

  static ServerPing? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return ServerPing(
      url: raw['url']?.toString() ?? '',
      pingMs: (raw['ms'] as num?)?.toInt() ?? 0,
      online: raw['online'] == true,
    );
  }

  String label(S s) => online ? s.ms(pingMs) : '—';

  int get quality {
    if (!online) {
      return 3;
    }
    if (pingMs < 120) {
      return 0;
    }
    return pingMs < 220 ? 1 : 2;
  }
}

class ModEntry {
  const ModEntry({
    required this.fileName,
    required this.path,
    required this.size,
    required this.kind,
    required this.name,
    required this.description,
    required this.version,
    this.game = false,
    this.preload = false,
  });

  final String fileName;
  final String path;
  final int size;
  final String kind;
  final String name;
  final String description;
  final String version;
  final bool game;
  final bool preload;

  bool get isDll => kind == 'dll';

  bool get isGameMod => isDll && game;

  static ModEntry fromMap(Object? raw) {
    if (raw is! Map) {
      return const ModEntry(
        fileName: '',
        path: '',
        size: 0,
        kind: 'zip',
        name: '',
        description: '',
        version: '',
      );
    }
    return ModEntry(
      fileName: raw['file_name']?.toString() ?? '',
      path: raw['path']?.toString() ?? '',
      size: (raw['size'] as num?)?.toInt() ?? 0,
      kind: raw['kind']?.toString() ?? 'zip',
      name: raw['name']?.toString() ?? '',
      description: raw['description']?.toString() ?? '',
      version: raw['version']?.toString() ?? '',
      game: raw['game'] == true,
      preload: raw['preload'] == true,
    );
  }

  String sizeLabel(S s) => s.formatBytes(size);
}

class ResPackEntry {
  const ResPackEntry({
    required this.dirName,
    required this.path,
    required this.name,
    required this.description,
    required this.target,
    required this.files,
    required this.size,
    required this.valid,
  });

  final String dirName;
  final String path;
  final String name;
  final String description;
  final String target;
  final int files;
  final int size;
  final bool valid;

  static ResPackEntry fromMap(Object? raw) {
    if (raw is! Map) {
      return const ResPackEntry(
        dirName: '',
        path: '',
        name: '',
        description: '',
        target: '',
        files: 0,
        size: 0,
        valid: false,
      );
    }
    return ResPackEntry(
      dirName: raw['dir_name']?.toString() ?? '',
      path: raw['path']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
      description: raw['description']?.toString() ?? '',
      target: raw['target']?.toString() ?? '',
      files: (raw['files'] as num?)?.toInt() ?? 0,
      size: (raw['size'] as num?)?.toInt() ?? 0,
      valid: raw['valid'] == true,
    );
  }

  String sizeLabel(S s) => s.formatBytes(size);
}
