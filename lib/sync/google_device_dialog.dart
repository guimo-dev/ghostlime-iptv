import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../ui/app_theme.dart';
import 'account_service.dart';
import 'auth_gateway.dart' show AccountException;
import 'google_device_flow.dart';

/// Opens the TV's Google sign-in ([GoogleDeviceDialog]) for [account].
/// Returns `true` when it left a session open (signed in, or a state to
/// settle in Ajustes → Cuenta such as [AccountStatus.needsPassword]); `false`
/// when it was cancelled or closed with Back.
Future<bool> showGoogleDeviceDialog(
  BuildContext context,
  AccountService account,
) async {
  final signedIn = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => GoogleDeviceDialog(account: account),
  );
  return signedIn ?? false;
}

/// Where the dialog stands.
enum _Phase { starting, waiting, signingIn, failed }

/// Google sign-in on a TV: shows a QR of Google's verification address, the
/// code to type there and the time left, while it polls Google
/// ([newGoogleTvFlow]). With the `id_token` it signs [account] in and closes
/// with `true`. Failures show their message with "Reintentar"; "Cancelar" and
/// Back close it and stop the polling.
class GoogleDeviceDialog extends StatefulWidget {
  const GoogleDeviceDialog({super.key, required this.account});

  final AccountService account;

  @override
  State<GoogleDeviceDialog> createState() => _GoogleDeviceDialogState();
}

class _GoogleDeviceDialogState extends State<GoogleDeviceDialog> {
  static const _networkMessage =
      'No se ha podido conectar con Google. Comprueba tu red e inténtalo de '
      'nuevo.';

  final GoogleDeviceFlow _flow = newGoogleTvFlow();
  final _cancelFocus = FocusNode();
  final _retryFocus = FocusNode();

  _Phase _phase = _Phase.starting;
  DeviceCode? _code;
  String? _error;

  /// How long the shown code still lasts.
  Duration _left = Duration.zero;

  /// Ticks the countdown every second while waiting.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _flow.close();
    _cancelFocus.dispose();
    _retryFocus.dispose();
    super.dispose();
  }

  /// Gets a code, waits for the user to approve it and signs in.
  Future<void> _run() async {
    _setPhase(_Phase.starting);
    try {
      final code = await _flow.start();
      if (!mounted) return;
      _code = code;
      _left = code.expiresIn;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (ticker) {
        if (!mounted) return;
        setState(() => _left -= const Duration(seconds: 1));
        if (_left <= Duration.zero) ticker.cancel();
      });
      _setPhase(_Phase.waiting);
      final idToken = await _flow.waitForIdToken(code);
      if (!mounted) return;
      _ticker?.cancel();
      _setPhase(_Phase.signingIn);
      await widget.account.signInWithGoogleIdToken(idToken);
      if (!mounted) return;
      final status = widget.account.status;
      Navigator.pop(
        context,
        status != AccountStatus.signedOut &&
            status != AccountStatus.awaitingConfirmation,
      );
    } on GoogleDeviceFlowCancelled {
      // Closed: nothing to show.
    } on GoogleDeviceFlowException catch (e) {
      _fail(switch (e.kind) {
        GoogleDeviceFlowError.denied => 'Se ha denegado el acceso con Google.',
        GoogleDeviceFlowError.expired =>
          'El código ha caducado. Pide otro con «Reintentar».',
        GoogleDeviceFlowError.network => _networkMessage,
      });
    } on AccountException catch (e) {
      _fail(e.message);
    } catch (_) {
      // Anything else (never shown raw) must not leave the spinner up.
      _fail(_networkMessage);
    }
  }

  /// "Reintentar": starts over, once, and only after a failure.
  void _retry() {
    if (_phase == _Phase.failed) unawaited(_run());
  }

  /// Shows [message] with "Reintentar", which takes the focus.
  void _fail(String message) {
    if (!mounted) return;
    _ticker?.cancel();
    _error = message;
    _setPhase(_Phase.failed);
  }

  /// Moves to [phase] and gives the focus to its main button: "Reintentar"
  /// after a failure, "Cancelar" otherwise.
  void _setPhase(_Phase phase) {
    if (!mounted) return;
    setState(() => _phase = phase);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (phase == _Phase.failed ? _retryFocus : _cancelFocus).requestFocus();
    });
  }

  /// The time left as `m:ss`.
  String _timeLeft() {
    final seconds = _left.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Signing in cannot be stopped halfway: closing then would leave a
    // session open that nobody goes on with.
    final signingIn = _phase == _Phase.signingIn;
    return PopScope(
      canPop: !signingIn,
      child: AlertDialog(
        title: const Text('Entrar con Google'),
        content: SizedBox(
          width: 560,
          child: switch (_phase) {
            _Phase.starting => const _Busy('Pidiendo un código a Google…'),
            _Phase.signingIn => const _Busy('Entrando en tu cuenta…'),
            _Phase.waiting => _CodePanel(code: _code!, timeLeft: _timeLeft()),
            _Phase.failed => Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          },
        ),
        actions: [
          TextButton(
            focusNode: _cancelFocus,
            autofocus: true,
            onPressed: signingIn ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          if (_phase == _Phase.failed)
            FilledButton(
              focusNode: _retryFocus,
              onPressed: _retry,
              child: const Text('Reintentar'),
            ),
        ],
      ),
    );
  }
}

/// A progress indicator with [message].
class _Busy extends StatelessWidget {
  const _Busy(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 16,
      children: [
        const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        Expanded(child: Text(message)),
      ],
    );
  }
}

/// The QR of the verification address, the steps, the [code] in big letters
/// and the [timeLeft].
class _CodePanel extends StatelessWidget {
  const _CodePanel({required this.code, required this.timeLeft});

  final DeviceCode code;
  final String timeLeft;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final address = code.verificationUrl.replaceFirst(RegExp('^https?://'), '');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 24,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: QrImageView(
            data: code.verificationUrl,
            size: 168,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            semanticsLabel: 'Código QR de $address',
          ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(
                'En el móvil o el ordenador, escanea el código QR o abre '
                '$address y escribe este código:',
              ),
              Text(
                code.userCode,
                style: text.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
              Text(
                'Caduca en $timeLeft',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
