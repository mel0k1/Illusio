class GameServer {
  const GameServer({required this.name, required this.url});

  final String name;
  final String url;

  factory GameServer.fromJson(Map<String, dynamic> json) {
    return GameServer(
      name: (json['name'] as String?) ?? 'Сервер',
      url: (json['url'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
}
