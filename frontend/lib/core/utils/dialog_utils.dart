import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A dialog's max height should never be a bare pixel number — it must
/// adapt to the actual browser/window viewport, or content below that
/// number silently renders off-screen with no way to reach it.
double dialogMaxHeight(BuildContext context, {double fraction = 0.85, double cap = 900}) {
  return math.min(cap, MediaQuery.of(context).size.height * fraction);
}

/// On mobile (< 720px), dialogs should be nearly full-width.
double dialogMaxWidth(BuildContext context, {double desktopMax = 540}) {
  final w = MediaQuery.of(context).size.width;
  return w < 720 ? w * 0.95 : desktopMax;
}

/// True when the current viewport is phone-sized.
bool isMobile(BuildContext context) =>
    MediaQuery.of(context).size.width < 720;
