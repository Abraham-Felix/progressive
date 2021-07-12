// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_devicelab/framework/framework.dart';
import 'package:flutter_devicelab/framework/ios.dart';
import 'package:flutter_devicelab/framework/task_result.dart';
import 'package:flutter_devicelab/framework/utils.dart';
import 'package:path/path.dart' as path;
import 'package:meta/meta.dart';

Future<void> main() async {
  await task(() async {
    section('Copy test Flutter App with watchOS Companion');

    String watchDeviceID;
    String phoneDeviceID;
    final Directory tempDir = Directory.systemTemp
        .createTempSync('ios_app_with_extensions_test');
    final Directory projectDir =
        Directory(path.join(tempDir.path, 'app_with_extensions'));
    try {
      mkdir(projectDir);
      recursiveCopy(
        Directory(path.join(flutterDirectory.path, 'dev', 'integration_tests',
            'ios_app_with_extensions')),
        projectDir,
      );

      // For some reason devicelab machines have really old spec snapshots.
      // TODO(jmagman): Remove this if this test is moved to a machine that installs CocoaPods on every run.
      await eval('pod', <String>['repo', 'update', '--verbose']);

      section('Create release build');

      await inDirectory(projectDir, () async {
        await flutter(
          'build',
          options: <String>['ios', '--no-codesign', '--release', '--verbose'],
        );
      });

      final String appBundle = Directory(path.join(
        projectDir.path,
        'build',
        'ios',
        'iphoneos',
        'Runner.app',
      )).path;

      final String appFrameworkPath = path.join(
        appBundle,
        'Frameworks',
        'App.framework',
        'App',
      );
      final String flutterFrameworkPath = path.join(
        appBundle,
        'Frameworks',
        'Flutter.framework',
        'Flutter',
      );

      checkDirectoryExists(appBundle);
      await _checkFlutterFrameworkArchs(appFrameworkPath, isSimulator: false);
      await _checkFlutterFrameworkArchs(flutterFrameworkPath, isSimulator: false);

      // Check the watch extension framework added in the Podfile
      // is in place with the expected watch archs.
      final String watchExtensionFrameworkPath = path.join(
        appBundle,
        'Watch',
        'watch.app',
        'PlugIns',
        'watch Extension.appex',
        'Frameworks',
        'EFQRCode.framework',
        'EFQRCode',
      );
      _checkWatchExtensionFrameworkArchs(watchExtensionFrameworkPath);

      section('Clean build');

      await inDirectory(projectDir, () async {
        await flutter('clean');
      });

      section('Create debug build');

      await inDirectory(projectDir, () async {
        await flutter(
          'build',
          options: <String>['ios', '--debug', '--no-codesign', '--verbose'],
        );
      });

      checkDirectoryExists(appBundle);
      await _checkFlutterFrameworkArchs(appFrameworkPath, isSimulator: false);
      await _checkFlutterFrameworkArchs(flutterFrameworkPath, isSimulator: false);
      _checkWatchExtensionFrameworkArchs(watchExtensionFrameworkPath);

      section('Clean build');

      await inDirectory(projectDir, () async {
        await flutter('clean');
      });

      section('Run app on simulator device');

      // Xcode 11.4 simctl create makes the runtime argument optional, and defaults to latest.
      // TODO(jmagman): Remove runtime parsing when devicelab upgrades to Xcode 11.4 https://github.com/flutter/flutter/issues/54889
      final String availableRuntimes = await eval(
        'xcrun',
        <String>[
          'simctl',
          'list',
          'runtimes',
        ],
        canFail: false,
        workingDirectory: flutterDirectory.path,
      );

      // Example simctl list:
      //    == Runtimes ==
      //    iOS 10.3 (10.3.1 - 14E8301) - com.apple.CoreSimulator.SimRuntime.iOS-10-3
      //    iOS 13.4 (13.4 - 17E255) - com.apple.CoreSimulator.SimRuntime.iOS-13-4
      //    tvOS 13.4 (13.4 - 17L255) - com.apple.CoreSimulator.SimRuntime.tvOS-13-4
      //    watchOS 6.2 (6.2 - 17T256) - com.apple.CoreSimulator.SimRuntime.watchOS-6-2
      String iOSSimRuntime;
      String watchSimRuntime;

      final RegExp iOSRuntimePattern = RegExp(r'iOS .*\) - (.*)');
      final RegExp watchOSRuntimePattern = RegExp(r'watchOS .*\) - (.*)');

      for (final String runtime in LineSplitter.split(availableRuntimes)) {
        // These seem to be in order, so allow matching multiple lines so it grabs
        // the last (hopefully latest) one.
        final RegExpMatch iOSRuntimeMatch = iOSRuntimePattern.firstMatch(runtime);
        if (iOSRuntimeMatch != null) {
          iOSSimRuntime = iOSRuntimeMatch.group(1).trim();
          continue;
        }
        final RegExpMatch watchOSRuntimeMatch = watchOSRuntimePattern.firstMatch(runtime);
        if (watchOSRuntimeMatch != null) {
          watchSimRuntime = watchOSRuntimeMatch.group(1).trim();
        }
      }
      if (iOSSimRuntime == null || watchSimRuntime == null) {
        String message;
        if (iOSSimRuntime != null) {
          message = 'Found "$iOSSimRuntime", but no watchOS simulator runtime found.';
        } else if (watchSimRuntime != null) {
          message = 'Found "$watchSimRuntime", but no iOS simulator runtime found.';
        } else {
          message = 'watchOS and iOS simulator runtimes not found.';
        }
        return TaskResult.failure('$message Available runtimes:\n$availableRuntimes');
      }

      // Create iOS simulator.
      phoneDeviceID = await eval(
        'xcrun',
        <String>[
          'simctl',
          'create',
          'TestFlutteriPhoneWithWatch',
          'com.apple.CoreSimulator.SimDeviceType.iPhone-11',
          iOSSimRuntime,
        ],
        canFail: false,
        workingDirectory: flutterDirectory.path,
      );

      // Create watchOS simulator.
      watchDeviceID = await eval(
        'xcrun',
        <String>[
          'simctl',
          'create',
          'TestFlutterWatch',
          'com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-5-44mm',
          watchSimRuntime,
        ],
        canFail: false,
        workingDirectory: flutterDirectory.path,
      );

      // Pair watch with phone.
      await eval(
        'xcrun',
        <String>['simctl', 'pair', watchDeviceID, phoneDeviceID],
        canFail: false,
        workingDirectory: flutterDirectory.path,
      );

      // Boot simulator devices.
      await eval(
        'xcrun',
        <String>['simctl', 'bootstatus', phoneDeviceID, '-b'],
        canFail: false,
        workingDirectory: flutterDirectory.path,
      );
      await eval(
        'xcrun',
        <String>['simctl', 'bootstatus', watchDeviceID, '-b'],
        canFail: false,
        workingDirectory: flutterDirectory.path,
      );

      // Start app on simulated device.
      final Process process = await startProcess(
          path.join(flutterDirectory.path, 'bin', 'flutter'),
          <String>['run', '-d', phoneDeviceID],
          workingDirectory: projectDir.path);

      process.stdout
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((String line) {
        print('stdout: $line');
        // Wait for app startup to complete and quit immediately afterwards.
        if (line.startsWith('An Observatory debugger')) {
          process.stdin.write('q');
        }
      });
      process.stderr
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((String line) {
        print('stderr: $line');
      });

      final int exitCode = await process.exitCode;

      if (exitCode != 0) {
        return TaskResult.failure(
            'Failed to start flutter iOS app with WatchOS companion on simulated device.');
      }

      final String simulatorAppBundle = Directory(path.join(
        projectDir.path,
        'build',
        'ios',
        'iphonesimulator',
        'Runner.app',
      )).path;

      checkDirectoryExists(simulatorAppBundle);

      final String simulatorAppFrameworkPath = path.join(
        simulatorAppBundle,
        'Frameworks',
        'App.framework',
        'App',
      );
      final String simulatorFlutterFrameworkPath = path.join(
        simulatorAppBundle,
        'Frameworks',
        'Flutter.framework',
        'Flutter',
      );

      await _checkFlutterFrameworkArchs(simulatorAppFrameworkPath, isSimulator: true);
      await _checkFlutterFrameworkArchs(simulatorFlutterFrameworkPath, isSimulator: true);

      return TaskResult.success(null);
    } catch (e) {
      return TaskResult.failure(e.toString());
    } finally {
      rmTree(tempDir);
      // Delete simulator devices
      if (watchDeviceID != null && watchDeviceID != '') {
        await eval(
          'xcrun',
          <String>['simctl', 'shutdown', watchDeviceID],
          canFail: true,
          workingDirectory: flutterDirectory.path,
        );
        await eval(
          'xcrun',
          <String>['simctl', 'delete', watchDeviceID],
          canFail: true,
          workingDirectory: flutterDirectory.path,
        );
      }
      if (phoneDeviceID != null && phoneDeviceID != '') {
        await eval(
          'xcrun',
          <String>['simctl', 'shutdown', phoneDeviceID],
          canFail: true,
          workingDirectory: flutterDirectory.path,
        );
        await eval(
          'xcrun',
          <String>['simctl', 'delete', phoneDeviceID],
          canFail: true,
          workingDirectory: flutterDirectory.path,
        );
      }
    }
  });
}

Future<void> _checkFlutterFrameworkArchs(String frameworkPath, {
  @required bool isSimulator
}) async {
  checkFileExists(frameworkPath);

  final String archs = await fileType(frameworkPath);
  if (isSimulator == archs.contains('armv7')) {
    throw TaskResult.failure('$frameworkPath armv7 architecture unexpected');
  }

  if (isSimulator == archs.contains('arm64')) {
    throw TaskResult.failure('$frameworkPath arm64 architecture unexpected');
  }

  if (isSimulator != archs.contains('x86_64')) {
    throw TaskResult.failure(
        '$frameworkPath x86_64 architecture unexpected');
  }
}

Future<void> _checkWatchExtensionFrameworkArchs(String frameworkPath) async {
  checkFileExists(frameworkPath);
  final String archs = await fileType(frameworkPath);
  if (!archs.contains('armv7k')) {
    throw TaskResult.failure('$frameworkPath armv7k architecture missing');
  }

  if (!archs.contains('arm64_32')) {
    throw TaskResult.failure('$frameworkPath arm64_32 architecture missing');
  }
}
