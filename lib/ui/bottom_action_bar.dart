import 'package:flutter/material.dart';

import 'form_factor.dart';

/// Whether the screen around [context] puts its Cancelar/Guardar actions in
/// a [BottomActionBar]: the phone layout held upright. A landscape phone
/// keeps them in the app bar: with the keyboard open, a bar at the bottom
/// would leave almost no room for the field being typed in.
bool usesBottomActions(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return usesPhoneLayout(context) && size.height > size.width;
}

/// Bottom bar of a phone screen, within the thumb's reach: "Cancelar" on
/// the left and the filled primary action on the right, each half the width.
///
/// Put it at the end of the body (not in `Scaffold.bottomNavigationBar`) so
/// it rides above the keyboard when the body shrinks for it.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.saveLabel = 'Guardar',
  });

  /// Runs on "Cancelar".
  final VoidCallback onCancel;

  /// Runs on the primary action; `null` disables it.
  final VoidCallback? onSave;

  /// Label of the primary action.
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              phonePageMargin,
              12,
              phonePageMargin,
              12,
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Cancelar'),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: onSave,
                    child: Text(saveLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
