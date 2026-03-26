import 'package:flutter/material.dart';

class Responsive {
  static bool isSizeMobile(BuildContext ctx)  => MediaQuery.of(ctx).size.width < 600;
  static bool isSizeTablet(BuildContext ctx)  => MediaQuery.of(ctx).size.width >= 600 && MediaQuery.of(ctx).size.width < 1024;
  static bool isSizeDesktop(BuildContext ctx) => MediaQuery.of(ctx).size.width >= 1024;

  static T value<T>(BuildContext ctx, {required T mobile, required T tablet, required T desktop}) {
    double width = MediaQuery.of(ctx).size.width;
    if (width >= 1024) return desktop;
    if (width >= 600)  return tablet;
    return mobile;
  }
}
