// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import '../base/common.dart';
import '../base/utils.dart';
import '../doctor_validator.dart';
import '../emulator.dart';
import '../globals.dart' as globals;
import '../runner/flutter_command.dart';

class EmulatorsCommand extends FlutterCommand {
  EmulatorsCommand() {
    argParser.addOption('launch',
        help: 'The full or partial ID of the emulator to launch.');
    argParser.addFlag('create',
        help: 'Creates a new Android emulator based on a Pixel device.',
        negatable: false);
    argParser.addOption('name',
        help: 'Used with the "--create" flag. Specifies a name for the emulator being created.');
  }

  @override
  final String name = 'emulators';

  @override
  final String description = 'List, launch and create emulators.';

  @override
  final List<String> aliases = <String>['emulator'];

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (globals.doctor.workflows.every((Workflow w) => !w.canListEmulators)) {
      throwToolExit(
          'Unable to find any emulator sources. Please ensure you have some\n'
              'Android AVD images ' +
              (globals.platform.isMacOS ? 'or an iOS Simulator ' : '') +
              'available.',
          exitCode: 1);
    }

    if (argResults.wasParsed('launch')) {
      await _launchEmulator(stringArg('launch'));
    } else if (argResults.wasParsed('create')) {
      await _createEmulator(name: stringArg('name'));
    } else {
      final String searchText =
          argResults.rest != null && argResults.rest.isNotEmpty
              ? argResults.rest.first
              : null;
      await _listEmulators(searchText);
    }

    return FlutterCommandResult.success();
  }

  Future<void> _launchEmulator(String id) async {
    final List<Emulator> emulators =
        await emulatorManager.getEmulatorsMatching(id);

    if (emulators.isEmpty) {
      globals.printStatus("No emulator found that matches '$id'.");
    } else if (emulators.length > 1) {
      _printEmulatorList(
        emulators,
        "More than one emulator matches '$id':",
      );
    } else {
      await emulators.first.launch();
    }
  }

  Future<void> _createEmulator({ String name }) async {
    final CreateEmulatorResult createResult =
        await emulatorManager.createEmulator(name: name);

    if (createResult.success) {
      globals.printStatus("Emulator '${createResult.emulatorName}' created successfully.");
    } else {
      globals.printStatus("Failed to create emulator '${createResult.emulatorName}'.\n");
      globals.printStatus(createResult.error.trim());
      _printAdditionalInfo();
    }
  }

  Future<void> _listEmulators(String searchText) async {
    final List<Emulator> emulators = searchText == null
        ? await emulatorManager.getAllAvailableEmulators()
        : await emulatorManager.getEmulatorsMatching(searchText);

    if (emulators.isEmpty) {
      globals.printStatus('No emulators available.');
      _printAdditionalInfo(showCreateInstruction: true);
    } else {
      _printEmulatorList(
        emulators,
        '${emulators.length} available ${pluralize('emulator', emulators.length)}:',
      );
    }
  }

  void _printEmulatorList(List<Emulator> emulators, String message) {
    globals.printStatus('$message\n');
    Emulator.printEmulators(emulators, globals.logger);
    _printAdditionalInfo(showCreateInstruction: true, showRunInstruction: true);
  }

  void _printAdditionalInfo({
    bool showRunInstruction = false,
    bool showCreateInstruction = false,
  }) {
    globals.printStatus('');
    if (showRunInstruction) {
      globals.printStatus(
          "To run an emulator, run 'flutter emulators --launch <emulator id>'.");
    }
    if (showCreateInstruction) {
      globals.printStatus(
          "To create a new emulator, run 'flutter emulators --create [--name xyz]'.");
    }

    if (showRunInstruction || showCreateInstruction) {
      globals.printStatus('');
    }
    // TODO(dantup): Update this link to flutter.dev if/when we have a better page.
    // That page can then link out to these places if required.
    globals.printStatus('You can find more information on managing emulators at the links below:\n'
        '  https://developer.android.com/studio/run/managing-avds\n'
        '  https://developer.android.com/studio/command-line/avdmanager');
  }
}
