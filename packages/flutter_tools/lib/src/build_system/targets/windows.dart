// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import '../../artifacts.dart';
import '../../base/file_system.dart';
import '../../build_info.dart';
import '../build_system.dart';
import '../depfile.dart';
import '../exceptions.dart';
import 'assets.dart';
import 'common.dart';
import 'desktop.dart';
import 'icon_tree_shaker.dart';

/// The only files/subdirectories we care about.
const List<String> _kWindowsArtifacts = <String>[
  'flutter_windows.dll',
  'flutter_windows.dll.exp',
  'flutter_windows.dll.lib',
  'flutter_windows.dll.pdb',
  'flutter_export.h',
  'flutter_messenger.h',
  'flutter_plugin_registrar.h',
  'flutter_texture_registrar.h',
  'flutter_windows.h',
];

const List<String> _kWindowsUwpArtifacts = <String>[
  'flutter_windows_winuwp.dll',
  'flutter_windows_winuwp.dll.exp',
  'flutter_windows_winuwp.dll.lib',
  'flutter_windows_winuwp.dll.pdb',
  'flutter_export.h',
  'flutter_messenger.h',
  'flutter_plugin_registrar.h',
  'flutter_texture_registrar.h',
  'flutter_windows.h',
];

const String _kWindowsDepfile = 'windows_engine_sources.d';
const String _kWindowsUwpDepfile = 'windows_uwp_engine_sources.d';

/// Copies the Windows desktop embedding files to the copy directory.
class UnpackWindows extends Target {
  const UnpackWindows();

  @override
  String get name => 'unpack_windows';

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/windows.dart'),
  ];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<String> get depfiles => const <String>[_kWindowsDepfile];

  @override
  List<Target> get dependencies => const <Target>[];

  @override
  Future<void> build(Environment environment) async {
    final BuildMode buildMode = getBuildModeForName(environment.defines[kBuildMode]);
    final String engineSourcePath = environment.artifacts
      .getArtifactPath(
        Artifact.windowsDesktopPath,
        platform: TargetPlatform.windows_x64,
        mode: buildMode,
      );
    final String clientSourcePath = environment.artifacts
      .getArtifactPath(
        Artifact.windowsCppClientWrapper,
        platform: TargetPlatform.windows_x64,
        mode: buildMode,
      );
    final Directory outputDirectory = environment.fileSystem.directory(
      environment.fileSystem.path.join(
        environment.projectDir.path,
        'windows',
        'flutter',
        'ephemeral',
      ),
    );
    final Depfile depfile = unpackDesktopArtifacts(
      fileSystem: environment.fileSystem,
      artifacts: _kWindowsArtifacts,
      engineSourcePath: engineSourcePath,
      outputDirectory: outputDirectory,
      clientSourcePaths: <String>[clientSourcePath],
      icuDataPath: environment.artifacts.getArtifactPath(
        Artifact.icuData,
        platform: TargetPlatform.windows_x64
      )
    );
    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );
    depfileService.writeToFile(
      depfile,
      environment.buildDir.childFile(_kWindowsDepfile),
    );
  }
}


/// Copies the Windows desktop embedding files to the copy directory.
class UnpackWindowsUwp extends Target {
  const UnpackWindowsUwp();

  @override
  String get name => 'unpack_windows_uwp';

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/windows.dart'),
  ];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<String> get depfiles => const <String>[_kWindowsUwpDepfile];

  @override
  List<Target> get dependencies => const <Target>[];

  @override
  Future<void> build(Environment environment) async {
    // These artifact look ups need to modified to windows-x64-uwp once
    // the cache updates have landed.
    final BuildMode buildMode = getBuildModeForName(environment.defines[kBuildMode]);
    final String engineSourcePath = environment.artifacts
      .getArtifactPath(
        Artifact.windowsDesktopPath,
        platform: TargetPlatform.windows_x64,
        mode: buildMode,
      );
    final String clientSourcePath = environment.artifacts
      .getArtifactPath(
        Artifact.windowsCppClientWrapper,
        platform: TargetPlatform.windows_x64,
        mode: buildMode,
      );
    final Directory outputDirectory = environment.fileSystem.directory(
      environment.fileSystem.path.join(
        environment.projectDir.path,
        'winuwp',
        'flutter',
        'ephemeral',
      ),
    );
    final Depfile depfile = unpackDesktopArtifacts(
      fileSystem: environment.fileSystem,
      artifacts: _kWindowsUwpArtifacts,
      engineSourcePath: engineSourcePath,
      outputDirectory: outputDirectory,
      clientSourcePaths: <String>[clientSourcePath],
      icuDataPath: environment.artifacts.getArtifactPath(
        Artifact.icuData,
        platform: TargetPlatform.windows_x64
      )
    );
    // Copy flutter_windows.h into flutter directory as well.
    final File flutterWindows = outputDirectory.childFile('flutter_windows.h');
    final File flutterWindowsDest = flutterWindows.parent.parent.childFile('flutter_windows.h');
    flutterWindows.copySync(flutterWindowsDest.path);
    depfile.outputs.add(flutterWindowsDest);
    //

    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );
    depfileService.writeToFile(
      depfile,
      environment.buildDir.childFile(_kWindowsUwpDepfile),
    );
  }
}

/// Creates a bundle for the Windows desktop target.
abstract class BundleWindowsAssets extends Target {
  const BundleWindowsAssets();

  @override
  List<Target> get dependencies => const <Target>[
    KernelSnapshot(),
    UnpackWindows(),
  ];

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/windows.dart'),
    Source.pattern('{PROJECT_DIR}/pubspec.yaml'),
    ...IconTreeShaker.inputs,
  ];

  @override
  List<String> get depfiles => const <String>[
    'flutter_assets.d',
  ];

  @override
  Future<void> build(Environment environment) async {
    if (environment.defines[kBuildMode] == null) {
      throw MissingDefineException(kBuildMode, 'bundle_windows_assets');
    }
    final BuildMode buildMode = getBuildModeForName(environment.defines[kBuildMode]);
    final Directory outputDirectory = environment.outputDir
      .childDirectory('flutter_assets');
    if (!outputDirectory.existsSync()) {
      outputDirectory.createSync();
    }

    // Only copy the kernel blob in debug mode.
    if (buildMode == BuildMode.debug) {
      environment.buildDir.childFile('app.dill')
        .copySync(outputDirectory.childFile('kernel_blob.bin').path);
    }
    final Depfile depfile = await copyAssets(
      environment,
      outputDirectory,
      targetPlatform: TargetPlatform.windows_x64,
    );
    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );
    depfileService.writeToFile(
      depfile,
      environment.buildDir.childFile('flutter_assets.d'),
    );
  }
}


/// Creates a bundle for the Windows desktop target.
abstract class BundleWindowsAssetsUwp extends BundleWindowsAssets {
  const BundleWindowsAssetsUwp();

  @override
  List<Target> get dependencies => const <Target>[
    KernelSnapshot(),
    UnpackWindowsUwp(),
  ];
}

/// A wrapper for AOT compilation that copies app.so into the output directory.
class WindowsAotBundle extends Target {
  /// Create a [WindowsAotBundle] wrapper for [aotTarget].
  const WindowsAotBundle(this.aotTarget);

  /// The [AotElfBase] subclass that produces the app.so.
  final AotElfBase aotTarget;

  @override
  String get name => 'windows_aot_bundle';

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{BUILD_DIR}/app.so'),
  ];

  @override
  List<Source> get outputs => const <Source>[
    Source.pattern('{OUTPUT_DIR}/windows/app.so'),
  ];

  @override
  List<Target> get dependencies => <Target>[
    aotTarget,
  ];

  @override
  Future<void> build(Environment environment) async {
    final File outputFile = environment.buildDir.childFile('app.so');
    final Directory outputDirectory = environment.outputDir.childDirectory('windows');
    if (!outputDirectory.existsSync()) {
      outputDirectory.createSync(recursive: true);
    }
    outputFile.copySync(outputDirectory.childFile('app.so').path);
  }
}

class ReleaseBundleWindowsAssets extends BundleWindowsAssets {
  const ReleaseBundleWindowsAssets();

  @override
  String get name => 'release_bundle_windows_assets';

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<Target> get dependencies => <Target>[
    ...super.dependencies,
    const WindowsAotBundle(AotElfRelease(TargetPlatform.windows_x64)),
  ];
}

class ProfileBundleWindowsAssets extends BundleWindowsAssets {
  const ProfileBundleWindowsAssets();

  @override
  String get name => 'profile_bundle_windows_assets';

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<Target> get dependencies => <Target>[
    ...super.dependencies,
    const WindowsAotBundle(AotElfProfile(TargetPlatform.windows_x64)),
  ];
}

class DebugBundleWindowsAssets extends BundleWindowsAssets {
  const DebugBundleWindowsAssets();

  @override
  String get name => 'debug_bundle_windows_assets';

  @override
  List<Source> get inputs => <Source>[
    const Source.pattern('{BUILD_DIR}/app.dill'),
  ];

  @override
  List<Source> get outputs => <Source>[
    const Source.pattern('{OUTPUT_DIR}/flutter_assets/kernel_blob.bin'),
  ];
}


class ReleaseBundleWindowsAssetsUwp extends BundleWindowsAssetsUwp {
  const ReleaseBundleWindowsAssetsUwp();

  @override
  String get name => 'release_bundle_windows_assets_uwp';

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<Target> get dependencies => <Target>[
    ...super.dependencies,
    const WindowsAotBundle(AotElfRelease(TargetPlatform.windows_x64)),
  ];
}

class ProfileBundleWindowsAssetsUwp extends BundleWindowsAssetsUwp {
  const ProfileBundleWindowsAssetsUwp();

  @override
  String get name => 'profile_bundle_windows_assets_uwp';

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<Target> get dependencies => <Target>[
    ...super.dependencies,
    const WindowsAotBundle(AotElfProfile(TargetPlatform.windows_x64)),
  ];
}

class DebugBundleWindowsAssetsUwp extends BundleWindowsAssetsUwp {
  const DebugBundleWindowsAssetsUwp();

  @override
  String get name => 'debug_bundle_windows_assets_uwp';

  @override
  List<Source> get inputs => <Source>[
    const Source.pattern('{BUILD_DIR}/app.dill'),
  ];

  @override
  List<Source> get outputs => <Source>[
    const Source.pattern('{OUTPUT_DIR}/flutter_assets/kernel_blob.bin'),
  ];
}
