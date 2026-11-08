class ServerBuildInfo {
  const ServerBuildInfo({
    required this.downloadUrl,
    required this.version,
    required this.forkId,
    required this.hash,
    required this.engineVersion,
  });

  final String downloadUrl;
  final String version;
  final String forkId;
  final String hash;
  final String engineVersion;

  static ServerBuildInfo fromMap(Object? raw) {
    if (raw is! Map) {
      return const ServerBuildInfo(
        downloadUrl: '',
        version: '',
        forkId: '',
        hash: '',
        engineVersion: '',
      );
    }
    return ServerBuildInfo(
      downloadUrl: raw['download_url']?.toString() ?? '',
      version: raw['version']?.toString() ?? '',
      forkId: raw['fork_id']?.toString() ?? '',
      hash: raw['hash']?.toString() ?? '',
      engineVersion: raw['engine_version']?.toString() ?? '',
    );
  }
}

class ServerFullInfo {
  const ServerFullInfo({
    required this.connectAddress,
    required this.authMode,
    required this.authPublicKey,
    required this.build,
  });

  final String connectAddress;
  final int authMode;
  final String authPublicKey;
  final ServerBuildInfo build;

  static const int authModeDisabled = 2;

  bool get authUsable => authMode != authModeDisabled;

  static ServerFullInfo? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final auth = (raw['auth'] as Map?) ?? const {};
    return ServerFullInfo(
      connectAddress: raw['connect_address']?.toString() ?? '',
      authMode: (auth['mode'] is int)
          ? auth['mode'] as int
          : int.tryParse(auth['mode']?.toString() ?? '') ?? 0,
      authPublicKey: auth['public_key']?.toString() ?? '',
      build: ServerBuildInfo.fromMap(raw['build']),
    );
  }
}

class DownloadStateInfo {
  const DownloadStateInfo({
    required this.phase,
    required this.downloaded,
    required this.total,
    required this.message,
    required this.error,
    required this.running,
    required this.installDir,
    required this.mode,
    required this.engineZip,
    required this.contentZip,
    required this.engineSig,
    required this.info,
  });

  final String phase;
  final int downloaded;
  final int total;
  final String message;
  final String error;
  final bool running;
  final String installDir;
  final String mode;
  final String engineZip;
  final String contentZip;
  final String engineSig;
  final ServerFullInfo? info;

  bool get isDone => phase == 'done';

  bool get isError => phase == 'error';

  bool get isAcz => mode == 'acz';

  double? get progress {
    if (total <= 0) {
      return null;
    }
    return (downloaded / total).clamp(0.0, 1.0);
  }

  String get sizeLabel => _formatBytes(downloaded);

  String get totalLabel => _formatBytes(total);

  static String _formatBytes(int bytes) {
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

  String get phaseLabel {
    switch (phase) {
      case 'info':
        return message.isEmpty ? 'Получаем данные сервера' : message;
      case 'engine':
        return message.isEmpty ? 'Загружаем движок' : message;
      case 'download':
        return 'Загружаем клиент';
      case 'extract':
        return message.isEmpty ? 'Распаковываем' : message;
      case 'done':
        return message.isEmpty ? 'Клиент готов' : message;
      case 'error':
        return error;
      default:
        return '';
    }
  }

  static const DownloadStateInfo empty = DownloadStateInfo(
    phase: 'idle',
    downloaded: 0,
    total: 0,
    message: '',
    error: '',
    running: false,
    installDir: '',
    mode: '',
    engineZip: '',
    contentZip: '',
    engineSig: '',
    info: null,
  );

  static DownloadStateInfo fromMap(Object? raw) {
    if (raw is! Map) {
      return empty;
    }
    return DownloadStateInfo(
      phase: raw['phase']?.toString() ?? 'idle',
      downloaded: (raw['downloaded'] as num?)?.toInt() ?? 0,
      total: (raw['total'] as num?)?.toInt() ?? 0,
      message: raw['message']?.toString() ?? '',
      error: raw['error']?.toString() ?? '',
      running: raw['running'] == true,
      installDir: raw['install_dir']?.toString() ?? '',
      mode: raw['mode']?.toString() ?? '',
      engineZip: raw['engineZip']?.toString() ?? '',
      contentZip: raw['contentZip']?.toString() ?? '',
      engineSig: raw['engineSig']?.toString() ?? '',
      info: ServerFullInfo.fromMap(raw['info']),
    );
  }
}
