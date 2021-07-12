// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:meta/meta.dart';
import 'package:process/process.dart';

import '../artifacts.dart';
import '../build_info.dart';
import '../macos/xcode.dart';

import 'file_system.dart';
import 'logger.dart';
import 'process.dart';

/// A snapshot build configuration.
class SnapshotType {
  SnapshotType(this.platform, this.mode)
    : assert(mode != null);

  final TargetPlatform platform;
  final BuildMode mode;

  @override
  String toString() => '$platform $mode';
}

/// Interface to the gen_snapshot command-line tool.
class GenSnapshot {
  GenSnapshot({
    @required Artifacts artifacts,
    @required ProcessManager processManager,
    @required Logger logger,
  }) : _artifacts = artifacts,
       _processUtils = ProcessUtils(logger: logger, processManager: processManager);

  final Artifacts _artifacts;
  final ProcessUtils _processUtils;

  String getSnapshotterPath(SnapshotType snapshotType) {
    return _artifacts.getArtifactPath(
        Artifact.genSnapshot, platform: snapshotType.platform, mode: snapshotType.mode);
  }

  /// Ignored warning messages from gen_snapshot.
  static const Set<String> kIgnoredWarnings = <String>{
    // --strip on elf snapshot.
    'Warning: Generating ELF library without DWARF debugging information.',
    // --strip on ios-assembly snapshot.
    'Warning: Generating assembly code without DWARF debugging information.',
    // A fun two-part message with spaces for obfuscation.
    'Warning: This VM has been configured to obfuscate symbol information which violates the Dart standard.',
    '         See dartbug.com/30524 for more information.',
  };

  Future<int> run({
    @required SnapshotType snapshotType,
    DarwinArch darwinArch,
    Iterable<String> additionalArgs = const <String>[],
  }) {
    final List<String> args = <String>[
      ...additionalArgs,
    ];

    String snapshotterPath = getSnapshotterPath(snapshotType);

    // iOS has a separate gen_snapshot for armv7 and arm64 in the same,
    // directory. So we need to select the right one.
    if (snapshotType.platform == TargetPlatform.ios) {
      snapshotterPath += '_' + getNameForDarwinArch(darwinArch);
    }

    return _processUtils.stream(
      <String>[snapshotterPath, ...args],
      mapFunction: (String line) =>  kIgnoredWarnings.contains(line) ? null : line,
    );
  }
}

class AOTSnapshotter {
  AOTSnapshotter({
    this.reportTimings = false,
    @required Logger logger,
    @required FileSystem fileSystem,
    @required Xcode xcode,
    @required ProcessManager processManager,
    @required Artifacts artifacts,
  }) : _logger = logger,
      _fileSystem = fileSystem,
      _xcode = xcode,
      _genSnapshot = GenSnapshot(
        artifacts: artifacts,
        processManager: processManager,
        logger: logger,
      );

  final Logger _logger;
  final FileSystem _fileSystem;
  final Xcode _xcode;
  final GenSnapshot _genSnapshot;

  /// If true then AOTSnapshotter would report timings for individual building
  /// steps (Dart front-end parsing and snapshot generation) in a stable
  /// machine readable form. See [AOTSnapshotter._timedStep].
  final bool reportTimings;

  /// Builds an architecture-specific ahead-of-time compiled snapshot of the specified script.
  Future<int> build({
    @required TargetPlatform platform,
    @required BuildMode buildMode,
    @required String mainPath,
    @required String outputPath,
    DarwinArch darwinArch,
    String sdkRoot,
    List<String> extraGenSnapshotOptions = const <String>[],
    @required bool bitcode,
    @required String splitDebugInfo,
    @required bool dartObfuscation,
    bool quiet = false,
  }) async {
    assert(platform != TargetPlatform.ios || darwinArch != null);
    if (bitcode && platform != TargetPlatform.ios) {
      _logger.printError('Bitcode is only supported for iOS.');
      return 1;
    }

    if (!_isValidAotPlatform(platform, buildMode)) {
      _logger.printError('${getNameForTargetPlatform(platform)} does not support AOT compilation.');
      return 1;
    }

    final Directory outputDir = _fileSystem.directory(outputPath);
    outputDir.createSync(recursive: true);

    final List<String> genSnapshotArgs = <String>[
      '--deterministic',
    ];

    // We strip snapshot by default, but allow to suppress this behavior
    // by supplying --no-strip in extraGenSnapshotOptions.
    bool shouldStrip = true;

    if (extraGenSnapshotOptions != null && extraGenSnapshotOptions.isNotEmpty) {
      _logger.printTrace('Extra gen_snapshot options: $extraGenSnapshotOptions');
      for (final String option in extraGenSnapshotOptions) {
        if (option == '--no-strip') {
          shouldStrip = false;
          continue;
        }
        genSnapshotArgs.add(option);
      }
    }

    final String assembly = _fileSystem.path.join(outputDir.path, 'snapshot_assembly.S');
    if (platform == TargetPlatform.ios || platform == TargetPlatform.darwin_x64) {
      genSnapshotArgs.addAll(<String>[
        '--snapshot_kind=app-aot-assembly',
        '--assembly=$assembly',
      ]);
    } else {
      final String aotSharedLibrary = _fileSystem.path.join(outputDir.path, 'app.so');
      genSnapshotArgs.addAll(<String>[
        '--snapshot_kind=app-aot-elf',
        '--elf=$aotSharedLibrary',
      ]);
    }

    if (shouldStrip) {
      genSnapshotArgs.add('--strip');
    }

    if (platform == TargetPlatform.android_arm || darwinArch == DarwinArch.armv7) {
      // Use softfp for Android armv7 devices.
      // This is the default for armv7 iOS builds, but harmless to set.
      // TODO(cbracken): eliminate this when we fix https://github.com/flutter/flutter/issues/17489
      genSnapshotArgs.add('--no-sim-use-hardfp');

      // Not supported by the Pixel in 32-bit mode.
      genSnapshotArgs.add('--no-use-integer-division');
    }

    // The name of the debug file must contain additional information about
    // the architecture, since a single build command may produce
    // multiple debug files.
    final String archName = getNameForTargetPlatform(platform, darwinArch: darwinArch);
    final String debugFilename = 'app.$archName.symbols';
    final bool shouldSplitDebugInfo = splitDebugInfo?.isNotEmpty ?? false;
    if (shouldSplitDebugInfo) {
      _fileSystem.directory(splitDebugInfo)
        .createSync(recursive: true);
    }

    // Optimization arguments.
    genSnapshotArgs.addAll(<String>[
      // Faster async/await
      if (shouldSplitDebugInfo) ...<String>[
        '--dwarf-stack-traces',
        '--save-debugging-info=${_fileSystem.path.join(splitDebugInfo, debugFilename)}'
      ],
      if (dartObfuscation)
        '--obfuscate',
    ]);

    genSnapshotArgs.add(mainPath);

    final SnapshotType snapshotType = SnapshotType(platform, buildMode);
    final int genSnapshotExitCode = await _genSnapshot.run(
      snapshotType: snapshotType,
      additionalArgs: genSnapshotArgs,
      darwinArch: darwinArch,
    );
    if (genSnapshotExitCode != 0) {
      _logger.printError('Dart snapshot generator failed with exit code $genSnapshotExitCode');
      return genSnapshotExitCode;
    }

    // On iOS and macOS, we use Xcode to compile the snapshot into a dynamic library that the
    // end-developer can link into their app.
    if (platform == TargetPlatform.ios || platform == TargetPlatform.darwin_x64) {
      final RunResult result = await _buildFramework(
        appleArch: darwinArch,
        isIOS: platform == TargetPlatform.ios,
        sdkRoot: sdkRoot,
        assemblyPath: assembly,
        outputPath: outputDir.path,
        bitcode: bitcode,
        quiet: quiet,
      );
      if (result.exitCode != 0) {
        return result.exitCode;
      }
    }
    return 0;
  }

  /// Builds an iOS or macOS framework at [outputPath]/App.framework from the assembly
  /// source at [assemblyPath].
  Future<RunResult> _buildFramework({
    @required DarwinArch appleArch,
    @required bool isIOS,
    @required String sdkRoot,
    @required String assemblyPath,
    @required String outputPath,
    @required bool bitcode,
    @required bool quiet
  }) async {
    final String targetArch = getNameForDarwinArch(appleArch);
    if (!quiet) {
      _logger.printStatus('Building App.framework for $targetArch...');
    }

    final List<String> commonBuildOptions = <String>[
      '-arch', targetArch,
      if (isIOS)
        // When the minimum version is updated, remember to update
        // template MinimumOSVersion.
        // https://github.com/flutter/flutter/pull/62902
        '-miphoneos-version-min=8.0',
    ];

    const String embedBitcodeArg = '-fembed-bitcode';
    final String assemblyO = _fileSystem.path.join(outputPath, 'snapshot_assembly.o');
    List<String> isysrootArgs;
    if (sdkRoot != null) {
      isysrootArgs = <String>['-isysroot', sdkRoot];
    }

    final RunResult compileResult = await _xcode.cc(<String>[
      '-arch', targetArch,
      if (isysrootArgs != null) ...isysrootArgs,
      if (bitcode) embedBitcodeArg,
      '-c',
      assemblyPath,
      '-o',
      assemblyO,
    ]);
    if (compileResult.exitCode != 0) {
      _logger.printError('Failed to compile AOT snapshot. Compiler terminated with exit code ${compileResult.exitCode}');
      return compileResult;
    }

    final String frameworkDir = _fileSystem.path.join(outputPath, 'App.framework');
    _fileSystem.directory(frameworkDir).createSync(recursive: true);
    final String appLib = _fileSystem.path.join(frameworkDir, 'App');
    final List<String> linkArgs = <String>[
      ...commonBuildOptions,
      '-dynamiclib',
      '-Xlinker', '-rpath', '-Xlinker', '@executable_path/Frameworks',
      '-Xlinker', '-rpath', '-Xlinker', '@loader_path/Frameworks',
      '-install_name', '@rpath/App.framework/App',
      if (bitcode) embedBitcodeArg,
      if (isysrootArgs != null) ...isysrootArgs,
      '-o', appLib,
      assemblyO,
    ];
    final RunResult linkResult = await _xcode.clang(linkArgs);
    if (linkResult.exitCode != 0) {
      _logger.printError('Failed to link AOT snapshot. Linker terminated with exit code ${compileResult.exitCode}');
    }
    return linkResult;
  }

  bool _isValidAotPlatform(TargetPlatform platform, BuildMode buildMode) {
    if (buildMode == BuildMode.debug) {
      return false;
    }
    return const <TargetPlatform>[
      TargetPlatform.android_arm,
      TargetPlatform.android_arm64,
      TargetPlatform.android_x64,
      TargetPlatform.ios,
      TargetPlatform.darwin_x64,
      TargetPlatform.linux_x64,
      TargetPlatform.linux_arm64,
      TargetPlatform.windows_x64,
    ].contains(platform);
  }
}
