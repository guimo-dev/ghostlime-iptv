import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/xtream/xtream_client.dart';
import 'package:iptv_player/xtream/xtream_credentials.dart';

const _credentials = XtreamCredentials('http://h', 'u', 'p');

/// Builds a client whose HTTP layer always answers [body] with [status].
XtreamClient _clientReturning(
  String body, {
  int status = 200,
  void Function(http.Request)? onRequest,
}) {
  return XtreamClient(
    _credentials,
    httpClient: MockClient((request) async {
      onRequest?.call(request);
      return http.Response(body, status);
    }),
  );
}

void main() {
  group('authenticate', () {
    test('completes when auth is 1', () async {
      final client = _clientReturning(
        jsonEncode({
          'user_info': {'auth': 1},
        }),
      );
      await client.authenticate();
    });

    test('rejects wrong credentials', () async {
      final client = _clientReturning(
        jsonEncode({
          'user_info': {'auth': 0},
        }),
      );
      await expectLater(
        client.authenticate(),
        throwsA(
          isA<XtreamException>().having(
            (e) => e.message,
            'message',
            contains('credenciales'),
          ),
        ),
      );
    });

    test('rejects HTML responses', () async {
      final client = _clientReturning('<html>');
      await expectLater(
        client.authenticate(),
        throwsA(
          isA<XtreamException>().having(
            (e) => e.message,
            'message',
            contains('respuesta no válida'),
          ),
        ),
      );
    });

    test('reports HTTP status errors', () async {
      final client = _clientReturning('down', status: 503);
      await expectLater(
        client.authenticate(),
        throwsA(
          isA<XtreamException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });

    test('never leaks the password in the message', () async {
      final client = XtreamClient(
        const XtreamCredentials('http://h', 'u', 'secret-pass'),
        httpClient: MockClient((_) async => http.Response('down', 503)),
      );
      await expectLater(
        client.authenticate(),
        throwsA(
          isA<XtreamException>().having(
            (e) => e.message,
            'message',
            isNot(contains('secret-pass')),
          ),
        ),
      );
    });
  });

  group('userAgent', () {
    test('is sent when configured', () async {
      String? agent;
      final client = XtreamClient(
        _credentials,
        userAgent: 'TestUA',
        httpClient: MockClient((r) async {
          agent = r.headers['User-Agent'];
          return http.Response('[]', 200);
        }),
      );
      await client.getLiveCategories();
      expect(agent, 'TestUA');
    });
  });

  group('getLiveCategories', () {
    test('parses categories', () async {
      final client = _clientReturning(
        jsonEncode([
          {'category_id': '1', 'category_name': 'Deportes'},
          {'category_id': 2, 'category_name': 'Noticias'},
        ]),
      );
      final categories = await client.getLiveCategories();
      expect(categories.map((c) => c.name), ['Deportes', 'Noticias']);
    });
  });

  group('getLiveStreams', () {
    test('sends action and category id', () async {
      late Uri requested;
      final client = _clientReturning(
        '[]',
        onRequest: (r) => requested = r.url,
      );
      await client.getLiveStreams(categoryId: '7');
      expect(requested.queryParameters['action'], 'get_live_streams');
      expect(requested.queryParameters['category_id'], '7');
    });

    test('returns empty list for [] and {}', () async {
      expect(await _clientReturning('[]').getLiveStreams(), isEmpty);
      expect(await _clientReturning('{}').getLiveStreams(), isEmpty);
    });
  });
}
