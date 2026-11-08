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

  String get hubLabel => hub.isEmpty ? '' : 'хаб $hub';

  String get playersLabel {
    if (softMaxPlayers <= 0) {
      return '$players';
    }
    return '$players/$softMaxPlayers';
  }

  String get runLevelLabel {
    switch (runLevel) {
      case 0:
        return 'Лобби';
      case 1:
        return 'В раунде';
      case 2:
        return 'После раунда';
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

  String get label => online ? '$pingMs мс' : '—';

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
  });

  final String fileName;
  final String path;
  final int size;

  static ModEntry fromMap(Object? raw) {
    if (raw is! Map) {
      return const ModEntry(fileName: '', path: '', size: 0);
    }
    return ModEntry(
      fileName: raw['file_name']?.toString() ?? '',
      path: raw['path']?.toString() ?? '',
      size: (raw['size'] as num?)?.toInt() ?? 0,
    );
  }

  String get sizeLabel => HubServerFormats.formatBytes(size);
}

class HubServerFormats {
  const HubServerFormats._();

  static String formatBytes(int bytes) {
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final shown = value >= 100
        ? value.round().toString()
        : value.toStringAsFixed(value >= 10 ? 1 : 2);
    return '$shown ${units[unit]}';
  }
}
