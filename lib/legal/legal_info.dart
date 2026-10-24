import 'package:flutter/services.dart';

/// Version of the terms; bump it when they change so users accept again.
const termsVersion = 1;

/// Markers left in the legal texts until the owner provides the real data.
const legalPlaceholders = ['[DOMINIO]', '[EMAIL_CONTACTO]', '[RESPONSABLE]'];

/// The two legal documents shown in the app.
enum LegalDoc {
  terms('docs/legal/terminos.md', 'Términos de uso'),
  privacy('docs/legal/privacidad.md', 'Política de privacidad');

  const LegalDoc(this.assetPath, this.title);

  /// Asset holding the Markdown text.
  final String assetPath;

  /// Spanish title shown in the reader.
  final String title;
}

/// Whether [text] still contains any of the [legalPlaceholders].
bool hasPlaceholders(String text) => legalPlaceholders.any(text.contains);

/// Reads the Markdown text of [doc] from the app assets.
Future<String> loadLegalText(LegalDoc doc) =>
    rootBundle.loadString(doc.assetPath);
