// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:meta/meta.dart';

import '../../artifacts.dart';
import '../../base/build.dart';
import '../../base/common.dart';
import '../../base/file_system.dart';
import '../../base/io.dart';
import '../../build_info.dart';
import '../../globals.dart' as globals show xcode;
import '../../macos/xcode.dart';
import '../../project.dart';
import '../build_system.dart';
import '../depfile.dart';
import '../exceptions.dart';
import 'assets.dart';
import 'common.dart';
import 'icon_tree_shaker.dart';

/// Supports compiling a dart kernel file to an assembly file.
///
/// If more than one iOS arch is provided, then this rule will
/// produce a universal binary.
abstract class AotAssemblyBase extends Target {
  const AotAssemblyBase();

  @override
  String get analyticsName => 'ios_aot';

  @override
  Future<void> build(Environment environment) async {
    final AOTSnapshotter snapshotter = AOTSnapshotter(
      reportTimings: false,
      fileSystem: environment.fileSystem,
      logger: environment.logger,
      xcode: globals.xcode,
      artifacts: environment.artifacts,
      processManager: environment.processManager,
    );
    final String buildOutputPath = environment.buildDir.path;
    if (environment.defines[kBuildMode] == null) {
      throw MissingDefineException(kBuildMode, 'aot_assembly');
    }
    if (environment.defines[kTargetPlatform] == null) {
      throw MissingDefineException(kTargetPlatform, 'aot_assembly');
    }
    if (environment.defines[kSdkRoot] == null) {
      throw MissingDefineException(kSdkRoot, 'aot_assembly');
    }

    final List<String> extraGenSnapshotOptions = decodeCommaSeparated(environment.defines, kExtraGenSnapshotOptions);
    final bool bitcode = environment.defines[kBitcodeFlag] == 'true';
    final BuildMode buildMode = getBuildModeForName(environment.defines[kBuildMode]);
    final TargetPlatform targetPlatform = getTargetPlatformForName(environment.defines[kTargetPlatform]);
    final String splitDebugInfo = environment.defines[kSplitDebugInfo];
    final bool dartObfuscation = environment.defines[kDartObfuscation] == 'true';
    final List<DarwinArch> darwinArchs = environment.defines[kIosArchs]
      ?.split(' ')
      ?.map(getIOSArchForName)
      ?.toList()
      ?? <DarwinArch>[DarwinArch.arm64];
    if (targetPlatform != TargetPlatform.ios) {
      throw Exception('aot_assembly is only supported for iOS applications.');
    }

    final String sdkRoot = environment.defines[kSdkRoot];
    final EnvironmentType environmentType =
        environmentTypeFromSdkroot(environment.fileSystem.directory(sdkRoot));
    if (environmentType == EnvironmentType.simulator) {
      throw Exception(
        'release/profile builds are only supported for physical devices. '
        'attempted to build for simulator.'
      );
    }
    final String codeSizeDirectory = environment.defines[kCodeSizeDirectory];

    // If we're building multiple iOS archs the binaries need to be lipo'd
    // together.
    final List<Future<int>> pending = <Future<int>>[];
    for (final DarwinArch darwinArch in darwinArchs) {
      final List<String> archExtraGenSnapshotOptions = List<String>.of(extraGenSnapshotOptions);
      if (codeSizeDirectory != null) {
        final File codeSizeFile = environment.fileSystem
          .directory(codeSizeDirectory)
          .childFile('snapshot.${getNameForDarwinArch(darwinArch)}.json');
        final File precompilerTraceFile = environment.fileSystem
          .directory(codeSizeDirectory)
          .childFile('trace.${getNameForDarwinArch(darwinArch)}.json');
        archExtraGenSnapshotOptions.add('--write-v8-snapshot-profile-to=${codeSizeFile.path}');
        archExtraGenSnapshotOptions.add('--trace-precompiler-to=${precompilerTraceFile.path}');
      }
      pending.add(snapshotter.build(
        platform: targetPlatform,
        buildMode: buildMode,
        mainPath: environment.buildDir.childFile('app.dill').path,
        outputPath: environment.fileSystem.path.join(buildOutputPath, getNameForDarwinArch(darwinArch)),
        darwinArch: darwinArch,
        sdkRoot: sdkRoot,
        bitcode: bitcode,
        quiet: true,
        splitDebugInfo: splitDebugInfo,
        dartObfuscation: dartObfuscation,
        extraGenSnapshotOptions: archExtraGenSnapshotOptions,
      ));
    }
    final List<int> results = await Future.wait(pending);
    if (results.any((int result) => result != 0)) {
      throw Exception('AOT snapshotter exited with code ${results.join()}');
    }
    final String resultPath = environment.fileSystem.path.join(environment.buildDir.path, 'App.framework', 'App');
    environment.fileSystem.directory(resultPath).parent.createSync(recursive: true);
    final ProcessResult result = await environment.processManager.run(<String>[
      'lipo',
      ...darwinArchs.map((DarwinArch iosArch) =>
          environment.fileSystem.path.join(buildOutputPath, getNameForDarwinArch(iosArch), 'App.framework', 'App')),
      '-create',
      '-output',
      resultPath,
    ]);
    if (result.exitCode != 0) {
      throw Exception('lipo exited with code ${result.exitCode}.\n${result.stderr}');
    }
  }
}

/// Generate an assembly target from a dart kernel file in release mode.
class AotAssemblyRelease extends AotAssemblyBase {
  const AotAssemblyRelease();

  @override
  String get name => 'aot_assembly_release';

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/ios.dart'),
    Source.pattern('{BUILD_DIR}/app.dill'),
    Source.artifact(Artifact.engineDartBinary),
    Source.artifact(Artifact.skyEnginePath),
    // TODO(jonahwilliams): cannot reference gen_snapshot with artifacts since
    // it resolves to a file (ios/gen_snapshot) that never exists. This was
    // split into gen_snapshot_arm64 and gen_snapshot_armv7.
    // Source.artifact(Artifact.genSnapshot,
    //   platform: TargetPlatform.ios,
    //   mode: BuildMode.release,
    // ),
  ];

  @override
  List<Source> get outputs => const <Source>[
    Source.pattern('{OUTPUT_DIR}/App.framework/App'),
  ];

  @override
  List<Target> get dependencies => const <Target>[
    ReleaseUnpackIOS(),
    KernelSnapshot(),
  ];
}


/// Generate an assembly target from a dart kernel file in profile mode.
class AotAssemblyProfile extends AotAssemblyBase {
  const AotAssemblyProfile();

  @override
  String get name => 'aot_assembly_profile';

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/ios.dart'),
    Source.pattern('{BUILD_DIR}/app.dill'),
    Source.artifact(Artifact.engineDartBinary),
    Source.artifact(Artifact.skyEnginePath),
    // TODO(jonahwilliams): cannot reference gen_snapshot with artifacts since
    // it resolves to a file (ios/gen_snapshot) that never exists. This was
    // split into gen_snapshot_arm64 and gen_snapshot_armv7.
    // Source.artifact(Artifact.genSnapshot,
    //   platform: TargetPlatform.ios,
    //   mode: BuildMode.profile,
    // ),
  ];

  @override
  List<Source> get outputs => const <Source>[
    Source.pattern('{OUTPUT_DIR}/App.framework/App'),
  ];

  @override
  List<Target> get dependencies => const <Target>[
    ProfileUnpackIOS(),
    KernelSnapshot(),
  ];
}

/// Create a trivial App.framework file for debug iOS builds.
class DebugUniversalFramework extends Target {
  const DebugUniversalFramework();

  @override
  String get name => 'debug_universal_framework';

  @override
  List<Target> get dependencies => const <Target>[
    DebugUnpackIOS(),
    KernelSnapshot(),
  ];

  @override
  List<Source> get inputs => const <Source>[
     Source.pattern('{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/ios.dart'),
  ];

  @override
  List<Source> get outputs => const <Source>[
    Source.pattern('{BUILD_DIR}/App.framework/App'),
  ];

  @override
  Future<void> build(Environment environment) async {
    // Generate a trivial App.framework.
    final Set<String> iosArchNames = environment.defines[kIosArchs]
      ?.split(' ')
      ?.toSet();
    final File output = environment.buildDir
      .childDirectory('App.framework')
      .childFile('App');
    environment.buildDir.createSync(recursive: true);
    await _createStubAppFramework(
      output,
      environment,
      iosArchNames,
    );
  }
}

/// Copy the iOS framework to the correct copy dir by invoking 'rsync'.
///
/// This class is abstract to share logic between the three concrete
/// implementations. The shelling out is done to avoid complications with
/// preserving special files (e.g., symbolic links) in the framework structure.
abstract class UnpackIOS extends Target {
  const UnpackIOS();

  @override
  List<Source> get inputs => <Source>[
        const Source.pattern(
            '{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/ios.dart'),
        Source.artifact(
          Artifact.flutterXcframework,
          platform: TargetPlatform.ios,
          mode: buildMode,
        ),
      ];

  @override
  List<Source> get outputs => const <Source>[
        Source.pattern('{OUTPUT_DIR}/Flutter.framework/Flutter'),
      ];

  @override
  List<Target> get dependencies => <Target>[];

  @visibleForOverriding
  BuildMode get buildMode;

  @override
  Future<void> build(Environment environment) async {
    if (environment.defines[kSdkRoot] == null) {
      throw MissingDefineException(kSdkRoot, name);
    }
    if (environment.defines[kIosArchs] == null) {
      throw MissingDefineException(kIosArchs, name);
    }
    if (environment.defines[kBitcodeFlag] == null) {
      throw MissingDefineException(kBitcodeFlag, name);
    }
    _copyFramework(environment);

    final File frameworkBinary = environment.outputDir.childDirectory('Flutter.framework').childFile('Flutter');
    final String frameworkBinaryPath = frameworkBinary.path;
    if (!frameworkBinary.existsSync()) {
      throw Exception('Binary $frameworkBinaryPath does not exist, cannot thin');
    }
    _thinFramework(environment, frameworkBinaryPath);
    _bitcodeStripFramework(environment, frameworkBinaryPath);
    _signFramework(environment, frameworkBinaryPath, buildMode);
  }

  void _copyFramework(Environment environment) {
    final Directory sdkRoot = environment.fileSystem.directory(environment.defines[kSdkRoot]);
    final EnvironmentType environmentType = environmentTypeFromSdkroot(sdkRoot);
    final String basePath = environment.artifacts.getArtifactPath(
      Artifact.flutterFramework,
      platform: TargetPlatform.ios,
      mode: buildMode,
      environmentType: environmentType,
    );

    final ProcessResult result = environment.processManager.runSync(<String>[
      'rsync',
      '-av',
      '--delete',
      '--filter',
      '- .DS_Store/',
      basePath,
      environment.outputDir.path,
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        'Failed to copy framework (exit ${result.exitCode}:\n'
        '${result.stdout}\n---\n${result.stderr}',
      );
    }
  }

  /// Destructively thin Flutter.framework to include only the specified architectures.
  void _thinFramework(Environment environment, String frameworkBinaryPath) {
    final String archs = environment.defines[kIosArchs];
    final List<String> archList = archs.split(' ').toList();
    final ProcessResult infoResult = environment.processManager.runSync(<String>[
      'lipo',
      '-info',
      frameworkBinaryPath,
    ]);
    final String lipoInfo = infoResult.stdout as String;

    final ProcessResult verifyResult = environment.processManager.runSync(<String>[
      'lipo',
      frameworkBinaryPath,
      '-verify_arch',
      ...archList
    ]);

    if (verifyResult.exitCode != 0) {
      throw Exception('Binary $frameworkBinaryPath does not contain $archs. Running lipo -info:\n$lipoInfo');
    }

    // Skip thinning for non-fat executables.
    if (lipoInfo.startsWith('Non-fat file:')) {
      environment.logger.printTrace('Skipping lipo for non-fat file $frameworkBinaryPath');
      return;
    }

    // Thin in-place.
    final ProcessResult extractResult = environment.processManager.runSync(<String>[
      'lipo',
      '-output',
      frameworkBinaryPath,
      for (final String arch in archList)
        ...<String>[
          '-extract',
          arch,
        ],
      ...<String>[frameworkBinaryPath],
    ]);

    if (extractResult.exitCode != 0) {
      throw Exception('Failed to extract $archs for $frameworkBinaryPath.\n${extractResult.stderr}\nRunning lipo -info:\n$lipoInfo');
    }
  }

  /// Destructively strip bitcode from the framework, if needed.
  void _bitcodeStripFramework(Environment environment, String frameworkBinaryPath) {
    if (environment.defines[kBitcodeFlag] == 'true') {
      return;
    }
    final ProcessResult stripResult = environment.processManager.runSync(<String>[
      'xcrun',
      'bitcode_strip',
      frameworkBinaryPath,
      '-m', // leave the bitcode marker.
      '-o',
      frameworkBinaryPath,
    ]);

    if (stripResult.exitCode != 0) {
      throw Exception('Failed to strip bitcode for $frameworkBinaryPath.\n${stripResult.stderr}');
    }
  }
}

/// Unpack the release prebuilt engine framework.
class ReleaseUnpackIOS extends UnpackIOS {
  const ReleaseUnpackIOS();

  @override
  String get name => 'release_unpack_ios';

  @override
  BuildMode get buildMode => BuildMode.release;
}

/// Unpack the profile prebuilt engine framework.
class ProfileUnpackIOS extends UnpackIOS {
  const ProfileUnpackIOS();

  @override
  String get name => 'profile_unpack_ios';

  @override
  BuildMode get buildMode => BuildMode.profile;
}

/// Unpack the debug prebuilt engine framework.
class DebugUnpackIOS extends UnpackIOS {
  const DebugUnpackIOS();

  @override
  String get name => 'debug_unpack_ios';

  @override
  BuildMode get buildMode => BuildMode.debug;
}

/// The base class for all iOS bundle targets.
///
/// This is responsible for setting up the basic App.framework structure, including:
/// * Copying the app.dill/kernel_blob.bin from the build directory to assets (debug)
/// * Copying the precompiled isolate/vm data from the engine (debug)
/// * Copying the flutter assets to App.framework/flutter_assets
/// * Copying either the stub or real App assembly file to App.framework/App
abstract class IosAssetBundle extends Target {
  const IosAssetBundle();

  @override
  List<Target> get dependencies => const <Target>[
    KernelSnapshot(),
  ];

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{BUILD_DIR}/App.framework/App'),
    Source.pattern('{PROJECT_DIR}/pubspec.yaml'),
    ...IconTreeShaker.inputs,
  ];

  @override
  List<Source> get outputs => const <Source>[
    Source.pattern('{OUTPUT_DIR}/App.framework/App'),
    Source.pattern('{OUTPUT_DIR}/App.framework/Info.plist')
  ];

  @override
  List<String> get depfiles => <String>[
    'flutter_assets.d',
  ];

  @override
  Future<void> build(Environment environment) async {
    if (environment.defines[kBuildMode] == null) {
      throw MissingDefineException(kBuildMode, name);
    }
    final BuildMode buildMode = getBuildModeForName(environment.defines[kBuildMode]);
    final Directory frameworkDirectory = environment.outputDir.childDirectory('App.framework');
    final String frameworkBinaryPath = frameworkDirectory.childFile('App').path;
    final Directory assetDirectory = frameworkDirectory.childDirectory('flutter_assets');
    frameworkDirectory.createSync(recursive: true);
    assetDirectory.createSync();

    // Only copy the prebuilt runtimes and kernel blob in debug mode.
    if (buildMode == BuildMode.debug) {
      // Copy the App.framework to the output directory.
      environment.buildDir
        .childDirectory('App.framework')
        .childFile('App')
        .copySync(frameworkBinaryPath);

      final String vmSnapshotData = environment.artifacts.getArtifactPath(Artifact.vmSnapshotData, mode: BuildMode.debug);
      final String isolateSnapshotData = environment.artifacts.getArtifactPath(Artifact.isolateSnapshotData, mode: BuildMode.debug);
      environment.buildDir.childFile('app.dill')
          .copySync(assetDirectory.childFile('kernel_blob.bin').path);
      environment.fileSystem.file(vmSnapshotData)
          .copySync(assetDirectory.childFile('vm_snapshot_data').path);
      environment.fileSystem.file(isolateSnapshotData)
          .copySync(assetDirectory.childFile('isolate_snapshot_data').path);
    } else {
      environment.buildDir.childDirectory('App.framework').childFile('App')
        .copySync(frameworkBinaryPath);
    }

    // Copy the assets.
    final Depfile assetDepfile = await copyAssets(
      environment,
      assetDirectory,
      targetPlatform: TargetPlatform.ios,
    );
    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );
    depfileService.writeToFile(
      assetDepfile,
      environment.buildDir.childFile('flutter_assets.d'),
    );

    // Copy the plist from either the project or module.
    // TODO(jonahwilliams): add plist to inputs
    final FlutterProject flutterProject = FlutterProject.fromDirectory(environment.projectDir);
    final Directory plistRoot = flutterProject.isModule
      ? flutterProject.ios.ephemeralModuleDirectory
      : environment.projectDir.childDirectory('ios');
    plistRoot
      .childDirectory('Flutter')
      .childFile('AppFrameworkInfo.plist')
      .copySync(environment.outputDir
      .childDirectory('App.framework')
      .childFile('Info.plist').path);

    _signFramework(environment, frameworkBinaryPath, buildMode);
  }
}

/// Build a debug iOS application bundle.
class DebugIosApplicationBundle extends IosAssetBundle {
  const DebugIosApplicationBundle();

  @override
  String get name => 'debug_ios_bundle_flutter_assets';

  @override
  List<Source> get inputs => <Source>[
    const Source.artifact(Artifact.vmSnapshotData, mode: BuildMode.debug),
    const Source.artifact(Artifact.isolateSnapshotData, mode: BuildMode.debug),
    const Source.pattern('{BUILD_DIR}/app.dill'),
    ...super.inputs,
  ];

  @override
  List<Source> get outputs => <Source>[
    const Source.pattern('{OUTPUT_DIR}/App.framework/flutter_assets/vm_snapshot_data'),
    const Source.pattern('{OUTPUT_DIR}/App.framework/flutter_assets/isolate_snapshot_data'),
    const Source.pattern('{OUTPUT_DIR}/App.framework/flutter_assets/kernel_blob.bin'),
    ...super.outputs,
  ];

  @override
  List<Target> get dependencies => <Target>[
    const DebugUniversalFramework(),
    ...super.dependencies,
  ];
}

/// Build a profile iOS application bundle.
class ProfileIosApplicationBundle extends IosAssetBundle {
  const ProfileIosApplicationBundle();

  @override
  String get name => 'profile_ios_bundle_flutter_assets';

  @override
  List<Target> get dependencies => const <Target>[
    AotAssemblyProfile(),
  ];
}

/// Build a release iOS application bundle.
class ReleaseIosApplicationBundle extends IosAssetBundle {
  const ReleaseIosApplicationBundle();

  @override
  String get name => 'release_ios_bundle_flutter_assets';

  @override
  List<Target> get dependencies => const <Target>[
    AotAssemblyRelease(),
  ];
}

/// Create an App.framework for debug iOS targets.
///
/// This framework needs to exist for the Xcode project to link/bundle,
/// but it isn't actually executed. To generate something valid, we compile a trivial
/// constant.
Future<void> _createStubAppFramework(File outputFile, Environment environment,
    Set<String> iosArchNames) async {
  try {
    outputFile.createSync(recursive: true);
  } on Exception catch (e) {
    throwToolExit('Failed to create App.framework stub at ${outputFile.path}: $e');
  }

  final Directory tempDir = outputFile.fileSystem.systemTempDirectory
    .createTempSync('flutter_tools_stub_source.');
  try {
    final File stubSource = tempDir.childFile('debug_app.cc')
      ..writeAsStringSync(r'''
  static const int Moo = 88;
  ''');

    final String sdkRoot = environment.defines[kSdkRoot];
    await globals.xcode.clang(<String>[
      '-x',
      'c',
      for (String arch in iosArchNames) ...<String>['-arch', arch],
      stubSource.path,
      '-dynamiclib',
      '-fembed-bitcode-marker',
      // Keep version in sync with AOTSnapshotter flag
      '-miphoneos-version-min=8.0',
      '-Xlinker', '-rpath', '-Xlinker', '@executable_path/Frameworks',
      '-Xlinker', '-rpath', '-Xlinker', '@loader_path/Frameworks',
      '-install_name', '@rpath/App.framework/App',
      '-isysroot', sdkRoot,
      '-o', outputFile.path,
    ]);
  } finally {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort. Sometimes we can't delete things from system temp.
    } on Exception catch (e) {
      throwToolExit('Failed to create App.framework stub at ${outputFile.path}: $e');
    }
  }

  _signFramework(environment, outputFile.path, BuildMode.debug);
}

void _signFramework(Environment environment, String binaryPath, BuildMode buildMode) {
  final String codesignIdentity = environment.defines[kCodesignIdentity];
  if (codesignIdentity == null || codesignIdentity.isEmpty) {
    return;
  }
  final ProcessResult result = environment.processManager.runSync(<String>[
    'codesign',
    '--force',
    '--sign',
    codesignIdentity,
    if (buildMode != BuildMode.release) ...<String>[
      // Mimic Xcode's timestamp codesigning behavior on non-release binaries.
      '--timestamp=none',
    ],
    binaryPath,
  ]);
  if (result.exitCode != 0) {
    throw Exception('Failed to codesign $binaryPath with identity $codesignIdentity.\n${result.stderr}');
  }
}
