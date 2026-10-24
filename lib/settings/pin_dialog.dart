import 'package:flutter/material.dart';

import 'pin_store.dart';

/// Asks for a 4-digit PIN. With [confirm], asks twice and checks both match.
/// Returns the PIN, or `null` when cancelled.
Future<String?> askPin(
  BuildContext context, {
  required String title,
  bool confirm = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(title: title, confirm: confirm),
  );
}

/// Asks for the current PIN and checks it. Returns whether it matched.
Future<bool> verifyPin(BuildContext context, PinStore store) async {
  final pin = await askPin(context, title: 'Introduce el PIN');
  if (pin == null) return false;
  final ok = await store.verify(pin);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN incorrecto.')));
  }
  return ok;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, required this.confirm});

  final String title;
  final bool confirm;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _first.text;
    if (!isValidPin(pin)) {
      setState(() => _error = 'El PIN son 4 números.');
      return;
    }
    if (widget.confirm && pin != _second.text) {
      setState(() => _error = 'Los PIN no coinciden.');
      return;
    }
    Navigator.pop(context, pin);
  }

  Widget _field(TextEditingController controller, String label, bool focus) {
    return TextField(
      controller: controller,
      autofocus: focus,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      decoration: InputDecoration(labelText: label, counterText: ''),
      onSubmitted: (_) => _submit(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_first, 'PIN', true),
            if (widget.confirm) ...[
              const SizedBox(height: 12),
              _field(_second, 'Repite el PIN', false),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Aceptar')),
      ],
    );
  }
}
