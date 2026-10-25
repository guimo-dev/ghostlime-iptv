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

/// Title, text, "Leer más" (which shows the links to both documents) and the
/// answers, which close the notice with `true` ("Aceptar", on the right) or
/// `false` ("Rechazar", on the left); the same in the dialog and the sheet.
class _NoticeBody extends StatefulWidget {
  const _NoticeBody();

  @override
  State<_NoticeBody> createState() => _NoticeBodyState();
}

class _NoticeBodyState extends State<_NoticeBody> {
  bool _showsDocs = false;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 8),
        // "Leer más" sits under the text, so the two answers fit in one row
        // even on narrow phones; it gives way to the two documents.
        Wrap(
          spacing: 8,
          children: [
            if (_showsDocs)
              for (final doc in LegalDoc.values)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LegalScreen(doc: doc),
                    ),
                  ),
                  child: Text(doc.title),
                )
            else
              TextButton(
                onPressed: () => setState(() => _showsDocs = true),
                child: const Text('Leer más'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Rechazar'),
            ),
            const Spacer(),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ],
    );
  }
}
