// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui hide window;

/// [SingletonFlutterWindow] that wraps another [SingletonFlutterWindow] and
/// allows faking of some properties for testing purposes.
///
/// Tests for certain widgets, e.g., [MaterialApp], might require faking certain
/// properties of a [SingletonFlutterWindow]. [TestWindow] facilitates the
/// faking of these properties by overriding the properties of a real
/// [SingletonFlutterWindow] with desired fake values. The binding used within
/// tests, [TestWidgetsFlutterBinding], contains a [TestWindow] that is used by
/// all tests.
///
/// ## Sample Code
///
/// A test can utilize a [TestWindow] in the following way:
///
/// ```dart
/// testWidgets('your test name here', (WidgetTester tester) async {
///   // Retrieve the TestWidgetsFlutterBinding.
///   final TestWidgetsFlutterBinding testBinding = tester.binding;
///
///   // Fake the desired properties of the TestWindow. All code running
///   // within this test will perceive the following fake text scale
///   // factor as the real text scale factor of the window.
///   testBinding.window.textScaleFactorFakeValue = 2.5;
///
///   // Test code that depends on text scale factor here.
/// });
/// ```
///
/// The [TestWidgetsFlutterBinding] is recreated for each test and
/// therefore any fake values defined in one test will not persist
/// to the next.
///
/// If a test needs to override a real [SingletonFlutterWindow] property and
/// then later return to using the real [SingletonFlutterWindow] property,
/// [TestWindow] provides methods to clear each individual test value, e.g.,
/// [clearLocaleTestValue()].
///
/// To clear all fake test values in a [TestWindow], consider using
/// [clearAllTestValues()].
class TestWindow implements ui.SingletonFlutterWindow {
  /// Constructs a [TestWindow] that defers all behavior to the given
  /// [dart:ui.SingletonFlutterWindow] unless explicitly overridden for test purposes.
  TestWindow({
    required ui.SingletonFlutterWindow window,
  }) : _window = window;

  /// The [dart:ui.SingletonFlutterWindow] that is wrapped by this [TestWindow].
  final ui.SingletonFlutterWindow _window;

  @override
  double get devicePixelRatio => _devicePixelRatio ?? _window.devicePixelRatio;
  double? _devicePixelRatio;
  /// Hides the real device pixel ratio and reports the given [devicePixelRatio]
  /// instead.
  set devicePixelRatioTestValue(double devicePixelRatio) {
    _devicePixelRatio = devicePixelRatio;
    onMetricsChanged?.call();
  }
  /// Deletes any existing test device pixel ratio and returns to using the real
  /// device pixel ratio.
  void clearDevicePixelRatioTestValue() {
    _devicePixelRatio = null;
    onMetricsChanged?.call();
  }

  @override
  ui.Size get physicalSize => _physicalSizeTestValue ?? _window.physicalSize;
  ui.Size? _physicalSizeTestValue;
  /// Hides the real physical size and reports the given [physicalSizeTestValue]
  /// instead.
  set physicalSizeTestValue (ui.Size physicalSizeTestValue) {
    _physicalSizeTestValue = physicalSizeTestValue;
    onMetricsChanged?.call();
  }
  /// Deletes any existing test physical size and returns to using the real
  /// physical size.
  void clearPhysicalSizeTestValue() {
    _physicalSizeTestValue = null;
    onMetricsChanged?.call();
  }

  @override
  ui.WindowPadding get viewInsets => _viewInsetsTestValue ??  _window.viewInsets;
  ui.WindowPadding? _viewInsetsTestValue;
  /// Hides the real view insets and reports the given [viewInsetsTestValue]
  /// instead.
  set viewInsetsTestValue(ui.WindowPadding viewInsetsTestValue) {
    _viewInsetsTestValue = viewInsetsTestValue;
    onMetricsChanged?.call();
  }
  /// Deletes any existing test view insets and returns to using the real view
  /// insets.
  void clearViewInsetsTestValue() {
    _viewInsetsTestValue = null;
    onMetricsChanged?.call();
  }

  @override
  ui.WindowPadding get viewPadding => _viewPaddingTestValue ?? _window.padding;
  ui.WindowPadding? _viewPaddingTestValue;
  /// Hides the real view padding and reports the given [paddingTestValue]
  /// instead.
  set viewPaddingTestValue(ui.WindowPadding viewPaddingTestValue) {
    _viewPaddingTestValue = viewPaddingTestValue;
    onMetricsChanged?.call();
  }
  /// Deletes any existing test view padding and returns to using the real
  /// viewPadding.
  void clearViewPaddingTestValue() {
    _viewPaddingTestValue = null;
    onMetricsChanged?.call();
  }

  @override
  ui.WindowPadding get padding => _paddingTestValue ?? _window.padding;
  ui.WindowPadding? _paddingTestValue;
  /// Hides the real padding and reports the given [paddingTestValue] instead.
  set paddingTestValue(ui.WindowPadding paddingTestValue) {
    _paddingTestValue = paddingTestValue;
    onMetricsChanged?.call();
  }
  /// Deletes any existing test padding and returns to using the real padding.
  void clearPaddingTestValue() {
    _paddingTestValue = null;
    onMetricsChanged?.call();
  }

  @override
  ui.WindowPadding get systemGestureInsets => _systemGestureInsetsTestValue ?? _window.systemGestureInsets;
  ui.WindowPadding? _systemGestureInsetsTestValue;
  /// Hides the real system gesture insets and reports the given [systemGestureInsetsTestValue] instead.
  set systemGestureInsetsTestValue(ui.WindowPadding systemGestureInsetsTestValue) {
    _systemGestureInsetsTestValue = systemGestureInsetsTestValue;
    onMetricsChanged?.call();
  }
  /// Deletes any existing test system gesture insets and returns to using the real system gesture insets.
  void clearSystemGestureInsetsTestValue() {
    _systemGestureInsetsTestValue = null;
    onMetricsChanged?.call();
  }

  @override
  ui.VoidCallback? get onMetricsChanged => platformDispatcher.onMetricsChanged;
  @override
  set onMetricsChanged(ui.VoidCallback? callback) {
    platformDispatcher.onMetricsChanged = callback;
  }

  @override
  ui.Locale get locale => _localeTestValue ?? platformDispatcher.locale;
  ui.Locale? _localeTestValue;
  /// Hides the real locale and reports the given [localeTestValue] instead.
  set localeTestValue(ui.Locale localeTestValue) {
    _localeTestValue = localeTestValue;
    onLocaleChanged?.call();
  }
  /// Deletes any existing test locale and returns to using the real locale.
  void clearLocaleTestValue() {
    _localeTestValue = null;
    onLocaleChanged?.call();
  }

  @override
  List<ui.Locale> get locales => _localesTestValue ?? platformDispatcher.locales;
  List<ui.Locale>? _localesTestValue;
  /// Hides the real locales and reports the given [localesTestValue] instead.
  set localesTestValue(List<ui.Locale> localesTestValue) {
    _localesTestValue = localesTestValue;
    onLocaleChanged?.call();
  }
  /// Deletes any existing test locales and returns to using the real locales.
  void clearLocalesTestValue() {
    _localesTestValue = null;
    onLocaleChanged?.call();
  }

  @override
  ui.VoidCallback? get onLocaleChanged => platformDispatcher.onLocaleChanged;
  @override
  set onLocaleChanged(ui.VoidCallback? callback) {
    platformDispatcher.onLocaleChanged = callback;
  }

  @override
  String get initialLifecycleState => _initialLifecycleStateTestValue;
  String _initialLifecycleStateTestValue = '';
  /// Sets a faked initialLifecycleState for testing.
  set initialLifecycleStateTestValue(String state) {
    _initialLifecycleStateTestValue = state;
  }

  @override
  double get textScaleFactor => _textScaleFactorTestValue ?? platformDispatcher.textScaleFactor;
  double? _textScaleFactorTestValue;
  /// Hides the real text scale factor and reports the given
  /// [textScaleFactorTestValue] instead.
  set textScaleFactorTestValue(double textScaleFactorTestValue) {
    _textScaleFactorTestValue = textScaleFactorTestValue;
    onTextScaleFactorChanged?.call();
  }
  /// Deletes any existing test text scale factor and returns to using the real
  /// text scale factor.
  void clearTextScaleFactorTestValue() {
    _textScaleFactorTestValue = null;
    onTextScaleFactorChanged?.call();
  }

  @override
  ui.Brightness get platformBrightness => _platformBrightnessTestValue ?? platformDispatcher.platformBrightness;
  ui.Brightness? _platformBrightnessTestValue;
  @override
  ui.VoidCallback? get onPlatformBrightnessChanged => platformDispatcher.onPlatformBrightnessChanged;
  @override
  set onPlatformBrightnessChanged(ui.VoidCallback? callback) {
    platformDispatcher.onPlatformBrightnessChanged = callback;
  }
  /// Hides the real text scale factor and reports the given
  /// [platformBrightnessTestValue] instead.
  set platformBrightnessTestValue(ui.Brightness platformBrightnessTestValue) {
    _platformBrightnessTestValue = platformBrightnessTestValue;
    onPlatformBrightnessChanged?.call();
  }
  /// Deletes any existing test platform brightness and returns to using the
  /// real platform brightness.
  void clearPlatformBrightnessTestValue() {
    _platformBrightnessTestValue = null;
    onPlatformBrightnessChanged?.call();
  }

  @override
  bool get alwaysUse24HourFormat => _alwaysUse24HourFormatTestValue ?? platformDispatcher.alwaysUse24HourFormat;
  bool? _alwaysUse24HourFormatTestValue;
  /// Hides the real clock format and reports the given
  /// [alwaysUse24HourFormatTestValue] instead.
  set alwaysUse24HourFormatTestValue(bool alwaysUse24HourFormatTestValue) {
    _alwaysUse24HourFormatTestValue = alwaysUse24HourFormatTestValue;
  }
  /// Deletes any existing test clock format and returns to using the real clock
  /// format.
  void clearAlwaysUse24HourTestValue() {
    _alwaysUse24HourFormatTestValue = null;
  }

  @override
  ui.VoidCallback? get onTextScaleFactorChanged => platformDispatcher.onTextScaleFactorChanged;
  @override
  set onTextScaleFactorChanged(ui.VoidCallback? callback) {
    platformDispatcher.onTextScaleFactorChanged = callback;
  }

  @override
  ui.FrameCallback? get onBeginFrame => platformDispatcher.onBeginFrame;
  @override
  set onBeginFrame(ui.FrameCallback? callback) {
    platformDispatcher.onBeginFrame = callback;
  }

  @override
  ui.VoidCallback? get onDrawFrame => platformDispatcher.onDrawFrame;
  @override
  set onDrawFrame(ui.VoidCallback? callback) {
    platformDispatcher.onDrawFrame = callback;
  }

  @override
  ui.TimingsCallback? get onReportTimings => platformDispatcher.onReportTimings;
  @override
  set onReportTimings(ui.TimingsCallback? callback) {
    platformDispatcher.onReportTimings = callback;
  }

  @override
  ui.PointerDataPacketCallback? get onPointerDataPacket => platformDispatcher.onPointerDataPacket;
  @override
  set onPointerDataPacket(ui.PointerDataPacketCallback? callback) {
    platformDispatcher.onPointerDataPacket = callback;
  }

  @override
  String get defaultRouteName => _defaultRouteNameTestValue ?? platformDispatcher.defaultRouteName;
  String? _defaultRouteNameTestValue;
  /// Hides the real default route name and reports the given
  /// [defaultRouteNameTestValue] instead.
  set defaultRouteNameTestValue(String defaultRouteNameTestValue) {
    _defaultRouteNameTestValue = defaultRouteNameTestValue;
  }
  /// Deletes any existing test default route name and returns to using the real
  /// default route name.
  void clearDefaultRouteNameTestValue() {
    _defaultRouteNameTestValue = null;
  }

  @override
  void scheduleFrame() {
    platformDispatcher.scheduleFrame();
  }

  @override
  void render(ui.Scene scene) {
    _window.render(scene);
  }

  @override
  bool get semanticsEnabled => _semanticsEnabledTestValue ?? platformDispatcher.semanticsEnabled;
  bool? _semanticsEnabledTestValue;
  /// Hides the real semantics enabled and reports the given
  /// [semanticsEnabledTestValue] instead.
  set semanticsEnabledTestValue(bool semanticsEnabledTestValue) {
    _semanticsEnabledTestValue = semanticsEnabledTestValue;
    onSemanticsEnabledChanged?.call();
  }
  /// Deletes any existing test semantics enabled and returns to using the real
  /// semantics enabled.
  void clearSemanticsEnabledTestValue() {
    _semanticsEnabledTestValue = null;
    onSemanticsEnabledChanged?.call();
  }

  @override
  ui.VoidCallback? get onSemanticsEnabledChanged => platformDispatcher.onSemanticsEnabledChanged;
  @override
  set onSemanticsEnabledChanged(ui.VoidCallback? callback) {
    platformDispatcher.onSemanticsEnabledChanged = callback;
  }

  @override
  ui.SemanticsActionCallback? get onSemanticsAction => platformDispatcher.onSemanticsAction;
  @override
  set onSemanticsAction(ui.SemanticsActionCallback? callback) {
    platformDispatcher.onSemanticsAction = callback;
  }

  @override
  ui.AccessibilityFeatures get accessibilityFeatures => _accessibilityFeaturesTestValue ?? platformDispatcher.accessibilityFeatures;
  ui.AccessibilityFeatures? _accessibilityFeaturesTestValue;
  /// Hides the real accessibility features and reports the given
  /// [accessibilityFeaturesTestValue] instead.
  set accessibilityFeaturesTestValue(ui.AccessibilityFeatures accessibilityFeaturesTestValue) {
    _accessibilityFeaturesTestValue = accessibilityFeaturesTestValue;
    onAccessibilityFeaturesChanged?.call();
  }
  /// Deletes any existing test accessibility features and returns to using the
  /// real accessibility features.
  void clearAccessibilityFeaturesTestValue() {
    _accessibilityFeaturesTestValue = null;
    onAccessibilityFeaturesChanged?.call();
  }

  @override
  ui.VoidCallback? get onAccessibilityFeaturesChanged => platformDispatcher.onAccessibilityFeaturesChanged;
  @override
  set onAccessibilityFeaturesChanged(ui.VoidCallback? callback) {
    platformDispatcher.onAccessibilityFeaturesChanged = callback;
  }

  @override
  void updateSemantics(ui.SemanticsUpdate update) {
    platformDispatcher.updateSemantics(update);
  }

  @override
  void setIsolateDebugName(String name) {
    platformDispatcher.setIsolateDebugName(name);
  }

  @override
  void sendPlatformMessage(
    String name,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) {
    platformDispatcher.sendPlatformMessage(name, data, callback);
  }

  @override
  ui.PlatformMessageCallback? get onPlatformMessage => platformDispatcher.onPlatformMessage;
  @override
  set onPlatformMessage(ui.PlatformMessageCallback? callback) {
    platformDispatcher.onPlatformMessage = callback;
  }

  @override
  ui.PlatformDispatcher get platformDispatcher => _window.platformDispatcher;

  /// Delete any test value properties that have been set on this [TestWindow]
  /// and return to reporting the real [SingletonFlutterWindow] values for all
  /// [SingletonFlutterWindow] properties.
  ///
  /// If desired, clearing of properties can be done on an individual basis,
  /// e.g., [clearLocaleTestValue()].
  void clearAllTestValues() {
    clearAccessibilityFeaturesTestValue();
    clearAlwaysUse24HourTestValue();
    clearDefaultRouteNameTestValue();
    clearDevicePixelRatioTestValue();
    clearPlatformBrightnessTestValue();
    clearLocaleTestValue();
    clearLocalesTestValue();
    clearPaddingTestValue();
    clearPhysicalSizeTestValue();
    clearSemanticsEnabledTestValue();
    clearTextScaleFactorTestValue();
    clearViewInsetsTestValue();
  }

  /// This gives us some grace time when the dart:ui side adds something to
  /// Window, and makes things easier when we do rolls to give us time to catch
  /// up.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}
