// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';

import 'package:file/file.dart';

import '../src/common.dart';
import 'test_data/background_project.dart';
import 'test_driver.dart';
import 'test_utils.dart';

void main() {
  Directory tempDir;

  setUp(() async {
    tempDir = createResolvedTempDirectorySync('hot_reload_test.');
  });

  tearDown(() async {
    tryToDelete(tempDir);
  });

  testWithoutContext('Hot restart kills background isolates', () async {
    final BackgroundProject project = BackgroundProject();
    await project.setUpIn(tempDir);
    final FlutterRunTestDriver flutter = FlutterRunTestDriver(tempDir);

    const String newBackgroundMessage = 'New Background';
    final Completer<void> sawForgroundMessage = Completer<void>.sync();
    final Completer<void> sawBackgroundMessage = Completer<void>.sync();
    final Completer<void> sawNewBackgroundMessage = Completer<void>.sync();
    final StreamSubscription<String> subscription = flutter.stdout.listen((String line) {
        print('[LOG]:"$line"');
        if (line.contains('Main thread') && !sawForgroundMessage.isCompleted) {
          sawForgroundMessage.complete();
        }
        if (line.contains('Isolate thread')) {
          sawBackgroundMessage.complete();
        }
        if (line.contains(newBackgroundMessage)) {
          sawNewBackgroundMessage.complete();
        }
      },
    );
    await flutter.run();
    await sawForgroundMessage.future;
    await sawBackgroundMessage.future;

    project.updateTestIsolatePhrase(newBackgroundMessage);
    await flutter.hotRestart();
    await sawBackgroundMessage.future;
    // Wait a tiny amount of time in case we did not kill the background isolate.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await subscription.cancel();
    await flutter?.stop();
  });

  testWithoutContext('Hot reload updates background isolates', () async {
    final RepeatingBackgroundProject project = RepeatingBackgroundProject();
    await project.setUpIn(tempDir);
    final FlutterRunTestDriver flutter = FlutterRunTestDriver(tempDir);

    const String newBackgroundMessage = 'New Background';
    final Completer<void> sawBackgroundMessage = Completer<void>.sync();
    final Completer<void> sawNewBackgroundMessage = Completer<void>.sync();
    final StreamSubscription<String> subscription = flutter.stdout.listen((String line) {
        print('[LOG]:"$line"');
        if (line.contains('Isolate thread') && !sawBackgroundMessage.isCompleted) {
          sawBackgroundMessage.complete();
        }
        if (line.contains(newBackgroundMessage) && !sawNewBackgroundMessage.isCompleted) {
          sawNewBackgroundMessage.complete();
        }
      },
    );
    await flutter.run();
    await sawBackgroundMessage.future;

    project.updateTestIsolatePhrase(newBackgroundMessage);
    await flutter.hotReload();
    await sawNewBackgroundMessage.future;
    await subscription.cancel();
    await flutter?.stop();
  });
}
