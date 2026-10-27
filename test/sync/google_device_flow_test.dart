import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/sync/google_device_flow.dart';

/// A device code as Google returns it, with [interval] seconds between polls.
String deviceCodeBody({int interval = 5, int expiresIn = 1800}) => jsonEncode({
  'device_code': 'device-123',
  'user_code': 'ABCD-EFGH',
  'verification_url': 'https://www.google.com/device',
  'expires_in': expiresIn,
  'interval': interval,
});

/// A token endpoint error reply.
http.Response tokenError(String error) =>
    http.Response(jsonEncode({'error': error}), 428);

void main() {
  const code = DeviceCode(
    deviceCode: 'device-123',
    userCode: 'ABCD-EFGH',
    verificationUrl: 'https://www.google.com/device',
    interval: Duration(seconds: 5),
    expiresIn: Duration(minutes: 30),
  );

  /// A flow whose token endpoint answers with [replies] in order; the
  /// waits it makes go to [waits].
  GoogleDeviceFlow flowReplying(
    List<http.Response> replies,
    List<Duration> waits, {
    List<http.Request>? requests,
  }) {
    var next = 0;
    return GoogleDeviceFlow(
      client: MockClient((request) async {
        requests?.add(request);
        return replies[next++];
      }),
      clientId: 'test-client',
      clientSecret: 'test-secret',
      wait: (duration) async => waits.add(duration),
    );
  }

  test('start asks Google for a code with the openid scopes', () async {
    late http.Request sent;
    final flow = GoogleDeviceFlow(
      client: MockClient((request) async {
        sent = request;
        return http.Response(deviceCodeBody(interval: 7, expiresIn: 900), 200);
      }),
      clientId: 'test-client',
      clientSecret: 'test-secret',
    );

    final started = await flow.start();

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://oauth2.googleapis.com/device/code');
    expect(sent.bodyFields, {
      'client_id': 'test-client',
      'scope': 'openid email profile',
    });
    expect(started.deviceCode, 'device-123');
    expect(started.userCode, 'ABCD-EFGH');
    expect(started.verificationUrl, 'https://www.google.com/device');
    expect(started.interval, const Duration(seconds: 7));
    expect(started.expiresIn, const Duration(seconds: 900));
  });

  test('start fails with network when Google cannot be reached', () async {
    final flow = GoogleDeviceFlow(
      client: MockClient((_) async => throw http.ClientException('offline')),
      clientId: 'test-client',
      clientSecret: 'test-secret',
    );

    await expectLater(
      flow.start(),
      throwsA(
        isA<GoogleDeviceFlowException>().having(
          (e) => e.kind,
          'kind',
          GoogleDeviceFlowError.network,
        ),
      ),
    );
  });

  test('returns the id_token after two authorization_pending', () async {
    final waits = <Duration>[];
    final requests = <http.Request>[];
    final flow = flowReplying(
      [
        tokenError('authorization_pending'),
        tokenError('authorization_pending'),
        http.Response(jsonEncode({'id_token': 'id-token-xyz'}), 200),
      ],
      waits,
      requests: requests,
    );

    expect(await flow.waitForIdToken(code), 'id-token-xyz');
    expect(waits, List.filled(3, const Duration(seconds: 5)));
    expect(requests, hasLength(3));
    expect(
      requests.first.url.toString(),
      'https://oauth2.googleapis.com/token',
    );
    expect(requests.first.bodyFields, {
      'client_id': 'test-client',
      'client_secret': 'test-secret',
      'device_code': 'device-123',
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
    });
  });

  test('slow_down waits 5 seconds more from then on', () async {
    final waits = <Duration>[];
    final flow = flowReplying([
      tokenError('slow_down'),
      tokenError('authorization_pending'),
      http.Response(jsonEncode({'id_token': 'id-token-xyz'}), 200),
    ], waits);

    await flow.waitForIdToken(code);

    expect(waits, const [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 10),
    ]);
  });

  /// Expects [flow.waitForIdToken] to fail with [kind].
  Future<void> expectFailure(
    GoogleDeviceFlow flow,
    GoogleDeviceFlowError kind,
  ) => expectLater(
    flow.waitForIdToken(code),
    throwsA(
      isA<GoogleDeviceFlowException>().having((e) => e.kind, 'kind', kind),
    ),
  );

  test('access_denied fails with denied', () async {
    await expectFailure(
      flowReplying([tokenError('access_denied')], []),
      GoogleDeviceFlowError.denied,
    );
  });

  test('expired_token fails with expired', () async {
    await expectFailure(
      flowReplying([tokenError('expired_token')], []),
      GoogleDeviceFlowError.expired,
    );
  });

  test('a network error fails with network', () async {
    final flow = GoogleDeviceFlow(
      client: MockClient((_) async => throw http.ClientException('offline')),
      clientId: 'test-client',
      clientSecret: 'test-secret',
      wait: (_) async {},
    );
    await expectFailure(flow, GoogleDeviceFlowError.network);
  });

  test('an unexpected reply fails with network', () async {
    await expectFailure(
      flowReplying([http.Response('<html>oops</html>', 500)], []),
      GoogleDeviceFlowError.network,
    );
  });

  test('a TLS handshake failure fails with network', () async {
    final flow = GoogleDeviceFlow(
      client: MockClient((_) async => throw const HandshakeException('x')),
      clientId: 'test-client',
      clientSecret: 'test-secret',
      wait: (_) async {},
    );
    await expectFailure(flow, GoogleDeviceFlowError.network);
    await expectLater(
      flow.start(),
      throwsA(
        isA<GoogleDeviceFlowException>().having(
          (e) => e.kind,
          'kind',
          GoogleDeviceFlowError.network,
        ),
      ),
    );
  });

  test('slow round trips cannot poll past the deadline set by start', () async {
    // A fake clock: each wait takes its time and each request 10 s more.
    var now = DateTime(2026, 10, 28, 12);
    var tokenRequests = 0;
    final flow = GoogleDeviceFlow(
      client: MockClient((request) async {
        if (request.url.path == '/device/code') {
          return http.Response(deviceCodeBody(expiresIn: 30), 200);
        }
        tokenRequests++;
        now = now.add(const Duration(seconds: 10));
        return tokenError('authorization_pending');
      }),
      clientId: 'test-client',
      clientSecret: 'test-secret',
      wait: (duration) async => now = now.add(duration),
      now: () => now,
    );

    final started = await flow.start();
    expect(started.expiresAt, DateTime(2026, 10, 28, 12, 0, 30));
    await expectLater(
      flow.waitForIdToken(started),
      throwsA(
        isA<GoogleDeviceFlowException>().having(
          (e) => e.kind,
          'kind',
          GoogleDeviceFlowError.expired,
        ),
      ),
    );
    // Polls at 5 s and 20 s; at 35 s the code is gone.
    expect(tokenRequests, 2);
  });
  test('cancel stops the polling', () async {
    final requests = <http.Request>[];
    late GoogleDeviceFlow flow;
    flow = GoogleDeviceFlow(
      client: MockClient((request) async {
        requests.add(request);
        return tokenError('authorization_pending');
      }),
      clientId: 'test-client',
      clientSecret: 'test-secret',
      wait: (_) async {
        if (requests.length == 2) flow.cancel();
      },
    );

    await expectLater(
      flow.waitForIdToken(code),
      throwsA(isA<GoogleDeviceFlowCancelled>()),
    );
    expect(requests, hasLength(2));
  });
}
