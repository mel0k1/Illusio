class EngineEntry {
  const EngineEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.fileName,
  });

  final String id;
  final String name;
  final String version;
  final String fileName;

  static EngineEntry fromMap(Object? raw) {
    if (raw is! Map) {
      return const EngineEntry(id: '', name: '', version: '', fileName: '');
    }
    return EngineEntry(
      id: raw['id']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
      version: raw['version']?.toString() ?? '',
      fileName: raw['fileName']?.toString() ?? '',
    );
  }
}
