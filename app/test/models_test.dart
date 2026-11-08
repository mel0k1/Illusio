import 'package:flutter_test/flutter_test.dart';

import 'package:illusio/models/hub_server.dart';
import 'package:illusio/models/server.dart';
import 'package:illusio/models/tags.dart';

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

  test('server tags infer from name', () {
    final server = HubServer.fromMap({
      'address': 'ss14://example.com',
      'name': '[RU] [18+] [LRP] Example',
      'players': 10,
    });
    final tags = ServerTagInfo.infer(server);
    expect(tags, contains('lang:ru'));
    expect(tags, contains('18+'));
    expect(tags, contains('rp:low'));
  });

  test('server tags respect explicit values and no_tag_infer', () {
    final explicit = HubServer.fromMap({
      'address': 'ss14://a.example',
      'name': '[EN] Server',
      'tags': ['lang:ru', 'region:eu_e'],
    });
    expect(ServerTagInfo.infer(explicit), contains('lang:ru'));
    expect(ServerTagInfo.infer(explicit), contains('region:eu_e'));
    expect(ServerTagInfo.infer(explicit), isNot(contains('lang:en')));
    final hidden = HubServer.fromMap({
      'address': 'ss14://b.example',
      'name': '[EN] [18+] Server',
      'tags': ['no_tag_infer'],
    });
    expect(ServerTagInfo.infer(hidden), isEmpty);
  });

  test('filter categories split correctly', () {
    expect(ServerTagInfo.categoryOf('lang:ru'), 'lang');
    expect(ServerTagInfo.categoryOf('region:eu'), 'region');
    expect(ServerTagInfo.categoryOf('rp:mrp'), 'rp');
    expect(ServerTagInfo.categoryOf('18+'), '18+');
    expect(ServerTagInfo.categoryOf('wl'), 'wl');
    expect(ServerTagInfo.filterLabel('lang:ru'), 'Язык: RU');
    expect(ServerTagInfo.filterLabel('rp:low'), 'RP: лёгкий');
    expect(ServerTagInfo.filterLabel('wl'), 'Вайтлист');
  });

  test('ping quality maps to colors', () {
    expect(
      ServerPing.fromMap({'url': 'a', 'ms': 42, 'online': true})!.quality,
      0,
    );
    expect(
      ServerPing.fromMap({'url': 'a', 'ms': 150, 'online': true})!.quality,
      1,
    );
    expect(
      ServerPing.fromMap({'url': 'a', 'ms': 400, 'online': true})!.quality,
      2,
    );
    expect(
      ServerPing.fromMap({'url': 'a', 'ms': 0, 'online': false})!.quality,
      3,
    );
    expect(ServerPing.fromMap(null), isNull);
  });

  test('game server keeps raised time', () {
    final server = GameServer.fromJson({
      'name': 'A',
      'url': 'ss14://a.example',
      'raised': 12345,
    });
    expect(server.raised, 12345);
    final copy = server.copyWith(raised: 999);
    expect(copy.raised, 999);
    expect(copy.url, 'ss14://a.example');
  });
}
