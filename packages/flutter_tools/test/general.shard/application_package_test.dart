// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/android/android_sdk.dart';
import 'package:flutter_tools/src/android/application_package.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/user_messages.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/fuchsia/application_package.dart';
import 'package:flutter_tools/src/globals_null_migrated.dart' as globals;
import 'package:flutter_tools/src/ios/application_package.dart';
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:mockito/mockito.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fakes.dart';

FakePlatform _kNoColorTerminalPlatform() => FakePlatform(stdoutSupportsAnsi: false);
final Map<Type, Generator> noColorTerminalOverride = <Type, Generator>{
  Platform: _kNoColorTerminalPlatform,
};

class MockitoAndroidSdk extends Mock implements AndroidSdk {}
class MockitoAndroidSdkVersion extends Mock implements AndroidSdkVersion {}

void main() {
  group('Apk with partial Android SDK works', () {
    AndroidSdk sdk;
    FakeProcessManager fakeProcessManager;
    MemoryFileSystem fs;
    Cache cache;

    final Map<Type, Generator> overrides = <Type, Generator>{
      AndroidSdk: () => sdk,
      ProcessManager: () => fakeProcessManager,
      FileSystem: () => fs,
      Cache: () => cache,
    };

    setUp(() async {
      sdk = MockitoAndroidSdk();
      fakeProcessManager = FakeProcessManager.list(<FakeCommand>[]);
      fs = MemoryFileSystem.test();
      cache = Cache.test(
        processManager: FakeProcessManager.any(),
      );
      Cache.flutterRoot = '../..';
      when(sdk.licensesAvailable).thenReturn(true);
      final FlutterProject project = FlutterProject.fromDirectoryTest(fs.currentDirectory);
      fs.file(project.android.hostAppGradleRoot.childFile(
        globals.platform.isWindows ? 'gradlew.bat' : 'gradlew',
      ).path).createSync(recursive: true);
    });

    testUsingContext('Licenses not available, platform and buildtools available, apk exists', () async {
      const String aaptPath = 'aaptPath';
      final File apkFile = globals.fs.file('app.apk');
      final AndroidSdkVersion sdkVersion = MockitoAndroidSdkVersion();
      when(sdkVersion.aaptPath).thenReturn(aaptPath);
      when(sdk.latestVersion).thenReturn(sdkVersion);
      when(sdk.platformToolsAvailable).thenReturn(true);
      when(sdk.licensesAvailable).thenReturn(false);

      fakeProcessManager.addCommand(
        FakeCommand(
          command: <String>[
            aaptPath,
            'dump',
            'xmltree',
             apkFile.path,
            'AndroidManifest.xml',
          ],
          stdout: _aaptDataWithDefaultEnabledAndMainLauncherActivity
        )
      );

      final ApplicationPackage applicationPackage = await ApplicationPackageFactory.instance.getPackageForPlatform(
        TargetPlatform.android_arm,
        buildInfo: null,
        applicationBinary: apkFile,
      );
      expect(applicationPackage.name, 'app.apk');
      expect(fakeProcessManager.hasRemainingExpectations, isFalse);
    }, overrides: overrides);

    testUsingContext('Licenses available, build tools not, apk exists', () async {
      when(sdk.latestVersion).thenReturn(null);
      final FlutterProject project = FlutterProject.fromDirectoryTest(fs.currentDirectory);
      project.android.hostAppGradleRoot
        .childFile('gradle.properties')
        .writeAsStringSync('irrelevant');

      final Directory gradleWrapperDir = cache.getArtifactDirectory('gradle_wrapper');

      gradleWrapperDir.fileSystem.directory(gradleWrapperDir.childDirectory('gradle').childDirectory('wrapper'))
          .createSync(recursive: true);
      gradleWrapperDir.childFile('gradlew').writeAsStringSync('irrelevant');
      gradleWrapperDir.childFile('gradlew.bat').writeAsStringSync('irrelevant');

      await ApplicationPackageFactory.instance.getPackageForPlatform(
        TargetPlatform.android_arm,
        buildInfo: null,
        applicationBinary: globals.fs.file('app.apk'),
      );
      expect(fakeProcessManager.hasRemainingExpectations, isFalse);
    }, overrides: overrides);

    testUsingContext('Licenses available, build tools available, does not call gradle dependencies', () async {
      final AndroidSdkVersion sdkVersion = MockitoAndroidSdkVersion();
      when(sdk.latestVersion).thenReturn(sdkVersion);

      await ApplicationPackageFactory.instance.getPackageForPlatform(
        TargetPlatform.android_arm,
        buildInfo: null,
      );
      expect(fakeProcessManager.hasRemainingExpectations, isFalse);
    }, overrides: overrides);

    testWithoutContext('returns null when failed to extract manifest', () async {
      final AndroidSdkVersion sdkVersion = MockitoAndroidSdkVersion();
      when(sdk.latestVersion).thenReturn(sdkVersion);
      final AndroidApk androidApk = AndroidApk.fromApk(
        null,
        processManager: fakeProcessManager,
        logger: BufferLogger.test(),
        userMessages: UserMessages(),
        androidSdk: sdk,
      );

      expect(androidApk, isNull);
      expect(fakeProcessManager.hasRemainingExpectations, isFalse);
    });
  });

  group('ApkManifestData', () {
    testWithoutContext('Parses manifest with an Activity that has enabled set to true, action set to android.intent.action.MAIN and category set to android.intent.category.LAUNCHER', () {
      final ApkManifestData data = ApkManifestData.parseFromXmlDump(
        _aaptDataWithExplicitEnabledAndMainLauncherActivity,
        BufferLogger.test(),
      );

      expect(data, isNotNull);
      expect(data.packageName, 'io.flutter.examples.hello_world');
      expect(data.launchableActivityName, 'io.flutter.examples.hello_world.MainActivity2');
    });

    testWithoutContext('Parses manifest with an Activity that has no value for its enabled field, action set to android.intent.action.MAIN and category set to android.intent.category.LAUNCHER', () {
      final ApkManifestData data = ApkManifestData.parseFromXmlDump(
        _aaptDataWithDefaultEnabledAndMainLauncherActivity,
        BufferLogger.test(),
      );

      expect(data, isNotNull);
      expect(data.packageName, 'io.flutter.examples.hello_world');
      expect(data.launchableActivityName, 'io.flutter.examples.hello_world.MainActivity2');
    });

    testWithoutContext('Parses manifest with a dist namespace', () {
      final ApkManifestData data = ApkManifestData.parseFromXmlDump(
        _aaptDataWithDistNamespace,
        BufferLogger.test(),
      );

      expect(data, isNotNull);
      expect(data.packageName, 'io.flutter.examples.hello_world');
      expect(data.launchableActivityName, 'io.flutter.examples.hello_world.MainActivity');
    });

    testWithoutContext('Error when parsing manifest with no Activity that has enabled set to true nor has no value for its enabled field', () {
      final BufferLogger logger = BufferLogger.test();
      final ApkManifestData data = ApkManifestData.parseFromXmlDump(
        _aaptDataWithNoEnabledActivity,
        logger,
      );

      expect(data, isNull);
      expect(
        logger.errorText,
        'Error running io.flutter.examples.hello_world. Default activity not found\n',
      );
    });

    testWithoutContext('Error when parsing manifest with no Activity that has action set to android.intent.action.MAIN', () {
      final BufferLogger logger = BufferLogger.test();
      final ApkManifestData data = ApkManifestData.parseFromXmlDump(
        _aaptDataWithNoMainActivity,
        logger,
      );

      expect(data, isNull);
      expect(
        logger.errorText,
        'Error running io.flutter.examples.hello_world. Default activity not found\n',
      );
    });

    testWithoutContext('Error when parsing manifest with no Activity that has category set to android.intent.category.LAUNCHER', () {
      final BufferLogger logger = BufferLogger.test();
      final ApkManifestData data = ApkManifestData.parseFromXmlDump(
        _aaptDataWithNoLauncherActivity,
        logger,
      );

      expect(data, isNull);
      expect(
        logger.errorText,
        'Error running io.flutter.examples.hello_world. Default activity not found\n',
      );
    });

    testWithoutContext('Parsing manifest with Activity that has multiple category, android.intent.category.LAUNCHER and android.intent.category.DEFAULT', () {
      final ApkManifestData data = ApkManifestData.parseFromXmlDump(
        _aaptDataWithLauncherAndDefaultActivity,
        BufferLogger.test(),
      );

      expect(data, isNotNull);
      expect(data.packageName, 'io.flutter.examples.hello_world');
      expect(data.launchableActivityName, 'io.flutter.examples.hello_world.MainActivity');
    });

    testWithoutContext('Parses manifest with missing application tag', () async {
      final ApkManifestData data = ApkManifestData.parseFromXmlDump(
        _aaptDataWithoutApplication,
        BufferLogger.test(),
      );

      expect(data, isNull);
    });
  });

  group('PrebuiltIOSApp', () {
    MockOperatingSystemUtils os;
    FakePlistParser testPlistParser;

    final Map<Type, Generator> overrides = <Type, Generator>{
      FileSystem: () => MemoryFileSystem.test(),
      ProcessManager: () => FakeProcessManager.any(),
      PlistParser: () => testPlistParser,
      Platform: _kNoColorTerminalPlatform,
      OperatingSystemUtils: () => os,
    };

    setUp(() {
      os = MockOperatingSystemUtils();
      testPlistParser = FakePlistParser();
    });

    testUsingContext('Error on non-existing file', () {
      final PrebuiltIOSApp iosApp =
          IOSApp.fromPrebuiltApp(globals.fs.file('not_existing.ipa')) as PrebuiltIOSApp;
      expect(iosApp, isNull);
      expect(
        testLogger.errorText,
        'File "not_existing.ipa" does not exist. Use an app bundle or an ipa.\n',
      );
    }, overrides: overrides);

    testUsingContext('Error on non-app-bundle folder', () {
      globals.fs.directory('regular_folder').createSync();
      final PrebuiltIOSApp iosApp =
          IOSApp.fromPrebuiltApp(globals.fs.file('regular_folder')) as PrebuiltIOSApp;
      expect(iosApp, isNull);
      expect(
          testLogger.errorText, 'Folder "regular_folder" is not an app bundle.\n');
    }, overrides: overrides);

    testUsingContext('Error on no info.plist', () {
      globals.fs.directory('bundle.app').createSync();
      final PrebuiltIOSApp iosApp = IOSApp.fromPrebuiltApp(globals.fs.file('bundle.app')) as PrebuiltIOSApp;
      expect(iosApp, isNull);
      expect(
        testLogger.errorText,
        'Invalid prebuilt iOS app. Does not contain Info.plist.\n',
      );
    }, overrides: overrides);

    testUsingContext('Error on bad info.plist', () {
      globals.fs.directory('bundle.app').createSync();
      globals.fs.file('bundle.app/Info.plist').createSync();
      final PrebuiltIOSApp iosApp = IOSApp.fromPrebuiltApp(globals.fs.file('bundle.app')) as PrebuiltIOSApp;
      expect(iosApp, isNull);
      expect(
        testLogger.errorText,
        contains(
            'Invalid prebuilt iOS app. Info.plist does not contain bundle identifier\n'),
      );
    }, overrides: overrides);

    testUsingContext('Success with app bundle', () {
      globals.fs.directory('bundle.app').createSync();
      globals.fs.file('bundle.app/Info.plist').createSync();
      testPlistParser.setProperty('CFBundleIdentifier', 'fooBundleId');
      final PrebuiltIOSApp iosApp = IOSApp.fromPrebuiltApp(globals.fs.file('bundle.app')) as PrebuiltIOSApp;
      expect(testLogger.errorText, isEmpty);
      expect(iosApp.bundleDir.path, 'bundle.app');
      expect(iosApp.id, 'fooBundleId');
      expect(iosApp.bundleName, 'bundle.app');
    }, overrides: overrides);

    testUsingContext('Bad ipa zip-file, no payload dir', () {
      globals.fs.file('app.ipa').createSync();
      when(os.unzip(globals.fs.file('app.ipa'), any)).thenAnswer((Invocation _) { });
      final PrebuiltIOSApp iosApp = IOSApp.fromPrebuiltApp(globals.fs.file('app.ipa')) as PrebuiltIOSApp;
      expect(iosApp, isNull);
      expect(
        testLogger.errorText,
        'Invalid prebuilt iOS ipa. Does not contain a "Payload" directory.\n',
      );
    }, overrides: overrides);

    testUsingContext('Bad ipa zip-file, two app bundles', () {
      globals.fs.file('app.ipa').createSync();
      when(os.unzip(any, any)).thenAnswer((Invocation invocation) {
        final File zipFile = invocation.positionalArguments[0] as File;
        if (zipFile.path != 'app.ipa') {
          return;
        }
        final Directory targetDirectory = invocation.positionalArguments[1] as Directory;
        final String bundlePath1 =
            globals.fs.path.join(targetDirectory.path, 'Payload', 'bundle1.app');
        final String bundlePath2 =
            globals.fs.path.join(targetDirectory.path, 'Payload', 'bundle2.app');
        globals.fs.directory(bundlePath1).createSync(recursive: true);
        globals.fs.directory(bundlePath2).createSync(recursive: true);
      });
      final PrebuiltIOSApp iosApp = IOSApp.fromPrebuiltApp(globals.fs.file('app.ipa')) as PrebuiltIOSApp;
      expect(iosApp, isNull);
      expect(testLogger.errorText,
          'Invalid prebuilt iOS ipa. Does not contain a single app bundle.\n');
    }, overrides: overrides);

    testUsingContext('Success with ipa', () {
      globals.fs.file('app.ipa').createSync();
      when(os.unzip(any, any)).thenAnswer((Invocation invocation) {
        final File zipFile = invocation.positionalArguments[0] as File;
        if (zipFile.path != 'app.ipa') {
          return;
        }
        final Directory targetDirectory = invocation.positionalArguments[1] as Directory;
        final Directory bundleAppDir = globals.fs.directory(
            globals.fs.path.join(targetDirectory.path, 'Payload', 'bundle.app'));
        bundleAppDir.createSync(recursive: true);
        testPlistParser.setProperty('CFBundleIdentifier', 'fooBundleId');
        globals.fs
            .file(globals.fs.path.join(bundleAppDir.path, 'Info.plist'))
            .createSync();
      });
      final PrebuiltIOSApp iosApp = IOSApp.fromPrebuiltApp(globals.fs.file('app.ipa')) as PrebuiltIOSApp;
      expect(testLogger.errorText, isEmpty);
      expect(iosApp.bundleDir.path, endsWith('bundle.app'));
      expect(iosApp.id, 'fooBundleId');
      expect(iosApp.bundleName, 'bundle.app');
    }, overrides: overrides);

    testUsingContext('returns null when there is no ios or .ios directory', () async {
      globals.fs.file('pubspec.yaml').createSync();
      globals.fs.file('.packages').createSync();
      final BuildableIOSApp iosApp = await IOSApp.fromIosProject(
        FlutterProject.fromDirectory(globals.fs.currentDirectory).ios, null) as BuildableIOSApp;

      expect(iosApp, null);
    }, overrides: overrides);

    testUsingContext('returns null when there is no Runner.xcodeproj', () async {
      globals.fs.file('pubspec.yaml').createSync();
      globals.fs.file('.packages').createSync();
      globals.fs.file('ios/FooBar.xcodeproj').createSync(recursive: true);
      final BuildableIOSApp iosApp = await IOSApp.fromIosProject(
        FlutterProject.fromDirectory(globals.fs.currentDirectory).ios, null) as BuildableIOSApp;

      expect(iosApp, null);
    }, overrides: overrides);

    testUsingContext('returns null when there is no Runner.xcodeproj/project.pbxproj', () async {
      globals.fs.file('pubspec.yaml').createSync();
      globals.fs.file('.packages').createSync();
      globals.fs.file('ios/Runner.xcodeproj').createSync(recursive: true);
      final BuildableIOSApp iosApp = await IOSApp.fromIosProject(
        FlutterProject.fromDirectory(globals.fs.currentDirectory).ios, null) as BuildableIOSApp;

      expect(iosApp, null);
    }, overrides: overrides);
  });

  group('FuchsiaApp', () {
    final Map<Type, Generator> overrides = <Type, Generator>{
      FileSystem: () => MemoryFileSystem.test(),
      ProcessManager: () => FakeProcessManager.any(),
      Platform: _kNoColorTerminalPlatform,
      OperatingSystemUtils: () => MockOperatingSystemUtils(),
    };

    testUsingContext('Error on non-existing file', () {
      final PrebuiltFuchsiaApp fuchsiaApp =
          FuchsiaApp.fromPrebuiltApp(globals.fs.file('not_existing.far')) as PrebuiltFuchsiaApp;
      expect(fuchsiaApp, isNull);
      expect(
        testLogger.errorText,
        'File "not_existing.far" does not exist or is not a .far file. Use far archive.\n',
      );
    }, overrides: overrides);

    testUsingContext('Error on non-far file', () {
      globals.fs.directory('regular_folder').createSync();
      final PrebuiltFuchsiaApp fuchsiaApp =
          FuchsiaApp.fromPrebuiltApp(globals.fs.file('regular_folder')) as PrebuiltFuchsiaApp;
      expect(fuchsiaApp, isNull);
      expect(
        testLogger.errorText,
        'File "regular_folder" does not exist or is not a .far file. Use far archive.\n',
      );
    }, overrides: overrides);

    testUsingContext('Success with far file', () {
      globals.fs.file('bundle.far').createSync();
      final PrebuiltFuchsiaApp fuchsiaApp = FuchsiaApp.fromPrebuiltApp(globals.fs.file('bundle.far')) as PrebuiltFuchsiaApp;
      expect(testLogger.errorText, isEmpty);
      expect(fuchsiaApp.id, 'bundle.far');
    }, overrides: overrides);

    testUsingContext('returns null when there is no fuchsia', () async {
      globals.fs.file('pubspec.yaml').createSync();
      globals.fs.file('.packages').createSync();
      final BuildableFuchsiaApp fuchsiaApp = FuchsiaApp.fromFuchsiaProject(FlutterProject.fromDirectory(globals.fs.currentDirectory).fuchsia) as BuildableFuchsiaApp;

      expect(fuchsiaApp, null);
    }, overrides: overrides);
  });
}

const String _aaptDataWithExplicitEnabledAndMainLauncherActivity = '''
N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=7)
    A: android:versionCode(0x0101021b)=(type 0x10)0x1
    A: android:versionName(0x0101021c)="0.0.1" (Raw: "0.0.1")
    A: package="io.flutter.examples.hello_world" (Raw: "io.flutter.examples.hello_world")
    E: uses-sdk (line=12)
      A: android:minSdkVersion(0x0101020c)=(type 0x10)0x10
      A: android:targetSdkVersion(0x01010270)=(type 0x10)0x1b
    E: uses-permission (line=21)
      A: android:name(0x01010003)="android.permission.INTERNET" (Raw: "android.permission.INTERNET")
    E: application (line=29)
      A: android:label(0x01010001)="hello_world" (Raw: "hello_world")
      A: android:icon(0x01010002)=@0x7f010000
      A: android:name(0x01010003)="io.flutter.app.FlutterApplication" (Raw: "io.flutter.app.FlutterApplication")
      A: android:debuggable(0x0101000f)=(type 0x12)0xffffffff
      E: activity (line=34)
        A: android:theme(0x01010000)=@0x1030009
        A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity" (Raw: "io.flutter.examples.hello_world.MainActivity")
        A: android:enabled(0x0101000e)=(type 0x12)0x0
        A: android:launchMode(0x0101001d)=(type 0x10)0x1
        A: android:configChanges(0x0101001f)=(type 0x11)0x400035b4
        A: android:windowSoftInputMode(0x0101022b)=(type 0x11)0x10
        A: android:hardwareAccelerated(0x010102d3)=(type 0x12)0xffffffff
        E: intent-filter (line=42)
          E: action (line=43)
            A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
          E: category (line=45)
            A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
      E: activity (line=48)
        A: android:theme(0x01010000)=@0x1030009
        A: android:label(0x01010001)="app2" (Raw: "app2")
        A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity2" (Raw: "io.flutter.examples.hello_world.MainActivity2")
        A: android:enabled(0x0101000e)=(type 0x12)0xffffffff
        E: intent-filter (line=53)
          E: action (line=54)
            A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
          E: category (line=56)
            A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")''';


const String _aaptDataWithDefaultEnabledAndMainLauncherActivity = '''
N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=7)
    A: android:versionCode(0x0101021b)=(type 0x10)0x1
    A: android:versionName(0x0101021c)="0.0.1" (Raw: "0.0.1")
    A: package="io.flutter.examples.hello_world" (Raw: "io.flutter.examples.hello_world")
    E: uses-sdk (line=12)
      A: android:minSdkVersion(0x0101020c)=(type 0x10)0x10
      A: android:targetSdkVersion(0x01010270)=(type 0x10)0x1b
    E: uses-permission (line=21)
      A: android:name(0x01010003)="android.permission.INTERNET" (Raw: "android.permission.INTERNET")
    E: application (line=29)
      A: android:label(0x01010001)="hello_world" (Raw: "hello_world")
      A: android:icon(0x01010002)=@0x7f010000
      A: android:name(0x01010003)="io.flutter.app.FlutterApplication" (Raw: "io.flutter.app.FlutterApplication")
      A: android:debuggable(0x0101000f)=(type 0x12)0xffffffff
      E: activity (line=34)
        A: android:theme(0x01010000)=@0x1030009
        A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity" (Raw: "io.flutter.examples.hello_world.MainActivity")
        A: android:enabled(0x0101000e)=(type 0x12)0x0
        A: android:launchMode(0x0101001d)=(type 0x10)0x1
        A: android:configChanges(0x0101001f)=(type 0x11)0x400035b4
        A: android:windowSoftInputMode(0x0101022b)=(type 0x11)0x10
        A: android:hardwareAccelerated(0x010102d3)=(type 0x12)0xffffffff
        E: intent-filter (line=42)
          E: action (line=43)
            A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
          E: category (line=45)
            A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
      E: activity (line=48)
        A: android:theme(0x01010000)=@0x1030009
        A: android:label(0x01010001)="app2" (Raw: "app2")
        A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity2" (Raw: "io.flutter.examples.hello_world.MainActivity2")
        E: intent-filter (line=53)
          E: action (line=54)
            A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
          E: category (line=56)
            A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")''';


const String _aaptDataWithNoEnabledActivity = '''
N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=7)
    A: android:versionCode(0x0101021b)=(type 0x10)0x1
    A: android:versionName(0x0101021c)="0.0.1" (Raw: "0.0.1")
    A: package="io.flutter.examples.hello_world" (Raw: "io.flutter.examples.hello_world")
    E: uses-sdk (line=12)
      A: android:minSdkVersion(0x0101020c)=(type 0x10)0x10
      A: android:targetSdkVersion(0x01010270)=(type 0x10)0x1b
    E: uses-permission (line=21)
      A: android:name(0x01010003)="android.permission.INTERNET" (Raw: "android.permission.INTERNET")
    E: application (line=29)
      A: android:label(0x01010001)="hello_world" (Raw: "hello_world")
      A: android:icon(0x01010002)=@0x7f010000
      A: android:name(0x01010003)="io.flutter.app.FlutterApplication" (Raw: "io.flutter.app.FlutterApplication")
      A: android:debuggable(0x0101000f)=(type 0x12)0xffffffff
      E: activity (line=34)
        A: android:theme(0x01010000)=@0x1030009
        A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity" (Raw: "io.flutter.examples.hello_world.MainActivity")
        A: android:enabled(0x0101000e)=(type 0x12)0x0
        A: android:launchMode(0x0101001d)=(type 0x10)0x1
        A: android:configChanges(0x0101001f)=(type 0x11)0x400035b4
        A: android:windowSoftInputMode(0x0101022b)=(type 0x11)0x10
        A: android:hardwareAccelerated(0x010102d3)=(type 0x12)0xffffffff
        E: intent-filter (line=42)
          E: action (line=43)
            A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
          E: category (line=45)
            A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")''';

const String _aaptDataWithNoMainActivity = '''
N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=7)
    A: android:versionCode(0x0101021b)=(type 0x10)0x1
    A: android:versionName(0x0101021c)="0.0.1" (Raw: "0.0.1")
    A: package="io.flutter.examples.hello_world" (Raw: "io.flutter.examples.hello_world")
    E: uses-sdk (line=12)
      A: android:minSdkVersion(0x0101020c)=(type 0x10)0x10
      A: android:targetSdkVersion(0x01010270)=(type 0x10)0x1b
    E: uses-permission (line=21)
      A: android:name(0x01010003)="android.permission.INTERNET" (Raw: "android.permission.INTERNET")
    E: application (line=29)
      A: android:label(0x01010001)="hello_world" (Raw: "hello_world")
      A: android:icon(0x01010002)=@0x7f010000
      A: android:name(0x01010003)="io.flutter.app.FlutterApplication" (Raw: "io.flutter.app.FlutterApplication")
      A: android:debuggable(0x0101000f)=(type 0x12)0xffffffff
      E: activity (line=34)
        A: android:theme(0x01010000)=@0x1030009
        A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity" (Raw: "io.flutter.examples.hello_world.MainActivity")
        A: android:enabled(0x0101000e)=(type 0x12)0xffffffff
        A: android:launchMode(0x0101001d)=(type 0x10)0x1
        A: android:configChanges(0x0101001f)=(type 0x11)0x400035b4
        A: android:windowSoftInputMode(0x0101022b)=(type 0x11)0x10
        A: android:hardwareAccelerated(0x010102d3)=(type 0x12)0xffffffff
        E: intent-filter (line=42)
          E: category (line=43)
            A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")''';

const String _aaptDataWithNoLauncherActivity = '''
N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=7)
    A: android:versionCode(0x0101021b)=(type 0x10)0x1
    A: android:versionName(0x0101021c)="0.0.1" (Raw: "0.0.1")
    A: package="io.flutter.examples.hello_world" (Raw: "io.flutter.examples.hello_world")
    E: uses-sdk (line=12)
      A: android:minSdkVersion(0x0101020c)=(type 0x10)0x10
      A: android:targetSdkVersion(0x01010270)=(type 0x10)0x1b
    E: uses-permission (line=21)
      A: android:name(0x01010003)="android.permission.INTERNET" (Raw: "android.permission.INTERNET")
    E: application (line=29)
      A: android:label(0x01010001)="hello_world" (Raw: "hello_world")
      A: android:icon(0x01010002)=@0x7f010000
      A: android:name(0x01010003)="io.flutter.app.FlutterApplication" (Raw: "io.flutter.app.FlutterApplication")
      A: android:debuggable(0x0101000f)=(type 0x12)0xffffffff
      E: activity (line=34)
        A: android:theme(0x01010000)=@0x1030009
        A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity" (Raw: "io.flutter.examples.hello_world.MainActivity")
        A: android:enabled(0x0101000e)=(type 0x12)0xffffffff
        A: android:launchMode(0x0101001d)=(type 0x10)0x1
        A: android:configChanges(0x0101001f)=(type 0x11)0x400035b4
        A: android:windowSoftInputMode(0x0101022b)=(type 0x11)0x10
        A: android:hardwareAccelerated(0x010102d3)=(type 0x12)0xffffffff
        E: intent-filter (line=42)
          E: action (line=43)
            A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")''';

const String _aaptDataWithLauncherAndDefaultActivity = '''
N: android=http://schemas.android.com/apk/res/android
  N: dist=http://schemas.android.com/apk/distribution
    E: manifest (line=7)
      A: android:versionCode(0x0101021b)=(type 0x10)0x1
      A: android:versionName(0x0101021c)="1.0" (Raw: "1.0")
      A: android:compileSdkVersion(0x01010572)=(type 0x10)0x1c
      A: android:compileSdkVersionCodename(0x01010573)="9" (Raw: "9")
      A: package="io.flutter.examples.hello_world" (Raw: "io.flutter.examples.hello_world")
      A: platformBuildVersionCode=(type 0x10)0x1
      A: platformBuildVersionName=(type 0x4)0x3f800000
      E: uses-sdk (line=13)
        A: android:minSdkVersion(0x0101020c)=(type 0x10)0x10
        A: android:targetSdkVersion(0x01010270)=(type 0x10)0x1c
      E: dist:module (line=17)
        A: dist:instant=(type 0x12)0xffffffff
      E: uses-permission (line=24)
        A: android:name(0x01010003)="android.permission.INTERNET" (Raw: "android.permission.INTERNET")
      E: application (line=32)
        A: android:label(0x01010001)="hello_world" (Raw: "hello_world")
        A: android:icon(0x01010002)=@0x7f010000
        A: android:name(0x01010003)="io.flutter.app.FlutterApplication" (Raw: "io.flutter.app.FlutterApplication")
        E: activity (line=36)
          A: android:theme(0x01010000)=@0x01030009
          A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity" (Raw: "io.flutter.examples.hello_world.MainActivity")
          A: android:launchMode(0x0101001d)=(type 0x10)0x1
          A: android:configChanges(0x0101001f)=(type 0x11)0x400037b4
          A: android:windowSoftInputMode(0x0101022b)=(type 0x11)0x10
          A: android:hardwareAccelerated(0x010102d3)=(type 0x12)0xffffffff
          E: intent-filter (line=43)
            E: action (line=44)
              A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
            E: category (line=46)
              A: android:name(0x01010003)="android.intent.category.DEFAULT" (Raw: "android.intent.category.DEFAULT")
            E: category (line=47)
              A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
''';

const String _aaptDataWithDistNamespace = '''
N: android=http://schemas.android.com/apk/res/android
  N: dist=http://schemas.android.com/apk/distribution
    E: manifest (line=7)
      A: android:versionCode(0x0101021b)=(type 0x10)0x1
      A: android:versionName(0x0101021c)="1.0" (Raw: "1.0")
      A: android:compileSdkVersion(0x01010572)=(type 0x10)0x1c
      A: android:compileSdkVersionCodename(0x01010573)="9" (Raw: "9")
      A: package="io.flutter.examples.hello_world" (Raw: "io.flutter.examples.hello_world")
      A: platformBuildVersionCode=(type 0x10)0x1
      A: platformBuildVersionName=(type 0x4)0x3f800000
      E: uses-sdk (line=13)
        A: android:minSdkVersion(0x0101020c)=(type 0x10)0x10
        A: android:targetSdkVersion(0x01010270)=(type 0x10)0x1c
      E: dist:module (line=17)
        A: dist:instant=(type 0x12)0xffffffff
      E: uses-permission (line=24)
        A: android:name(0x01010003)="android.permission.INTERNET" (Raw: "android.permission.INTERNET")
      E: application (line=32)
        A: android:label(0x01010001)="hello_world" (Raw: "hello_world")
        A: android:icon(0x01010002)=@0x7f010000
        A: android:name(0x01010003)="io.flutter.app.FlutterApplication" (Raw: "io.flutter.app.FlutterApplication")
        E: activity (line=36)
          A: android:theme(0x01010000)=@0x01030009
          A: android:name(0x01010003)="io.flutter.examples.hello_world.MainActivity" (Raw: "io.flutter.examples.hello_world.MainActivity")
          A: android:launchMode(0x0101001d)=(type 0x10)0x1
          A: android:configChanges(0x0101001f)=(type 0x11)0x400037b4
          A: android:windowSoftInputMode(0x0101022b)=(type 0x11)0x10
          A: android:hardwareAccelerated(0x010102d3)=(type 0x12)0xffffffff
          E: intent-filter (line=43)
            E: action (line=44)
              A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
            E: category (line=46)
              A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
''';

const String _aaptDataWithoutApplication = '''
N: android=http://schemas.android.com/apk/res/android
  N: dist=http://schemas.android.com/apk/distribution
    E: manifest (line=7)
      A: android:versionCode(0x0101021b)=(type 0x10)0x1
      A: android:versionName(0x0101021c)="1.0" (Raw: "1.0")
      A: android:compileSdkVersion(0x01010572)=(type 0x10)0x1c
      A: android:compileSdkVersionCodename(0x01010573)="9" (Raw: "9")
      A: package="io.flutter.examples.hello_world" (Raw: "io.flutter.examples.hello_world")
      A: platformBuildVersionCode=(type 0x10)0x1
      A: platformBuildVersionName=(type 0x4)0x3f800000
      E: uses-sdk (line=13)
        A: android:minSdkVersion(0x0101020c)=(type 0x10)0x10
        A: android:targetSdkVersion(0x01010270)=(type 0x10)0x1c
      E: dist:module (line=17)
        A: dist:instant=(type 0x12)0xffffffff
      E: uses-permission (line=24)
        A: android:name(0x01010003)="android.permission.INTERNET" (Raw: "android.permission.INTERNET")
''';

class MockOperatingSystemUtils extends Mock implements OperatingSystemUtils { }
