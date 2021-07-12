// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/ios/application_package.dart';
import 'package:flutter_tools/src/ios/devices.dart';
import 'package:flutter_tools/src/ios/ios_deploy.dart';
import 'package:flutter_tools/src/ios/iproxy.dart';
import 'package:flutter_tools/src/ios/mac.dart';
import 'package:flutter_tools/src/ios/xcodeproj.dart';
import 'package:flutter_tools/src/macos/xcode.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:mockito/mockito.dart';
import 'package:fake_async/fake_async.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fake_process_manager.dart';
import '../../src/fakes.dart';

List<String> _xattrArgs(FlutterProject flutterProject) {
  return <String>[
    'xattr',
    '-r',
    '-d',
    'com.apple.FinderInfo',
    flutterProject.directory.path,
  ];
}

const List<String> kRunReleaseArgs = <String>[
  'xcrun',
  'xcodebuild',
  '-configuration',
  'Release',
  '-quiet',
  '-workspace',
  'Runner.xcworkspace',
  '-scheme',
  'Runner',
  'BUILD_DIR=/build/ios',
  '-sdk',
  'iphoneos',
  'ONLY_ACTIVE_ARCH=YES',
  'ARCHS=arm64',
  'FLUTTER_SUPPRESS_ANALYTICS=true',
  'COMPILER_INDEX_STORE_ENABLE=NO',
];

const String kConcurrentBuildErrorMessage = '''
"/Developer/Xcode/DerivedData/foo/XCBuildData/build.db":
database is locked
Possibly there are two concurrent builds running in the same filesystem location.
''';

final FakePlatform macPlatform = FakePlatform(
  operatingSystem: 'macos',
  environment: <String, String>{},
);

void main() {
  Artifacts artifacts;
  String iosDeployPath;

  setUp(() {
    artifacts = Artifacts.test();
    iosDeployPath = artifacts.getArtifactPath(Artifact.iosDeploy, platform: TargetPlatform.ios);
  });

  group('IOSDevice.startApp succeeds in release mode', () {
    FileSystem fileSystem;
    FakeProcessManager processManager;
    BufferLogger logger;
    Xcode xcode;
    MockXcodeProjectInterpreter mockXcodeProjectInterpreter;

    setUp(() {
      logger = BufferLogger.test();
      fileSystem = MemoryFileSystem.test();
      processManager = FakeProcessManager.list(<FakeCommand>[]);

      mockXcodeProjectInterpreter = MockXcodeProjectInterpreter();
      when(mockXcodeProjectInterpreter.isInstalled).thenReturn(true);
      when(mockXcodeProjectInterpreter.majorVersion).thenReturn(1000);
      when(mockXcodeProjectInterpreter.xcrunCommand()).thenReturn(<String>['xcrun']);
      when(mockXcodeProjectInterpreter.getInfo(any, projectFilename: anyNamed('projectFilename'))).thenAnswer(
          (_) {
          return Future<XcodeProjectInfo>.value(XcodeProjectInfo(
            <String>['Runner'],
            <String>['Debug', 'Release'],
            <String>['Runner'],
            logger,
          ));
        }
      );
      xcode = Xcode.test(processManager: FakeProcessManager.any(), xcodeProjectInterpreter: mockXcodeProjectInterpreter);
      fileSystem.file('foo/.packages')
        ..createSync(recursive: true)
        ..writeAsStringSync('\n');
    });

    testUsingContext('with buildable app', () async {
      final IOSDevice iosDevice = setUpIOSDevice(
        fileSystem: fileSystem,
        processManager: processManager,
        logger: logger,
        artifacts: artifacts,
      );
      setUpIOSProject(fileSystem);
      final FlutterProject flutterProject = FlutterProject.fromDirectory(fileSystem.currentDirectory);
      final BuildableIOSApp buildableIOSApp = BuildableIOSApp(flutterProject.ios, 'flutter', 'My Super Awesome App.app');
      fileSystem.directory('build/ios/Release-iphoneos/My Super Awesome App.app').createSync(recursive: true);

      processManager.addCommand(FakeCommand(command: _xattrArgs(flutterProject)));
      processManager.addCommand(const FakeCommand(command: kRunReleaseArgs));
      processManager.addCommand(const FakeCommand(command: <String>[...kRunReleaseArgs, '-showBuildSettings'], stdout: r'''
      TARGET_BUILD_DIR=build/ios/Release-iphoneos
      WRAPPER_NAME=My Super Awesome App.app
      '''
      ));
      processManager.addCommand(const FakeCommand(command: <String>[
        'rsync',
        '-av',
        '--delete',
        'build/ios/Release-iphoneos/My Super Awesome App.app',
        'build/ios/iphoneos',
      ]));
      processManager.addCommand(FakeCommand(
        command: <String>[
          iosDeployPath,
          '--id',
          '123',
          '--bundle',
          'build/ios/iphoneos/My Super Awesome App.app',
          '--app_deltas',
          'build/ios/app-delta',
          '--no-wifi',
          '--justlaunch',
          '--args',
          const <String>[
            '--enable-dart-profiling',
            '--disable-service-auth-codes',
          ].join(' ')
        ])
      );

      final LaunchResult launchResult = await iosDevice.startApp(
        buildableIOSApp,
        debuggingOptions: DebuggingOptions.disabled(BuildInfo.release),
        platformArgs: <String, Object>{},
      );

      expect(fileSystem.directory('build/ios/iphoneos'), exists);
      expect(launchResult.started, true);
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      FileSystem: () => fileSystem,
      Logger: () => logger,
      Platform: () => macPlatform,
      XcodeProjectInterpreter: () => mockXcodeProjectInterpreter,
      Xcode: () => xcode,
    });

    testUsingContext('with flaky buildSettings call', () async {
      LaunchResult launchResult;
      FakeAsync().run((FakeAsync time) {
        final IOSDevice iosDevice = setUpIOSDevice(
          fileSystem: fileSystem,
          processManager: processManager,
          logger: logger,
          artifacts: artifacts,
        );
        setUpIOSProject(fileSystem);
        final FlutterProject flutterProject = FlutterProject.fromDirectory(fileSystem.currentDirectory);
        final BuildableIOSApp buildableIOSApp = BuildableIOSApp(flutterProject.ios, 'flutter', 'My Super Awesome App.app');
        fileSystem.directory('build/ios/Release-iphoneos/My Super Awesome App.app').createSync(recursive: true);

        processManager.addCommand(FakeCommand(command: _xattrArgs(flutterProject)));
        processManager.addCommand(const FakeCommand(command: kRunReleaseArgs));
        // The first showBuildSettings call should timeout.
        processManager.addCommand(
          const FakeCommand(
            command: <String>[...kRunReleaseArgs, '-showBuildSettings'],
            duration: Duration(minutes: 5), // this is longer than the timeout of 1 minute.
          ));
        // The second call succeeds and is made after the first times out.
        processManager.addCommand(
          const FakeCommand(
            command: <String>[...kRunReleaseArgs, '-showBuildSettings'],
            exitCode: 0,
            stdout: r'''
      TARGET_BUILD_DIR=build/ios/Release-iphoneos
      WRAPPER_NAME=My Super Awesome App.app
      '''
          ));
        processManager.addCommand(const FakeCommand(command: <String>[
          'rsync',
          '-av',
          '--delete',
          'build/ios/Release-iphoneos/My Super Awesome App.app',
          'build/ios/iphoneos',
        ]));
        processManager.addCommand(FakeCommand(
          command: <String>[
            iosDeployPath,
            '--id',
            '123',
            '--bundle',
            'build/ios/iphoneos/My Super Awesome App.app',
            '--app_deltas',
            'build/ios/app-delta',
            '--no-wifi',
            '--justlaunch',
            '--args',
            const <String>[
              '--enable-dart-profiling',
              '--disable-service-auth-codes',
            ].join(' ')
          ])
        );

        iosDevice.startApp(
          buildableIOSApp,
          debuggingOptions: DebuggingOptions.disabled(BuildInfo.release),
          platformArgs: <String, Object>{},
        ).then((LaunchResult result) {
          launchResult = result;
        });

        // Elapse duration for process timeout.
        time.flushMicrotasks();
        time.elapse(const Duration(minutes: 1));

        // Elapse duration for overall process timer.
        time.flushMicrotasks();
        time.elapse(const Duration(minutes: 5));

        time.flushTimers();
      });

      expect(launchResult?.started, true);
      expect(fileSystem.directory('build/ios/iphoneos'), exists);
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      FileSystem: () => fileSystem,
      Logger: () => logger,
      Platform: () => macPlatform,
      XcodeProjectInterpreter: () => mockXcodeProjectInterpreter,
      Xcode: () => xcode,
    });

    testUsingContext('with concurrent build failures', () async {
      final IOSDevice iosDevice = setUpIOSDevice(
        fileSystem: fileSystem,
        processManager: processManager,
        logger: logger,
        artifacts: artifacts,
      );
      setUpIOSProject(fileSystem);
      final FlutterProject flutterProject = FlutterProject.fromDirectory(fileSystem.currentDirectory);
      final BuildableIOSApp buildableIOSApp = BuildableIOSApp(flutterProject.ios, 'flutter', 'My Super Awesome App.app');

      processManager.addCommand(FakeCommand(command: _xattrArgs(flutterProject)));
      // The first xcrun call should fail with a
      // concurrent build exception.
      processManager.addCommand(
        const FakeCommand(
          command: kRunReleaseArgs,
          exitCode: 1,
          stdout: kConcurrentBuildErrorMessage,
        ));
      processManager.addCommand(const FakeCommand(command: kRunReleaseArgs));
      processManager.addCommand(
        const FakeCommand(
          command: <String>[...kRunReleaseArgs, '-showBuildSettings'],
          exitCode: 0,
        ));
      processManager.addCommand(FakeCommand(
        command: <String>[
          iosDeployPath,
          '--id',
          '123',
          '--bundle',
          'build/ios/iphoneos/My Super Awesome App.app',
          '--no-wifi',
          '--justlaunch',
          '--args',
          const <String>[
            '--enable-dart-profiling',
            '--disable-service-auth-codes',
          ].join(' ')
        ])
      );

      await FakeAsync().run((FakeAsync time) async {
        final LaunchResult launchResult = await iosDevice.startApp(
          buildableIOSApp,
          debuggingOptions: DebuggingOptions.disabled(BuildInfo.release),
          platformArgs: <String, Object>{},
        );
        time.elapse(const Duration(seconds: 2));

        expect(logger.statusText,
          contains('Xcode build failed due to concurrent builds, will retry in 2 seconds'));
        expect(launchResult.started, true);
        expect(processManager, hasNoRemainingExpectations);
      });
    }, overrides: <Type, Generator>{
      ProcessManager: () => processManager,
      FileSystem: () => fileSystem,
      Logger: () => logger,
      Platform: () => macPlatform,
      XcodeProjectInterpreter: () => mockXcodeProjectInterpreter,
      Xcode: () => xcode,
    }, skip: true); // TODO(jonahwilliams): clean up with https://github.com/flutter/flutter/issues/60675
  });
}

void setUpIOSProject(FileSystem fileSystem) {
  fileSystem.file('pubspec.yaml').createSync();
  fileSystem.file('.packages').writeAsStringSync('\n');
  fileSystem.directory('ios').createSync();
  fileSystem.directory('ios/Runner.xcworkspace').createSync();
  fileSystem.file('ios/Runner.xcodeproj/project.pbxproj').createSync(recursive: true);
  // This is the expected output directory.
  fileSystem.directory('build/ios/iphoneos/My Super Awesome App.app').createSync(recursive: true);
}

IOSDevice setUpIOSDevice({
  String sdkVersion = '13.0.1',
  FileSystem fileSystem,
  Logger logger,
  ProcessManager processManager,
  Artifacts artifacts,
}) {
  artifacts ??= Artifacts.test();
  final Cache cache = Cache.test(
    artifacts: <ArtifactSet>[
      FakeDyldEnvironmentArtifact(),
    ],
    processManager: FakeProcessManager.any(),
  );

  logger ??= BufferLogger.test();
  return IOSDevice('123',
    name: 'iPhone 1',
    sdkVersion: sdkVersion,
    fileSystem: fileSystem ?? MemoryFileSystem.test(),
    platform: macPlatform,
    iProxy: IProxy.test(logger: logger, processManager: processManager ?? FakeProcessManager.any()),
    logger: logger,
    iosDeploy: IOSDeploy(
      logger: logger,
      platform: macPlatform,
      processManager: processManager ?? FakeProcessManager.any(),
      artifacts: artifacts,
      cache: cache,
    ),
    iMobileDevice: IMobileDevice(
      logger: logger,
      processManager: processManager ?? FakeProcessManager.any(),
      artifacts: artifacts,
      cache: cache,
    ),
    cpuArchitecture: DarwinArch.arm64,
    interfaceType: IOSDeviceInterface.usb,
  );
}

class MockXcodeProjectInterpreter extends Mock implements XcodeProjectInterpreter {}
