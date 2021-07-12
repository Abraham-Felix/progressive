// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'package:flutter_gallery/demo/shrine/backdrop.dart';
import 'package:flutter_gallery/demo/shrine/category_menu_page.dart';
import 'package:flutter_gallery/demo/shrine/colors.dart';
import 'package:flutter_gallery/demo/shrine/expanding_bottom_sheet.dart';
import 'package:flutter_gallery/demo/shrine/home.dart';
import 'package:flutter_gallery/demo/shrine/login.dart';
import 'package:flutter_gallery/demo/shrine/supplemental/cut_corners_border.dart';

class ShrineApp extends StatefulWidget {
  const ShrineApp({Key? key}) : super(key: key);

  @override
  _ShrineAppState createState() => _ShrineAppState();
}

class _ShrineAppState extends State<ShrineApp> with SingleTickerProviderStateMixin {
  // Controller to coordinate both the opening/closing of backdrop and sliding
  // of expanding bottom sheet
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: 1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shrine',
      home: HomePage(
        backdrop: Backdrop(
          frontLayer: const ProductPage(),
          backLayer: CategoryMenuPage(onCategoryTap: () => _controller.forward()),
          frontTitle: const Text('SHRINE'),
          backTitle: const Text('MENU'),
          controller: _controller,
        ),
        expandingBottomSheet: ExpandingBottomSheet(hideController: _controller),
      ),
      initialRoute: '/login',
      onGenerateRoute: _getRoute,
      // Copy the platform from the main theme in order to support platform
      // toggling from the Gallery options menu.
      theme: _kShrineTheme.copyWith(platform: Theme.of(context).platform),
    );
  }
}

Route<dynamic>? _getRoute(RouteSettings settings) {
  if (settings.name != '/login') {
    return null;
  }

  return MaterialPageRoute<void>(
    settings: settings,
    builder: (BuildContext context) => const LoginPage(),
    fullscreenDialog: true,
  );
}

final ThemeData _kShrineTheme = _buildShrineTheme();

IconThemeData _customIconTheme(IconThemeData original) {
  return original.copyWith(color: kShrineBrown900);
}

ThemeData _buildShrineTheme() {
  final ThemeData base = ThemeData.light();
  return base.copyWith(
    colorScheme: kShrineColorScheme,
    primaryColor: kShrinePink100,
    scaffoldBackgroundColor: kShrineBackgroundWhite,
    cardColor: kShrineBackgroundWhite,
    errorColor: kShrineErrorRed,
    primaryIconTheme: _customIconTheme(base.iconTheme),
    inputDecorationTheme: const InputDecorationTheme(border: CutCornersBorder()),
    textTheme: _buildShrineTextTheme(base.textTheme),
    primaryTextTheme: _buildShrineTextTheme(base.primaryTextTheme),
    iconTheme: _customIconTheme(base.iconTheme),
  );
}

TextTheme _buildShrineTextTheme(TextTheme base) {
  return base.copyWith(
    headline5: base.headline5!.copyWith(fontWeight: FontWeight.w500),
    headline6: base.headline6!.copyWith(fontSize: 18.0),
    caption: base.caption!.copyWith(fontWeight: FontWeight.w400, fontSize: 14.0),
    bodyText1: base.bodyText1!.copyWith(fontWeight: FontWeight.w500, fontSize: 16.0),
    button: base.button!.copyWith(fontWeight: FontWeight.w500, fontSize: 14.0),
  ).apply(
    fontFamily: 'Raleway',
    displayColor: kShrineBrown900,
    bodyColor: kShrineBrown900,
  );
}

const ColorScheme kShrineColorScheme = ColorScheme(
  primary: kShrinePink100,
  primaryVariant: kShrineBrown900,
  secondary: kShrinePink50,
  secondaryVariant: kShrineBrown900,
  surface: kShrineSurfaceWhite,
  background: kShrineBackgroundWhite,
  error: kShrineErrorRed,
  onPrimary: kShrineBrown900,
  onSecondary: kShrineBrown900,
  onSurface: kShrineBrown900,
  onBackground: kShrineBrown900,
  onError: kShrineSurfaceWhite,
  brightness: Brightness.light,
);
