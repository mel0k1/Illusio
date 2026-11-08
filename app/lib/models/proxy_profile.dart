class ProxyProfileInfo {
  const ProxyProfileInfo({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  factory ProxyProfileInfo.fromMap(Map? map) {
    final value = map ?? const {};
    return ProxyProfileInfo(
      id: value['id']?.toString() ?? '',
      name: value['name']?.toString() ?? '',
      host: value['host']?.toString() ?? '',
      port: (value['port'] as num?)?.toInt() ?? 0,
      username: value['username']?.toString() ?? '',
      password: value['password']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
      };

  ProxyProfileInfo copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
  }) {
    return ProxyProfileInfo(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}
