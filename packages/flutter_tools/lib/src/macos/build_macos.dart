// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:meta/meta.dart';

import '../base/analyze_size.dart';
import '../base/common.dart';
import '../base/file_system.dart';
import '../base/logger.dart';
import '../base/project_migrator.dart';
import '../build_info.dart';
import '../convert.dart';
import '../globals.dart' as globals;
import '../ios/xcodeproj.dart';
import '../project.dart';
import 'cocoapod_utils.dart';
import 'migrations/remove_macos_framework_link_and_embedding_migration.dart';

/// When run in -quiet mode, Xcode only prints from the underlying tasks to stdout.
/// Passing this regexp to trace moves the stdout output to stderr.
final RegExp _anyOutput = RegExp('.*');

/// Builds the macOS project through xcodebuild.
// TODO(jonahwilliams): refactor to share code with the existing iOS code.
Future<void> buildMacOS({
  FlutterProject flutterProject,
  BuildInfo buildInfo,
  String targetOverride,
  @required bool verboseLogging,
  SizeAnalyzer sizeAnalyzer,
}) async {
  if (!flutterProject.macos.xcodeWorkspace.existsSync()) {
    throwToolExit('No macOS desktop project configured. '
      'See https://flutter.dev/desktop#add-desktop-support-to-an-existing-flutter-app '
      'to learn about adding macOS support to a project.');
  }

  final List<ProjectMigrator> migrators = <ProjectMigrator>[
    RemoveMacOSFrameworkLinkAndEmbeddingMigration(
      flutterProject.macos,
      globals.logger,
      globals.flutterUsage,
    ),
  ];

  final ProjectMigration migration = ProjectMigration(migrators);
  if (!migration.run()) {
    throwToolExit('Could not migrate project file');
  }

  final Directory flutterBuildDir = globals.fs.directory(getMacOSBuildDirectory());
  if (!flutterBuildDir.existsSync()) {
    flutterBuildDir.createSync(recursive: true);
  }
  // Write configuration to an xconfig file in a standard location.
  await updateGeneratedXcodeProperties(
    project: flutterProject,
    buildInfo: buildInfo,
    targetOverride: targetOverride,
    useMacOSConfig: true,
    setSymroot: false,
  );
  await processPodsIfNeeded(flutterProject.macos, getMacOSBuildDirectory(), buildInfo.mode);
  // If the xcfilelists do not exist, create empty version.
  if (!flutterProject.macos.inputFileList.existsSync()) {
    flutterProject.macos.inputFileList.createSync(recursive: true);
  }
  if (!flutterProject.macos.outputFileList.existsSync()) {
    flutterProject.macos.outputFileList.createSync(recursive: true);
  }

  final Directory xcodeProject = flutterProject.macos.xcodeProject;

  // If the standard project exists, specify it to getInfo to handle the case where there are
  // other Xcode projects in the macos/ directory. Otherwise pass no name, which will work
  // regardless of the project name so long as there is exactly one project.
  final String xcodeProjectName = xcodeProject.existsSync() ? xcodeProject.basename : null;
  final XcodeProjectInfo projectInfo = await globals.xcodeProjectInterpreter.getInfo(
    xcodeProject.parent.path,
    projectFilename: xcodeProjectName,
  );
  final String scheme = projectInfo.schemeFor(buildInfo);
  if (scheme == null) {
    projectInfo.reportFlavorNotFoundAndExit();
  }
  final String configuration = projectInfo.buildConfigurationFor(buildInfo, scheme);
  if (configuration == null) {
    throwToolExit('Unable to find expected configuration in Xcode project.');
  }

  // Run the Xcode build.
  final Stopwatch sw = Stopwatch()..start();
  final Status status = globals.logger.startProgress(
    'Building macOS application...',
  );
  int result;
  try {
    result = await globals.processUtils.stream(<String>[
      '/usr/bin/env',
      'xcrun',
      'xcodebuild',
      '-workspace', flutterProject.macos.xcodeWorkspace.path,
      '-configuration', configuration,
      '-scheme', 'Runner',
      '-derivedDataPath', flutterBuildDir.absolute.path,
      'OBJROOT=${globals.fs.path.join(flutterBuildDir.absolute.path, 'Build', 'Intermediates.noindex')}',
      'SYMROOT=${globals.fs.path.join(flutterBuildDir.absolute.path, 'Build', 'Products')}',
      if (verboseLogging)
        'VERBOSE_SCRIPT_LOGGING=YES'
      else
        '-quiet',
      'COMPILER_INDEX_STORE_ENABLE=NO',
    ],
    trace: true,
    stdoutErrorMatcher: verboseLogging ? null : _anyOutput,
  );
  } finally {
    status.cancel();
  }
  if (result != 0) {
    throwToolExit('Build process failed');
  }
  if (buildInfo.codeSizeDirectory != null && sizeAnalyzer != null) {
    final String arch = getNameForDarwinArch(DarwinArch.x86_64);
    final File aotSnapshot = globals.fs.directory(buildInfo.codeSizeDirectory)
      .childFile('snapshot.$arch.json');
    final File precompilerTrace = globals.fs.directory(buildInfo.codeSizeDirectory)
      .childFile('trace.$arch.json');

    // This analysis is only supported for release builds.
    // Attempt to guess the correct .app by picking the first one.
    final Directory candidateDirectory = globals.fs.directory(
      globals.fs.path.join(getMacOSBuildDirectory(), 'Build', 'Products', 'Release'),
    );
    final Directory appDirectory = candidateDirectory.listSync()
      .whereType<Directory>()
      .firstWhere((Directory directory) {
      return globals.fs.path.extension(directory.path) == '.app';
    });
    final Map<String, Object> output = await sizeAnalyzer.analyzeAotSnapshot(
      aotSnapshot: aotSnapshot,
      precompilerTrace: precompilerTrace,
      outputDirectory: appDirectory,
      type: 'macos',
      excludePath: 'Versions', // Avoid double counting caused by symlinks
    );
    final File outputFile = globals.fsUtils.getUniqueFile(
      globals.fs
        .directory(globals.fsUtils.homeDirPath)
        .childDirectory('.flutter-devtools'), 'macos-code-size-analysis', 'json',
    )..writeAsStringSync(jsonEncode(output));
    // This message is used as a sentinel in analyze_apk_size_test.dart
    globals.printStatus(
      'A summary of your macOS bundle analysis can be found at: ${outputFile.path}',
    );

    // DevTools expects a file path relative to the .flutter-devtools/ dir.
    final String relativeAppSizePath = outputFile.path.split('.flutter-devtools/').last.trim();
    globals.printStatus(
      '\nTo analyze your app size in Dart DevTools, run the following command:\n'
      'flutter pub global activate devtools; flutter pub global run devtools '
      '--appSizeBase=$relativeAppSizePath'
    );
  }
  globals.flutterUsage.sendTiming('build', 'xcode-macos', Duration(milliseconds: sw.elapsedMilliseconds));
}
