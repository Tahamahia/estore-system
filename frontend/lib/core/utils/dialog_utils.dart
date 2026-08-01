import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A dialog's max height should never be a bare pixel number — it must
/// adapt to the actual browser/window viewport, or content below that
/// number silently renders off-screen with no way to reach it.
double dialogMaxHeight(BuildContext context, {double fraction = 0.85, double cap = 900}) {
  return math.min(cap, MediaQuery.of(context).size.height * fraction);
}
