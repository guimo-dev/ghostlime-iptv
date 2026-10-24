import 'package:flutter/material.dart';

import 'legal_info.dart';

/// Widest the text grows, so lines stay readable on large windows.
const _maxTextWidth = 720.0;

/// Read-only screen showing a legal document ([doc]) from the app assets.
///
/// Renders the simple Markdown of `docs/legal/`: `#` and `##` headings, `- `
/// bullets, `**bold**` runs and paragraphs.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: FutureBuilder<String>(
        future: loadLegalText(doc),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se ha podido cargar el texto.'),
            );
          }
          final text = snapshot.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxTextWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    for (final line in text.split('\n'))
                      if (line.trim().isNotEmpty) _line(context, line),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds the widget for one non-empty Markdown [line].
  Widget _line(BuildContext context, String line) {
    final styles = Theme.of(context).textTheme;
    if (line.startsWith('## ')) {
      return SelectableText(line.substring(3), style: styles.titleMedium);
    }
    if (line.startsWith('# ')) {
      return SelectableText(line.substring(2), style: styles.headlineSmall);
    }
    if (line.startsWith('- ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 16),
        child: SelectableText.rich(
          TextSpan(
            children: [
              const TextSpan(text: '•  '),
              ..._runs(line.substring(2)),
            ],
          ),
        ),
      );
    }
    return SelectableText.rich(TextSpan(children: _runs(line)));
  }

  /// Splits [text] on `**` into plain and bold spans.
  List<TextSpan> _runs(String text) {
    final parts = text.split('**');
    return [
      for (var i = 0; i < parts.length; i++)
        TextSpan(
          text: parts[i],
          style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
    ];
  }
}
