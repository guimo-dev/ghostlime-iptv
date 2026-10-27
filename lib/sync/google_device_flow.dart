import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client ID of the Google OAuth client of type "TVs and Limited Input
/// devices", given only with `--dart-define=GOOGLE_TV_CLIENT_ID`; empty in
/// builds without it (the TV then offers no Google sign-in).
const _clientId = String.fromEnvironment('GOOGLE_TV_CLIENT_ID');

/// Secret of that client, `--dart-define=GOOGLE_TV_CLIENT_SECRET`. Google
/// asks for it even though a TV app cannot keep it secret.
const _clientSecret = String.fromEnvironment('GOOGLE_TV_CLIENT_SECRET');

/// Test replacement of [newGoogleTvFlow]; `null` uses the build's client.
GoogleDeviceFlow Function()? _debugFlowFactory;

/// Makes [googleTvConfigured] true and [newGoogleTvFlow] return [factory]'s
/// flows in tests; `null` restores the build's client.
@visibleForTesting
set debugGoogleTvFlow(GoogleDeviceFlow Function()? factory) =>
    _debugFlowFactory = factory;

/// Whether this build can sign in with Google on a TV (it has a TV client).
bool get googleTvConfigured =>
    _debugFlowFactory != null || _clientId.isNotEmpty;

/// A new device flow with the build's TV client; close it when done.
GoogleDeviceFlow newGoogleTvFlow() =>
    _debugFlowFactory?.call() ??
    GoogleDeviceFlow(
      client: http.Client(),
      clientId: _clientId,
      clientSecret: _clientSecret,
    );

/// What Google answered to [GoogleDeviceFlow.start]: the code to type on
/// another device at [verificationUrl].
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresIn,
    this.expiresAt,
  });

  /// The code this device polls with; never shown.
  final String deviceCode;

  /// The code the user types, e.g. `ABCD-EFGH`.
  final String userCode;

  /// Where the user types [userCode] (https://www.google.com/device).
  final String verificationUrl;

  /// How long to wait between polls.
  final Duration interval;

  /// How long the code lasts from when it was given.
  final Duration expiresIn;

  /// When the code runs out on this device's clock: set by
  /// [GoogleDeviceFlow.start]; without it [GoogleDeviceFlow.waitForIdToken]
  /// counts [expiresIn] from its own start.
  final DateTime? expiresAt;
}

/// Why a device sign-in failed.
enum GoogleDeviceFlowError {
  /// The user said no on the other device.
  denied,

  /// The code ran out before the user approved it.
  expired,

  /// Google could not be reached or answered something unexpected.
  network,
}

/// A failed device sign-in; [kind] says why.
class GoogleDeviceFlowException implements Exception {
  const GoogleDeviceFlowException(this.kind);

  final GoogleDeviceFlowError kind;

  @override
  String toString() => 'GoogleDeviceFlowException: ${kind.name}';
}

/// Thrown by [GoogleDeviceFlow.waitForIdToken] after
/// [GoogleDeviceFlow.cancel].
class GoogleDeviceFlowCancelled implements Exception {
  const GoogleDeviceFlowCancelled();
}

/// Google's OAuth device authorization flow ("TVs and Limited Input
/// devices"): [start] gets a code the user approves on a phone or computer,
/// and [waitForIdToken] polls until Google hands over the `id_token`. Tokens
/// and codes are never logged.
class GoogleDeviceFlow {
  GoogleDeviceFlow({
    required this._client,
    required this._clientId,
    required this._clientSecret,
    this._wait,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final http.Client _client;
  final String _clientId;
  final String _clientSecret;

  /// Waits between polls when given (tests, to skip the time); otherwise
  /// [_sleep] does.
  final Future<void> Function(Duration duration)? _wait;

  /// The clock for the code's deadline; tests replace it.
  final DateTime Function() _now;

  bool _cancelled = false;

  /// The wait of [_sleep] under way, ended early by [cancel].
  Timer? _sleepTimer;
  Completer<void>? _sleepDone;

  static final _deviceCodeUrl = Uri.parse(
    'https://oauth2.googleapis.com/device/code',
  );
  static final _tokenUrl = Uri.parse('https://oauth2.googleapis.com/token');
  static const _grantType = 'urn:ietf:params:oauth:grant-type:device_code';

  /// How much [waitForIdToken] slows down when Google says `slow_down`.
  static const _slowDownStep = Duration(seconds: 5);

  /// Asks Google for a code to show. Throws [GoogleDeviceFlowException]
  /// ([GoogleDeviceFlowError.network]) when that fails.
  Future<DeviceCode> start() async {
    final json = await _post(_deviceCodeUrl, {
      'client_id': _clientId,
      'scope': 'openid email profile',
    });
    try {
      final expiresIn = Duration(seconds: (json['expires_in'] as num).toInt());
      return DeviceCode(
        deviceCode: json['device_code'] as String,
        userCode: json['user_code'] as String,
        verificationUrl:
            (json['verification_url'] ?? json['verification_uri']) as String,
        interval: Duration(seconds: (json['interval'] as num?)?.toInt() ?? 5),
        expiresIn: expiresIn,
        expiresAt: _now().add(expiresIn),
      );
    } on TypeError {
      throw const GoogleDeviceFlowException(GoogleDeviceFlowError.network);
    }
  }

  /// Polls Google every [DeviceCode.interval] (5 s more after each
  /// `slow_down`) until the user approves [code]; returns the `id_token`.
  /// Throws [GoogleDeviceFlowException] when the user denies it, the code
  /// expires or Google cannot be reached, and [GoogleDeviceFlowCancelled]
  /// after [cancel].
  Future<String> waitForIdToken(DeviceCode code) async {
    var interval = code.interval;
    final deadline = code.expiresAt ?? _now().add(code.expiresIn);
    while (true) {
      await (_wait?.call(interval) ?? _sleep(interval));
      if (_cancelled) throw const GoogleDeviceFlowCancelled();
      if (!_now().isBefore(deadline)) {
        throw const GoogleDeviceFlowException(GoogleDeviceFlowError.expired);
      }
      final json = await _post(_tokenUrl, {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'device_code': code.deviceCode,
        'grant_type': _grantType,
      }, acceptErrors: true);
      if (_cancelled) throw const GoogleDeviceFlowCancelled();
      switch (json) {
        case {'id_token': final String idToken}:
          return idToken;
        case {'error': 'authorization_pending'}:
          continue;
        case {'error': 'slow_down'}:
          interval += _slowDownStep;
        case {'error': 'access_denied'}:
          throw const GoogleDeviceFlowException(GoogleDeviceFlowError.denied);
        case {'error': 'expired_token'}:
          throw const GoogleDeviceFlowException(GoogleDeviceFlowError.expired);
        default:
          throw const GoogleDeviceFlowException(GoogleDeviceFlowError.network);
      }
    }
  }

  /// Stops [waitForIdToken] at its next step.
  void cancel() {
    _cancelled = true;
    _sleepTimer?.cancel();
    final sleeping = _sleepDone;
    if (sleeping != null && !sleeping.isCompleted) sleeping.complete();
  }

  /// Waits [duration], or less if [cancel] comes first.
  Future<void> _sleep(Duration duration) {
    final done = _sleepDone = Completer<void>();
    _sleepTimer = Timer(duration, done.complete);
    return done.future;
  }

  /// Cancels and frees the HTTP client.
  void close() {
    cancel();
    _client.close();
  }

  /// Posts [fields] as a form and returns the JSON object answered. Replies
  /// other than 200 count only with [acceptErrors] (the token endpoint
  /// answers its `error`s that way). Anything else is a
  /// [GoogleDeviceFlowError.network].
  Future<Map<String, dynamic>> _post(
    Uri url,
    Map<String, String> fields, {
    bool acceptErrors = false,
  }) async {
    try {
      final response = await _client
          .post(url, body: fields)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 && !acceptErrors) {
        throw const GoogleDeviceFlowException(GoogleDeviceFlowError.network);
      }
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) return json;
    } on http.ClientException {
      // Falls through to the network error.
    } on IOException {
      // Sockets, TLS handshakes (old sticks with a wrong clock): same.
    } on TimeoutException {
      // Same.
    } on FormatException {
      // Not JSON: same.
    }
    throw const GoogleDeviceFlowException(GoogleDeviceFlowError.network);
  }
}
