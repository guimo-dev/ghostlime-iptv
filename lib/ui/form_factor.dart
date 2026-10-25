import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// Device class by the shortest side, in any orientation.
enum FormFactor { phone, tablet }

/// Shortest side, in logical pixels, from which a device counts as a tablet.
const _tabletShortestSide = 600;

/// Width, in logical pixels, from which a tablet uses the desktop layout.
const _desktopMinWidth = 1024;

/// Whether a screen of [size] is a phone (shortest side under 600) or a tablet.
FormFactor formFactorOf(Size size) =>
    math.min(size.width, size.height) < _tabletShortestSide
    ? FormFactor.phone
    : FormFactor.tablet;

/// Whether a screen of [size] gets the desktop layout (side bar): a tablet at
/// least 1024 wide. Portrait tablets and phones use the phone layout.
bool usesDesktopLayout(Size size) =>
    formFactorOf(size) == FormFactor.tablet && size.width >= _desktopMinWidth;

/// Whether the app runs on a phone or tablet system (Android, iOS), where
/// the player takes touch gestures and turning the device matters.
bool get isTouchPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Side margin of pages in the phone layout.
const phonePageMargin = 16.0;

/// Whether the screen around [context] uses the phone layout (bottom bar):
/// phones in any orientation and portrait tablets.
bool usesPhoneLayout(BuildContext context) =>
    !usesDesktopLayout(MediaQuery.sizeOf(context));
