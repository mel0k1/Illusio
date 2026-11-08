class GameServer {
  const GameServer({required this.name, required this.url, this.raised = 0});

  final String name;
  final String url;
  final int raised;

  factory GameServer.fromJson(Map<String, dynamic> json) {
    return GameServer(
      name: (json['name'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      raised: (json['raised'] as num?)?.toInt() ?? 0,
    );
  }

  GameServer copyWith({String? name, int? raised}) {
    return GameServer(
      name: name ?? this.name,
      url: url,
      raised: raised ?? this.raised,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'raised': raised};
}
