import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

Widget iconSvg(
  String assetName,
  ThemeProvider? themeProvider, {
  double size = 24,
  bool isActive = false,
  bool alwaysActive = false, // NEW: Force active color even if not selected
}) {
  return SvgPicture.asset(
    assetName,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      isActive
          ? (themeProvider?.primaryColor ?? Colors.black)
          : alwaysActive
          ? Colors.black
          : Colors.grey,
      BlendMode.srcIn,
    ),
  );
}
