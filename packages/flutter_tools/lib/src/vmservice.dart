// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';

import 'package:meta/meta.dart' show required, visibleForTesting;
import 'package:vm_service/vm_service.dart' as vm_service;

import 'base/common.dart';
import 'base/context.dart';
import 'base/io.dart' as io;
import 'base/logger.dart';
import 'base/utils.dart';
import 'convert.dart';
import 'device.dart';
import 'version.dart';

const String kGetSkSLsMethod = '_flutter.getSkSLs';
const String kSetAssetBundlePathMethod = '_flutter.setAssetBundlePath';
const String kFlushUIThreadTasksMethod = '_flutter.flushUIThreadTasks';
const String kRunInViewMethod = '_flutter.runInView';
const String kListViewsMethod = '_flutter.listViews';
const String kScreenshotSkpMethod = '_flutter.screenshotSkp';
const String kScreenshotMethod = '_flutter.screenshot';

/// The error response code from an unrecoverable compilation failure.
const int kIsolateReloadBarred = 1005;

/// Override `WebSocketConnector` in [context] to use a different constructor
/// for [WebSocket]s (used by tests).
typedef WebSocketConnector = Future<io.WebSocket> Function(String url, {io.CompressionOptions compression, @required Logger logger});

typedef PrintStructuredErrorLogMethod = void Function(vm_service.Event);

WebSocketConnector _openChannel = _defaultOpenChannel;

/// A testing only override of the WebSocket connector.
///
/// Provide a `null` value to restore the original connector.
@visibleForTesting
set openChannelForTesting(WebSocketConnector connector) {
  _openChannel = connector ?? _defaultOpenChannel;
}

/// The error codes for the JSON-RPC standard, including VM service specific
/// error codes.
///
/// See also: https://www.jsonrpc.org/specification#error_object
abstract class RPCErrorCodes {
  /// The method does not exist or is not available.
  static const int kMethodNotFound = -32601;

  /// Invalid method parameter(s), such as a mismatched type.
  static const int kInvalidParams = -32602;

  /// Internal JSON-RPC error.
  static const int kInternalError = -32603;

  /// Application specific error codes.
  static const int kServerError = -32000;

  /// Non-standard JSON-RPC error codes:

  /// The VM service or extension service has disappeared.
  static const int kServiceDisappeared = 112;
}

/// A function that reacts to the invocation of the 'reloadSources' service.
///
/// The VM Service Protocol allows clients to register custom services that
/// can be invoked by other clients through the service protocol itself.
///
/// Clients like Observatory use external 'reloadSources' services,
/// when available, instead of the VM internal one. This allows these clients to
/// invoke Flutter HotReload when connected to a Flutter Application started in
/// hot mode.
///
/// See: https://github.com/dart-lang/sdk/issues/30023
typedef ReloadSources = Future<void> Function(
  String isolateId, {
  bool force,
  bool pause,
});

typedef Restart = Future<void> Function({ bool pause });

typedef CompileExpression = Future<String> Function(
  String isolateId,
  String expression,
  List<String> definitions,
  List<String> typeDefinitions,
  String libraryUri,
  String klass,
  bool isStatic,
);

/// A method that pulls an SkSL shader from the device and writes it to a file.
///
/// The name of the file returned as a result.
typedef GetSkSLMethod = Future<String> Function();

Future<io.WebSocket> _defaultOpenChannel(String url, {
  io.CompressionOptions compression = io.CompressionOptions.compressionDefault,
  @required Logger logger,
}) async {
  Duration delay = const Duration(milliseconds: 100);
  int attempts = 0;
  io.WebSocket socket;

  Future<void> handleError(dynamic e) async {
    void Function(String) printVisibleTrace = logger.printTrace;
    if (attempts == 10) {
      logger.printStatus('Connecting to the VM Service is taking longer than expected...');
    } else if (attempts == 20) {
      logger.printStatus('Still attempting to connect to the VM Service...');
      logger.printStatus(
        'If you do NOT see the Flutter application running, it might have '
        'crashed. The device logs (e.g. from adb or XCode) might have more '
        'details.');
      logger.printStatus(
        'If you do see the Flutter application running on the device, try '
        're-running with --host-vmservice-port to use a specific port known to '
        'be available.');
    } else if (attempts % 50 == 0) {
      printVisibleTrace = logger.printStatus;
    }

    printVisibleTrace('Exception attempting to connect to the VM Service: $e');
    printVisibleTrace('This was attempt #$attempts. Will retry in $delay.');

    // Delay next attempt.
    await Future<void>.delayed(delay);

    // Back off exponentially, up to 1600ms per attempt.
    if (delay < const Duration(seconds: 1)) {
      delay *= 2;
    }
  }

  final WebSocketConnector constructor = context.get<WebSocketConnector>() ?? (String url, {
    io.CompressionOptions compression = io.CompressionOptions.compressionDefault,
    @required Logger logger,
  }) => io.WebSocket.connect(url, compression: compression);

  while (socket == null) {
    attempts += 1;
    try {
      socket = await constructor(url, compression: compression);
    } on io.WebSocketException catch (e) {
      await handleError(e);
    } on io.SocketException catch (e) {
      await handleError(e);
    }
  }
  return socket;
}

/// Override `VMServiceConnector` in [context] to return a different VMService
/// from [VMService.connect] (used by tests).
typedef VMServiceConnector = Future<FlutterVmService> Function(Uri httpUri, {
  ReloadSources reloadSources,
  Restart restart,
  CompileExpression compileExpression,
  GetSkSLMethod getSkSLMethod,
  PrintStructuredErrorLogMethod printStructuredErrorLogMethod,
  io.CompressionOptions compression,
  Device device,
  Logger logger,
});

/// Set up the VM Service client by attaching services for each of the provided
/// callbacks.
///
/// All parameters besides [vmService] may be null.
Future<vm_service.VmService> setUpVmService(
  ReloadSources reloadSources,
  Restart restart,
  CompileExpression compileExpression,
  Device device,
  GetSkSLMethod skSLMethod,
  PrintStructuredErrorLogMethod printStructuredErrorLogMethod,
  vm_service.VmService vmService
) async {
  // Each service registration requires a request to the attached VM service. Since the
  // order of these requests does not mattter, store each future in a list and await
  // all at the end of this method.
  final List<Future<vm_service.Success>> registrationRequests = <Future<vm_service.Success>>[];
  if (reloadSources != null) {
    vmService.registerServiceCallback('reloadSources', (Map<String, dynamic> params) async {
      final String isolateId = _validateRpcStringParam('reloadSources', params, 'isolateId');
      final bool force = _validateRpcBoolParam('reloadSources', params, 'force');
      final bool pause = _validateRpcBoolParam('reloadSources', params, 'pause');

      await reloadSources(isolateId, force: force, pause: pause);

      return <String, dynamic>{
        'result': <String, Object>{
          'type': 'Success',
        }
      };
    });
    registrationRequests.add(vmService.registerService('reloadSources', 'Flutter Tools'));
  }

  if (restart != null) {
    vmService.registerServiceCallback('hotRestart', (Map<String, dynamic> params) async {
      final bool pause = _validateRpcBoolParam('compileExpression', params, 'pause');
      await restart(pause: pause);
      return <String, dynamic>{
        'result': <String, Object>{
          'type': 'Success',
        }
      };
    });
    registrationRequests.add(vmService.registerService('hotRestart', 'Flutter Tools'));
  }

  vmService.registerServiceCallback('flutterVersion', (Map<String, dynamic> params) async {
    final FlutterVersion version = context.get<FlutterVersion>() ?? FlutterVersion();
    final Map<String, Object> versionJson = version.toJson();
    versionJson['frameworkRevisionShort'] = version.frameworkRevisionShort;
    versionJson['engineRevisionShort'] = version.engineRevisionShort;
    return <String, dynamic>{
      'result': <String, Object>{
        'type': 'Success',
        ...versionJson,
      }
    };
  });
  registrationRequests.add(vmService.registerService('flutterVersion', 'Flutter Tools'));

  if (compileExpression != null) {
    vmService.registerServiceCallback('compileExpression', (Map<String, dynamic> params) async {
      final String isolateId = _validateRpcStringParam('compileExpression', params, 'isolateId');
      final String expression = _validateRpcStringParam('compileExpression', params, 'expression');
      final List<String> definitions = List<String>.from(params['definitions'] as List<dynamic>);
      final List<String> typeDefinitions = List<String>.from(params['typeDefinitions'] as List<dynamic>);
      final String libraryUri = params['libraryUri'] as String;
      final String klass = params['klass'] as String;
      final bool isStatic = _validateRpcBoolParam('compileExpression', params, 'isStatic');

      final String kernelBytesBase64 = await compileExpression(isolateId,
          expression, definitions, typeDefinitions, libraryUri, klass,
          isStatic);
      return <String, dynamic>{
        'type': 'Success',
        'result': <String, dynamic>{'kernelBytes': kernelBytesBase64},
      };
    });
    registrationRequests.add(vmService.registerService('compileExpression', 'Flutter Tools'));
  }
  if (device != null) {
    vmService.registerServiceCallback('flutterMemoryInfo', (Map<String, dynamic> params) async {
      final MemoryInfo result = await device.queryMemoryInfo();
      return <String, dynamic>{
        'result': <String, Object>{
          'type': 'Success',
          ...result.toJson(),
        }
      };
    });
    registrationRequests.add(vmService.registerService('flutterMemoryInfo', 'Flutter Tools'));
  }
  if (skSLMethod != null) {
    vmService.registerServiceCallback('flutterGetSkSL', (Map<String, dynamic> params) async {
      final String filename = await skSLMethod();
      return <String, dynamic>{
        'result': <String, Object>{
          'type': 'Success',
          'filename': filename,
        }
      };
    });
    registrationRequests.add(vmService.registerService('flutterGetSkSL', 'Flutter Tools'));
  }
  if (printStructuredErrorLogMethod != null) {
    vmService.onExtensionEvent.listen(printStructuredErrorLogMethod);
    // It is safe to ignore this error because we expect an error to be
    // thrown if we're already subscribed.
    registrationRequests.add(vmService
      .streamListen(vm_service.EventStreams.kExtension)
      .catchError((dynamic error) {}, test: (dynamic error) => error is vm_service.RPCError)
    );
  }

  try {
    await Future.wait(registrationRequests);
  } on vm_service.RPCError catch (e) {
    throwToolExit('Failed to register service methods on attached VM Service: $e');
  }
  return vmService;
}

/// Connect to a Dart VM Service at [httpUri].
///
/// If the [reloadSources] parameter is not null, the 'reloadSources' service
/// will be registered. The VM Service Protocol allows clients to register
/// custom services that can be invoked by other clients through the service
/// protocol itself.
///
/// See: https://github.com/dart-lang/sdk/commit/df8bf384eb815cf38450cb50a0f4b62230fba217
Future<FlutterVmService> connectToVmService(
  Uri httpUri, {
    ReloadSources reloadSources,
    Restart restart,
    CompileExpression compileExpression,
    GetSkSLMethod getSkSLMethod,
    PrintStructuredErrorLogMethod printStructuredErrorLogMethod,
    io.CompressionOptions compression = io.CompressionOptions.compressionDefault,
    Device device,
    @required Logger logger,
  }) async {
  final VMServiceConnector connector = context.get<VMServiceConnector>() ?? _connect;
  return connector(httpUri,
    reloadSources: reloadSources,
    restart: restart,
    compileExpression: compileExpression,
    compression: compression,
    device: device,
    getSkSLMethod: getSkSLMethod,
    printStructuredErrorLogMethod: printStructuredErrorLogMethod,
    logger: logger,
  );
}

Future<vm_service.VmService> createVmServiceDelegate(
  Uri wsUri, {
    io.CompressionOptions compression = io.CompressionOptions.compressionDefault,
    @required Logger logger,
  }) async {
  final io.WebSocket channel = await _openChannel(wsUri.toString(), compression: compression, logger: logger);
  return vm_service.VmService(
    channel,
    channel.add,
    log: null,
    disposeHandler: () async {
      await channel.close();
    },
  );
}

Future<FlutterVmService> _connect(
  Uri httpUri, {
  ReloadSources reloadSources,
  Restart restart,
  CompileExpression compileExpression,
  GetSkSLMethod getSkSLMethod,
  PrintStructuredErrorLogMethod printStructuredErrorLogMethod,
  io.CompressionOptions compression = io.CompressionOptions.compressionDefault,
  Device device,
  @required Logger logger,
}) async {
  final Uri wsUri = httpUri.replace(scheme: 'ws', path: urlContext.join(httpUri.path, 'ws'));
  final vm_service.VmService delegateService = await createVmServiceDelegate(
    wsUri, compression: compression, logger: logger,
  );

  final vm_service.VmService service = await setUpVmService(
    reloadSources,
    restart,
    compileExpression,
    device,
    getSkSLMethod,
    printStructuredErrorLogMethod,
    delegateService,
  );

  // This call is to ensure we are able to establish a connection instead of
  // keeping on trucking and failing farther down the process.
  await delegateService.getVersion();
  return FlutterVmService(service, httpAddress: httpUri, wsAddress: wsUri);
}

String _validateRpcStringParam(String methodName, Map<String, dynamic> params, String paramName) {
  final dynamic value = params[paramName];
  if (value is! String || (value as String).isEmpty) {
    throw vm_service.RPCError(
      methodName,
      RPCErrorCodes.kInvalidParams,
      "Invalid '$paramName': $value",
    );
  }
  return value as String;
}

bool _validateRpcBoolParam(String methodName, Map<String, dynamic> params, String paramName) {
  final dynamic value = params[paramName];
  if (value != null && value is! bool) {
    throw vm_service.RPCError(
      methodName,
      RPCErrorCodes.kInvalidParams,
      "Invalid '$paramName': $value",
    );
  }
  return (value as bool) ?? false;
}

/// Peered to an Android/iOS FlutterView widget on a device.
class FlutterView {
  FlutterView({
    @required this.id,
    @required this.uiIsolate,
  });

  factory FlutterView.parse(Map<String, Object> json) {
    final Map<String, Object> rawIsolate = json['isolate'] as Map<String, Object>;
    vm_service.IsolateRef isolate;
    if (rawIsolate != null) {
      rawIsolate['number'] = rawIsolate['number']?.toString();
      isolate = vm_service.IsolateRef.parse(rawIsolate);
    }
    return FlutterView(
      id: json['id'] as String,
      uiIsolate: isolate,
    );
  }

  final vm_service.IsolateRef uiIsolate;
  final String id;

  bool get hasIsolate => uiIsolate != null;

  @override
  String toString() => id;

  Map<String, Object> toJson() {
    return <String, Object>{
      'id': id,
      'isolate': uiIsolate?.toJson(),
    };
  }
}

/// Flutter specific VM Service functionality.
class FlutterVmService {
  FlutterVmService(this.service, {this.wsAddress, this.httpAddress});

  final vm_service.VmService service;
  final Uri wsAddress;
  final Uri httpAddress;

  Future<vm_service.Response> callMethodWrapper(
    String method, {
    String isolateId,
    Map<String, dynamic> args
  }) async {
    try {
      return await service.callMethod(method, isolateId: isolateId, args: args);
    } on vm_service.RPCError catch (e) {
      // If the service disappears mid-request the tool is unable to recover
      // and should begin to shutdown due to the service connection closing.
      // Swallow the exception here and let the shutdown logic elsewhere deal
      // with cleaning up.
      if (e.code == RPCErrorCodes.kServiceDisappeared) {
        return null;
      }
      rethrow;
    }
  }

  /// Set the asset directory for the an attached Flutter view.
  Future<void> setAssetDirectory({
    @required Uri assetsDirectory,
    @required String viewId,
    @required String uiIsolateId,
  }) async {
    assert(assetsDirectory != null);
    await callMethodWrapper(kSetAssetBundlePathMethod,
      isolateId: uiIsolateId,
      args: <String, dynamic>{
        'viewId': viewId,
        'assetDirectory': assetsDirectory.toFilePath(windows: false),
      });
  }

  /// Retrieve the cached SkSL shaders from an attached Flutter view.
  ///
  /// This method will only return data if `--cache-sksl` was provided as a
  /// flutter run argument, and only then on physical devices.
  Future<Map<String, Object>> getSkSLs({
    @required String viewId,
  }) async {
    final vm_service.Response response = await callMethodWrapper(
      kGetSkSLsMethod,
      args: <String, String>{
        'viewId': viewId,
      },
    );
    if (response == null) {
      return null;
    }
    return response.json['SkSLs'] as Map<String, Object>;
  }

  /// Flush all tasks on the UI thread for an attached Flutter view.
  ///
  /// This method is currently used only for benchmarking.
  Future<void> flushUIThreadTasks({
    @required String uiIsolateId,
  }) async {
    await callMethodWrapper(
      kFlushUIThreadTasksMethod,
      args: <String, String>{
        'isolateId': uiIsolateId,
      },
    );
  }

  /// Launch the Dart isolate with entrypoint [main] in the Flutter engine [viewId]
  /// with [assetsDirectory] as the devFS.
  ///
  /// This method is used by the tool to hot restart an already running Flutter
  /// engine.
  Future<void> runInView({
    @required String viewId,
    @required Uri main,
    @required Uri assetsDirectory,
  }) async {
    try {
      await service.streamListen(vm_service.EventStreams.kIsolate);
    } on vm_service.RPCError {
      // Do nothing, since the tool is already subscribed.
    }
    final Future<void> onRunnable = service.onIsolateEvent.firstWhere((vm_service.Event event) {
      return event.kind == vm_service.EventKind.kIsolateRunnable;
    });
    await callMethodWrapper(
      kRunInViewMethod,
      args: <String, Object>{
        'viewId': viewId,
        'mainScript': main.toString(),
        'assetDirectory': assetsDirectory.toString(),
      },
    );
    await onRunnable;
  }

  Future<String> flutterDebugDumpApp({
    @required String isolateId,
  }) async {
    final Map<String, Object> response = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.debugDumpApp',
      isolateId: isolateId,
    );
    return response['data']?.toString();
  }

  Future<String> flutterDebugDumpRenderTree({
    @required String isolateId,
  }) async {
    final Map<String, Object> response = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.debugDumpRenderTree',
      isolateId: isolateId,
      args: <String, Object>{}
    );
    return response['data']?.toString();
  }

  Future<String> flutterDebugDumpLayerTree({
    @required String isolateId,
  }) async {
    final Map<String, Object> response = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.debugDumpLayerTree',
      isolateId: isolateId,
    );
    return response['data']?.toString();
  }

  Future<String> flutterDebugDumpSemanticsTreeInTraversalOrder({
    @required String isolateId,
  }) async {
    final Map<String, Object> response = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.debugDumpSemanticsTreeInTraversalOrder',
      isolateId: isolateId,
    );
    return response['data']?.toString();
  }

  Future<String> flutterDebugDumpSemanticsTreeInInverseHitTestOrder({
    @required String isolateId,
  }) async {
    final Map<String, Object> response = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.debugDumpSemanticsTreeInInverseHitTestOrder',
      isolateId: isolateId,
    );
    return response['data']?.toString();
  }

  Future<Map<String, dynamic>> _flutterToggle(String name, {
    @required String isolateId,
  }) async {
    Map<String, dynamic> state = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.$name',
      isolateId: isolateId,
    );
    if (state != null && state.containsKey('enabled') && state['enabled'] is String) {
      state = await invokeFlutterExtensionRpcRaw(
        'ext.flutter.$name',
        isolateId: isolateId,
        args: <String, dynamic>{
          'enabled': state['enabled'] == 'true' ? 'false' : 'true',
        },
      );
    }

    return state;
  }

  Future<Map<String, dynamic>> flutterToggleDebugPaintSizeEnabled({
    @required String isolateId,
  }) => _flutterToggle('debugPaint', isolateId: isolateId);

  Future<Map<String, dynamic>> flutterToggleDebugCheckElevationsEnabled({
    @required String isolateId,
  }) => _flutterToggle('debugCheckElevationsEnabled', isolateId: isolateId);

  Future<Map<String, dynamic>> flutterTogglePerformanceOverlayOverride({
    @required String isolateId,
  }) => _flutterToggle('showPerformanceOverlay', isolateId: isolateId);

  Future<Map<String, dynamic>> flutterToggleWidgetInspector({
    @required String isolateId,
  }) => _flutterToggle('inspector.show', isolateId: isolateId);

  Future<Map<String,dynamic>> flutterToggleInvertOversizedImages({
    @required String isolateId,
  }) => _flutterToggle('invertOversizedImages', isolateId: isolateId);

  Future<Map<String, dynamic>> flutterToggleProfileWidgetBuilds({
    @required String isolateId,
  }) => _flutterToggle('profileWidgetBuilds', isolateId: isolateId);

  Future<Map<String, dynamic>> flutterDebugAllowBanner(bool show, {
    @required String isolateId,
  }) {
    return invokeFlutterExtensionRpcRaw(
      'ext.flutter.debugAllowBanner',
      isolateId: isolateId,
      args: <String, dynamic>{'enabled': show ? 'true' : 'false'},
    );
  }

  Future<Map<String, dynamic>> flutterReassemble({
    @required String isolateId,
  }) {
    return invokeFlutterExtensionRpcRaw(
      'ext.flutter.reassemble',
      isolateId: isolateId,
    );
  }

  Future<Map<String, dynamic>> flutterFastReassemble({
   @required String isolateId,
   @required String className,
  }) {
    return invokeFlutterExtensionRpcRaw(
      'ext.flutter.fastReassemble',
      isolateId: isolateId,
      args: <String, Object>{
        'className': className,
      },
    );
  }

  Future<bool> flutterAlreadyPaintedFirstUsefulFrame({
    @required String isolateId,
  }) async {
    final Map<String, dynamic> result = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.didSendFirstFrameRasterizedEvent',
      isolateId: isolateId,
    );
    // result might be null when the service extension is not initialized
    return result != null && result['enabled'] == 'true';
  }

  Future<Map<String, dynamic>> uiWindowScheduleFrame({
    @required String isolateId,
  }) {
    return invokeFlutterExtensionRpcRaw(
      'ext.ui.window.scheduleFrame',
      isolateId: isolateId,
    );
  }

  Future<Map<String, dynamic>> flutterEvictAsset(String assetPath, {
   @required String isolateId,
  }) {
    return invokeFlutterExtensionRpcRaw(
      'ext.flutter.evict',
      isolateId: isolateId,
      args: <String, dynamic>{
        'value': assetPath,
      },
    );
  }

  /// Exit the application by calling [exit] from `dart:io`.
  ///
  /// This method is only supported by certain embedders. This is
  /// described by [Device.supportsFlutterExit].
  Future<void> flutterExit({
    @required String isolateId,
  }) {
    return invokeFlutterExtensionRpcRaw(
      'ext.flutter.exit',
      isolateId: isolateId,
    ).catchError((dynamic error, StackTrace stackTrace) {
      // Do nothing on sentinel or exception, the isolate already exited.
    }, test: (dynamic error) => error is vm_service.SentinelException || error is vm_service.RPCError);
  }

  /// Return the current platform override for the flutter view running with
  /// the main isolate [isolateId].
  ///
  /// If a non-null value is provided for [platform], the platform override
  /// is updated with this value.
  Future<String> flutterPlatformOverride({
    String platform,
    @required String isolateId,
  }) async {
    final Map<String, dynamic> result = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.platformOverride',
      isolateId: isolateId,
      args: platform != null
        ? <String, dynamic>{'value': platform}
        : <String, String>{},
    );
    if (result != null && result['value'] is String) {
      return result['value'] as String;
    }
    return 'unknown';
  }

  /// Return the current brightness value for the flutter view running with
  /// the main isolate [isolateId].
  ///
  /// If a non-null value is provided for [brightness], the brightness override
  /// is updated with this value.
  Future<Brightness> flutterBrightnessOverride({
    Brightness brightness,
    @required String isolateId,
  }) async {
    final Map<String, dynamic> result = await invokeFlutterExtensionRpcRaw(
      'ext.flutter.brightnessOverride',
      isolateId: isolateId,
      args: brightness != null
        ? <String, dynamic>{'value': brightness.toString()}
        : <String, String>{},
    );
    if (result != null && result['value'] is String) {
      return (result['value'] as String) == 'Brightness.light'
        ? Brightness.light
        : Brightness.dark;
    }
    return null;
  }

  Future<vm_service.Response> _checkedCallServiceExtension(
    String method, {
    Map<String, dynamic> args,
  }) async {
    try {
      return await service.callServiceExtension(method, args: args);
    } on vm_service.RPCError catch (err) {
      // If an application is not using the framework or the VM service
      // disappears while handling a request, return null.
      if ((err.code == RPCErrorCodes.kMethodNotFound)
          || (err.code == RPCErrorCodes.kServiceDisappeared)) {
        return null;
      }
      rethrow;
    }
  }

  /// Invoke a flutter extension method, if the flutter extension is not
  /// available, returns null.
  Future<Map<String, dynamic>> invokeFlutterExtensionRpcRaw(
    String method, {
    @required String isolateId,
    Map<String, dynamic> args,
  }) async {
    final vm_service.Response response = await _checkedCallServiceExtension(
      method,
      args: <String, Object>{
        'isolateId': isolateId,
        ...?args,
      },
    );
    return response?.json;
  }

  /// List all [FlutterView]s attached to the current VM.
  ///
  /// If this returns an empty list, it will poll forever unless [returnEarly]
  /// is set to true.
  ///
  /// By default, the poll duration is 50 milliseconds.
  Future<List<FlutterView>> getFlutterViews({
    bool returnEarly = false,
    Duration delay = const Duration(milliseconds: 50),
  }) async {
    while (true) {
      final vm_service.Response response = await callMethodWrapper(
        kListViewsMethod,
      );
      if (response == null) {
        // The service may have disappeared mid-request.
        // Return an empty list now, and let the shutdown logic elsewhere deal
        // with cleaning up.
        return <FlutterView>[];
      }
      final List<Object> rawViews = response.json['views'] as List<Object>;
      final List<FlutterView> views = <FlutterView>[
        for (final Object rawView in rawViews)
          FlutterView.parse(rawView as Map<String, Object>)
      ];
      if (views.isNotEmpty || returnEarly) {
        return views;
      }
      await Future<void>.delayed(delay);
    }
  }

  /// Waits for a signal from the VM service that [extensionName] is registered.
  ///
  /// Looks at the list of loaded extensions for first Flutter view, as well as
  /// the stream of added extensions to avoid races.
  ///
  /// Throws a [VmServiceDisappearedException] should the VM Service disappear
  /// while making calls to it.
  Future<vm_service.IsolateRef> findExtensionIsolate(String extensionName) async {
    try {
      await service.streamListen(vm_service.EventStreams.kIsolate);
    } on vm_service.RPCError {
      // Do nothing, since the tool is already subscribed.
    }

    final Completer<vm_service.IsolateRef> extensionAdded = Completer<vm_service.IsolateRef>();
    StreamSubscription<vm_service.Event> isolateEvents;
    isolateEvents = service.onIsolateEvent.listen((vm_service.Event event) {
      if (event.kind == vm_service.EventKind.kServiceExtensionAdded
          && event.extensionRPC == extensionName) {
        isolateEvents.cancel();
        extensionAdded.complete(event.isolate);
      }
    });

    try {
      final List<FlutterView> flutterViews = await getFlutterViews();
      if (flutterViews.isEmpty) {
        throw VmServiceDisappearedException();
      }

      for (final FlutterView flutterView in flutterViews) {
        final vm_service.IsolateRef isolateRef = flutterView.uiIsolate;
        if (isolateRef == null) {
          continue;
        }

        final vm_service.Isolate isolate = await getIsolateOrNull(isolateRef.id);
        if (isolate != null && isolate.extensionRPCs.contains(extensionName)) {
          return isolateRef;
        }
      }
      return await extensionAdded.future;
    } finally {
      await isolateEvents.cancel();
      try {
        await service.streamCancel(vm_service.EventStreams.kIsolate);
      } on vm_service.RPCError {
        // It's ok for cleanup to fail, such as when the service disappears.
      }
    }
  }

  /// Attempt to retrieve the isolate with id [isolateId], or `null` if it has
  /// been collected.
  Future<vm_service.Isolate> getIsolateOrNull(String isolateId) {
    return service.getIsolate(isolateId)
      .catchError((dynamic error, StackTrace stackTrace) {
        return null;
      }, test: (dynamic error) {
        return (error is vm_service.SentinelException) ||
          (error is vm_service.RPCError && error.code == RPCErrorCodes.kServiceDisappeared);
      });
  }

  /// Create a new development file system on the device.
  Future<vm_service.Response> createDevFS(String fsName) {
    // Call the unchecked version of `callServiceExtension` because the caller
    // has custom handling of certain RPCErrors.
    return service.callServiceExtension(
      '_createDevFS',
      args: <String, dynamic>{'fsName': fsName},
    );
  }

  /// Delete an existing file system.
  Future<void> deleteDevFS(String fsName) async {
    await _checkedCallServiceExtension(
      '_deleteDevFS',
      args: <String, dynamic>{'fsName': fsName},
    );
  }

  Future<vm_service.Response> screenshot() {
    return _checkedCallServiceExtension(kScreenshotMethod);
  }

  Future<vm_service.Response> screenshotSkp() {
    return _checkedCallServiceExtension(kScreenshotSkpMethod);
  }

  /// Set the VM timeline flags.
  Future<void> setTimelineFlags(List<String> recordedStreams) async {
    assert(recordedStreams != null);
    await _checkedCallServiceExtension(
      'setVMTimelineFlags',
      args: <String, dynamic>{
        'recordedStreams': recordedStreams,
      },
    );
  }

  Future<vm_service.Response> getTimeline() {
    return _checkedCallServiceExtension('getVMTimeline');
  }

  Future<void> dispose() async {
     await service.dispose();
  }
}

/// Thrown when the VM Service disappears while calls are being made to it.
class VmServiceDisappearedException implements Exception {}

/// Whether the event attached to an [Isolate.pauseEvent] should be considered
/// a "pause" event.
bool isPauseEvent(String kind) {
  return kind == vm_service.EventKind.kPauseStart ||
         kind == vm_service.EventKind.kPauseExit ||
         kind == vm_service.EventKind.kPauseBreakpoint ||
         kind == vm_service.EventKind.kPauseInterrupted ||
         kind == vm_service.EventKind.kPauseException ||
         kind == vm_service.EventKind.kPausePostRequest ||
         kind == vm_service.EventKind.kNone;
}

/// A brightness enum that matches the values https://github.com/flutter/engine/blob/3a96741247528133c0201ab88500c0c3c036e64e/lib/ui/window.dart#L1328
/// Describes the contrast of a theme or color palette.
enum Brightness {
  /// The color is dark and will require a light text color to achieve readable
  /// contrast.
  ///
  /// For example, the color might be dark grey, requiring white text.
  dark,

  /// The color is light and will require a dark text color to achieve readable
  /// contrast.
  ///
  /// For example, the color might be bright white, requiring black text.
  light,
}

/// Process a VM service log event into a string message.
String processVmServiceMessage(vm_service.Event event) {
  final String message = utf8.decode(base64.decode(event.bytes));
  // Remove extra trailing newlines appended by the vm service.
  if (message.endsWith('\n')) {
    return message.substring(0, message.length - 1);
  }
  return message;
}
