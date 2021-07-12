// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:flutter_tools/src/ios/xcodeproj.dart';
import 'package:flutter_tools/src/reporting/reporting.dart';
import 'package:process/process.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/test_flutter_command_runner.dart';
import '../../src/testbed.dart';

class FakeXcodeProjectInterpreterWithBuildSettings extends FakeXcodeProjectInterpreter {
  @override
  Future<Map<String, String>> getBuildSettings(
      String projectPath, {
        String scheme,
        Duration timeout = const Duration(minutes: 1),
      }) async {
    return <String, String>{
      'PRODUCT_BUNDLE_IDENTIFIER': 'io.flutter.someProject',
      'DEVELOPMENT_TEAM': 'abc',
    };
  }
}

final Platform macosPlatform = FakePlatform(
  operatingSystem: 'macos',
  environment: <String, String>{
    'FLUTTER_ROOT': '/',
    'HOME': '/',
  }
);
final Platform notMacosPlatform = FakePlatform(
  operatingSystem: 'linux',
  environment: <String, String>{
    'FLUTTER_ROOT': '/',
  }
);

void main() {
  FileSystem fileSystem;
  TestUsage usage;

  setUpAll(() {
    Cache.disableLocking();
  });

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    usage = TestUsage();
  });

  // Sets up the minimal mock project files necessary to look like a Flutter project.
  void _createCoreMockProjectFiles() {
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('.packages').createSync();
    fileSystem.file(fileSystem.path.join('lib', 'main.dart')).createSync(recursive: true);
  }

  // Sets up the minimal mock project files necessary for iOS builds to succeed.
  void _createMinimalMockProjectFiles() {
    fileSystem.directory(fileSystem.path.join('ios', 'Runner.xcodeproj')).createSync(recursive: true);
    fileSystem.directory(fileSystem.path.join('ios', 'Runner.xcworkspace')).createSync(recursive: true);
    fileSystem.file(fileSystem.path.join('ios', 'Runner.xcodeproj', 'project.pbxproj')).createSync();
    _createCoreMockProjectFiles();
  }

  const FakeCommand xattrCommand = FakeCommand(command: <String>[
    'xattr', '-r', '-d', 'com.apple.FinderInfo', '/'
  ]);

  FakeCommand _setUpRsyncCommand({void Function() onRun}) {
    return FakeCommand(
      command: const <String>[
        'rsync',
        '-av',
        '--delete',
        'build/ios/Release-iphoneos/Runner.app',
        'build/ios/iphoneos',
      ],
      onRun: onRun);
  }

  // Creates a FakeCommand for the xcodebuild call to build the app
  // in the given configuration.
  FakeCommand _setUpFakeXcodeBuildHandler({ bool verbose = false, bool showBuildSettings = false, void Function() onRun }) {
    return FakeCommand(
      command: <String>[
        'xcrun',
        'xcodebuild',
        '-configuration', 'Release',
        if (verbose)
          'VERBOSE_SCRIPT_LOGGING=YES'
        else
          '-quiet',
        '-workspace', 'Runner.xcworkspace',
        '-scheme', 'Runner',
        'BUILD_DIR=/build/ios',
        '-sdk', 'iphoneos',
        'FLUTTER_SUPPRESS_ANALYTICS=true',
        'COMPILER_INDEX_STORE_ENABLE=NO',
        if (showBuildSettings)
          '-showBuildSettings',
      ],
      stdout: '''
      TARGET_BUILD_DIR=build/ios/Release-iphoneos
      WRAPPER_NAME=Runner.app
''',
      onRun: onRun,
    );
  }

  testUsingContext('ios build fails when there is no ios project', () async {
    final BuildCommand command = BuildCommand();
    _createCoreMockProjectFiles();

    expect(createTestCommandRunner(command).run(
      const <String>['build', 'ios', '--no-pub']
    ), throwsToolExit(message: 'Application not configured for iOS'));
  }, overrides: <Type, Generator>{
    Platform: () => macosPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
    XcodeProjectInterpreter: () => FakeXcodeProjectInterpreterWithBuildSettings(),
  });

  testUsingContext('ios build fails in debug with code analysis', () async {
    final BuildCommand command = BuildCommand();
    _createCoreMockProjectFiles();

    expect(createTestCommandRunner(command).run(
      const <String>['build', 'ios', '--no-pub', '--debug', '--analyze-size']
    ), throwsToolExit(message: '--analyze-size" can only be used on release builds'));
  }, overrides: <Type, Generator>{
    Platform: () => macosPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
    XcodeProjectInterpreter: () => FakeXcodeProjectInterpreterWithBuildSettings(),
  });

  testUsingContext('ios build fails on non-macOS platform', () async {
    final BuildCommand command = BuildCommand();
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('.packages').createSync();
    fileSystem.file(fileSystem.path.join('lib', 'main.dart'))
      .createSync(recursive: true);

    expect(createTestCommandRunner(command).run(
      const <String>['build', 'ios', '--no-pub']
    ), throwsToolExit());
  }, overrides: <Type, Generator>{
    Platform: () => notMacosPlatform,
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
    XcodeProjectInterpreter: () => FakeXcodeProjectInterpreterWithBuildSettings(),
  });

  testUsingContext('ios build invokes xcode build', () async {
    final BuildCommand command = BuildCommand();
    _createMinimalMockProjectFiles();

    await createTestCommandRunner(command).run(
      const <String>['build', 'ios', '--no-pub']
    );
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.list(<FakeCommand>[
      xattrCommand,
      _setUpFakeXcodeBuildHandler(onRun: () {
        fileSystem.directory('build/ios/Release-iphoneos/Runner.app').createSync(recursive: true);
      }),
      _setUpFakeXcodeBuildHandler(showBuildSettings: true),
      _setUpRsyncCommand(),
    ]),
    Platform: () => macosPlatform,
    XcodeProjectInterpreter: () => FakeXcodeProjectInterpreterWithBuildSettings(),
  });

  testUsingContext('ios build invokes xcode build with verbosity', () async {
    final BuildCommand command = BuildCommand();
    _createMinimalMockProjectFiles();

    await createTestCommandRunner(command).run(
      const <String>['build', 'ios', '--no-pub', '-v']
    );
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.list(<FakeCommand>[
      xattrCommand,
      _setUpFakeXcodeBuildHandler(verbose: true, onRun: () {
        fileSystem.directory('build/ios/Release-iphoneos/Runner.app').createSync(recursive: true);
      }),
      _setUpFakeXcodeBuildHandler(verbose: true, showBuildSettings: true),
      _setUpRsyncCommand(),
    ]),
    Platform: () => macosPlatform,
    XcodeProjectInterpreter: () => FakeXcodeProjectInterpreterWithBuildSettings(),
  });

  testUsingContext('Performs code size analysis and sends analytics', () async {
    final BuildCommand command = BuildCommand();
    _createMinimalMockProjectFiles();

    await createTestCommandRunner(command).run(
      const <String>['build', 'ios', '--no-pub', '--analyze-size']
    );

    expect(testLogger.statusText, contains('A summary of your iOS bundle analysis can be found at'));
    expect(testLogger.statusText, contains('flutter pub global activate devtools; flutter pub global run devtools --appSizeBase='));
    expect(usage.events, contains(
      const TestUsageEvent('code-size-analysis', 'ios'),
    ));
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.list(<FakeCommand>[
      xattrCommand,
      _setUpFakeXcodeBuildHandler(onRun: () {
        fileSystem.directory('build/ios/Release-iphoneos/Runner.app').createSync(recursive: true);
        fileSystem.file('build/flutter_size_01/snapshot.arm64.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('''
[
  {
    "l": "dart:_internal",
    "c": "SubListIterable",
    "n": "[Optimized] skip",
    "s": 2400
  }
]''');
        fileSystem.file('build/flutter_size_01/trace.arm64.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('{}');
      }),
      _setUpFakeXcodeBuildHandler(showBuildSettings: true),
      _setUpRsyncCommand(onRun: () => fileSystem.file('build/ios/iphoneos/Runner.app/Frameworks/App.framework/App')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List<int>.generate(10000, (int index) => 0))),
    ]),
    Platform: () => macosPlatform,
    FileSystemUtils: () => FileSystemUtils(fileSystem: fileSystem, platform: macosPlatform),
    Usage: () => usage,
    XcodeProjectInterpreter: () => FakeXcodeProjectInterpreterWithBuildSettings(),
  });
}
