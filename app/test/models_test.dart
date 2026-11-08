import 'package:flutter_test/flutter_test.dart';

import 'package:illusio/models/login_info.dart';
import 'package:illusio/models/server_info.dart';

void main() {
  test('parses server info payload from core', () {
    final info = ServerFullInfo.fromMap({
      'connect_address': 'udp://game.example.com:1212',
      'auth': {'mode': 1, 'public_key': 'pubkey'},
      'build': {
        'download_url': 'https://cdn.example.com/client.zip',
        'version': '240.1',
        'fork_id': 'space_wizards',
        'hash': 'deadbeef',
        'engine_version': '240.1.0.5',
      },
    });
    expect(info, isNotNull);
    expect(info!.connectAddress, 'udp://game.example.com:1212');
    expect(info.authMode, 1);
    expect(info.authUsable, isTrue);
    expect(info.build.version, '240.1');
    expect(info.build.forkId, 'space_wizards');
  });

  test('auth disabled mode is not usable', () {
    final info = ServerFullInfo.fromMap({
      'connect_address': '',
      'auth': {'mode': 2, 'public_key': ''},
      'build': {},
    });
    expect(info!.authUsable, isFalse);
  });

  test('download state computes progress and labels', () {
    const state = DownloadStateInfo(
      phase: 'download',
      downloaded: 52428800,
      total: 104857600,
      message: '',
      error: '',
      running: true,
      installDir: '',
      info: null,
    );
    expect(state.progress, closeTo(0.5, 0.001));
    expect(state.sizeLabel, '50.0 МБ');
    expect(state.totalLabel, '100 МБ');
    expect(state.phaseLabel, 'Загружаем клиент');
    expect(state.isDone, isFalse);
    expect(state.isError, isFalse);
  });

  test('download state without total has indeterminate progress', () {
    const state = DownloadStateInfo(
      phase: 'download',
      downloaded: 1024,
      total: 0,
      message: '',
      error: '',
      running: true,
      installDir: '',
      info: null,
    );
    expect(state.progress, isNull);
  });

  test('login info parses and roundtrips', () {
    final login = LoginInfo.fromMap({
      'token': 'tok',
      'username': 'mel0k1',
      'userId': 'guid',
      'expireTime': '2026-12-01T00:00:00Z',
      'authServer': 'https://auth.spacestation14.com/',
    });
    expect(login, isNotNull);
    final json = login!.toJson();
    final restored = LoginInfo.fromMap(json);
    expect(restored!.token, 'tok');
    expect(restored.username, 'mel0k1');
    expect(LoginInfo.fromMap(const {}), isNull);
    expect(LoginInfo.fromMap(null), isNull);
  });
}
