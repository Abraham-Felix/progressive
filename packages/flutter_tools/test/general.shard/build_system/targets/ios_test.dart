// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/targets/assets.dart';
import 'package:flutter_tools/src/build_system/targets/common.dart';
import 'package:flutter_tools/src/build_system/targets/ios.dart';
import 'package:flutter_tools/src/convert.dart';

import '../../../src/common.dart';
import '../../../src/context.dart';

final Platform macPlatform = FakePlatform(operatingSystem: 'macos', environment: <String, String>{});

const List<String> _kSharedConfig = <String>[
  '-dynamiclib',
  '-fembed-bitcode-marker',
  '-miphoneos-version-min=8.0',
  '-Xlinker',
  '-rpath',
  '-Xlinker',
  '@executable_path/Frameworks',
  '-Xlinker',
  '-rpath',
  '-Xlinker',
  '@loader_path/Frameworks',
  '-install_name',
  '@rpath/App.framework/App',
  '-isysroot',
  'path/to/sdk',
];

void main() {
  Environment environment;
  FileSystem fileSystem;
  FakeProcessManager processManager;
  Artifacts artifacts;
  BufferLogger logger;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.list(<FakeCommand>[]);
    logger = BufferLogger.test();
    artifacts = Artifacts.test();
    environment = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kTargetPlatform: 'ios',
      },
      inputs: <String, String>{},
      processManager: processManager,
      artifacts: artifacts,
      logger: logger,
      fileSystem: fileSystem,
      engineVersion: '2',
    );
  });

  testWithoutContext('iOS AOT targets has analyicsName', () {
    expect(const AotAssemblyRelease().analyticsName, 'ios_aot');
    expect(const AotAssemblyProfile().analyticsName, 'ios_aot');
  });

  testUsingContext('DebugUniveralFramework creates expected binary with arm64 only arch', () async {
    environment.defines[kIosArchs] = 'arm64';
    environment.defines[kSdkRoot] = 'path/to/sdk';
    processManager.addCommand(
      FakeCommand(command: <String>[
        'xcrun',
        'clang',
        '-x',
        'c',
        // iphone only gets 64 bit arch based on kIosArchs
        '-arch',
        'arm64',
        fileSystem.path.absolute(fileSystem.path.join(
            '.tmp_rand0', 'flutter_tools_stub_source.rand0', 'debug_app.cc')),
        ..._kSharedConfig,
        '-o',
        environment.buildDir
            .childDirectory('App.framework')
            .childFile('App')
            .path,
      ]),
    );

    await const DebugUniversalFramework().build(environment);
    expect(processManager.hasRemainingExpectations, isFalse);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    Platform: () => macPlatform,
  });

  testUsingContext('DebugIosApplicationBundle', () async {
    environment.inputs[kBundleSkSLPath] = 'bundle.sksl';
    environment.defines[kBuildMode] = 'debug';
    environment.defines[kCodesignIdentity] = 'ABC123';
    // Precompiled dart data

    fileSystem.file(artifacts.getArtifactPath(Artifact.vmSnapshotData, mode: BuildMode.debug))
      .createSync();
    fileSystem.file(artifacts.getArtifactPath(Artifact.isolateSnapshotData, mode: BuildMode.debug))
      .createSync();
    // Project info
    fileSystem.file('pubspec.yaml').writeAsStringSync('name: hello');
    fileSystem.file('.packages').writeAsStringSync('\n');
    // Plist file
    fileSystem.file(fileSystem.path.join('ios', 'Flutter', 'AppFrameworkInfo.plist'))
      .createSync(recursive: true);
    // App kernel
    environment.buildDir.childFile('app.dill').createSync(recursive: true);
    // Stub framework
    environment.buildDir
        .childDirectory('App.framework')
      .childFile('App')
      .createSync(recursive: true);
    // sksl bundle
    fileSystem.file('bundle.sksl').writeAsStringSync(json.encode(
      <String, Object>{
        'engineRevision': '2',
        'platform': 'ios',
        'data': <String, Object>{
          'A': 'B',
        }
      }
    ));

    final Directory frameworkDirectory = environment.outputDir.childDirectory('App.framework');
    final File frameworkDirectoryBinary = frameworkDirectory.childFile('App');
    processManager.addCommand(
      FakeCommand(command: <String>[
        'codesign',
        '--force',
        '--sign',
        'ABC123',
        '--timestamp=none',
        frameworkDirectoryBinary.path,
      ]),
    );

    await const DebugIosApplicationBundle().build(environment);
    expect(processManager.hasRemainingExpectations, isFalse);

    expect(frameworkDirectoryBinary, exists);
    expect(frameworkDirectory.childFile('Info.plist'), exists);

    final Directory assetDirectory = frameworkDirectory.childDirectory('flutter_assets');
    expect(assetDirectory.childFile('kernel_blob.bin'), exists);
    expect(assetDirectory.childFile('AssetManifest.json'), exists);
    expect(assetDirectory.childFile('vm_snapshot_data'), exists);
    expect(assetDirectory.childFile('isolate_snapshot_data'), exists);
    expect(assetDirectory.childFile('io.flutter.shaders.json'), exists);
    expect(assetDirectory.childFile('io.flutter.shaders.json').readAsStringSync(), '{"data":{"A":"B"}}');
  });

  testUsingContext('ReleaseIosApplicationBundle', () async {
    environment.defines[kBuildMode] = 'release';
    environment.defines[kCodesignIdentity] = 'ABC123';

    // Project info
    fileSystem.file('pubspec.yaml').writeAsStringSync('name: hello');
    fileSystem.file('.packages').writeAsStringSync('\n');
    // Plist file
    fileSystem.file(fileSystem.path.join('ios', 'Flutter', 'AppFrameworkInfo.plist'))
      .createSync(recursive: true);

    // Real framework
    environment.buildDir
      .childDirectory('App.framework')
      .childFile('App')
      .createSync(recursive: true);


    final Directory frameworkDirectory = environment.outputDir.childDirectory('App.framework');
    final File frameworkDirectoryBinary = frameworkDirectory.childFile('App');
    processManager.addCommand(
      FakeCommand(command: <String>[
        'codesign',
        '--force',
        '--sign',
        'ABC123',
        frameworkDirectoryBinary.path,
      ]),
    );

    await const ReleaseIosApplicationBundle().build(environment);
    expect(processManager.hasRemainingExpectations, isFalse);

    expect(frameworkDirectoryBinary, exists);
    expect(frameworkDirectory.childFile('Info.plist'), exists);

    final Directory assetDirectory = frameworkDirectory.childDirectory('flutter_assets');
    expect(assetDirectory.childFile('kernel_blob.bin'), isNot(exists));
    expect(assetDirectory.childFile('AssetManifest.json'), exists);
    expect(assetDirectory.childFile('vm_snapshot_data'), isNot(exists));
    expect(assetDirectory.childFile('isolate_snapshot_data'), isNot(exists));
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    Platform: () => macPlatform,
  });

  testUsingContext('AotAssemblyRelease throws exception if asked to build for simulator', () async {
    final FileSystem fileSystem = MemoryFileSystem.test();
    final Environment environment = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kTargetPlatform: 'ios',
        kSdkRoot: 'path/to/iPhoneSimulator.sdk',
        kBuildMode: 'release',
        kIosArchs: 'x86_64',
      },
      processManager: processManager,
      artifacts: artifacts,
      logger: logger,
      fileSystem: fileSystem,
    );

    expect(const AotAssemblyRelease().build(environment), throwsA(isA<Exception>()
      .having(
        (Exception exception) => exception.toString(),
        'description',
        contains('release/profile builds are only supported for physical devices.'),
      )
    ));
    expect(processManager.hasRemainingExpectations, isFalse);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    Platform: () => macPlatform,
  });

  testUsingContext('AotAssemblyRelease throws exception if sdk root is missing', () async {
    final FileSystem fileSystem = MemoryFileSystem.test();
    final Environment environment = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kTargetPlatform: 'ios',
      },
      processManager: processManager,
      artifacts: artifacts,
      logger: logger,
      fileSystem: fileSystem,
    );
    environment.defines[kBuildMode] = 'release';
    environment.defines[kIosArchs] = 'x86_64';

    expect(const AotAssemblyRelease().build(environment), throwsA(isA<Exception>()
        .having(
          (Exception exception) => exception.toString(),
      'description',
      contains('required define SdkRoot but it was not provided'),
    )
    ));
    expect(processManager.hasRemainingExpectations, isFalse);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    Platform: () => macPlatform,
  });

  group('copies Flutter.framework', () {
    Directory outputDir;
    File binary;
    FakeCommand copyPhysicalFrameworkCommand;
    FakeCommand lipoCommandNonFatResult;
    FakeCommand lipoVerifyArm64Command;
    FakeCommand bitcodeStripCommand;

    setUp(() {
      final FileSystem fileSystem = MemoryFileSystem.test();
      outputDir = fileSystem.directory('output');
      binary = outputDir.childDirectory('Flutter.framework').childFile('Flutter');
      copyPhysicalFrameworkCommand = FakeCommand(command: <String>[
        'rsync',
        '-av',
        '--delete',
        '--filter',
        '- .DS_Store/',
        'Artifact.flutterFramework.TargetPlatform.ios.debug.EnvironmentType.physical',
        outputDir.path,
      ]);

      lipoCommandNonFatResult = FakeCommand(command: <String>[
        'lipo',
        '-info',
        binary.path,
      ], stdout: 'Non-fat file:');

      lipoVerifyArm64Command = FakeCommand(command: <String>[
        'lipo',
        binary.path,
        '-verify_arch',
        'arm64',
      ]);

      bitcodeStripCommand = FakeCommand(command: <String>[
        'xcrun',
        'bitcode_strip',
        binary.path,
        '-m',
        '-o',
        binary.path,
      ]);
    });

    testWithoutContext('iphonesimulator', () async {
      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'x86_64',
          kSdkRoot: 'path/to/iPhoneSimulator.sdk',
          kBitcodeFlag: 'true',
        },
      );

      processManager.addCommands(<FakeCommand>[
        FakeCommand(command: <String>[
          'rsync',
          '-av',
          '--delete',
          '--filter',
          '- .DS_Store/',
          'Artifact.flutterFramework.TargetPlatform.ios.debug.EnvironmentType.simulator',
          outputDir.path,
          ],
          onRun: () => binary.createSync(recursive: true),
        ),
        lipoCommandNonFatResult,
        FakeCommand(command: <String>[
          'lipo',
          binary.path,
          '-verify_arch',
          'x86_64',
        ]),
      ]);
      await const DebugUnpackIOS().build(environment);

      expect(logger.traceText, contains('Skipping lipo for non-fat file output/Flutter.framework/Flutter'));
      expect(processManager.hasRemainingExpectations, isFalse);
    });

    testWithoutContext('fails when frameworks missing', () async {
      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: '',
        },
      );
      processManager.addCommand(copyPhysicalFrameworkCommand);
      await expectLater(
        const DebugUnpackIOS().build(environment),
        throwsA(isA<Exception>().having(
          (Exception exception) => exception.toString(),
          'description',
          contains('Flutter.framework/Flutter does not exist, cannot thin'),
        )));
    });

    testWithoutContext('fails when requested archs missing from framework', () async {
      binary.createSync(recursive: true);

      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64 armv7',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: '',
        },
      );

      processManager.addCommands(<FakeCommand>[
        copyPhysicalFrameworkCommand,
        FakeCommand(command: <String>[
          'lipo',
          '-info',
          binary.path,
        ], stdout: 'Architectures in the fat file:'),
        FakeCommand(command: <String>[
          'lipo',
          binary.path,
          '-verify_arch',
          'arm64',
          'armv7',
        ], exitCode: 1),
      ]);

      await expectLater(
          const DebugUnpackIOS().build(environment),
          throwsA(isA<Exception>().having(
                (Exception exception) => exception.toString(),
            'description',
            contains('does not contain arm64 armv7. Running lipo -info:\nArchitectures in the fat file:'),
          )));
    });

    testWithoutContext('fails when lipo extract fails', () async {
      binary.createSync(recursive: true);

      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64 armv7',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: '',
        },
      );

      processManager.addCommands(<FakeCommand>[
        copyPhysicalFrameworkCommand,
        FakeCommand(command: <String>[
          'lipo',
          '-info',
          binary.path,
        ], stdout: 'Architectures in the fat file:'),
        FakeCommand(command: <String>[
          'lipo',
          binary.path,
          '-verify_arch',
          'arm64',
          'armv7',
        ]),
        FakeCommand(command: <String>[
          'lipo',
          '-output',
          binary.path,
          '-extract',
          'arm64',
          '-extract',
          'armv7',
          binary.path,
        ], exitCode: 1,
        stderr: 'lipo error'),
      ]);

      await expectLater(
        const DebugUnpackIOS().build(environment),
        throwsA(isA<Exception>().having(
              (Exception exception) => exception.toString(),
          'description',
          contains('Failed to extract arm64 armv7 for output/Flutter.framework/Flutter.\nlipo error\nRunning lipo -info:\nArchitectures in the fat file:'),
        )));
    });

    testWithoutContext('skips thin framework', () async {
      binary.createSync(recursive: true);

      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: 'true',
        },
      );

      processManager.addCommands(<FakeCommand>[
        copyPhysicalFrameworkCommand,
        lipoCommandNonFatResult,
        lipoVerifyArm64Command,
      ]);
      await const DebugUnpackIOS().build(environment);

      expect(logger.traceText, contains('Skipping lipo for non-fat file output/Flutter.framework/Flutter'));

      expect(processManager.hasRemainingExpectations, isFalse);
    });

    testWithoutContext('thins fat framework', () async {
      binary.createSync(recursive: true);

      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64 armv7',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: 'true',
        },
      );

      processManager.addCommands(<FakeCommand>[
        copyPhysicalFrameworkCommand,
        FakeCommand(command: <String>[
          'lipo',
          '-info',
          binary.path,
        ], stdout: 'Architectures in the fat file:'),
        FakeCommand(command: <String>[
          'lipo',
          binary.path,
          '-verify_arch',
          'arm64',
          'armv7',
        ]),
        FakeCommand(command: <String>[
          'lipo',
          '-output',
          binary.path,
          '-extract',
          'arm64',
          '-extract',
          'armv7',
          binary.path,
        ]),
      ]);

      await const DebugUnpackIOS().build(environment);
      expect(processManager.hasRemainingExpectations, isFalse);
    });

    testWithoutContext('fails when bitcode strip fails', () async {
      binary.createSync(recursive: true);

      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: '',
        },
      );

      processManager.addCommands(<FakeCommand>[
        copyPhysicalFrameworkCommand,
        lipoCommandNonFatResult,
        lipoVerifyArm64Command,
        FakeCommand(command: <String>[
          'xcrun',
          'bitcode_strip',
          binary.path,
          '-m',
          '-o',
          binary.path,
        ], exitCode: 1, stderr: 'bitcode_strip error'),
      ]);

      await expectLater(
          const DebugUnpackIOS().build(environment),
          throwsA(isA<Exception>().having(
                (Exception exception) => exception.toString(),
            'description',
            contains('Failed to strip bitcode for output/Flutter.framework/Flutter.\nbitcode_strip error'),
          )));

      expect(processManager.hasRemainingExpectations, isFalse);
    });

    testWithoutContext('strips framework', () async {
      binary.createSync(recursive: true);

      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: '',
        },
      );

      processManager.addCommands(<FakeCommand>[
        copyPhysicalFrameworkCommand,
        lipoCommandNonFatResult,
        lipoVerifyArm64Command,
        bitcodeStripCommand,
      ]);
      await const DebugUnpackIOS().build(environment);

      expect(processManager.hasRemainingExpectations, isFalse);
    });

    testWithoutContext('fails when codesign fails', () async {
      binary.createSync(recursive: true);

      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: '',
          kCodesignIdentity: 'ABC123',
        },
      );

      processManager.addCommands(<FakeCommand>[
        copyPhysicalFrameworkCommand,
        lipoCommandNonFatResult,
        lipoVerifyArm64Command,
        bitcodeStripCommand,
        FakeCommand(command: <String>[
          'codesign',
          '--force',
          '--sign',
          'ABC123',
          '--timestamp=none',
          binary.path,
        ], exitCode: 1, stderr: 'codesign error'),
      ]);

      await expectLater(
          const DebugUnpackIOS().build(environment),
          throwsA(isA<Exception>().having(
                (Exception exception) => exception.toString(),
            'description',
            contains('Failed to codesign output/Flutter.framework/Flutter with identity ABC123.\ncodesign error'),
          )));

      expect(processManager.hasRemainingExpectations, isFalse);
    });

    testWithoutContext('codesigns framework', () async {
      binary.createSync(recursive: true);

      final Environment environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: processManager,
        artifacts: artifacts,
        logger: logger,
        fileSystem: fileSystem,
        outputDir: outputDir,
        defines: <String, String>{
          kIosArchs: 'arm64',
          kSdkRoot: 'path/to/iPhoneOS.sdk',
          kBitcodeFlag: '',
          kCodesignIdentity: 'ABC123',
        },
      );

      processManager.addCommands(<FakeCommand>[
        copyPhysicalFrameworkCommand,
        lipoCommandNonFatResult,
        lipoVerifyArm64Command,
        bitcodeStripCommand,
        FakeCommand(command: <String>[
          'codesign',
          '--force',
          '--sign',
          'ABC123',
          '--timestamp=none',
          binary.path,
        ]),
      ]);
      await const DebugUnpackIOS().build(environment);

      expect(processManager.hasRemainingExpectations, isFalse);
    });
  });
}
