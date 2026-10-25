import 'package:flutter/material.dart';

import '../ui/form_factor.dart';
import 'legal_info.dart';
import 'legal_screen.dart';

/// Title of the legal notice.
const _noticeTitle = 'Términos de uso y privacidad';

/// The short "only a player" text of the legal notice.
const legalNoticeText =
    'Ghostlime IPTV es solo un reproductor: no incluye ni proporciona canales '
    'ni contenido. Añade solo listas que tengas derecho a usar. Para usar la '
    'app, acepta los términos de uso y la política de privacidad.';

/// Shows the legal notice with "Aceptar", "Leer más" and "Rechazar": a
/// dialog in the desktop layout, a sheet from the bottom in the phone layout
/// (the main button bottom right). It cannot be dismissed by tapping outside;
/// going back counts as "Rechazar". Returns whether the user accepted.
Future<bool> showLegalNotice(BuildContext context) async {
  final bool? accepted;
  if (usesPhoneLayout(context)) {
    accepted = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (context) => const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 16, 16),
          child: _NoticeBody(),
        ),
      ),
    );
  } else {
    accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _NoticeDialog(),
    );
  }
  return accepted ?? false;
}

/// The notice as a dialog, for the desktop layout.
class _NoticeDialog extends StatelessWidget {
  const _NoticeDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 16, 16),
          child: _NoticeBody(),
        ),
      ),
    );
  }
}

/// Title, text and the three options, "Rechazar", "Leer más" and "Aceptar"
/// (the last, on the right; stacked at the bottom when the row does not
/// fit). "Leer más" shows the links to both documents and moves the focus
/// to the first. The notice closes once, with `true` ("Aceptar") or `false`
/// ("Rechazar", also Escape); the same in the dialog and the sheet, which
/// screen readers announce by the title.
class _NoticeBody extends StatefulWidget {
  const _NoticeBody();

  @override
  State<_NoticeBody> createState() => _NoticeBodyState();
}

class _NoticeBodyState extends State<_NoticeBody> {
  bool _showsDocs = false;

  /// Whether an answer already closed the notice (a double tap pops once).
  bool _answered = false;

  /// Focus of the first document link, given when "Leer más" shows them.
  final _firstDocFocus = FocusNode(debugLabel: 'First legal document');

  @override
  void dispose() {
    _firstDocFocus.dispose();
    super.dispose();
  }

  /// Closes the notice with [accepted], only the first time.
  void _answer(bool accepted) {
    if (_answered) return;
    _answered = true;
    Navigator.pop(context, accepted);
  }

  /// Shows the document links and focuses the first one.
  void _showDocs() {
    setState(() => _showsDocs = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstDocFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: _noticeTitle,
      child: Actions(
        // The route ignores Escape (it cannot be dismissed): answer instead.
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => _answer(false),
          ),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                _noticeTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(legalNoticeText),
            ),
            if (_showsDocs) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final doc in LegalDoc.values)
                    TextButton(
                      focusNode: doc == LegalDoc.values.first
                          ? _firstDocFocus
                          : null,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LegalScreen(doc: doc),
                        ),
                      ),
                      child: Text(doc.title),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => _answer(false),
                  child: const Text('Rechazar'),
                ),
                TextButton(onPressed: _showDocs, child: const Text('Leer más')),
                FilledButton(
                  autofocus: true,
                  onPressed: () => _answer(true),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
