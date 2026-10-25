import 'package:flutter/material.dart';

import '../legal/legal_notice.dart';
import '../sync/account_form.dart';
import '../sync/account_service.dart';
import '../sync/google_sign_in.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import '../ui/brand_state.dart';
import '../ui/ghostlime_logo.dart';

/// Widest the first-run content grows.
const _maxWidth = 520.0;

/// Shown once per installation: what the app is (and is not) and the
/// account options. Unless [termsAccepted] (the current terms), it opens the
/// legal notice; the options stay disabled until it is accepted, and after
/// "Rechazar" a "Revisar términos" link opens it again. Without an [account]
/// (a build without Supabase) the only option is "Continuar sin cuenta".
/// [onDone] runs when the user is through, with or without an account.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    this.account,
    this.termsAccepted = false,
    required this.onDone,
  });

  final AccountService? account;
  final bool termsAccepted;
  final VoidCallback onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late bool _accepted = widget.termsAccepted;

  /// Whether the legal notice was closed with "Rechazar".
  bool _rejected = false;

  @override
  void initState() {
    super.initState();
    if (!_accepted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reviewTerms());
    }
  }

  /// Opens the legal notice and keeps the answer.
  Future<void> _reviewTerms() async {
    final accepted = await showLegalNotice(context);
    if (!mounted) return;
    setState(() {
      _accepted = accepted;
      _rejected = !accepted;
    });
  }

  /// Opens the shared account form in a dialog titled [title]; finishes the
  /// welcome when it leaves a session open. A session that still needs a
  /// decision also finishes it: the app then opens Ajustes → Cuenta.
  Future<void> _openAccountForm(AccountService account, String title) async {
    final signedIn = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    accountSyncExplanation(
                      supportsGoogle: account.supportsGoogle,
                    ),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
                AccountForm(
                  account: account,
                  onSignedIn: () => Navigator.pop(context, true),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (signedIn == true) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final account = widget.account;
    VoidCallback? whenAccepted(VoidCallback action) =>
        _accepted ? action : null;
    return _FirstRunFrame(
      children: [
        const Center(
          child: GhostlimeLogo(size: 96, semanticLabel: 'Ghostlime'),
        ),
        const SizedBox(height: 20),
        Text.rich(
          const TextSpan(
            text: 'Ghostlime ',
            children: [
              TextSpan(
                text: 'IPTV',
                style: TextStyle(color: AppColors.accent),
              ),
            ],
          ),
          style: text.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Reproductor para tus listas IPTV',
          style: text.titleMedium?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (_rejected) ...[
          _TermsRejected(onReview: _reviewTerms),
          const SizedBox(height: 24),
        ],
        if (account == null)
          FilledButton(
            onPressed: whenAccepted(widget.onDone),
            child: const Text('Continuar sin cuenta'),
          )
        else ...[
          FilledButton(
            onPressed: whenAccepted(
              () => _openAccountForm(account, 'Entrar con email'),
            ),
            child: const Text('Entrar con email'),
          ),
          const SizedBox(height: 12),
          if (account.supportsGoogle)
            GoogleSignInButton(
              account: account,
              enabled: _accepted,
              showsError: true,
              onSignedIn: widget.onDone,
            )
          else
            // No way back from the browser on this platform yet.
            const Tooltip(
              message: 'Disponible pronto',
              child: OutlinedButton(
                onPressed: null,
                child: Text('Continuar con Google'),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: whenAccepted(widget.onDone),
            child: const Text('Continuar sin cuenta'),
          ),
          const SizedBox(height: 32),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              const Text(
                '¿No tienes cuenta?',
                style: TextStyle(color: AppColors.textMuted),
              ),
              TextButton(
                onPressed: whenAccepted(
                  () => _openAccountForm(account, 'Crear cuenta'),
                ),
                child: const Text('Crear cuenta'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Asks an existing installation to accept the terms, the first time or after
/// they changed (`termsVersion`), without the rest of the welcome: it opens
/// the legal notice and, after "Rechazar", stays with a "Revisar términos"
/// link. [onAccepted] runs on "Aceptar".
class AcceptTermsScreen extends StatefulWidget {
  const AcceptTermsScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  State<AcceptTermsScreen> createState() => _AcceptTermsScreenState();
}

class _AcceptTermsScreenState extends State<AcceptTermsScreen> {
  /// Whether the legal notice was closed with "Rechazar".
  bool _rejected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reviewTerms());
  }

  /// Opens the legal notice; goes on when accepted.
  Future<void> _reviewTerms() async {
    final accepted = await showLegalNotice(context);
    if (!mounted) return;
    if (accepted) {
      widget.onAccepted();
    } else {
      setState(() => _rejected = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FirstRunFrame(
      children: [
        const BrandMessage(
          title: 'Términos de uso y privacidad',
          message:
              'Para seguir usando Ghostlime IPTV, lee y acepta los términos '
              'de uso y la política de privacidad.',
          logoSize: 96,
        ),
        if (_rejected) ...[
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: _reviewTerms,
              child: const Text('Revisar términos'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Branded, scrollable, centred column shared by the first-run screens. It
/// cannot be left with the back key: the screens finish through their
/// buttons.
class _FirstRunFrame extends StatelessWidget {
  const _FirstRunFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(
          // Keeps the content clear of a phone's status bar.
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the welcome shows after "Rechazar": the terms are needed to go on,
/// and [onReview] ("Revisar términos") opens the legal notice again.
class _TermsRejected extends StatelessWidget {
  const _TermsRejected({required this.onReview});

  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Para usar Ghostlime IPTV tienes que aceptar los términos de uso '
            'y la política de privacidad.',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onReview,
              child: const Text('Revisar términos'),
            ),
          ),
        ],
      ),
    );
  }
}
