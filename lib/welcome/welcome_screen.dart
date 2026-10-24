import 'package:flutter/material.dart';

import '../legal/legal_info.dart';
import '../legal/legal_screen.dart';
import '../sync/account_form.dart';
import '../sync/account_service.dart';
import '../ui/app_theme.dart';
import '../ui/backdrop.dart';
import '../ui/brand_state.dart';
import '../ui/ghostlime_logo.dart';

/// Widest the first-run content grows.
const _maxWidth = 520.0;

/// "Continuar con Google", always disabled for now: Google sign-in does not
/// exist yet.
const _googleButton = OutlinedButton(
  onPressed: null,
  child: Text('Continuar con Google'),
);

/// Shown once per installation: what the app is (and is not), the terms to
/// accept and the account options. The options stay disabled until the terms
/// are accepted. Without an [account] (a build without Supabase) the only
/// option is "Continuar sin cuenta". [onDone] runs when the user is through,
/// with or without an account.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.account, required this.onDone});

  final AccountService? account;
  final VoidCallback onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _accepted = false;

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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    accountSyncExplanation,
                    style: TextStyle(color: AppColors.textMuted),
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
        _TermsNotice(
          accepted: _accepted,
          onAccept: () => setState(() => _accepted = true),
        ),
        const SizedBox(height: 24),
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
          OutlinedButton(
            onPressed: whenAccepted(
              () => _openAccountForm(account, 'Crear cuenta'),
            ),
            child: const Text('Crear cuenta'),
          ),
          const SizedBox(height: 12),
          // TODO(task 5): enable with AccountService.signInWithGoogle once
          // the gateway supports it (AccountService.supportsGoogle).
          const Tooltip(message: 'Disponible pronto', child: _googleButton),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: whenAccepted(widget.onDone),
            child: const Text('Continuar sin cuenta'),
          ),
        ],
      ],
    );
  }
}

/// Asks an existing installation to accept the terms, the first time or after
/// they changed ([termsVersion]), without the rest of the welcome.
/// [onAccepted] runs on "Acepto y continúo".
class AcceptTermsScreen extends StatelessWidget {
  const AcceptTermsScreen({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

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
        const SizedBox(height: 32),
        _TermsNotice(accepted: false, onAccept: onAccepted),
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
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
    );
  }
}

/// The "only a player" notice with links to the terms and the privacy policy
/// and the "Acepto y continúo" button ([onAccept]); once [accepted], a check
/// instead of the button.
class _TermsNotice extends StatelessWidget {
  const _TermsNotice({required this.accepted, required this.onAccept});

  final bool accepted;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ghostlime IPTV es solo un reproductor: no incluye ni proporciona '
            'canales ni contenido. Añade solo listas que tengas derecho a '
            'usar. Al continuar aceptas los términos de uso y la política de '
            'privacidad.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final doc in LegalDoc.values)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LegalScreen(doc: doc),
                    ),
                  ),
                  child: Text(doc.title),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (accepted)
            const Row(
              spacing: 8,
              children: [
                Icon(Icons.check_circle, color: AppColors.accent),
                Text('Términos aceptados'),
              ],
            )
          else
            FilledButton(
              autofocus: true,
              onPressed: onAccept,
              child: const Text('Acepto y continúo'),
            ),
        ],
      ),
    );
  }
}
