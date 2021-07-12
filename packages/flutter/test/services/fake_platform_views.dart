// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Used in internal testing.
class FakePlatformViewController extends PlatformViewController {
  FakePlatformViewController(this.viewId);

  bool disposed = false;
  bool focusCleared = false;

  /// Events that are dispatched.
  List<PointerEvent> dispatchedPointerEvents = <PointerEvent>[];

  @override
  final int viewId;

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {
    dispatchedPointerEvents.add(event);
  }

  void clearTestingVariables() {
    dispatchedPointerEvents.clear();
    disposed = false;
    focusCleared = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> clearFocus() async {
    focusCleared = true;
  }
}

class FakeAndroidViewController implements AndroidViewController {
  FakeAndroidViewController(this.viewId);

  bool disposed = false;
  bool focusCleared = false;
  bool created = false;

  /// Events that are dispatched.
  List<PointerEvent> dispatchedPointerEvents = <PointerEvent>[];

  @override
  final int viewId;

  @override
  Offset Function(Offset position)? pointTransformer;

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {
    dispatchedPointerEvents.add(event);
  }

  void clearTestingVariables() {
    dispatchedPointerEvents.clear();
    disposed = false;
    focusCleared = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> clearFocus() async {
    focusCleared = true;
  }

  @override
  Future<void> setSize(Size size) {
    throw UnimplementedError();
  }

  @override
  int get textureId => throw UnimplementedError();

  @override
  bool get isCreated => throw UnimplementedError();

  @override
  void addOnPlatformViewCreatedListener(PlatformViewCreatedCallback listener) =>
      throw UnimplementedError();

  @override
  int get id => throw UnimplementedError();

  @override
  void removeOnPlatformViewCreatedListener(PlatformViewCreatedCallback listener) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendMotionEvent(AndroidMotionEvent event) {
    throw UnimplementedError();
  }

  @override
  Future<void> setLayoutDirection(TextDirection layoutDirection) {
    throw UnimplementedError();
  }

  @override
  Future<void> create() async {
    created = true;
  }
}

class FakeAndroidPlatformViewsController {
  FakeAndroidPlatformViewsController() {
    SystemChannels.platform_views.setMockMethodCallHandler(_onMethodCall);
  }

  Iterable<FakeAndroidPlatformView> get views => _views.values;
  final Map<int, FakeAndroidPlatformView> _views = <int, FakeAndroidPlatformView>{};

  final Map<int, List<FakeAndroidMotionEvent>> motionEvents = <int, List<FakeAndroidMotionEvent>>{};

  final Set<String> _registeredViewTypes = <String>{};

  int _textureCounter = 0;

  Completer<void>? resizeCompleter;

  Completer<void>? createCompleter;

  int? lastClearedFocusViewId;

  void registerViewType(String viewType) {
    _registeredViewTypes.add(viewType);
  }

  void invokeViewFocused(int viewId) {
    final MethodCodec codec = SystemChannels.platform_views.codec;
    final ByteData data = codec.encodeMethodCall(MethodCall('viewFocused', viewId));
    ServicesBinding.instance!.defaultBinaryMessenger
        .handlePlatformMessage(SystemChannels.platform_views.name, data, (ByteData? data) {});
  }

  Future<dynamic> _onMethodCall(MethodCall call) {
    switch(call.method) {
      case 'create':
        return _create(call);
      case 'dispose':
        return _dispose(call);
      case 'resize':
        return _resize(call);
      case 'touch':
        return _touch(call);
      case 'setDirection':
        return _setDirection(call);
      case 'clearFocus':
        return _clearFocus(call);
    }
    return Future<dynamic>.sync(() => null);
  }

  Future<dynamic> _create(MethodCall call) async {
    final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
    final int id = args['id'] as int;
    final String viewType = args['viewType'] as String;
    final double? width = args['width'] as double?;
    final double? height = args['height'] as double?;
    final int layoutDirection = args['direction'] as int;
    final bool? hybrid = args['hybrid'] as bool?;
    final Uint8List? creationParams = args['params'] as Uint8List?;

    if (_views.containsKey(id))
      throw PlatformException(
        code: 'error',
        message: 'Trying to create an already created platform view, view id: $id',
      );

    if (!_registeredViewTypes.contains(viewType))
      throw PlatformException(
        code: 'error',
        message: 'Trying to create a platform view of unregistered type: $viewType',
      );

    if (createCompleter != null) {
      await createCompleter!.future;
    }

    _views[id] = FakeAndroidPlatformView(id, viewType,
        width != null && height != null ? Size(width, height) : null,
        layoutDirection,
        hybrid,
        creationParams,
    );
    final int textureId = _textureCounter++;
    return Future<int>.sync(() => textureId);
  }

  Future<dynamic> _dispose(MethodCall call) {
    assert(call.arguments is Map);

    final int id = call.arguments['id'] as int;
    final bool hybrid = call.arguments['hybrid'] as bool;

    if (hybrid && !_views[id]!.hybrid!) {
      throw ArgumentError('An $AndroidViewController using hybrid composition must pass `hybrid: true`');
    } else if (!hybrid && (_views[id]!.hybrid ?? false)) {
      throw ArgumentError('An $AndroidViewController not using hybrid composition must pass `hybrid: false`');
    }

    if (!_views.containsKey(id))
      throw PlatformException(
        code: 'error',
        message: 'Trying to dispose a platform view with unknown id: $id',
      );

    _views.remove(id);
    return Future<dynamic>.sync(() => null);
  }

  Future<dynamic> _resize(MethodCall call) async {
    final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
    final int id = args['id'] as int;
    final double width = args['width'] as double;
    final double height = args['height'] as double;

    if (!_views.containsKey(id))
      throw PlatformException(
        code: 'error',
        message: 'Trying to resize a platform view with unknown id: $id',
      );

    if (resizeCompleter != null) {
      await resizeCompleter!.future;
    }
    _views[id] = _views[id]!.copyWith(size: Size(width, height));

    return Future<dynamic>.sync(() => null);
  }

  Future<dynamic> _touch(MethodCall call) {
    final List<dynamic> args = call.arguments as List<dynamic>;
    final int id = args[0] as int;
    final int action = args[3] as int;
    final List<List<dynamic>> pointerProperties = (args[5] as List<dynamic>).cast<List<dynamic>>();
    final List<List<dynamic>> pointerCoords = (args[6] as List<dynamic>).cast<List<dynamic>>();
    final List<Offset> pointerOffsets = <Offset> [];
    final List<int> pointerIds = <int> [];
    for (int i = 0; i < pointerCoords.length; i++) {
      pointerIds.add(pointerProperties[i][0] as int);
      final double x = pointerCoords[i][7] as double;
      final double y = pointerCoords[i][8] as double;
      pointerOffsets.add(Offset(x, y));
    }

    if (!motionEvents.containsKey(id))
      motionEvents[id] = <FakeAndroidMotionEvent> [];

    motionEvents[id]!.add(FakeAndroidMotionEvent(action, pointerIds, pointerOffsets));
    return Future<dynamic>.sync(() => null);
  }

  Future<dynamic> _setDirection(MethodCall call) async {
    final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
    final int id = args['id'] as int;
    final int layoutDirection = args['direction'] as int;

    if (!_views.containsKey(id))
      throw PlatformException(
        code: 'error',
        message: 'Trying to resize a platform view with unknown id: $id',
      );

    _views[id] = _views[id]!.copyWith(layoutDirection: layoutDirection);

    return Future<dynamic>.sync(() => null);
  }

  Future<dynamic> _clearFocus(MethodCall call) {
    final int id = call.arguments as int;

    if (!_views.containsKey(id))
      throw PlatformException(
        code: 'error',
        message: 'Trying to clear the focus on a platform view with unknown id: $id',
      );

    lastClearedFocusViewId = id;
    return Future<dynamic>.sync(() => null);
  }
}

class FakeIosPlatformViewsController {
  FakeIosPlatformViewsController() {
    SystemChannels.platform_views.setMockMethodCallHandler(_onMethodCall);
  }

  Iterable<FakeUiKitView> get views => _views.values;
  final Map<int, FakeUiKitView> _views = <int, FakeUiKitView>{};

  final Set<String> _registeredViewTypes = <String>{};

  // When this completer is non null, the 'create' method channel call will be
  // delayed until it completes.
  Completer<void>? creationDelay;

  // Maps a view id to the number of gestures it accepted so far.
  final Map<int, int> gesturesAccepted = <int, int>{};

  // Maps a view id to the number of gestures it rejected so far.
  final Map<int, int> gesturesRejected = <int, int>{};

  void registerViewType(String viewType) {
    _registeredViewTypes.add(viewType);
  }

  Future<dynamic> _onMethodCall(MethodCall call) {
    switch(call.method) {
      case 'create':
        return _create(call);
      case 'dispose':
        return _dispose(call);
      case 'acceptGesture':
        return _acceptGesture(call);
      case 'rejectGesture':
        return _rejectGesture(call);
    }
    return Future<dynamic>.sync(() => null);
  }

  Future<dynamic> _create(MethodCall call) async {
    if (creationDelay != null)
      await creationDelay!.future;
    final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
    final int id = args['id'] as int;
    final String viewType = args['viewType'] as String;
    final Uint8List? creationParams = args['params'] as Uint8List?;

    if (_views.containsKey(id)) {
      throw PlatformException(
        code: 'error',
        message: 'Trying to create an already created platform view, view id: $id',
      );
    }

    if (!_registeredViewTypes.contains(viewType)) {
      throw PlatformException(
        code: 'error',
        message: 'Trying to create a platform view of unregistered type: $viewType',
      );
    }

    _views[id] = FakeUiKitView(id, viewType, creationParams);
    gesturesAccepted[id] = 0;
    gesturesRejected[id] = 0;
    return Future<int?>.sync(() => null);
  }

  Future<dynamic> _acceptGesture(MethodCall call) async {
    final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
    final int id = args['id'] as int;
    gesturesAccepted[id] = gesturesAccepted[id]! + 1;
    return Future<int?>.sync(() => null);
  }

  Future<dynamic> _rejectGesture(MethodCall call) async {
    final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
    final int id = args['id'] as int;
    gesturesRejected[id] = gesturesRejected[id]! + 1;
    return Future<int?>.sync(() => null);
  }

  Future<dynamic> _dispose(MethodCall call) {
    final int id = call.arguments as int;

    if (!_views.containsKey(id)) {
      throw PlatformException(
        code: 'error',
        message: 'Trying to dispose a platform view with unknown id: $id',
      );
    }

    _views.remove(id);
    return Future<dynamic>.sync(() => null);
  }
}

class FakeHtmlPlatformViewsController {
  FakeHtmlPlatformViewsController() {
    SystemChannels.platform_views.setMockMethodCallHandler(_onMethodCall);
  }

  Iterable<FakeHtmlPlatformView> get views => _views.values;
  final Map<int, FakeHtmlPlatformView> _views = <int, FakeHtmlPlatformView>{};

  final Set<String> _registeredViewTypes = <String>{};

  late Completer<void> resizeCompleter;

  Completer<void>? createCompleter;

  void registerViewType(String viewType) {
    _registeredViewTypes.add(viewType);
  }

  Future<dynamic> _onMethodCall(MethodCall call) {
    switch(call.method) {
      case 'create':
        return _create(call);
      case 'dispose':
        return _dispose(call);
    }
    return Future<dynamic>.sync(() => null);
  }

  Future<dynamic> _create(MethodCall call) async {
    final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
    final int id = args['id'] as int;
    final String viewType = args['viewType'] as String;

    if (_views.containsKey(id))
      throw PlatformException(
        code: 'error',
        message: 'Trying to create an already created platform view, view id: $id',
      );

    if (!_registeredViewTypes.contains(viewType))
      throw PlatformException(
        code: 'error',
        message: 'Trying to create a platform view of unregistered type: $viewType',
      );

    if (createCompleter != null) {
      await createCompleter!.future;
    }

    _views[id] = FakeHtmlPlatformView(id, viewType);
    return Future<int?>.sync(() => null);
  }

  Future<dynamic> _dispose(MethodCall call) {
    final int id = call.arguments as int;

    if (!_views.containsKey(id))
      throw PlatformException(
        code: 'error',
        message: 'Trying to dispose a platform view with unknown id: $id',
      );

    _views.remove(id);
    return Future<dynamic>.sync(() => null);
  }
}

@immutable
class FakeAndroidPlatformView {
  const FakeAndroidPlatformView(this.id, this.type, this.size, this.layoutDirection, this.hybrid, [this.creationParams]);

  final int id;
  final String type;
  final Uint8List? creationParams;
  final Size? size;
  final int layoutDirection;
  final bool? hybrid;

  FakeAndroidPlatformView copyWith({Size? size, int? layoutDirection}) => FakeAndroidPlatformView(
    id,
    type,
    size ?? this.size,
    layoutDirection ?? this.layoutDirection,
    hybrid,
    creationParams,
  );

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    return other is FakeAndroidPlatformView
        && other.id == id
        && other.type == type
        && listEquals<int>(other.creationParams, creationParams)
        && other.size == size
        && other.hybrid == hybrid
        && other.layoutDirection == layoutDirection;
  }

  @override
  int get hashCode => hashValues(id, type, hashList(creationParams), size, layoutDirection, hybrid);

  @override
  String toString() {
    return 'FakeAndroidPlatformView(id: $id, type: $type, size: $size, layoutDirection: $layoutDirection, hybrid: $hybrid, creationParams: $creationParams)';
  }
}

@immutable
class FakeAndroidMotionEvent {
  const FakeAndroidMotionEvent(this.action, this.pointerIds, this.pointers);

  final int action;
  final List<Offset> pointers;
  final List<int> pointerIds;


  @override
  bool operator ==(Object other) {
    return other is FakeAndroidMotionEvent
        && listEquals<int>(other.pointerIds, pointerIds)
        && other.action == action
        && listEquals<Offset>(other.pointers, pointers);
  }

  @override
  int get hashCode => hashValues(action, hashList(pointers), hashList(pointerIds));

  @override
  String toString() {
    return 'FakeAndroidMotionEvent(action: $action, pointerIds: $pointerIds, pointers: $pointers)';
  }
}

@immutable
class FakeUiKitView {
  const FakeUiKitView(this.id, this.type, [this.creationParams]);

  final int id;
  final String type;
  final Uint8List? creationParams;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    return other is FakeUiKitView
        && other.id == id
        && other.type == type
        && other.creationParams == creationParams;
  }

  @override
  int get hashCode => hashValues(id, type);

  @override
  String toString() {
    return 'FakeUiKitView(id: $id, type: $type, creationParams: $creationParams)';
  }
}

@immutable
class FakeHtmlPlatformView {
  const FakeHtmlPlatformView(this.id, this.type);

  final int id;
  final String type;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    return other is FakeHtmlPlatformView
        && other.id == id
        && other.type == type;
  }

  @override
  int get hashCode => hashValues(id, type);

  @override
  String toString() {
    return 'FakeHtmlPlatformView(id: $id, type: $type)';
  }
}
