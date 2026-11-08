import 'package:flutter_test/flutter_test.dart';

import 'package:illusio/models/hub_server.dart';

void main() {
  test('hub server parses core payload', () {
    final server = HubServer.fromMap({
      'address': 'ss14s://erida.example.net',
      'name': 'Эрида',
      'players': 25,
      'soft_max_players': 100,
      'tags': ['lang:ru', 'region:eu_e', '18+'],
      'preset': 'Выживание+',
      'map': 'Box Station',
      'run_level': 1,
      'round_id': 5591,
      'status_message': 'привет',
    });
    expect(server.address, 'ss14s://erida.example.net');
    expect(server.name, 'Эрида');
    expect(server.playersLabel, '25/100');
    expect(server.runLevelLabel, 'В раунде');
    expect(server.empty, isFalse);
  });

  test('hub server tolerates missing fields', () {
    final server = HubServer.fromMap({
      'address': 'ss14://example.com',
      'name': 'Test',
      'players': 4,
    });
    expect(server.softMaxPlayers, 0);
    expect(server.playersLabel, '4');
    expect(server.tags, isEmpty);
    expect(server.runLevelLabel, 'Лобби');
  });

  test('empty hub server is marked empty', () {
    final server = HubServer.fromMap(null);
    expect(server.empty, isTrue);
  });

  test('mod entry parses and formats size', () {
    final mod = ModEntry.fromMap({
      'file_name': 'pack_a.zip',
      'path': '/data/mods/pack_a.zip',
      'size': 1048576,
    });
    expect(mod.fileName, 'pack_a.zip');
    expect(mod.sizeLabel, '1.00 МБ');
    expect(ModEntry.fromMap(null).fileName, isEmpty);
  });
}
