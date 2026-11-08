class LoginInfo {
  const LoginInfo({
    required this.token,
    required this.username,
    required this.userId,
    required this.expireTime,
    required this.authServer,
  });

  final String token;
  final String username;
  final String userId;
  final String expireTime;
  final String authServer;

  static LoginInfo? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final token = raw['token']?.toString() ?? '';
    if (token.isEmpty) {
      return null;
    }
    return LoginInfo(
      token: token,
      username: raw['username']?.toString() ?? '',
      userId: raw['userId']?.toString() ?? '',
      expireTime: raw['expireTime']?.toString() ?? '',
      authServer: raw['authServer']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'username': username,
        'userId': userId,
        'expireTime': expireTime,
        'authServer': authServer,
      };
}
