import 'package:flutter/widgets.dart';

import 'account_service.dart';

/// Exposes the [AccountService] to the widget tree; the service is `null` when
/// this build has no Supabase configured.
class AccountScope extends InheritedNotifier<AccountService> {
  const AccountScope({
    super.key,
    required AccountService? service,
    required super.child,
  }) : super(notifier: service);

  /// The service, rebuilding the caller whenever the account changes; `null`
  /// when sync is not configured.
  static AccountService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()?.notifier;

  /// The service without subscribing to changes.
  static AccountService? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AccountScope>()?.notifier;
}
