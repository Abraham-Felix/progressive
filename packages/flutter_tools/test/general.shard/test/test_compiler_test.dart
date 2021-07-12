// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/compile.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/test/test_compiler.dart';
import 'package:mockito/mockito.dart';
import 'package:package_config/package_config_types.dart';

import '../../src/common.dart';
import '../../src/context.dart';

final Platform linuxPlatform = FakePlatform(
  operatingSystem: 'linux',
  environment: <String, String>{},
);

final BuildInfo debugBuild = BuildInfo(
  BuildMode.debug,
  '',
  treeShakeIcons: false,
  packageConfig: PackageConfig(<Package>[
    Package('test_api', Uri.parse('file:///test_api/')),
  ])
);

void main() {
  MockResidentCompiler residentCompiler;
  FileSystem fileSystem;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('test/foo.dart').createSync(recursive: true);
    residentCompiler = MockResidentCompiler();
  });

  testUsingContext('TestCompiler reports a dill file when compile is successful', () async {
    final FakeTestCompiler testCompiler = FakeTestCompiler(
      debugBuild,
      FlutterProject.fromDirectoryTest(fileSystem.currentDirectory),
      residentCompiler,
    );
    when(residentCompiler.recompile(
      any,
      <Uri>[Uri.parse('test/foo.dart')],
      outputPath: testCompiler.outputDill.path,
      packageConfig: anyNamed('packageConfig'),
    )).thenAnswer((Invocation invocation) async {
      fileSystem.file('abc.dill').createSync();
      return const CompilerOutput('abc.dill', 0, <Uri>[]);
    });

    expect(await testCompiler.compile(Uri.parse('test/foo.dart')), 'test/foo.dart.dill');
    expect(fileSystem.file('test/foo.dart.dill'), exists);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    Platform: () => linuxPlatform,
    ProcessManager: () => FakeProcessManager.any(),
    Logger: () => BufferLogger.test(),
  });

  testUsingContext('TestCompiler reports null when a compile fails', () async {
    final FakeTestCompiler testCompiler = FakeTestCompiler(
      debugBuild,
      FlutterProject.fromDirectoryTest(fileSystem.currentDirectory),
      residentCompiler,
    );
    when(residentCompiler.recompile(
      any,
      <Uri>[Uri.parse('test/foo.dart')],
      outputPath: testCompiler.outputDill.path,
      packageConfig: anyNamed('packageConfig'),
    )).thenAnswer((Invocation invocation) async {
      fileSystem.file('abc.dill').createSync();
      return const CompilerOutput('abc.dill', 1, <Uri>[]);
    });

    expect(await testCompiler.compile(Uri.parse('test/foo.dart')), null);
    expect(fileSystem.file('test/foo.dart.dill'), isNot(exists));
    verify(residentCompiler.shutdown()).called(1);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    Platform: () => linuxPlatform,
    ProcessManager: () => FakeProcessManager.any(),
    Logger: () => BufferLogger.test(),
  });

  testUsingContext('TestCompiler disposing test compiler shuts down backing compiler', () async {
    final FakeTestCompiler testCompiler = FakeTestCompiler(
      debugBuild,
      FlutterProject.fromDirectoryTest(fileSystem.currentDirectory),
      residentCompiler,
    );
    testCompiler.compiler = residentCompiler;

    expect(testCompiler.compilerController.isClosed, false);

    await testCompiler.dispose();

    expect(testCompiler.compilerController.isClosed, true);
    verify(residentCompiler.shutdown()).called(1);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    Platform: () => linuxPlatform,
    ProcessManager: () => FakeProcessManager.any(),
    Logger: () => BufferLogger.test(),
  });
}

/// Override the creation of the Resident Compiler to simplify testing.
class FakeTestCompiler extends TestCompiler {
  FakeTestCompiler(
    BuildInfo buildInfo,
    FlutterProject flutterProject,
    this.residentCompiler,
  ) : super(buildInfo, flutterProject);

  final MockResidentCompiler residentCompiler;

  @override
  Future<ResidentCompiler> createCompiler() async {
    return residentCompiler;
  }
}

class MockResidentCompiler extends Mock implements ResidentCompiler {}
