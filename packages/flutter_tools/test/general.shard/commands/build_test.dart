// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:args/args.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/commands/attach.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:flutter_tools/src/commands/build_aar.dart';
import 'package:flutter_tools/src/commands/build_apk.dart';
import 'package:flutter_tools/src/commands/build_appbundle.dart';
import 'package:flutter_tools/src/commands/build_fuchsia.dart';
import 'package:flutter_tools/src/commands/build_ios.dart';
import 'package:flutter_tools/src/commands/build_ios_framework.dart';
import 'package:flutter_tools/src/commands/build_linux.dart';
import 'package:flutter_tools/src/commands/build_macos.dart';
import 'package:flutter_tools/src/commands/build_web.dart';
import 'package:flutter_tools/src/commands/build_windows.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../../src/common.dart';
import '../../src/context.dart';

void main() {
  testUsingContext('All build commands support null safety options', () {
    final List<FlutterCommand> commands = <FlutterCommand>[
      BuildWindowsCommand(verboseHelp: false),
      BuildLinuxCommand(verboseHelp: false, operatingSystemUtils: globals.os),
      BuildMacosCommand(verboseHelp: false),
      BuildWebCommand(verboseHelp: false),
      BuildApkCommand(verboseHelp: false),
      BuildIOSCommand(verboseHelp: false),
      BuildIOSArchiveCommand(verboseHelp: false),
      BuildAppBundleCommand(verboseHelp: false),
      BuildFuchsiaCommand(verboseHelp: false),
      BuildAarCommand(verboseHelp: false),
      BuildIOSFrameworkCommand(verboseHelp: false, buildSystem: globals.buildSystem),
      AttachCommand(verboseHelp: false),
    ];

    for (final FlutterCommand command in commands) {
      final ArgResults results = command.argParser.parse(<String>[
        '--sound-null-safety',
        '--enable-experiment=non-nullable',
      ]);

      expect(results.wasParsed('sound-null-safety'), true);
      expect(results.wasParsed('enable-experiment'), true);
    }
  });

  testUsingContext('BuildSubCommand displays current null safety mode', () async {
    const BuildInfo unsound = BuildInfo(
      BuildMode.debug,
      '',
      trackWidgetCreation: false,
      nullSafetyMode: NullSafetyMode.unsound,
      treeShakeIcons: false,
    );
    const BuildInfo sound = BuildInfo(
      BuildMode.debug,
      '',
      trackWidgetCreation: false,
      nullSafetyMode: NullSafetyMode.sound,
      treeShakeIcons: false,
    );

    FakeBuildSubCommand().test(unsound);
    expect(testLogger.statusText, contains('Building without sound null safety'));

    testLogger.clear();
    FakeBuildSubCommand().test(sound);
    expect(testLogger.statusText, contains('💪 Building with sound null safety 💪'));
  });
}

class FakeBuildSubCommand extends BuildSubCommand {
  @override
  String get description => throw UnimplementedError();

  @override
  String get name => throw UnimplementedError();

  void test(BuildInfo buildInfo) {
    displayNullSafetyMode(buildInfo);
  }

  @override
  Future<FlutterCommandResult> runCommand() {
    throw UnimplementedError();
  }
}
