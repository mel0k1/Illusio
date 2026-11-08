import '../l10n/strings.dart';

class ServerStatusInfo {
  const ServerStatusInfo({
    required this.name,
    required this.statusMessage,
    required this.tags,
    required this.playerCount,
    required this.softMaxPlayers,
  });

  final String name;
  final String statusMessage;
  final List<String> tags;
  final int playerCount;
  final int softMaxPlayers;

  static ServerStatusInfo? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return ServerStatusInfo(
      name: _string(raw['name']),
      statusMessage: _string(raw['statusMessage']),
      tags: ((raw['tags'] as List?) ?? const []).map(_string).toList(),
      playerCount: _int(raw['playerCount']),
      softMaxPlayers: _int(raw['softMaxPlayers']),
    );
  }

  static String _string(Object? value) => value?.toString() ?? '';

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String get cleanMessage =>
      statusMessage.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();

  String playersLabel(S s) => s.playersOf(playerCount, softMaxPlayers);
}
