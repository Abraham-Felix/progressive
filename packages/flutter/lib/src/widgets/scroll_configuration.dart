// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import 'framework.dart';
import 'overscroll_indicator.dart';
import 'scroll_physics.dart';
import 'scrollable.dart';
import 'scrollbar.dart';

const Color _kDefaultGlowColor = Color(0xFFFFFFFF);

/// Describes how [Scrollable] widgets should behave.
///
/// {@template flutter.widgets.scrollBehavior}
/// Used by [ScrollConfiguration] to configure the [Scrollable] widgets in a
/// subtree.
///
/// This class can be extended to further customize a [ScrollBehavior] for a
/// subtree. For example, overriding [ScrollBehavior.getScrollPhysics] sets the
/// default [ScrollPhysics] for [Scrollable]s that inherit this [ScrollConfiguration].
/// Overriding [ScrollBehavior.buildOverscrollIndicator] can be used to add or change
/// the default [GlowingOverscrollIndicator] decoration, while
/// [ScrollBehavior.buildScrollbar] can be changed to modify the default [Scrollbar].
///
/// When looking to easily toggle the default decorations, you can use
/// [ScrollBehavior.copyWith] instead of creating your own [ScrollBehavior] class.
/// The `scrollbar` and `overscrollIndicator` flags can turn these decorations off.
/// {@endtemplate}
///
/// See also:
///
///   * [ScrollConfiguration], the inherited widget that controls how
///     [Scrollable] widgets behave in a subtree.
@immutable
class ScrollBehavior {
  /// Creates a description of how [Scrollable] widgets should behave.
  const ScrollBehavior();

  /// Creates a copy of this ScrollBehavior, making it possible to
  /// easily toggle `scrollbar` and `overscrollIndicator` effects.
  ///
  /// This is used by widgets like [PageView] and [ListWheelScrollView] to
  /// override the current [ScrollBehavior] and manage how they are decorated.
  /// Widgets such as these have the option to provide a [ScrollBehavior] on
  /// the widget level, like [PageView.scrollBehavior], in order to change the
  /// default.
  ScrollBehavior copyWith({
    bool scrollbars = true,
    bool overscroll = true,
    ScrollPhysics? physics,
    TargetPlatform? platform,
  }) {
    return _WrappedScrollBehavior(
      delegate: this,
      scrollbar: scrollbars,
      overscrollIndicator: overscroll,
      physics: physics,
      platform: platform,
    );
  }

  /// The platform whose scroll physics should be implemented.
  ///
  /// Defaults to the current platform.
  TargetPlatform getPlatform(BuildContext context) => defaultTargetPlatform;

  /// Wraps the given widget, which scrolls in the given [AxisDirection].
  ///
  /// For example, on Android, this method wraps the given widget with a
  /// [GlowingOverscrollIndicator] to provide visual feedback when the user
  /// overscrolls.
  ///
  /// This method is deprecated. Use [ScrollBehavior.buildOverscrollIndicator]
  /// instead.
  @Deprecated(
    'Migrate to buildOverscrollIndicator. '
    'This feature was deprecated after v2.1.0-11.0.pre.'
  )
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return child;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      return GlowingOverscrollIndicator(
        child: child,
        axisDirection: axisDirection,
        color: _kDefaultGlowColor,
      );
    }
  }

  /// Applies a [RawScrollbar] to the child widget on desktop platforms.
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // When modifying this function, consider modifying the implementation in
    // the Material and Cupertino subclasses as well.
    switch (getPlatform(context)) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return RawScrollbar(
          child: child,
          controller: details.controller,
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return child;
    }
  }

  /// Applies a [GlowingOverscrollIndicator] to the child widget on
  /// [TargetPlatform.android] and [TargetPlatform.fuchsia].
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // TODO(Piinks): Move implementation from buildViewportChrome here after
    //  deprecation period
    // When modifying this function, consider modifying the implementation in
    // the Material and Cupertino subclasses as well.
    return buildViewportChrome(context, child, details.direction);
  }

  /// Specifies the type of velocity tracker to use in the descendant
  /// [Scrollable]s' drag gesture recognizers, for estimating the velocity of a
  /// drag gesture.
  ///
  /// This can be used to, for example, apply different fling velocity
  /// estimation methods on different platforms, in order to match the
  /// platform's native behavior.
  ///
  /// Typically, the provided [GestureVelocityTrackerBuilder] should return a
  /// fresh velocity tracker. If null is returned, [Scrollable] creates a new
  /// [VelocityTracker] to track the newly added pointer that may develop into
  /// a drag gesture.
  ///
  /// The default implementation provides a new
  /// [IOSScrollViewFlingVelocityTracker] on iOS and macOS for each new pointer,
  /// and a new [VelocityTracker] on other platforms for each new pointer.
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return (PointerEvent event) => IOSScrollViewFlingVelocityTracker(event.kind);
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return (PointerEvent event) => VelocityTracker.withKind(event.kind);
    }
  }

  static const ScrollPhysics _bouncingPhysics = BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());
  static const ScrollPhysics _clampingPhysics = ClampingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  /// The scroll physics to use for the platform given by [getPlatform].
  ///
  /// Defaults to [RangeMaintainingScrollPhysics] mixed with
  /// [BouncingScrollPhysics] on iOS and [ClampingScrollPhysics] on
  /// Android.
  ScrollPhysics getScrollPhysics(BuildContext context) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _bouncingPhysics;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return _clampingPhysics;
    }
  }

  /// Called whenever a [ScrollConfiguration] is rebuilt with a new
  /// [ScrollBehavior] of the same [runtimeType].
  ///
  /// If the new instance represents different information than the old
  /// instance, then the method should return true, otherwise it should return
  /// false.
  ///
  /// If this method returns true, all the widgets that inherit from the
  /// [ScrollConfiguration] will rebuild using the new [ScrollBehavior]. If this
  /// method returns false, the rebuilds might be optimized away.
  bool shouldNotify(covariant ScrollBehavior oldDelegate) => false;

  @override
  String toString() => objectRuntimeType(this, 'ScrollBehavior');
}

class _WrappedScrollBehavior implements ScrollBehavior {
  const _WrappedScrollBehavior({
    required this.delegate,
    this.scrollbar = true,
    this.overscrollIndicator = true,
    this.physics,
    this.platform,
  });

  final ScrollBehavior delegate;
  final bool scrollbar;
  final bool overscrollIndicator;
  final ScrollPhysics? physics;
  final TargetPlatform? platform;

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    if (overscrollIndicator)
      return delegate.buildOverscrollIndicator(context, child, details);
    return child;
  }

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    if (scrollbar)
      return delegate.buildScrollbar(context, child, details);
    return child;
  }

  @override
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) {
    return delegate.buildViewportChrome(context, child, axisDirection);
  }

  @override
  ScrollBehavior copyWith({
    bool scrollbars = true,
    bool overscroll = true,
    ScrollPhysics? physics,
    TargetPlatform? platform,
  }) {
    return delegate.copyWith(
      scrollbars: scrollbars,
      overscroll: overscroll,
      physics: physics,
      platform: platform,
    );
  }

  @override
  TargetPlatform getPlatform(BuildContext context) {
    return platform ?? delegate.getPlatform(context);
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return physics ?? delegate.getScrollPhysics(context);
  }

  @override
  bool shouldNotify(_WrappedScrollBehavior oldDelegate) {
    return oldDelegate.delegate.runtimeType != delegate.runtimeType
        || oldDelegate.scrollbar != scrollbar
        || oldDelegate.overscrollIndicator != overscrollIndicator
        || oldDelegate.physics != physics
        || oldDelegate.platform != platform
        || delegate.shouldNotify(oldDelegate.delegate);
  }

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    return delegate.velocityTrackerBuilder(context);
  }

  @override
  String toString() => objectRuntimeType(this, '_WrappedScrollBehavior');
}

/// Controls how [Scrollable] widgets behave in a subtree.
///
/// The scroll configuration determines the [ScrollPhysics] and viewport
/// decorations used by descendants of [child].
class ScrollConfiguration extends InheritedWidget {
  /// Creates a widget that controls how [Scrollable] widgets behave in a subtree.
  ///
  /// The [behavior] and [child] arguments must not be null.
  const ScrollConfiguration({
    Key? key,
    required this.behavior,
    required Widget child,
  }) : super(key: key, child: child);

  /// How [Scrollable] widgets that are descendants of [child] should behave.
  final ScrollBehavior behavior;

  /// The [ScrollBehavior] for [Scrollable] widgets in the given [BuildContext].
  ///
  /// If no [ScrollConfiguration] widget is in scope of the given `context`,
  /// a default [ScrollBehavior] instance is returned.
  static ScrollBehavior of(BuildContext context) {
    final ScrollConfiguration? configuration = context.dependOnInheritedWidgetOfExactType<ScrollConfiguration>();
    return configuration?.behavior ?? const ScrollBehavior();
  }

  @override
  bool updateShouldNotify(ScrollConfiguration oldWidget) {
    assert(behavior != null);
    return behavior.runtimeType != oldWidget.behavior.runtimeType
        || (behavior != oldWidget.behavior && behavior.shouldNotify(oldWidget.behavior));
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ScrollBehavior>('behavior', behavior));
  }
}
