// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';

import 'package:file/src/interface/directory.dart';
import 'package:file/src/interface/file.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/custom_devices/custom_device.dart';
import 'package:flutter_tools/src/custom_devices/custom_device_config.dart';
import 'package:flutter_tools/src/custom_devices/custom_devices_config.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/linux/application_package.dart';
import 'package:flutter_tools/src/globals_null_migrated.dart' as globals;

import 'package:file/memory.dart';
import 'package:file/file.dart';
import 'package:flutter_tools/src/project.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fake_process_manager.dart';
import '../../src/fakes.dart';


void _writeCustomDevicesConfigFile(Directory dir, List<CustomDeviceConfig> configs) {
  dir.createSync();

  final File file = dir.childFile('.flutter_custom_devices.json');
  file.writeAsStringSync(jsonEncode(
    <String, dynamic>{
      'custom-devices': configs.map<dynamic>((CustomDeviceConfig c) => c.toJson()).toList()
    }
  ));
}

FlutterProject _setUpFlutterProject(Directory directory) {
  final FlutterProjectFactory flutterProjectFactory = FlutterProjectFactory(
    fileSystem: directory.fileSystem,
    logger: BufferLogger.test(),
  );
  return flutterProjectFactory.fromDirectory(directory);
}

void main() {
  testWithoutContext('replacing string interpolation occurrences in custom device commands', () async {
    expect(
      interpolateCommand(
        <String>['scp', r'${localPath}', r'/tmp/${appName}', 'pi@raspberrypi'],
        <String, String>{
          'localPath': 'build/flutter_assets',
          'appName': 'hello_world'
        }
      ),
      <String>[
        'scp', 'build/flutter_assets', '/tmp/hello_world', 'pi@raspberrypi'
      ]
    );

    expect(
      interpolateCommand(
        <String>[r'${test1}', r' ${test2}', r'${test3}'],
        <String, String>{
          'test1': '_test1',
          'test2': '_test2'
        }
      ),
      <String>[
        '_test1', ' _test2', r''
      ]
    );

    expect(
      interpolateCommand(
        <String>[r'${test1}', r' ${test2}', r'${test3}'],
        <String, String>{
          'test1': '_test1',
          'test2': '_test2'
        },
        additionalReplacementValues: <String, String>{
          'test2': '_nottest2',
          'test3': '_test3'
        }
      ),
      <String>[
        '_test1', ' _test2', r'_test3'
      ]
    );
  });

  final CustomDeviceConfig testConfig = CustomDeviceConfig(
    id: 'testid',
    label: 'testlabel',
    sdkNameAndVersion: 'testsdknameandversion',
    disabled: false,
    pingCommand: const <String>['testping'],
    pingSuccessRegex: RegExp('testpingsuccess'),
    postBuildCommand: const <String>['testpostbuild'],
    installCommand: const <String>['testinstall'],
    uninstallCommand: const <String>['testuninstall'],
    runDebugCommand: const <String>['testrundebug'],
    forwardPortCommand: const <String>['testforwardport'],
    forwardPortSuccessRegex: RegExp('testforwardportsuccess')
  );

  const String testConfigPingSuccessOutput = 'testpingsuccess\n';
  const String testConfigForwardPortSuccessOutput = 'testforwardportsuccess\n';
  final CustomDeviceConfig disabledTestConfig = testConfig.copyWith(disabled: true);
  final CustomDeviceConfig testConfigNonForwarding = testConfig.copyWith(
    explicitForwardPortCommand: true,
    forwardPortCommand: null,
    explicitForwardPortSuccessRegex: true,
    forwardPortSuccessRegex: null,
  );

  testUsingContext('CustomDevice defaults',
    () async {
      final CustomDevice device = CustomDevice(
        config: testConfig,
        processManager: FakeProcessManager.any(),
        logger: BufferLogger.test()
      );

      final PrebuiltLinuxApp linuxApp = PrebuiltLinuxApp(executable: 'foo');

      expect(device.id, 'testid');
      expect(device.name, 'testlabel');
      expect(device.platformType, PlatformType.custom);
      expect(await device.sdkNameAndVersion, 'testsdknameandversion');
      expect(await device.targetPlatform, TargetPlatform.linux_arm64);
      expect(await device.installApp(linuxApp), true);
      expect(await device.uninstallApp(linuxApp), true);
      expect(await device.isLatestBuildInstalled(linuxApp), false);
      expect(await device.isAppInstalled(linuxApp), false);
      expect(await device.stopApp(linuxApp), false);
      expect(device.category, Category.mobile);

      expect(device.supportsRuntimeMode(BuildMode.debug), true);
      expect(device.supportsRuntimeMode(BuildMode.profile), false);
      expect(device.supportsRuntimeMode(BuildMode.release), false);
      expect(device.supportsRuntimeMode(BuildMode.jitRelease), false);
    },
    overrides: <Type, dynamic Function()>{
      FileSystem: () => MemoryFileSystem.test(),
      ProcessManager: () => FakeProcessManager.any()
    }
  );

  testWithoutContext('CustomDevice: no devices listed if only disabled devices configured', () async {
    final MemoryFileSystem fs = MemoryFileSystem.test();
    final Directory dir = fs.directory('custom_devices_config_dir');

    _writeCustomDevicesConfigFile(dir, <CustomDeviceConfig>[disabledTestConfig]);

    expect(await CustomDevices(
      featureFlags: TestFeatureFlags(areCustomDevicesEnabled: true),
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.any(),
      config: CustomDevicesConfig.test(
        fileSystem: fs,
        directory: dir,
        logger: BufferLogger.test()
      )
    ).devices, <Device>[]);
  });

  testWithoutContext('CustomDevice: no devices listed if custom devices feature flag disabled', () async {
    final MemoryFileSystem fs = MemoryFileSystem.test();
    final Directory dir = fs.directory('custom_devices_config_dir');

    _writeCustomDevicesConfigFile(dir, <CustomDeviceConfig>[testConfig]);

    expect(await CustomDevices(
      featureFlags: TestFeatureFlags(areCustomDevicesEnabled: false),
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.any(),
      config: CustomDevicesConfig.test(
        fileSystem: fs,
        directory: dir,
        logger: BufferLogger.test()
      )
    ).devices, <Device>[]);
  });

  testWithoutContext('CustomDevices.devices', () async {
    final MemoryFileSystem fs = MemoryFileSystem.test();
    final Directory dir = fs.directory('custom_devices_config_dir');

    _writeCustomDevicesConfigFile(dir, <CustomDeviceConfig>[testConfig]);

    expect(
      await CustomDevices(
        featureFlags: TestFeatureFlags(areCustomDevicesEnabled: true),
        logger: BufferLogger.test(),
        processManager: FakeProcessManager.list(<FakeCommand>[
          FakeCommand(
            command: testConfig.pingCommand,
            stdout: testConfigPingSuccessOutput
          ),
        ]),
        config: CustomDevicesConfig.test(
          fileSystem: fs,
          directory: dir,
          logger: BufferLogger.test()
        )
      ).devices,
      hasLength(1)
    );
  });

  testWithoutContext('CustomDevices.discoverDevices successfully discovers devices and executes ping command', () async {
    final MemoryFileSystem fs = MemoryFileSystem.test();
    final Directory dir = fs.directory('custom_devices_config_dir');

    _writeCustomDevicesConfigFile(dir, <CustomDeviceConfig>[testConfig]);

    bool pingCommandWasExecuted = false;

    final CustomDevices discovery = CustomDevices(
      featureFlags: TestFeatureFlags(areCustomDevicesEnabled: true),
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: testConfig.pingCommand,
          onRun: () => pingCommandWasExecuted = true,
          stdout: testConfigPingSuccessOutput
        ),
      ]),
      config: CustomDevicesConfig.test(
        fileSystem: fs,
        directory: dir,
        logger: BufferLogger.test(),
      ),
    );

    final List<Device> discoveredDevices = await discovery.discoverDevices();

    expect(discoveredDevices, hasLength(1));
    expect(pingCommandWasExecuted, true);
  });

  testWithoutContext('CustomDevices.discoverDevices doesn\'t report device when ping command fails', () async {
    final MemoryFileSystem fs = MemoryFileSystem.test();
    final Directory dir = fs.directory('custom_devices_config_dir');

    _writeCustomDevicesConfigFile(dir, <CustomDeviceConfig>[testConfig]);

    final CustomDevices discovery = CustomDevices(
      featureFlags: TestFeatureFlags(areCustomDevicesEnabled: true),
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: testConfig.pingCommand,
          stdout: testConfigPingSuccessOutput,
          exitCode: 1
        ),
      ]),
      config: CustomDevicesConfig.test(
        fileSystem: fs,
        directory: dir,
        logger: BufferLogger.test(),
      ),
    );

    expect(await discovery.discoverDevices(), hasLength(0));
  });

  testWithoutContext('CustomDevices.discoverDevices doesn\'t report device when ping command output doesn\'t match ping success regex', () async {
    final MemoryFileSystem fs = MemoryFileSystem.test();
    final Directory dir = fs.directory('custom_devices_config_dir');

    _writeCustomDevicesConfigFile(dir, <CustomDeviceConfig>[testConfig]);

    final CustomDevices discovery = CustomDevices(
      featureFlags: TestFeatureFlags(areCustomDevicesEnabled: true),
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: testConfig.pingCommand,
          exitCode: 0,
          stdout: '',
        ),
      ]),
      config: CustomDevicesConfig.test(
        fileSystem: fs,
        directory: dir,
        logger: BufferLogger.test(),
      ),
    );

    expect(await discovery.discoverDevices(), hasLength(0));
  });

  testWithoutContext('CustomDevice.isSupportedForProject is true with editable host app', () async {
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('.packages').createSync();

    final FlutterProject flutterProject = _setUpFlutterProject(fileSystem.currentDirectory);

    expect(CustomDevice(
      config: testConfig,
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.any(),
    ).isSupportedForProject(flutterProject), true);
  });

  testUsingContext(
    'CustomDevice.install invokes uninstall and install command',
    () async {
      bool bothCommandsWereExecuted = false;

      final CustomDevice device = CustomDevice(
          config: testConfig,
          logger: BufferLogger.test(),
          processManager: FakeProcessManager.list(<FakeCommand>[
            FakeCommand(command: testConfig.uninstallCommand),
            FakeCommand(command: testConfig.installCommand, onRun: () => bothCommandsWereExecuted = true)
          ])
      );

      expect(await device.installApp(PrebuiltLinuxApp(executable: 'exe')), true);
      expect(bothCommandsWereExecuted, true);
    },
    overrides: <Type, dynamic Function()>{
      FileSystem: () => MemoryFileSystem.test(),
      ProcessManager: () => FakeProcessManager.any()
    }
  );

  testWithoutContext('CustomDevicePortForwarder will run and terminate forwardPort command', () async {
    final Completer<void> forwardPortCommandCompleter = Completer<void>();

    final CustomDevicePortForwarder forwarder = CustomDevicePortForwarder(
      deviceName: 'testdevicename',
      forwardPortCommand: testConfig.forwardPortCommand,
      forwardPortSuccessRegex: testConfig.forwardPortSuccessRegex,
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.list(<FakeCommand>[
        FakeCommand(
          command: testConfig.forwardPortCommand,
          stdout: testConfigForwardPortSuccessOutput,
          completer: forwardPortCommandCompleter
        )
      ])
    );

    // this should start the command
    expect(await forwarder.forward(12345, hostPort: null), 12345);
    expect(forwardPortCommandCompleter.isCompleted, false);

    // this should terminate it
    await forwarder.dispose();

    // the termination should have completed our completer
    expect(forwardPortCommandCompleter.isCompleted, true);
  });

  testWithoutContext('CustomDevice forwards observatory port correctly when port forwarding is configured', () async {
    final Completer<void> runDebugCompleter = Completer<void>();
    final Completer<void> forwardPortCompleter = Completer<void>();

    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      FakeCommand(
        command: testConfig.runDebugCommand,
        completer: runDebugCompleter,
        stdout: 'Observatory listening on http://127.0.0.1:12345/abcd/\n',
      ),
      FakeCommand(
        command: testConfig.forwardPortCommand,
        completer: forwardPortCompleter,
        stdout: testConfigForwardPortSuccessOutput,
      )
    ]);

    final CustomDeviceAppSession appSession = CustomDeviceAppSession(
      name: 'testname',
      device: CustomDevice(
        config: testConfig,
        logger: BufferLogger.test(),
        processManager: processManager
      ),
      appPackage: PrebuiltLinuxApp(executable: 'testexecutable'),
      logger: BufferLogger.test(),
      processManager: processManager,
    );

    final LaunchResult launchResult = await appSession.start();

    expect(launchResult.started, true);
    expect(launchResult.observatoryUri, Uri.parse('http://127.0.0.1:12345/abcd/'));
    expect(runDebugCompleter.isCompleted, false);
    expect(forwardPortCompleter.isCompleted, false);

    expect(await appSession.stop(), true);
    expect(runDebugCompleter.isCompleted, true);
    expect(forwardPortCompleter.isCompleted, true);
  });

  testWithoutContext('CustomDeviceAppSession forwards observatory port correctly when port forwarding is not configured', () async {
    final Completer<void> runDebugCompleter = Completer<void>();

    final FakeProcessManager processManager = FakeProcessManager.list(
      <FakeCommand>[
        FakeCommand(
          command: testConfigNonForwarding.runDebugCommand,
          completer: runDebugCompleter,
          stdout: 'Observatory listening on http://192.168.178.123:12345/abcd/\n'
        ),
      ]
    );

    final CustomDeviceAppSession appSession = CustomDeviceAppSession(
      name: 'testname',
      device: CustomDevice(
        config: testConfigNonForwarding,
        logger: BufferLogger.test(),
        processManager: processManager
      ),
      appPackage: PrebuiltLinuxApp(executable: 'testexecutable'),
      logger: BufferLogger.test(),
      processManager: processManager
    );

    final LaunchResult launchResult = await appSession.start();

    expect(launchResult.started, true);
    expect(launchResult.observatoryUri, Uri.parse('http://192.168.178.123:12345/abcd/'));
    expect(runDebugCompleter.isCompleted, false);

    expect(await appSession.stop(), true);
    expect(runDebugCompleter.isCompleted, true);
  });

  testUsingContext(
    'custom device end-to-end test',
    () async {
      final Completer<void> runDebugCompleter = Completer<void>();
      final Completer<void> forwardPortCompleter = Completer<void>();

      final FakeProcessManager processManager = FakeProcessManager.list(
        <FakeCommand>[
          FakeCommand(
            command: testConfig.pingCommand,
            stdout: testConfigPingSuccessOutput
          ),
          FakeCommand(command: testConfig.postBuildCommand),
          FakeCommand(command: testConfig.uninstallCommand),
          FakeCommand(command: testConfig.installCommand),
          FakeCommand(
            command: testConfig.runDebugCommand,
            completer: runDebugCompleter,
            stdout: 'Observatory listening on http://127.0.0.1:12345/abcd/\n',
          ),
          FakeCommand(
            command: testConfig.forwardPortCommand,
            completer: forwardPortCompleter,
            stdout: testConfigForwardPortSuccessOutput
          )
        ]
      );

      // Reuse our filesystem from context instead of mixing two filesystem instances
      // together
      final FileSystem fs = globals.fs;

      // CustomDevice.startApp doesn't care whether we pass a prebuilt app or
      // buildable app as long as we pass prebuiltApplication as false
      final PrebuiltLinuxApp app = PrebuiltLinuxApp(executable: 'testexecutable');

      final Directory configFileDir = fs.directory('custom_devices_config_dir');
      _writeCustomDevicesConfigFile(configFileDir, <CustomDeviceConfig>[testConfig]);

      // finally start actually testing things
      final CustomDevices customDevices = CustomDevices(
        featureFlags: TestFeatureFlags(areCustomDevicesEnabled: true),
        processManager: processManager,
        logger: BufferLogger.test(),
        config: CustomDevicesConfig.test(
          fileSystem: fs,
          directory: configFileDir,
          logger: BufferLogger.test()
        )
      );

      final List<Device> devices = await customDevices.discoverDevices();
      expect(devices.length, 1);
      expect(devices.single, isA<CustomDevice>());

      final CustomDevice device = devices.single as CustomDevice;
      expect(device.id, testConfig.id);
      expect(device.name, testConfig.label);
      expect(await device.sdkNameAndVersion, testConfig.sdkNameAndVersion);

      final LaunchResult result = await device.startApp(
        app,
        debuggingOptions: DebuggingOptions.enabled(BuildInfo.debug),
        bundleBuilder: FakeBundleBuilder()
      );
      expect(result.started, true);
      expect(result.hasObservatory, true);
      expect(result.observatoryUri, Uri.tryParse('http://127.0.0.1:12345/abcd/'));
      expect(runDebugCompleter.isCompleted, false);
      expect(forwardPortCompleter.isCompleted, false);

      expect(await device.stopApp(app), true);
      expect(runDebugCompleter.isCompleted, true);
      expect(forwardPortCompleter.isCompleted, true);
    },
    overrides: <Type, Generator>{
      FileSystem: () => MemoryFileSystem.test(),
      ProcessManager: () => FakeProcessManager.any()
    }
  );
}
