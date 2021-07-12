// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:flutter_tools/src/android/gradle.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/reporting/reporting.dart';
import 'package:mockito/mockito.dart';

import '../../src/common.dart';
import '../../src/context.dart';

void main() {
  FileSystem fileSystem;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
  });

  testWithoutContext('Finds app bundle when flavor contains underscores in release mode', () {
    final FlutterProject project = generateFakeAppBundle('foo_barRelease', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.release, 'foo_bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barRelease', 'app.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores and uppercase letters in release mode', () {
    final FlutterProject project = generateFakeAppBundle('foo_barRelease', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.release, 'foo_Bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barRelease', 'app.aab'));
  });

  testWithoutContext("Finds app bundle when flavor doesn't contain underscores in release mode", () {
    final FlutterProject project = generateFakeAppBundle('fooRelease', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.release, 'foo', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'fooRelease', 'app.aab'));
  });

  testWithoutContext("Finds app bundle when flavor doesn't contain underscores but contains uppercase letters in release mode", () {
    final FlutterProject project = generateFakeAppBundle('fooaRelease', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.release, 'fooA', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'fooaRelease', 'app.aab'));
  });

  testWithoutContext('Finds app bundle when no flavor is used in release mode', () {
    final FlutterProject project = generateFakeAppBundle('release', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.release, null, treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'release', 'app.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores in debug mode', () {
    final FlutterProject project = generateFakeAppBundle('foo_barDebug', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.debug, 'foo_bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barDebug', 'app.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores and uppercase letters in debug mode', () {
    final FlutterProject project = generateFakeAppBundle('foo_barDebug', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.debug, 'foo_Bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barDebug', 'app.aab'));
  });

  testWithoutContext("Finds app bundle when flavor doesn't contain underscores in debug mode", () {
    final FlutterProject project = generateFakeAppBundle('fooDebug', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.debug, 'foo', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'fooDebug', 'app.aab'));
  });

  testWithoutContext("Finds app bundle when flavor doesn't contain underscores but contains uppercase letters in debug mode", () {
    final FlutterProject project = generateFakeAppBundle('fooaDebug', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.debug, 'fooA', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'fooaDebug', 'app.aab'));
  });

  testWithoutContext('Finds app bundle when no flavor is used in debug mode', () {
    final FlutterProject project = generateFakeAppBundle('debug', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      BuildInfo.debug,
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'debug', 'app.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores in profile mode', () {
    final FlutterProject project = generateFakeAppBundle('foo_barProfile', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.profile, 'foo_bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barProfile', 'app.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores and uppercase letters in profile mode', () {
    final FlutterProject project = generateFakeAppBundle('foo_barProfile', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.profile, 'foo_Bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barProfile', 'app.aab'));
  });

  testWithoutContext("Finds app bundle when flavor doesn't contain underscores in profile mode", () {
    final FlutterProject project = generateFakeAppBundle('fooProfile', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.profile, 'foo', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'fooProfile', 'app.aab'));
  });

  testWithoutContext("Finds app bundle when flavor doesn't contain underscores but contains uppercase letters in profile mode", () {
    final FlutterProject project = generateFakeAppBundle('fooaProfile', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.profile, 'fooA', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'fooaProfile', 'app.aab'));
  });

  testWithoutContext('Finds app bundle when no flavor is used in profile mode', () {
    final FlutterProject project = generateFakeAppBundle('profile', 'app.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.profile, null, treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'profile', 'app.aab'));
  });

  testWithoutContext('Finds app bundle in release mode - Gradle 3.5', () {
    final FlutterProject project = generateFakeAppBundle('release', 'app-release.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.release, null, treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'release', 'app-release.aab'));
  });

  testWithoutContext('Finds app bundle in profile mode - Gradle 3.5', () {
    final FlutterProject project = generateFakeAppBundle('profile', 'app-profile.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.profile, null, treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'profile', 'app-profile.aab'));
  });

  testWithoutContext('Finds app bundle in debug mode - Gradle 3.5', () {
    final FlutterProject project = generateFakeAppBundle('debug', 'app-debug.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      BuildInfo.debug,
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'debug', 'app-debug.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores in release mode - Gradle 3.5', () {
    final FlutterProject project = generateFakeAppBundle('foo_barRelease', 'app-foo_bar-release.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.release, 'foo_bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barRelease', 'app-foo_bar-release.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores and uppercase letters in release mode - Gradle 3.5', () {
    final FlutterProject project = generateFakeAppBundle('foo_barRelease', 'app-foo_bar-release.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.release, 'foo_Bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barRelease', 'app-foo_bar-release.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores in profile mode - Gradle 3.5', () {
    final FlutterProject project = generateFakeAppBundle('foo_barProfile', 'app-foo_bar-profile.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.profile, 'foo_bar', treeShakeIcons: false),
      BufferLogger.test(),
    TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant', 'app', 'outputs', 'bundle', 'foo_barProfile', 'app-foo_bar-profile.aab'));
  });

  testWithoutContext('Finds app bundle when flavor contains underscores and uppercase letters in debug mode - Gradle 3.5', () {
    final FlutterProject project = generateFakeAppBundle('foo_barDebug', 'app-foo_bar-debug.aab', fileSystem);
    final File bundle = findBundleFile(
      project,
      const BuildInfo(BuildMode.debug, 'foo_Bar', treeShakeIcons: false),
      BufferLogger.test(),
      TestUsage(),
    );

    expect(bundle, isNotNull);
    expect(bundle.path, fileSystem.path.join('irrelevant','app', 'outputs', 'bundle', 'foo_barDebug', 'app-foo_bar-debug.aab'));
  });

  // Context is required due to build failure analytics event grabbing FlutterCommand.current.
  testUsingContext('AAB not found', () {
    final FlutterProject project = FlutterProject.fromDirectoryTest(fileSystem.currentDirectory);
    final TestUsage testUsage = TestUsage();
    expect(
      () {
        findBundleFile(
          project,
          const BuildInfo(BuildMode.debug, 'foo_bar', treeShakeIcons: false),
          BufferLogger.test(),
          testUsage,
        );
      },
      throwsToolExit(
        message:
          "Gradle build failed to produce an .aab file. It's likely that this file "
          "was generated under ${project.android.buildDirectory.path}, but the tool couldn't find it."
      )
    );
    expect(testUsage.events, contains(
      const TestUsageEvent(
        'build',
        'unspecified',
        label: 'gradle-expected-file-not-found',
        parameters: <String, String> {
          'cd37': 'androidGradlePluginVersion: 6.7, fileExtension: .aab',
        },
      ),
    ));
  });
}

/// Generates a fake app bundle at the location [directoryName]/[fileName].
FlutterProject generateFakeAppBundle(String directoryName, String fileName, FileSystem fileSystem) {
  final FlutterProject project = MockFlutterProject();
  final AndroidProject androidProject = MockAndroidProject();

  when(project.isModule).thenReturn(false);
  when(project.android).thenReturn(androidProject);
  when(androidProject.buildDirectory).thenReturn(fileSystem.directory('irrelevant'));

  final Directory bundleDirectory = getBundleDirectory(project);
  bundleDirectory
    .childDirectory(directoryName)
    .createSync(recursive: true);

  bundleDirectory
    .childDirectory(directoryName)
    .childFile(fileName)
    .createSync();
  return project;
}

class MockAndroidProject extends Mock implements AndroidProject {}
class MockFlutterProject extends Mock implements FlutterProject {}
