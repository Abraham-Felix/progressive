// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/terminal.dart';

import '../src/common.dart';
import 'test_utils.dart';

const String _kInitialVersion = 'v1.9.1';
const String _kBranch = 'dev';

final Stdio stdio = Stdio();
final ProcessUtils processUtils = ProcessUtils(processManager: processManager, logger: StdoutLogger(
  terminal: AnsiTerminal(
    platform: platform,
    stdio: stdio,
  ),
  stdio: stdio,
  outputPreferences: OutputPreferences.test(wrapText: true),
));
final String flutterBin = fileSystem.path.join(getFlutterRoot(), 'bin', platform.isWindows ? 'flutter.bat' : 'flutter');
final String dartBin = fileSystem.path.join(getFlutterRoot(), 'bin', platform.isWindows ? 'dart.bat' : 'dart');

/// A test for flutter upgrade & downgrade that checks out a parallel flutter repo.
void main() {
  Directory parentDirectory;

  setUp(() {
    parentDirectory = fileSystem.systemTempDirectory
      .createTempSync('flutter_tools.');
    parentDirectory.createSync(recursive: true);
  });

  tearDown(() {
    try {
      parentDirectory.deleteSync(recursive: true);
    } on FileSystemException {
      print('Failed to delete test directory');
    }
  });

  testWithoutContext('Can upgrade and downgrade a Flutter checkout', () async {
    final Directory testDirectory = parentDirectory.childDirectory('flutter');
    testDirectory.createSync(recursive: true);

    int exitCode = 0;

    // Enable longpaths for windows integration test.
    await processManager.run(<String>[
      'git', 'config', '--system', 'core.longpaths', 'true',
    ]);

    print('Step 1 - clone the $_kBranch of flutter into the test directory');
    exitCode = await processUtils.stream(<String>[
      'git',
      'clone',
      'https://github.com/flutter/flutter.git',
    ], workingDirectory: parentDirectory.path, trace: true);
    expect(exitCode, 0);

    print('Step 2 - switch to the $_kBranch');
    exitCode = await processUtils.stream(<String>[
      'git',
      'checkout',
      '--track',
      '-b',
      _kBranch,
      'origin/$_kBranch',
    ], workingDirectory: testDirectory.path, trace: true);
    expect(exitCode, 0);

    print('Step 3 - revert back to $_kInitialVersion');
    exitCode = await processUtils.stream(<String>[
      'git',
      'reset',
      '--hard',
      _kInitialVersion,
    ], workingDirectory: testDirectory.path, trace: true);
    expect(exitCode, 0);

    print('Step 4 - upgrade to the newest $_kBranch');
    // This should update the persistent tool state with the sha for HEAD
    exitCode = await processUtils.stream(<String>[
      flutterBin,
      'upgrade',
      '--verbose',
      '--working-directory=${testDirectory.path}'
    ], workingDirectory: testDirectory.path, trace: true);
    expect(exitCode, 0);

    print('Step 5 - verify that the version is different');
    final RunResult versionResult = await processUtils.run(<String>[
      'git',
      'describe',
      '--match',
      'v*.*.*',
      '--long',
      '--tags',
    ], workingDirectory: testDirectory.path);
    expect(versionResult.stdout, isNot(contains(_kInitialVersion)));
    print('current version is ${versionResult.stdout.trim()}\ninitial was $_kInitialVersion');

    print('Step 6 - downgrade back to the initial version');
    // Step 6. Downgrade back to initial version.
    exitCode = await processUtils.stream(<String>[
       flutterBin,
      'downgrade',
      '--no-prompt',
      '--working-directory=${testDirectory.path}'
    ], workingDirectory: testDirectory.path, trace: true);
    expect(exitCode, 0);

    print('Step 7 - verify downgraded version matches original version');
    // Step 7. Verify downgraded version matches original version.
    final RunResult oldVersionResult = await processUtils.run(<String>[
      'git',
      'describe',
      '--match',
      'v*.*.*',
      '--long',
      '--tags',
    ], workingDirectory: testDirectory.path);
    expect(oldVersionResult.stdout, contains(_kInitialVersion));
    print('current version is ${oldVersionResult.stdout.trim()}\ninitial was $_kInitialVersion');
  });
}
