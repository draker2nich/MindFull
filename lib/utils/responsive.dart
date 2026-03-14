import 'dart:math';
import 'package:flutter/material.dart';

/// Responsive sizing utilities.
///
/// Usage:
///   final r = Responsive(context);
///   r.sp(16)  — scalable font size
///   r.wp(80)  — 80% of width
///   r.hp(50)  — 50% of height
///   r.dp(24)  — density-independent size that scales slightly with screen
class Responsive {
  final BuildContext context;
  late final Size _size;
  late final double _scaleFactor;
  late final bool isSmall;
  late final bool isLandscape;

  Responsive(this.context) {
    final mq = MediaQuery.of(context);
    _size = mq.size;
    isLandscape = _size.width > _size.height;

    // Base scale factor relative to a 390px wide reference screen
    final shortSide = min(_size.width, _size.height);
    _scaleFactor = (shortSide / 390).clamp(0.8, 1.4);
    isSmall = shortSide < 360;
  }

  double get width => _size.width;
  double get height => _size.height;

  /// Width percentage (0-100)
  double wp(double percent) => _size.width * percent / 100;

  /// Height percentage (0-100)
  double hp(double percent) => _size.height * percent / 100;

  /// Scaled dp — adapts to screen size
  double dp(double value) => value * _scaleFactor;

  /// Scaled sp for text
  double sp(double value) => value * _scaleFactor;

  /// Horizontal padding that adapts to screen width
  double get horizontalPadding {
    if (_size.width > 600) return 32;
    if (_size.width > 400) return 20;
    return 16;
  }

  /// Max content width for tablets
  double get maxContentWidth => min(_size.width, 560);
}