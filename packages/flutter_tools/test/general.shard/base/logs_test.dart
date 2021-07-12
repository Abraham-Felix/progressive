// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/logs.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/test_flutter_command_runner.dart';

void main() {
  group('logs', () {
    setUp(() {
      Cache.disableLocking();
    });

    tearDown(() {
      Cache.enableLocking();
    });

    testUsingContext('fail with a bad device id', () async {
      final LogsCommand command = LogsCommand();
      try {
        await createTestCommandRunner(command).run(<String>['-d', 'abc123', 'logs']);
        fail('Expect exception');
      } on ToolExit catch (e) {
        expect(e.exitCode ?? 1, 1);
      }
    });
  });
}
