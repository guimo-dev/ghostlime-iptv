import 'package:flutter/material.dart';

/// Asks whether to leave the app ("¿Salir de Ghostlime?"), with the focus on
/// Cancelar so a stray press of the remote does not close it. Returns `true`
/// for Salir; `false` for Cancelar or when dismissed.
Future<bool> confirmExit(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Salir de Ghostlime?'),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Salir'),
        ),
      ],
    ),
  );
  return leave ?? false;
}
