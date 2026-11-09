import '../l10n/strings.dart';

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

class ServerLinkInfo {
  const ServerLinkInfo({
    required this.name,
    required this.icon,
    required this.url,
  });

  final String name;
  final String icon;
  final String url;

  static ServerLinkInfo? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final url = raw['url']?.toString() ?? '';
    if (url.isEmpty) {
      return null;
    }
    return ServerLinkInfo(
      name: raw['name']?.toString() ?? '',
      icon: raw['icon']?.toString() ?? '',
      url: url,
    );
  }
}

class ServerPrivacyInfo {
  const ServerPrivacyInfo({
    required this.link,
    required this.identifier,
    required this.version,
  });

  final String link;
  final String identifier;
  final String version;

  static ServerPrivacyInfo? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final identifier = raw['identifier']?.toString() ?? '';
    if (identifier.isEmpty) {
      return null;
    }
    return ServerPrivacyInfo(
      link: raw['link']?.toString() ?? '',
      identifier: identifier,
      version: raw['version']?.toString() ?? '',
    );
  }
}

class ServerFullInfo {
  const ServerFullInfo({
    required this.connectAddress,
    required this.authMode,
    required this.authPublicKey,
    required this.build,
    this.desc = '',
    this.links = const [],
    this.privacyPolicy,
  });

  final String connectAddress;
  final int authMode;
  final String authPublicKey;
  final ServerBuildInfo build;
  final String desc;
  final List<ServerLinkInfo> links;
  final ServerPrivacyInfo? privacyPolicy;

  static const int authModeDisabled = 2;

  bool get authUsable => authMode != authModeDisabled;

  static ServerFullInfo? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final auth = (raw['auth'] as Map?) ?? const {};
    final links = ((raw['links'] as List?) ?? const [])
        .map(ServerLinkInfo.fromMap)
        .whereType<ServerLinkInfo>()
        .toList();
    return ServerFullInfo(
      connectAddress: raw['connect_address']?.toString() ?? '',
      authMode: (auth['mode'] is int)
          ? auth['mode'] as int
          : int.tryParse(auth['mode']?.toString() ?? '') ?? 0,
      authPublicKey: auth['public_key']?.toString() ?? '',
      build: ServerBuildInfo.fromMap(raw['build']),
      desc: raw['desc']?.toString() ?? '',
      links: links,
      privacyPolicy: ServerPrivacyInfo.fromMap(raw['privacy_policy']),
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
    this.bundleZip = '',
    this.modules = const [],
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
  final String bundleZip;
  final List<String> modules;

  bool get isDone => phase == 'done';

  bool get isError => phase == 'error';

  bool get isAcz => mode == 'acz';

  double? get progress {
    if (total <= 0) {
      return null;
    }
    return (downloaded / total).clamp(0.0, 1.0);
  }

  String sizeLabel(S s) => s.formatBytes(downloaded);

  String totalLabel(S s) => s.formatBytes(total);

  String phaseLabel(S s) {
    switch (phase) {
      case 'info':
        return message.isEmpty ? s.phaseServerData : message;
      case 'engine':
        return message.isEmpty ? s.phaseEngine : message;
      case 'download':
        return s.phaseClient;
      case 'extract':
        return message.isEmpty ? s.phaseExtract : message;
      case 'done':
        return message.isEmpty ? s.phaseReady : message;
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
      bundleZip: raw['bundleZip']?.toString() ?? '',
      modules: ((raw['modules'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(),
      info: ServerFullInfo.fromMap(raw['info']),
    );
  }
}
