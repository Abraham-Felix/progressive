// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/base/dds.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/drive/drive_service.dart';
import 'package:flutter_tools/src/version.dart';
import 'package:flutter_tools/src/vmservice.dart';
import 'package:meta/meta.dart';
import 'package:package_config/package_config_types.dart';
import 'package:test/fake.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fake_vm_services.dart';
import '../../src/fakes.dart';


final vm_service.Isolate fakeUnpausedIsolate = vm_service.Isolate(
  id: '1',
  pauseEvent: vm_service.Event(
    kind: vm_service.EventKind.kResume,
    timestamp: 0
  ),
  breakpoints: <vm_service.Breakpoint>[],
  exceptionPauseMode: null,
  libraries: <vm_service.LibraryRef>[
    vm_service.LibraryRef(
      id: '1',
      uri: 'file:///hello_world/main.dart',
      name: '',
    ),
  ],
  livePorts: 0,
  name: 'test',
  number: '1',
  pauseOnExit: false,
  runnable: true,
  startTime: 0,
  isSystemIsolate: false,
  isolateFlags: <vm_service.IsolateFlag>[],
);

final vm_service.Isolate fakePausedIsolate = vm_service.Isolate(
  id: '1',
  pauseEvent: vm_service.Event(
    kind: vm_service.EventKind.kPauseException,
    timestamp: 0
  ),
  breakpoints: <vm_service.Breakpoint>[
    vm_service.Breakpoint(
      breakpointNumber: 123,
      id: 'test-breakpoint',
      location: vm_service.SourceLocation(
        tokenPos: 0,
        script: vm_service.ScriptRef(id: 'test-script', uri: 'foo.dart'),
      ),
      resolved: true,
    ),
  ],
  exceptionPauseMode: null,
  libraries: <vm_service.LibraryRef>[],
  livePorts: 0,
  name: 'test',
  number: '1',
  pauseOnExit: false,
  runnable: true,
  startTime: 0,
  isSystemIsolate: false,
  isolateFlags: <vm_service.IsolateFlag>[],
);

final vm_service.VM fakeVM = vm_service.VM(
  isolates: <vm_service.IsolateRef>[fakeUnpausedIsolate],
  pid: 1,
  hostCPU: '',
  isolateGroups: <vm_service.IsolateGroupRef>[],
  targetCPU: '',
  startTime: 0,
  name: 'dart',
  architectureBits: 64,
  operatingSystem: '',
  version: '',
  systemIsolateGroups: <vm_service.IsolateGroupRef>[],
  systemIsolates: <vm_service.IsolateRef>[],
);

final FlutterView fakeFlutterView = FlutterView(
  id: 'a',
  uiIsolate: fakeUnpausedIsolate,
);

final FakeVmServiceRequest listViews = FakeVmServiceRequest(
  method: kListViewsMethod,
  jsonResponse: <String, Object>{
    'views': <Object>[
      fakeFlutterView.toJson(),
    ],
  },
);

final FakeVmServiceRequest getVM = FakeVmServiceRequest(
  method: 'getVM',
  args: <String, Object>{},
  jsonResponse: fakeVM.toJson(),
);

void main() {
  testWithoutContext('Exits if device fails to start', () {
    final DriverService driverService = setUpDriverService();
    final Device device = FakeDevice(LaunchResult.failed());

    expect(
      () => driverService.start(BuildInfo.profile, device, DebuggingOptions.enabled(BuildInfo.profile), true),
      throwsToolExit(message: 'Application failed to start. Will not run test. Quitting.'),
    );
  });

  testWithoutContext('Retries application launch if it fails the first time', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(
        command: <String>['dart', '--enable-experiment=non-nullable', 'foo.test', '-rexpanded'],
        exitCode: 23,
        environment: <String, String>{
          'FOO': 'BAR',
          'VM_SERVICE_URL': 'http://127.0.0.1:1234/' // dds forwarded URI
        },
      ),
    ]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final Device device = FakeDevice(LaunchResult.succeeded(
      observatoryUri: Uri.parse('http://127.0.0.1:63426/1UasC_ihpXY=/'),
    ))..failOnce = true;

    await expectLater(
      () async => driverService.start(BuildInfo.profile, device, DebuggingOptions.enabled(BuildInfo.profile), true),
      returnsNormally,
    );
  });

  testWithoutContext('Connects to device VM Service and runs test application', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(
        command: <String>['dart', '--enable-experiment=non-nullable', 'foo.test', '-rexpanded'],
        exitCode: 23,
        environment: <String, String>{
          'FOO': 'BAR',
          'VM_SERVICE_URL': 'http://127.0.0.1:1234/' // dds forwarded URI
        },
      ),
    ]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final Device device = FakeDevice(LaunchResult.succeeded(
      observatoryUri: Uri.parse('http://127.0.0.1:63426/1UasC_ihpXY=/'),
    ));

    await driverService.start(BuildInfo.profile, device, DebuggingOptions.enabled(BuildInfo.profile), true);
    final int testResult = await driverService.startTest(
      'foo.test',
      <String>['--enable-experiment=non-nullable'],
      <String, String>{'FOO': 'BAR'},
      PackageConfig(<Package>[Package('test', Uri.base)]),
    );

    expect(testResult, 23);
  });

  testWithoutContext('Uses dart to execute the test if there is no package:test dependency', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(
        command: <String>['dart', '--enable-experiment=non-nullable', 'foo.test', '-rexpanded'],
        exitCode: 23,
        environment: <String, String>{
          'FOO': 'BAR',
          'VM_SERVICE_URL': 'http://127.0.0.1:1234/' // dds forwarded URI
        },
      ),
    ]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final Device device = FakeDevice(LaunchResult.succeeded(
      observatoryUri: Uri.parse('http://127.0.0.1:63426/1UasC_ihpXY=/'),
    ));

    await driverService.start(BuildInfo.profile, device, DebuggingOptions.enabled(BuildInfo.profile), true);
    final int testResult = await driverService.startTest(
      'foo.test',
      <String>['--enable-experiment=non-nullable'],
      <String, String>{'FOO': 'BAR'},
      PackageConfig.empty,
    );

    expect(testResult, 23);
  });


  testWithoutContext('Connects to device VM Service and runs test application without dds', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(
        command: <String>['dart', 'foo.test', '-rexpanded'],
        exitCode: 11,
        environment: <String, String>{
          'VM_SERVICE_URL': 'http://127.0.0.1:1234/'
        },
      ),
    ]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final Device device = FakeDevice(LaunchResult.succeeded(
      observatoryUri: Uri.parse('http://127.0.0.1:63426/1UasC_ihpXY=/'),
    ));

    await driverService.start(BuildInfo.profile, device, DebuggingOptions.enabled(BuildInfo.profile, disableDds: true), true);
    final int testResult = await driverService.startTest(
      'foo.test',
      <String>[],
      <String, String>{},
      PackageConfig(<Package>[Package('test', Uri.base)]),
    );

    expect(testResult, 11);
  });

  testWithoutContext('Safely stops and uninstalls application', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final FakeDevice device = FakeDevice(LaunchResult.succeeded(
      observatoryUri: Uri.parse('http://127.0.0.1:63426/1UasC_ihpXY=/'),
    ));

    await driverService.start(BuildInfo.profile, device, DebuggingOptions.enabled(BuildInfo.profile), true);
    await driverService.stop();

    expect(device.didStopApp, true);
    expect(device.didUninstallApp, true);
    expect(device.didDispose, true);
  });

  // FlutterVersion requires context.
  testUsingContext('Writes SkSL to file when provided with out file', () async {
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
      listViews,
      const FakeVmServiceRequest(
        method: '_flutter.getSkSLs',
        args: <String, Object>{
          'viewId': 'a'
        },
        jsonResponse: <String, Object>{
          'SkSLs': <String, Object>{
            'A': 'B',
          }
        }
      ),
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final FakeDevice device = FakeDevice(LaunchResult.succeeded(
      observatoryUri: Uri.parse('http://127.0.0.1:63426/1UasC_ihpXY=/'),
    ));

    await driverService.start(BuildInfo.profile, device, DebuggingOptions.enabled(BuildInfo.profile), true);
    await driverService.stop(writeSkslOnExit: fileSystem.file('out.json'));

    expect(device.didStopApp, true);
    expect(device.didUninstallApp, true);
    expect(json.decode(fileSystem.file('out.json').readAsStringSync()), <String, Object>{
      'platform': 'android',
      'name': 'test',
      'engineRevision': 'abcdefghijklmnopqrstuvwxyz',
      'data': <String, Object>{'A': 'B'}
    });
  }, overrides: <Type, Generator>{
    FlutterVersion: () => FakeFlutterVersion(
      engineRevision: 'abcdefghijklmnopqrstuvwxyz',
    )
  });

  testWithoutContext('Can connect to existing application and stop it during cleanup', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
      getVM,
      const FakeVmServiceRequest(
        method: 'ext.flutter.exit',
        args: <String, Object>{
          'isolateId': '1',
        }
      )
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final FakeDevice device = FakeDevice(LaunchResult.failed());

    await driverService.reuseApplication(
      Uri.parse('http://127.0.0.1:63426/1UasC_ihpXY=/'),
      device,
      DebuggingOptions.enabled(BuildInfo.debug),
      false,
    );
    await driverService.stop();
  });

  testWithoutContext('Can connect to existing application using ws URI', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
      getVM,
      const FakeVmServiceRequest(
        method: 'ext.flutter.exit',
        args: <String, Object>{
          'isolateId': '1',
        }
      )
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final FakeDevice device = FakeDevice(LaunchResult.failed());

    await driverService.reuseApplication(
      Uri.parse('ws://127.0.0.1:63426/1UasC_ihpXY=/ws/'),
      device,
      DebuggingOptions.enabled(BuildInfo.debug),
      false,
    );
    await driverService.stop();
  });


  testWithoutContext('Does not call flutterExit on device types that do not support it', () async {
    final FakeVmServiceHost fakeVmServiceHost = FakeVmServiceHost(requests: <FakeVmServiceRequest>[
      getVM,
    ]);
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[]);
    final DriverService driverService = setUpDriverService(processManager: processManager, vmService: fakeVmServiceHost.vmService);
    final FakeDevice device = FakeDevice(LaunchResult.failed(), supportsFlutterExit: false);

    await driverService.reuseApplication(
      Uri.parse('http://127.0.0.1:63426/1UasC_ihpXY=/'),
      device,
      DebuggingOptions.enabled(BuildInfo.debug),
      false,
    );
    await driverService.stop();
  });
}

FlutterDriverService setUpDriverService({
  Logger logger,
  ProcessManager processManager,
  FlutterVmService vmService,
}) {
  logger ??= BufferLogger.test();
  return FlutterDriverService(
    applicationPackageFactory: FakeApplicationPackageFactory(FakeApplicationPackage()),
    logger: logger,
    processUtils: ProcessUtils(
      logger: logger,
      processManager: processManager ?? FakeProcessManager.any(),
    ),
    dartSdkPath: 'dart',
    vmServiceConnector: (Uri httpUri, {
      ReloadSources reloadSources,
      Restart restart,
      CompileExpression compileExpression,
      GetSkSLMethod getSkSLMethod,
      PrintStructuredErrorLogMethod printStructuredErrorLogMethod,
      Object compression,
      Device device,
      Logger logger,
    }) async {
      if (httpUri.scheme != 'http') {
        fail('Expected an HTTP scheme, found $httpUri');
      }
      return vmService;
    }
  );
}

class FakeApplicationPackageFactory extends Fake implements ApplicationPackageFactory {
  FakeApplicationPackageFactory(this.applicationPackage);

  ApplicationPackage applicationPackage;

  @override
  Future<ApplicationPackage> getPackageForPlatform(
    TargetPlatform platform, {
    BuildInfo buildInfo,
    File applicationBinary,
  }) async => applicationPackage;
}

class FakeApplicationPackage extends Fake implements ApplicationPackage {}

class FakeDevice extends Fake implements Device {
  FakeDevice(this.result, {this.supportsFlutterExit = true});

  LaunchResult result;
  bool didStopApp = false;
  bool didUninstallApp = false;
  bool didDispose = false;
  bool failOnce = false;

  @override
  String get name => 'test';

  @override
  final bool supportsFlutterExit;

  @override
  final DartDevelopmentService dds = FakeDartDevelopmentService();

  @override
  Future<TargetPlatform> get targetPlatform async => TargetPlatform.android_arm;

  @override
  Future<DeviceLogReader> getLogReader({
    covariant ApplicationPackage app,
    bool includePastLogs = false,
  }) async => NoOpDeviceLogReader('test');

  @override
  Future<LaunchResult> startApp(
    covariant ApplicationPackage package, {
    String mainPath,
    String route,
    DebuggingOptions debuggingOptions,
    Map<String, dynamic> platformArgs,
    bool prebuiltApplication = false,
    bool ipv6 = false,
    String userIdentifier,
  }) async {
    if (failOnce) {
      failOnce = false;
      return LaunchResult.failed();
    }
    return result;
  }

  @override
  Future<bool> stopApp(covariant ApplicationPackage app, {String userIdentifier}) async {
    didStopApp = true;
    return true;
  }

  @override
  Future<bool> uninstallApp(covariant ApplicationPackage app, {String userIdentifier}) async {
    didUninstallApp = true;
    return true;
  }

  @override
  Future<void> dispose() async {
    didDispose = true;
  }
}

class FakeDartDevelopmentService extends Fake implements DartDevelopmentService {
  bool started = false;
  bool disposed = false;

  @override
  final Uri uri = Uri.parse('http://127.0.0.1:1234/');

  @override
  Future<void> startDartDevelopmentService(
    Uri observatoryUri,
    int hostPort,
    bool ipv6,
    bool disableServiceAuthCodes, {
    @required Logger logger,
  }) async {
    started = true;
  }

  @override
  Future<void> shutdown() async {
    disposed = true;
  }
}
