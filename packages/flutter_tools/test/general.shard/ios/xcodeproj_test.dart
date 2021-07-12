// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/ios/xcodeproj.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/reporting/reporting.dart';
import 'package:mockito/mockito.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/mocks.dart' as mocks;

const String xcodebuild = '/usr/bin/xcodebuild';

void main() {
  group('MockProcessManager', () {
    mocks.MockProcessManager processManager;
    XcodeProjectInterpreter xcodeProjectInterpreter;
    FakePlatform platform;
    BufferLogger logger;

    setUp(() {
      processManager = mocks.MockProcessManager();
      platform = FakePlatform(operatingSystem: 'macos');
      final FileSystem fileSystem = MemoryFileSystem.test();
      fileSystem.file(xcodebuild).createSync(recursive: true);
      logger = BufferLogger.test();
      xcodeProjectInterpreter = XcodeProjectInterpreter(
        logger: logger,
        fileSystem: fileSystem,
        platform: platform,
        processManager: processManager,
        usage: null,
      );
    });

    testWithoutContext('xcodebuild build settings flakes', () async {
      const Duration delay = Duration(seconds: 1);
      processManager.processFactory = mocks.flakyProcessFactory(
        flakes: 1,
        delay: delay + const Duration(seconds: 1),
      );
      platform.environment = const <String, String>{};

      when(processManager.runSync(<String>['which', 'sysctl']))
          .thenReturn(ProcessResult(0, 0, '', ''));
      when(processManager.runSync(<String>['sysctl', 'hw.optional.arm64']))
          .thenReturn(ProcessResult(0, 1, '', ''));

      expect(await xcodeProjectInterpreter.getBuildSettings(
        '', scheme: 'Runner', timeout: delay),
        const <String, String>{});
      // build settings times out and is killed once, then succeeds.
      verify(processManager.killPid(any)).called(1);
      // The verbose logs should tell us something timed out.
      expect(logger.traceText, contains('timed out'));
    });
  });

  const FakeCommand kWhichSysctlCommand = FakeCommand(
    command: <String>[
      'which',
      'sysctl',
    ],
  );

  const FakeCommand kARMCheckCommand = FakeCommand(
    command: <String>[
      'sysctl',
      'hw.optional.arm64',
    ],
    exitCode: 1,
  );

  FakeProcessManager fakeProcessManager;
  XcodeProjectInterpreter xcodeProjectInterpreter;
  FakePlatform platform;
  FileSystem fileSystem;
  BufferLogger logger;

  setUp(() {
    fakeProcessManager = FakeProcessManager.list(<FakeCommand>[]);
    platform = FakePlatform(operatingSystem: 'macos');
    fileSystem = MemoryFileSystem.test();
    fileSystem.file(xcodebuild).createSync(recursive: true);
    logger = BufferLogger.test();
    xcodeProjectInterpreter = XcodeProjectInterpreter(
      logger: logger,
      fileSystem: fileSystem,
      platform: platform,
      processManager: fakeProcessManager,
      usage: null,
    );
  });

  testWithoutContext('xcodebuild versionText returns null when xcodebuild is not fully installed', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: "xcode-select: error: tool 'xcodebuild' requires Xcode, "
            "but active developer directory '/Library/Developer/CommandLineTools' "
            'is a command line tools instance',
        exitCode: 1,
      ),
    ]);

    expect(xcodeProjectInterpreter.versionText, isNull);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild versionText returns null when xcodebuild is not installed', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        exception: ProcessException(xcodebuild, <String>['-version']),
      ),
    ]);

    expect(xcodeProjectInterpreter.versionText, isNull);
  });

  testWithoutContext('xcodebuild versionText returns formatted version text', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: 'Xcode 8.3.3\nBuild version 8E3004b',
      ),
    ]);

    expect(xcodeProjectInterpreter.versionText, 'Xcode 8.3.3, Build version 8E3004b');
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild versionText handles Xcode version string with unexpected format', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: 'Xcode Ultra5000\nBuild version 8E3004b',
      ),
    ]);

    expect(xcodeProjectInterpreter.versionText, 'Xcode Ultra5000, Build version 8E3004b');
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild version parts can be parsed', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: 'Xcode 11.4.1\nBuild version 11N111s',
      ),
    ]);

    expect(xcodeProjectInterpreter.majorVersion, 11);
    expect(xcodeProjectInterpreter.minorVersion, 4);
    expect(xcodeProjectInterpreter.patchVersion, 1);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild minor and patch version default to 0', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: 'Xcode 11\nBuild version 11N111s',
      ),
    ]);

    expect(xcodeProjectInterpreter.majorVersion, 11);
    expect(xcodeProjectInterpreter.minorVersion, 0);
    expect(xcodeProjectInterpreter.patchVersion, 0);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild version parts is null when version has unexpected format', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: 'Xcode Ultra5000\nBuild version 8E3004b',
      ),
    ]);
    expect(xcodeProjectInterpreter.majorVersion, isNull);
    expect(xcodeProjectInterpreter.minorVersion, isNull);
    expect(xcodeProjectInterpreter.patchVersion, isNull);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild isInstalled is false when not on MacOS', () {
    final Platform platform = FakePlatform(operatingSystem: 'notMacOS');
    xcodeProjectInterpreter = XcodeProjectInterpreter(
      logger: logger,
      fileSystem: fileSystem,
      platform: platform,
      processManager: fakeProcessManager,
      usage: TestUsage(),
    );
    fileSystem.file(xcodebuild).deleteSync();

    expect(xcodeProjectInterpreter.isInstalled, isFalse);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild isInstalled is false when xcodebuild does not exist', () {
    fileSystem.file(xcodebuild).deleteSync();

    expect(xcodeProjectInterpreter.isInstalled, isFalse);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext(
      'xcodebuild isInstalled is false when Xcode is not fully installed', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: "xcode-select: error: tool 'xcodebuild' requires Xcode, "
            "but active developer directory '/Library/Developer/CommandLineTools' "
            'is a command line tools instance',
        exitCode: 1,
      ),
    ]);

    expect(xcodeProjectInterpreter.isInstalled, isFalse);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild isInstalled is false when version has unexpected format', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: 'Xcode Ultra5000\nBuild version 8E3004b',
      ),
    ]);

    expect(xcodeProjectInterpreter.isInstalled, isFalse);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild isInstalled is true when version has expected format', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-version'],
        stdout: 'Xcode 8.3.3\nBuild version 8E3004b',
      ),
    ]);

    expect(xcodeProjectInterpreter.isInstalled, isTrue);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcrun runs natively on arm64', () {
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      FakeCommand(
        command: <String>[
          'sysctl',
          'hw.optional.arm64',
        ],
        stdout: 'hw.optional.arm64: 1',
      ),
    ]);

    expect(xcodeProjectInterpreter.xcrunCommand(), <String>[
      '/usr/bin/arch',
      '-arm64e',
      'xcrun',
    ]);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild build settings is empty when xcodebuild failed to get the build settings', () async {
    platform.environment = const <String, String>{};

    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      FakeCommand(
        command: <String>[
          'sysctl',
          'hw.optional.arm64',
        ],
        exitCode: 1,
      ),
      FakeCommand(
        command: <String>[
          'xcrun',
          'xcodebuild',
          '-project',
          '/',
          '-scheme',
          'Free',
          '-showBuildSettings'
        ],
        exitCode: 1,
      ),
    ]);

    expect(await xcodeProjectInterpreter.getBuildSettings('', scheme: 'Free'), const <String, String>{});
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('build settings accepts an empty scheme', () async {
    platform.environment = const <String, String>{};

    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>[
          'xcrun',
          'xcodebuild',
          '-project',
          '/',
          '-showBuildSettings'
        ],
        exitCode: 1,
      ),
    ]);

    expect(await xcodeProjectInterpreter.getBuildSettings(''), const <String, String>{});
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild build settings contains Flutter Xcode environment variables', () async {
    platform.environment = const <String, String>{
      'FLUTTER_XCODE_CODE_SIGN_STYLE': 'Manual',
      'FLUTTER_XCODE_ARCHS': 'arm64'
    };
    fakeProcessManager.addCommands(<FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>[
          'xcrun',
          'xcodebuild',
          '-project',
          fileSystem.path.separator,
          '-scheme',
          'Free',
          '-showBuildSettings',
          'CODE_SIGN_STYLE=Manual',
          'ARCHS=arm64'
        ],
      ),
    ]);
    expect(await xcodeProjectInterpreter.getBuildSettings('', scheme: 'Free'), const <String, String>{});
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild clean contains Flutter Xcode environment variables', () async {
    platform.environment = const <String, String>{
      'FLUTTER_XCODE_CODE_SIGN_STYLE': 'Manual',
      'FLUTTER_XCODE_ARCHS': 'arm64'
    };

    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>[
          'xcrun',
          'xcodebuild',
          '-workspace',
          'workspace_path',
          '-scheme',
          'Free',
          '-quiet',
          'clean',
          'CODE_SIGN_STYLE=Manual',
          'ARCHS=arm64'
        ],
      ),
    ]);

    await xcodeProjectInterpreter.cleanWorkspace('workspace_path', 'Free');
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild -list getInfo returns something when xcodebuild -list succeeds', () async {
    const String workingDirectory = '/';
    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-list'],
      ),
    ]);

    final XcodeProjectInterpreter xcodeProjectInterpreter = XcodeProjectInterpreter(
      logger: logger,
      fileSystem: fileSystem,
      platform: platform,
      processManager: fakeProcessManager,
      usage: TestUsage(),
    );

    expect(await xcodeProjectInterpreter.getInfo(workingDirectory), isNotNull);
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('xcodebuild -list getInfo throws a tool exit when it is unable to find a project', () async {
    const String workingDirectory = '/';
    const String stderr = 'Useful Xcode failure message about missing project.';

    fakeProcessManager.addCommands(const <FakeCommand>[
      kWhichSysctlCommand,
      kARMCheckCommand,
      FakeCommand(
        command: <String>['xcrun', 'xcodebuild', '-list'],
        exitCode: 66,
        stderr: stderr,
      ),
    ]);

    final XcodeProjectInterpreter xcodeProjectInterpreter = XcodeProjectInterpreter(
      logger: logger,
      fileSystem: fileSystem,
      platform: platform,
      processManager: fakeProcessManager,
      usage: TestUsage(),
    );

    expect(
        () async => xcodeProjectInterpreter.getInfo(workingDirectory),
        throwsToolExit(message: stderr));
    expect(fakeProcessManager.hasRemainingExpectations, isFalse);
  });

  testWithoutContext('Xcode project properties from default project can be parsed', () {
    const String output = '''
Information about project "Runner":
    Targets:
        Runner

    Build Configurations:
        Debug
        Release

    If no build configuration is specified and -scheme is not passed then "Release" is used.

    Schemes:
        Runner

''';
    final XcodeProjectInfo info = XcodeProjectInfo.fromXcodeBuildOutput(output, logger);
    expect(info.targets, <String>['Runner']);
    expect(info.schemes, <String>['Runner']);
    expect(info.buildConfigurations, <String>['Debug', 'Release']);
  });

  testWithoutContext('Xcode project properties from project with custom schemes can be parsed', () {
    const String output = '''
Information about project "Runner":
    Targets:
        Runner

    Build Configurations:
        Debug (Free)
        Debug (Paid)
        Release (Free)
        Release (Paid)

    If no build configuration is specified and -scheme is not passed then "Release (Free)" is used.

    Schemes:
        Free
        Paid

''';
    final XcodeProjectInfo info = XcodeProjectInfo.fromXcodeBuildOutput(output, logger);
    expect(info.targets, <String>['Runner']);
    expect(info.schemes, <String>['Free', 'Paid']);
    expect(info.buildConfigurations, <String>['Debug (Free)', 'Debug (Paid)', 'Release (Free)', 'Release (Paid)']);
  });

  testWithoutContext('expected scheme for non-flavored build is Runner', () {
    expect(XcodeProjectInfo.expectedSchemeFor(BuildInfo.debug), 'Runner');
    expect(XcodeProjectInfo.expectedSchemeFor(BuildInfo.profile), 'Runner');
    expect(XcodeProjectInfo.expectedSchemeFor(BuildInfo.release), 'Runner');
  });

  testWithoutContext('expected build configuration for non-flavored build is derived from BuildMode', () {
    expect(XcodeProjectInfo.expectedBuildConfigurationFor(BuildInfo.debug, 'Runner'), 'Debug');
    expect(XcodeProjectInfo.expectedBuildConfigurationFor(BuildInfo.profile, 'Runner'), 'Profile');
    expect(XcodeProjectInfo.expectedBuildConfigurationFor(BuildInfo.release, 'Runner'), 'Release');
  });

  testWithoutContext('expected scheme for flavored build is the title-cased flavor', () {
    expect(XcodeProjectInfo.expectedSchemeFor(const BuildInfo(BuildMode.debug, 'hello', treeShakeIcons: false)), 'Hello');
    expect(XcodeProjectInfo.expectedSchemeFor(const BuildInfo(BuildMode.profile, 'HELLO', treeShakeIcons: false)), 'HELLO');
    expect(XcodeProjectInfo.expectedSchemeFor(const BuildInfo(BuildMode.release, 'Hello', treeShakeIcons: false)), 'Hello');
  });
  testWithoutContext('expected build configuration for flavored build is Mode-Flavor', () {
    expect(XcodeProjectInfo.expectedBuildConfigurationFor(const BuildInfo(BuildMode.debug, 'hello', treeShakeIcons: false), 'Hello'), 'Debug-Hello');
    expect(XcodeProjectInfo.expectedBuildConfigurationFor(const BuildInfo(BuildMode.profile, 'HELLO', treeShakeIcons: false), 'Hello'), 'Profile-Hello');
    expect(XcodeProjectInfo.expectedBuildConfigurationFor(const BuildInfo(BuildMode.release, 'Hello', treeShakeIcons: false), 'Hello'), 'Release-Hello');
  });

  testWithoutContext('scheme for default project is Runner', () {
    final XcodeProjectInfo info = XcodeProjectInfo(<String>['Runner'], <String>['Debug', 'Release'], <String>['Runner'], logger);

    expect(info.schemeFor(BuildInfo.debug), 'Runner');
    expect(info.schemeFor(BuildInfo.profile), 'Runner');
    expect(info.schemeFor(BuildInfo.release), 'Runner');
    expect(info.schemeFor(const BuildInfo(BuildMode.debug, 'unknown', treeShakeIcons: false)), isNull);
  });

  testWithoutContext('build configuration for default project is matched against BuildMode', () {
    final XcodeProjectInfo info = XcodeProjectInfo(<String>['Runner'], <String>['Debug', 'Profile', 'Release'], <String>['Runner'], logger);

    expect(info.buildConfigurationFor(BuildInfo.debug, 'Runner'), 'Debug');
    expect(info.buildConfigurationFor(BuildInfo.profile, 'Runner'), 'Profile');
    expect(info.buildConfigurationFor(BuildInfo.release, 'Runner'), 'Release');
  });

  testWithoutContext('scheme for project with custom schemes is matched against flavor', () {
    final XcodeProjectInfo info = XcodeProjectInfo(
      <String>['Runner'],
      <String>['Debug (Free)', 'Debug (Paid)', 'Release (Free)', 'Release (Paid)'],
      <String>['Free', 'Paid'],
      logger,
    );

    expect(info.schemeFor(const BuildInfo(BuildMode.debug, 'free', treeShakeIcons: false)), 'Free');
    expect(info.schemeFor(const BuildInfo(BuildMode.profile, 'Free', treeShakeIcons: false)), 'Free');
    expect(info.schemeFor(const BuildInfo(BuildMode.release, 'paid', treeShakeIcons: false)), 'Paid');
    expect(info.schemeFor(BuildInfo.debug), isNull);
    expect(info.schemeFor(const BuildInfo(BuildMode.debug, 'unknown', treeShakeIcons: false)), isNull);
  });

  testWithoutContext('reports default scheme error and exit', () {
    final XcodeProjectInfo defaultInfo = XcodeProjectInfo(
      <String>[],
      <String>[],
      <String>['Runner'],
      logger,
    );

    expect(
      defaultInfo.reportFlavorNotFoundAndExit,
      throwsToolExit(
        message: 'The Xcode project does not define custom schemes. You cannot use the --flavor option.'
      ),
    );
  });

  testWithoutContext('reports custom scheme error and exit', () {
    final XcodeProjectInfo info = XcodeProjectInfo(
      <String>[],
      <String>[],
      <String>['Free', 'Paid'],
      logger,
    );

    expect(
      info.reportFlavorNotFoundAndExit,
      throwsToolExit(
        message: 'You must specify a --flavor option to select one of the available schemes.'
      ),
    );
  });

  testWithoutContext('build configuration for project with custom schemes is matched against BuildMode and flavor', () {
    final XcodeProjectInfo info = XcodeProjectInfo(
      <String>['Runner'],
      <String>['debug (free)', 'Debug paid', 'profile - Free', 'Profile-Paid', 'release - Free', 'Release-Paid'],
      <String>['Free', 'Paid'],
      logger,
    );

    expect(info.buildConfigurationFor(const BuildInfo(BuildMode.debug, 'free', treeShakeIcons: false), 'Free'), 'debug (free)');
    expect(info.buildConfigurationFor(const BuildInfo(BuildMode.debug, 'Paid', treeShakeIcons: false), 'Paid'), 'Debug paid');
    expect(info.buildConfigurationFor(const BuildInfo(BuildMode.profile, 'FREE', treeShakeIcons: false), 'Free'), 'profile - Free');
    expect(info.buildConfigurationFor(const BuildInfo(BuildMode.release, 'paid', treeShakeIcons: false), 'Paid'), 'Release-Paid');
  });

  testWithoutContext('build configuration for project with inconsistent naming is null', () {
    final XcodeProjectInfo info = XcodeProjectInfo(
      <String>['Runner'],
      <String>['Debug-F', 'Dbg Paid', 'Rel Free', 'Release Full'],
      <String>['Free', 'Paid'],
      logger,
    );
    expect(info.buildConfigurationFor(const BuildInfo(BuildMode.debug, 'Free', treeShakeIcons: false), 'Free'), null);
    expect(info.buildConfigurationFor(const BuildInfo(BuildMode.profile, 'Free', treeShakeIcons: false), 'Free'), null);
    expect(info.buildConfigurationFor(const BuildInfo(BuildMode.release, 'Paid', treeShakeIcons: false), 'Paid'), null);
  });
 group('environmentVariablesAsXcodeBuildSettings', () {
    FakePlatform platform;

    setUp(() {
      platform = FakePlatform();
    });

    testWithoutContext('environment variables as Xcode build settings', () {
      platform.environment = const <String, String>{
        'Ignored': 'Bogus',
        'FLUTTER_NOT_XCODE': 'Bogus',
        'FLUTTER_XCODE_CODE_SIGN_STYLE': 'Manual',
        'FLUTTER_XCODE_ARCHS': 'arm64'
      };
      final List<String> environmentVariablesAsBuildSettings = environmentVariablesAsXcodeBuildSettings(platform);
      expect(environmentVariablesAsBuildSettings, <String>['CODE_SIGN_STYLE=Manual', 'ARCHS=arm64']);
    });
  });

  group('updateGeneratedXcodeProperties', () {
    Artifacts localArtifacts;
    FakePlatform macOS;
    FileSystem fs;

    setUp(() {
      fs = MemoryFileSystem.test();
      localArtifacts = Artifacts.test(localEngine: 'out/ios_profile_arm');
      macOS = FakePlatform(operatingSystem: 'macos');
      fs.file(xcodebuild).createSync(recursive: true);
    });

    void testUsingOsxContext(String description, dynamic Function() testMethod) {
      testUsingContext(description, testMethod, overrides: <Type, Generator>{
        Artifacts: () => localArtifacts,
        Platform: () => macOS,
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      });
    }

    testUsingOsxContext('sets ARCHS=armv7 when armv7 local engine is set', () async {
      const BuildInfo buildInfo = BuildInfo.debug;
      final FlutterProject project = FlutterProject.fromDirectoryTest(fs.directory('path/to/project'));
      await updateGeneratedXcodeProperties(
        project: project,
        buildInfo: buildInfo,
      );

      final File config = fs.file('path/to/project/ios/Flutter/Generated.xcconfig');
      expect(config.existsSync(), isTrue);

      final String contents = config.readAsStringSync();
      expect(contents.contains('ARCHS=armv7'), isTrue);
      expect(contents.contains('EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64 i386'), isTrue);

      final File buildPhaseScript = fs.file('path/to/project/ios/Flutter/flutter_export_environment.sh');
      expect(buildPhaseScript.existsSync(), isTrue);

      final String buildPhaseScriptContents = buildPhaseScript.readAsStringSync();
      expect(buildPhaseScriptContents.contains('ARCHS=armv7'), isTrue);
      expect(buildPhaseScriptContents.contains('EXCLUDED_ARCHS'), isFalse);
    });

    testUsingOsxContext('sets TRACK_WIDGET_CREATION=true when trackWidgetCreation is true', () async {
      const BuildInfo buildInfo = BuildInfo(BuildMode.debug, null, trackWidgetCreation: true, treeShakeIcons: false);
      final FlutterProject project = FlutterProject.fromDirectoryTest(fs.directory('path/to/project'));
      await updateGeneratedXcodeProperties(
        project: project,
        buildInfo: buildInfo,
      );

      final File config = fs.file('path/to/project/ios/Flutter/Generated.xcconfig');
      expect(config.existsSync(), isTrue);

      final String contents = config.readAsStringSync();
      expect(contents.contains('TRACK_WIDGET_CREATION=true'), isTrue);

      final File buildPhaseScript = fs.file('path/to/project/ios/Flutter/flutter_export_environment.sh');
      expect(buildPhaseScript.existsSync(), isTrue);

      final String buildPhaseScriptContents = buildPhaseScript.readAsStringSync();
      expect(buildPhaseScriptContents.contains('TRACK_WIDGET_CREATION=true'), isTrue);
    });

    testUsingOsxContext('does not set TRACK_WIDGET_CREATION when trackWidgetCreation is false', () async {
      const BuildInfo buildInfo = BuildInfo.debug;
      final FlutterProject project = FlutterProject.fromDirectoryTest(fs.directory('path/to/project'));
      await updateGeneratedXcodeProperties(
        project: project,
        buildInfo: buildInfo,
      );

      final File config = fs.file('path/to/project/ios/Flutter/Generated.xcconfig');
      expect(config.existsSync(), isTrue);

      final String contents = config.readAsStringSync();
      expect(contents.contains('TRACK_WIDGET_CREATION=true'), isFalse);

      final File buildPhaseScript = fs.file('path/to/project/ios/Flutter/flutter_export_environment.sh');
      expect(buildPhaseScript.existsSync(), isTrue);

      final String buildPhaseScriptContents = buildPhaseScript.readAsStringSync();
      expect(buildPhaseScriptContents.contains('TRACK_WIDGET_CREATION=true'), isFalse);
    });

    group('sim local engine', () {
      Artifacts localArtifacts;

      setUp(() {
        localArtifacts = Artifacts.test(localEngine: 'out/ios_debug_sim_unopt');
      });

      testUsingContext('sets ARCHS=x86_64 when sim local engine is set', () async {
        const BuildInfo buildInfo = BuildInfo.debug;
        final FlutterProject project = FlutterProject.fromDirectoryTest(fs.directory('path/to/project'));
        await updateGeneratedXcodeProperties(
          project: project,
          buildInfo: buildInfo,
        );

        final File config = fs.file('path/to/project/ios/Flutter/Generated.xcconfig');
        expect(config.existsSync(), isTrue);

        final String contents = config.readAsStringSync();
        expect(contents.contains('ARCHS=x86_64'), isTrue);

        final File buildPhaseScript = fs.file('path/to/project/ios/Flutter/flutter_export_environment.sh');
        expect(buildPhaseScript.existsSync(), isTrue);

        final String buildPhaseScriptContents = buildPhaseScript.readAsStringSync();
        expect(buildPhaseScriptContents.contains('ARCHS=x86_64'), isTrue);
      }, overrides: <Type, Generator>{
        Artifacts: () => localArtifacts,
        Platform: () => macOS,
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      });
    });

    group('armv7 local engine', () {
      Artifacts localArtifacts;

      setUp(() {
        localArtifacts = Artifacts.test(localEngine: 'out/ios_profile');
      });

      testUsingContext('sets ARCHS=armv7 when armv7 local engine is set', () async {
        const BuildInfo buildInfo = BuildInfo.debug;

        final FlutterProject project = FlutterProject.fromDirectoryTest(fs.directory('path/to/project'));
        await updateGeneratedXcodeProperties(
          project: project,
          buildInfo: buildInfo,
        );

        final File config = fs.file('path/to/project/ios/Flutter/Generated.xcconfig');
        expect(config.existsSync(), isTrue);

        final String contents = config.readAsStringSync();
        expect(contents.contains('ARCHS=arm64'), isTrue);
      }, overrides: <Type, Generator>{
        Artifacts: () => localArtifacts,
        Platform: () => macOS,
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      });
    });

    String propertyFor(String key, File file) {
      final List<String> properties = file
          .readAsLinesSync()
          .where((String line) => line.startsWith('$key='))
          .map((String line) => line.split('=')[1])
          .toList();
      return properties.isEmpty ? null : properties.first;
    }

    Future<void> checkBuildVersion({
      String manifestString,
      BuildInfo buildInfo,
      String expectedBuildName,
      String expectedBuildNumber,
    }) async {
      final File manifestFile = fs.file('path/to/project/pubspec.yaml');
      manifestFile.createSync(recursive: true);
      manifestFile.writeAsStringSync(manifestString);

      await updateGeneratedXcodeProperties(
        project: FlutterProject.fromDirectoryTest(fs.directory('path/to/project')),
        buildInfo: buildInfo,
      );

      final File localPropertiesFile = fs.file('path/to/project/ios/Flutter/Generated.xcconfig');
      expect(propertyFor('FLUTTER_BUILD_NAME', localPropertiesFile), expectedBuildName);
      expect(propertyFor('FLUTTER_BUILD_NUMBER', localPropertiesFile), expectedBuildNumber);
      expect(propertyFor('FLUTTER_BUILD_NUMBER', localPropertiesFile), isNotNull);
    }

    testUsingOsxContext('extract build name and number from pubspec.yaml', () async {
      const String manifest = '''
name: test
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
flutter:
''';

      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.0',
        expectedBuildNumber: '1',
      );
    });

    testUsingOsxContext('extract build name from pubspec.yaml', () async {
      const String manifest = '''
name: test
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.0',
        expectedBuildNumber: '1.0.0',
      );
    });

    testUsingOsxContext('allow build info to override build name', () async {
      const String manifest = '''
name: test
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '1',
      );
    });

    testUsingOsxContext('allow build info to override build name with build number fallback', () async {
      const String manifest = '''
name: test
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '1.0.2',
      );
    });

    testUsingOsxContext('allow build info to override build number', () async {
      const String manifest = '''
name: test
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildNumber: '3', treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.0',
        expectedBuildNumber: '3',
      );
    });

    testUsingOsxContext('allow build info to override build name and number', () async {
      const String manifest = '''
name: test
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', buildNumber: '3', treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '3',
      );
    });

    testUsingOsxContext('allow build info to override build name and set number', () async {
      const String manifest = '''
name: test
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', buildNumber: '3', treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '3',
      );
    });

    testUsingOsxContext('allow build info to set build name and number', () async {
      const String manifest = '''
name: test
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', buildNumber: '3', treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '3',
      );
    });

    testUsingOsxContext('default build name and number when version is missing', () async {
      const String manifest = '''
name: test
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, treeShakeIcons: false);
      await checkBuildVersion(
        manifestString: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.0',
        expectedBuildNumber: '1',
      );
    });
  });
}
