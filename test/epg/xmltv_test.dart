import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/programme.dart';
import 'package:iptv_player/epg/xmltv.dart';
import 'package:iptv_player/xtream/xtream_client.dart';

final _from = DateTime.utc(2026, 10, 18, 12);
final _to = DateTime.utc(2026, 10, 21, 22);

const _xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="test">
  <channel id="a.es"><display-name>A</display-name></channel>
  <channel id=""><display-name>Vacio</display-name></channel>
  <programme start="20261019100000 +0000" stop="20261019110000 +0000" channel="a.es">
    <title lang="es">Tom &amp; Jerry &#233;</title>
    <title lang="en">Tom and Jerry</title>
    <desc lang="es"><![CDATA[Dibujos <animados> & mas]]></desc>
  </programme>
  <programme start="20261019110000 +0000" stop="20261019120000 +0000" channel="b.es">
    <title>Canal b</title>
  </programme>
  <programme start="20261019130000 +0200" channel="a.es">
    <title>Sin stop</title>
  </programme>
  <programme start="20261019120000 +0000" stop="20261019130000 +0000" channel="a.es">
    <title>Segundo</title>
  </programme>
  <programme start="20261019150000 +0000" channel="a.es">
    <title>Ultimo sin stop</title>
  </programme>
  <programme start="20261001100000 +0000" stop="20261001110000 +0000" channel="a.es">
    <title>Muy antiguo</title>
  </programme>
  <programme start="20261101100000 +0000" stop="20261101110000 +0000" channel="a.es">
    <title>Muy futuro</title>
  </programme>
  <programme start="20261019100000 +0000" stop="20261019110000 +0000" channel="c.es">
    <title>No pedido</title>
  </programme>
</tv>
''';

Stream<List<int>> _chunks(List<int> bytes, [int size = 7]) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

Future<List<Programme>> _parse(List<int> bytes, [Set<String>? ids]) =>
    parseXmltv(
      _chunks(bytes),
      channelIds: ids ?? {'a.es', 'b.es'},
      from: _from,
      to: _to,
    );

void _expectSmallResult(List<Programme> result) {
  expect(result.map((p) => (p.channelId, p.title)).toList(), [
    ('a.es', 'Tom & Jerry é'),
    ('a.es', 'Sin stop'),
    ('a.es', 'Segundo'),
    ('a.es', 'Ultimo sin stop'),
    ('b.es', 'Canal b'),
  ]);
  final first = result.first;
  expect(first.start, DateTime.utc(2026, 10, 19, 10));
  expect(first.stop, DateTime.utc(2026, 10, 19, 11));
  expect(first.description, 'Dibujos <animados> & mas');
  expect(result.last.description, isNull);
  // Without stop: the next programme's start, or one hour when it is the last.
  expect(result[1].start, DateTime.utc(2026, 10, 19, 11));
  expect(result[1].stop, DateTime.utc(2026, 10, 19, 12));
  expect(result[3].stop, DateTime.utc(2026, 10, 19, 16));
}

void main() {
  group('parseXmltvTime', () {
    test('reads UTC and offsets', () {
      expect(
        parseXmltvTime('20261018120000 +0000'),
        DateTime.utc(2026, 10, 18, 12),
      );
      expect(
        parseXmltvTime('20261018120000 +0200'),
        DateTime.utc(2026, 10, 18, 10),
      );
      expect(
        parseXmltvTime('20261018120000 -0500'),
        DateTime.utc(2026, 10, 18, 17),
      );
    });

    test('no offset means UTC', () {
      expect(parseXmltvTime('20261018120000'), DateTime.utc(2026, 10, 18, 12));
    });

    test('garbage gives null', () {
      expect(parseXmltvTime('mañana'), isNull);
      expect(parseXmltvTime(''), isNull);
      expect(parseXmltvTime('20261318120000'), isNull);
    });
  });

  group('parseXmltv', () {
    test('filters channels and window, decodes text, sorts', () async {
      _expectSmallResult(await _parse(utf8.encode(_xml)));
    });

    test('reads a gzip file by its header', () async {
      _expectSmallResult(await _parse(gzip.encode(utf8.encode(_xml))));
    });

    test('ignores a leading BOM', () async {
      _expectSmallResult(
        await _parse([0xEF, 0xBB, 0xBF, ...utf8.encode(_xml)]),
      );
    });

    test('empty input gives no programmes', () async {
      expect(await _parse(const []), isEmpty);
    });

    test('malformed XML throws XtreamException', () async {
      expect(
        _parse(utf8.encode('<tv><programme start="x"')),
        throwsA(isA<XtreamException>()),
      );
    });

    test('200 000 programmes for 2 000 channels, 200 requested', () async {
      final buffer = StringBuffer('<tv>');
      final base = DateTime.utc(2026, 10, 19);
      for (var i = 0; i < 200000; i++) {
        final start = base.add(Duration(minutes: (i ~/ 2000) * 30));
        final stop = start.add(const Duration(minutes: 30));
        buffer.write(
          '<programme start="${_stamp(start)} +0000" '
          'stop="${_stamp(stop)} +0000" channel="c${i % 2000}">'
          '<title>P$i</title><desc>Descripcion $i</desc></programme>',
        );
      }
      buffer.write('</tv>');
      final bytes = utf8.encode(buffer.toString());
      final watch = Stopwatch()..start();
      final result = await parseXmltv(
        _chunks(bytes, 65536),
        channelIds: {for (var i = 0; i < 200; i++) 'c$i'},
        from: base,
        to: base.add(const Duration(days: 3)),
      );
      watch.stop();
      expect(result, hasLength(200 * 100));
      expect(result.map((p) => p.channelId).toSet(), hasLength(200));
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    });
  });

  group('fetchXmltv', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        if (request.uri.path == '/ok') {
          request.response.add(gzip.encode(utf8.encode(_xml)));
        } else {
          request.response.statusCode = 500;
        }
        request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Future<List<Programme>> fetch(String path) => fetchXmltv(
      Uri.parse('http://127.0.0.1:${server.port}$path?password=secret'),
      channelIds: {'a.es', 'b.es'},
      from: _from,
      to: _to,
    );

    test('downloads and parses in an isolate', () async {
      _expectSmallResult(await fetch('/ok'));
    });

    test('HTTP error gives a Spanish message without the URL', () async {
      await expectLater(
        fetch('/fail'),
        throwsA(
          isA<XtreamException>().having(
            (e) => e.message,
            'message',
            allOf(contains('500'), isNot(contains('secret'))),
          ),
        ),
      );
    });

    test('network error gives a message without the URL', () async {
      final port = server.port;
      await server.close(force: true);
      await expectLater(
        fetchXmltv(
          Uri.parse('http://127.0.0.1:$port/ok?password=secret'),
          channelIds: {'a.es'},
          from: _from,
          to: _to,
        ),
        throwsA(
          isA<XtreamException>().having(
            (e) => e.message,
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
    });
  });
}

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}00';
}
