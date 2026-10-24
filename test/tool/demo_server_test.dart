import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/demo_server/demo_server.dart';

void main() {
  late DemoServer server;
  final client = HttpClient();

  setUp(() async => server = await DemoServer.start(paced: false));
  tearDown(() async => server.close());
  tearDownAll(() => client.close(force: true));

  /// GETs [path] on the demo server and returns status and body bytes.
  Future<(int, List<int>)> get(String path) async {
    final request = await client.getUrl(server.baseUrl.resolve(path));
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (response.statusCode, bytes);
  }

  /// GETs [path] and decodes the body as JSON.
  Future<Object?> getJson(String path) async {
    final (_, bytes) = await get(path);
    return jsonDecode(utf8.decode(bytes));
  }

  String api(String action, [String extra = '']) =>
      '/player_api.php?username=demo&password=demo&action=$action$extra';

  test(
    'player_api without action returns user_info auth 1 for demo/demo',
    () async {
      final json = await getJson(
        '/player_api.php?username=demo&password=demo',
      ) as Map<String, dynamic>;
      expect((json['user_info'] as Map)['auth'], 1);
      // Live streams are only served as .ts.
      expect((json['user_info'] as Map)['allowed_output_formats'], ['ts']);
    },
  );

  test('wrong password returns auth 0', () async {
    final json = await getJson(
      '/player_api.php?username=demo&password=nope',
    ) as Map<String, dynamic>;
    expect((json['user_info'] as Map)['auth'], 0);
  });

  test('get_live_categories lists 4 categories', () async {
    final json = await getJson(api('get_live_categories')) as List;
    expect(json, hasLength(4));
  });

  test(
    'get_live_streams has a 120-char name and names with ñ, emoji and Cyrillic',
    () async {
      final json = await getJson(api('get_live_streams')) as List;
      final names = [for (final c in json) (c as Map)['name'] as String];
      expect(json, hasLength(24));
      expect(names.any((n) => n.length == 120), isTrue);
      expect(names.any((n) => n.contains('ñ')), isTrue);
      expect(names.any((n) => n.runes.any((r) => r > 0x1F000)), isTrue);
      expect(names.any((n) => RegExp(r'[Ѐ-ӿ]').hasMatch(n)), isTrue);
      final first = json.first as Map;
      expect(first['stream_id'], isA<int>());
      expect(first['category_id'], isA<String>());
    },
  );

  test('get_live_streams filters by category_id', () async {
    final json =
        await getJson(api('get_live_streams', '&category_id=1')) as List;
    expect(json, hasLength(6));
  });

  test('get_vod_info and get_series_info return posters under /img/', () async {
    final vod = await getJson(api('get_vod_info', '&vod_id=101')) as Map;
    expect((vod['info'] as Map)['movie_image'], contains('/img/'));
    final series =
        await getJson(api('get_series_info', '&series_id=201')) as Map;
    expect((series['info'] as Map)['cover'], contains('/img/'));
    final seasons = series['episodes'] as Map;
    expect(seasons.keys, ['1', '2']);
    expect((seasons['1'] as List), hasLength(4));
    expect(await getJson(api('get_vod_streams')), hasLength(18));
    expect(await getJson(api('get_series')), hasLength(6));
    expect(await getJson(api('get_vod_categories')), hasLength(3));
    expect(await getJson(api('get_series_categories')), hasLength(2));
  });

  test('xmltv.php covers every live channel for now-6h..now+72h', () async {
    final (_, bytes) = await get('/xmltv.php?username=demo&password=demo');
    final xml = utf8.decode(bytes);
    final channels = await getJson(api('get_live_streams')) as List;
    final now = DateTime.now().toUtc();
    expect(xml, contains('<programme start='));
    for (final channel in channels) {
      final id = (channel as Map)['epg_channel_id'];
      expect(xml, contains('channel="$id"'));
    }
    final starts = RegExp(
      r'programme start="(\d{14})',
    ).allMatches(xml).map((m) => m.group(1)!).toList()..sort();
    DateTime parse(String s) => DateTime.utc(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
      int.parse(s.substring(8, 10)),
      int.parse(s.substring(10, 12)),
      int.parse(s.substring(12, 14)),
    );
    expect(
      parse(starts.first).isBefore(now.subtract(const Duration(hours: 5))),
      isTrue,
    );
    expect(
      parse(starts.last).isAfter(now.add(const Duration(hours: 70))),
      isTrue,
    );
  });

  test('playlist.m3u has url-tvg pointing to /xmltv.php', () async {
    final (_, bytes) = await get('/playlist.m3u');
    final text = utf8.decode(bytes);
    expect(text, startsWith('#EXTM3U'));
    expect(text, contains('url-tvg="${server.baseUrl.origin}/xmltv.php'));
    expect(text, contains('/live/demo/demo/1.ts'));
  });

  test(
    'links follow the Host the client used (10.0.2.2 from the emulator)',
    () async {
      final host = '10.0.2.2:${server.baseUrl.port}';
      Future<String> getAs(String path) async {
        final request = await client.getUrl(server.baseUrl.resolve(path));
        request.headers.host = '10.0.2.2';
        request.headers.port = server.baseUrl.port;
        final response = await request.close();
        return utf8.decode(
          await response.fold<List<int>>([], (a, b) => a..addAll(b)),
        );
      }

      final playlist = await getAs('/playlist.m3u');
      expect(playlist, contains('url-tvg="http://$host/xmltv.php'));
      expect(playlist, contains('tvg-logo="http://$host/img/'));
      expect(playlist, contains('http://$host/live/demo/demo/1.ts'));
      expect(playlist, isNot(contains('127.0.0.1')));

      final streams = jsonDecode(await getAs(api('get_live_streams'))) as List;
      expect(
        (streams.first as Map)['stream_icon'],
        startsWith('http://$host/img/'),
      );
      final info = jsonDecode(
        await getAs('/player_api.php?username=demo&password=demo'),
      ) as Map;
      expect((info['server_info'] as Map)['url'], '10.0.2.2');
    },
  );

  /// Opens a GET on [path], returning the response without reading its body.
  Future<HttpClientResponse> open(String path, {String? range}) async {
    final request = await client.getUrl(server.baseUrl.resolve(path));
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    return request.close();
  }

  /// Reads at least [minBytes] from [response], then stops listening.
  Future<int> readAtLeast(HttpClientResponse response, int minBytes) async {
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
      if (total >= minBytes) break;
    }
    return total;
  }

  test('live stream keeps sending after the clip length', () async {
    final clipLength = File(DemoServer.defaultClipPath).lengthSync();
    final response = await open('/live/demo/demo/1.ts');
    expect(response.statusCode, 200);
    expect(response.contentLength, -1);
    expect(
      await readAtLeast(response, clipLength * 2),
      greaterThan(clipLength),
    );
  });

  test('series stream also loops', () async {
    final clipLength = File(DemoServer.defaultClipPath).lengthSync();
    final response = await open('/series/demo/demo/2001.ts');
    expect(
      await readAtLeast(response, clipLength + 1),
      greaterThan(clipLength),
    );
  });

  test('aborting a stream mid-body leaves the server serving', () async {
    final aborting = HttpClient();
    final request = await aborting.getUrl(
      server.baseUrl.resolve('/live/demo/demo/1.ts'),
    );
    final response = await request.close();
    await readAtLeast(response, 1000);
    aborting.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final json = await getJson(
      '/player_api.php?username=demo&password=demo',
    ) as Map<String, dynamic>;
    expect((json['user_info'] as Map)['auth'], 1);
  });

  test('movie supports Range requests (206 with Content-Range)', () async {
    final clipLength = File(DemoServer.defaultClipPath).lengthSync();
    final full = await open('/movie/demo/demo/101.mp4');
    expect(full.statusCode, 200);
    expect(full.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    await full.drain<void>();

    final response = await open(
      '/movie/demo/demo/101.mp4',
      range: 'bytes=100-199',
    );
    expect(response.statusCode, 206);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 100-199/$clipLength',
    );
    final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(body, hasLength(100));

    final open2 = await open(
      '/movie/demo/demo/101.mp4',
      range: 'bytes=${clipLength + 5}-',
    );
    expect(open2.statusCode, 416);
    await open2.drain<void>();
  });

  test('channel 24 closes at the injected cutoff', () async {
    final unstable = await DemoServer.start(
      unstableCutoff: const Duration(milliseconds: 400),
    );
    addTearDown(unstable.close);
    final request = await client.getUrl(
      unstable.baseUrl.resolve('/live/demo/demo/24.ts'),
    );
    final response = await request.close();
    final stopwatch = Stopwatch()..start();
    final bytes = await response.fold<int>(0, (n, c) => n + c.length);
    expect(bytes, greaterThan(0));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('stream routes require the demo credentials', () async {
    final response = await open('/movie/nope/nope/101.mp4');
    expect(response.statusCode, 403);
    await response.drain<void>();
  });

  test('down makes every route 503', () async {
    server.down = true;
    for (final path in [
      '/player_api.php?username=demo&password=demo',
      '/playlist.m3u',
      '/xmltv.php',
      '/img/7.png',
      '/live/demo/demo/1.ts',
    ]) {
      final (status, _) = await get(path);
      expect(status, 503, reason: path);
    }
  });

  test('/img/7.png is a valid PNG', () async {
    final (status, bytes) = await get('/img/7.png');
    expect(status, 200);
    expect(bytes.sublist(0, 8), [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
  });
}
