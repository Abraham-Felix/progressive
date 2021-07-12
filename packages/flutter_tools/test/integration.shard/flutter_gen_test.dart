// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:convert';

import 'package:file/file.dart';

import '../src/common.dart';
import 'test_data/basic_project.dart';
import 'test_driver.dart';
import 'test_utils.dart';

void main() {
  Directory tempDir;
  final BasicProjectWithFlutterGen project = BasicProjectWithFlutterGen();
  FlutterRunTestDriver flutter;

  setUp(() async {
    tempDir = createResolvedTempDirectorySync('run_test.');
    await project.setUpIn(tempDir);
    flutter = FlutterRunTestDriver(tempDir);
  });

  tearDown(() async {
    await flutter.stop();
    tryToDelete(tempDir);
  });

  testWithoutContext('can correctly reference flutter generated code.', () async {
    await flutter.run();
    final dynamic jsonContent = json.decode(project.dir
        .childDirectory('.dart_tool')
        .childFile('package_config.json')
        .readAsStringSync());
    final dynamic collection = jsonContent['packages']
        .firstWhere((dynamic e) => e['name'] == 'collection');
    expect(
      Uri.parse(collection['rootUri'] as String).isAbsolute,
      isTrue,
      reason: 'The generated package_config.json should use absolute root urls',
    );
    expect(
      collection['packageUri'] as String,
      'lib/',
      reason: 'The generated package_config.json should have package urls ending with /'
    );
  });
}
