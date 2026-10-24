import 'dart:math' as math;
import 'dart:ui';

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
