// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:dev_tools/codesign.dart';
import 'package:dev_tools/globals.dart';
import 'package:dev_tools/repository.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:meta/meta.dart';
import 'package:platform/platform.dart';

import '../../../packages/flutter_tools/test/src/fake_process_manager.dart';
import './common.dart';

void main() {
  group('codesign command', () {
    const String flutterRoot = '/flutter';
    const String checkoutsParentDirectory = '$flutterRoot/dev/tools/';
    const String flutterCache =
        '${checkoutsParentDirectory}flutter_conductor_checkouts/framework/bin/cache';
    const String flutterBin =
        '${checkoutsParentDirectory}flutter_conductor_checkouts/framework/bin/flutter';
    const String revision = 'abcd1234';
    CommandRunner<void> runner;
    Checkouts checkouts;
    MemoryFileSystem fileSystem;
    FakePlatform platform;
    TestStdio stdio;
    FakeProcessManager processManager;
    const List<String> binariesWithEntitlements = <String>[
      '$flutterCache/dart-sdk/bin/dart',
      '$flutterCache/dart-sdk/bin/dartaotruntime',
    ];
    const List<String> binariesWithoutEntitlements = <String>[
      '$flutterCache/engine/darwin-x64/font-subset',
    ];
    const List<String> allBinaries = <String>[
      ...binariesWithEntitlements,
      ...binariesWithoutEntitlements,
    ];

    void createRunner({
      String operatingSystem = 'macos',
      List<FakeCommand> commands,
    }) {
      stdio = TestStdio();
      fileSystem = MemoryFileSystem.test();
      platform = FakePlatform(operatingSystem: operatingSystem);
      processManager = FakeProcessManager.list(commands ?? <FakeCommand>[]);
      checkouts = Checkouts(
        fileSystem: fileSystem,
        parentDirectory: fileSystem.directory(checkoutsParentDirectory),
        platform: platform,
        processManager: processManager,
        stdio: stdio,
      );
      final FakeCodesignCommand command = FakeCodesignCommand(
        checkouts: checkouts,
        binariesWithEntitlements: binariesWithEntitlements,
        binariesWithoutEntitlements: binariesWithoutEntitlements,
        flutterRoot: fileSystem.directory(flutterRoot),
      );
      runner = CommandRunner<void>('codesign-test', '')
        ..addCommand(command);
    }

    test('throws exception if not run from macos', () async {
      createRunner(operatingSystem: 'linux');
      expect(
        () async => runner.run(<String>['codesign']),
        throwsExceptionWith('Error! Expected operating system "macos"'),
      );
    });

    test('throws exception if verify flag is not provided', () async {
      createRunner();
      expect(
        () async => runner.run(<String>['codesign']),
        throwsExceptionWith(
            'Sorry, but codesigning is not implemented yet. Please pass the --$kVerify flag to verify signatures'),
      );
    });

    test('succeeds if every binary is codesigned and has correct entitlements', () async {
      final List<FakeCommand> codesignCheckCommands = <FakeCommand>[];
      for (final String bin in binariesWithEntitlements) {
        codesignCheckCommands.add(
          FakeCommand(
            command: <String>['codesign', '-vvv', bin],
          ),
        );
        codesignCheckCommands.add(
          FakeCommand(
            command: <String>['codesign', '--display', '--entitlements', ':-', bin],
            stdout: expectedEntitlements.join('\n'),
          ),
        );
      }
      for (final String bin in binariesWithoutEntitlements) {
        codesignCheckCommands.add(
          FakeCommand(
            command: <String>['codesign', '-vvv', bin],
          ),
        );
      }
      createRunner(commands: <FakeCommand>[
        const FakeCommand(command: <String>[
          'git',
          'clone',
          '--',
          'file://$flutterRoot/',
          '${checkoutsParentDirectory}flutter_conductor_checkouts/framework',
        ]),
        const FakeCommand(command: <String>[
          'git',
          'rev-parse',
          'HEAD',
        ], stdout: revision),
        const FakeCommand(command: <String>[
          'git',
          'checkout',
          revision,
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'help',
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'help',
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'precache',
          '--android',
          '--ios',
          '--macos',
        ]),
        FakeCommand(
          command: const <String>[
            'find',
            '${checkoutsParentDirectory}flutter_conductor_checkouts/framework/bin/cache',
            '-type',
            'f',
          ],
          stdout: allBinaries.join('\n'),
        ),
        for (String bin in allBinaries)
          FakeCommand(
            command: <String>['file', '--mime-type', '-b', bin],
            stdout: 'application/x-mach-binary',
          ),
        ...codesignCheckCommands,
      ]);
      await runner.run(<String>['codesign', '--$kVerify', '--$kRevision', revision]);
      expect(processManager.hasRemainingExpectations, false);
    });

    test('fails if a single binary is not codesigned', () async {
      final List<FakeCommand> codesignCheckCommands = <FakeCommand>[];
      codesignCheckCommands.add(
        const FakeCommand(
          command: <String>['codesign', '-vvv', '$flutterCache/dart-sdk/bin/dart'],
        ),
      );
      codesignCheckCommands.add(
        FakeCommand(
          command: const <String>[
            'codesign',
            '--display',
            '--entitlements',
            ':-',
            '$flutterCache/dart-sdk/bin/dart',
          ],
          stdout: expectedEntitlements.join('\n'),
        )
      );
      // Not signed
      codesignCheckCommands.add(
        const FakeCommand(
          command: <String>['codesign', '-vvv', '$flutterCache/dart-sdk/bin/dartaotruntime'],
          exitCode: 1,
        ),
      );
      codesignCheckCommands.add(
        const FakeCommand(
          command: <String>['codesign', '-vvv', '$flutterCache/engine/darwin-x64/font-subset'],
        ),
      );

      createRunner(commands: <FakeCommand>[
        const FakeCommand(command: <String>[
          'git',
          'clone',
          '--',
          'file://$flutterRoot/',
          '${checkoutsParentDirectory}flutter_conductor_checkouts/framework',
        ]),
        const FakeCommand(command: <String>[
          'git',
          'rev-parse',
          'HEAD',
        ], stdout: revision),
        const FakeCommand(command: <String>[
          'git',
          'checkout',
          revision,
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'help',
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'help',
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'precache',
          '--android',
          '--ios',
          '--macos',
        ]),
        FakeCommand(
          command: const <String>[
            'find',
            '${checkoutsParentDirectory}flutter_conductor_checkouts/framework/bin/cache',
            '-type',
            'f',
          ],
          stdout: allBinaries.join('\n'),
        ),
        for (String bin in allBinaries)
          FakeCommand(
            command: <String>['file', '--mime-type', '-b', bin],
            stdout: 'application/x-mach-binary',
          ),
        ...codesignCheckCommands,
      ]);
      expect(
        () async => runner.run(<String>['codesign', '--$kVerify', '--$kRevision', revision]),
        throwsExceptionWith('Test failed because unsigned binaries detected.'),
      );
      expect(processManager.hasRemainingExpectations, false);
    });

    test('fails if a single binary has the wrong entitlements', () async {
      final List<FakeCommand> codesignCheckCommands = <FakeCommand>[];
      codesignCheckCommands.add(
        const FakeCommand(
          command: <String>['codesign', '-vvv', '$flutterCache/dart-sdk/bin/dart'],
        ),
      );
      codesignCheckCommands.add(
        FakeCommand(
          command: const <String>['codesign', '--display', '--entitlements', ':-', '$flutterCache/dart-sdk/bin/dart'],
          stdout: expectedEntitlements.join('\n'),
        )
      );
      codesignCheckCommands.add(
        const FakeCommand(
          command: <String>['codesign', '-vvv', '$flutterCache/dart-sdk/bin/dartaotruntime'],
        ),
      );
      // No entitlements
      codesignCheckCommands.add(
        const FakeCommand(
          command: <String>['codesign', '--display', '--entitlements', ':-', '$flutterCache/dart-sdk/bin/dartaotruntime'],
        )
      );
      codesignCheckCommands.add(
        const FakeCommand(
          command: <String>['codesign', '-vvv', '$flutterCache/engine/darwin-x64/font-subset'],
        ),
      );
      createRunner(commands: <FakeCommand>[
        const FakeCommand(command: <String>[
          'git',
          'clone',
          '--',
          'file://$flutterRoot/',
          '${checkoutsParentDirectory}flutter_conductor_checkouts/framework',
        ]),
        const FakeCommand(command: <String>[
          'git',
          'rev-parse',
          'HEAD',
        ], stdout: revision),
        const FakeCommand(command: <String>[
          'git',
          'checkout',
          revision,
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'help',
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'help',
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'precache',
          '--android',
          '--ios',
          '--macos',
        ]),
        FakeCommand(
          command: const <String>[
            'find',
            '${checkoutsParentDirectory}flutter_conductor_checkouts/framework/bin/cache',
            '-type',
            'f',
          ],
          stdout: allBinaries.join('\n'),
        ),
        for (String bin in allBinaries)
          FakeCommand(
            command: <String>['file', '--mime-type', '-b', bin],
            stdout: 'application/x-mach-binary',
          ),
        ...codesignCheckCommands,
      ]);
      expect(
        () async => runner.run(<String>['codesign', '--$kVerify', '--$kRevision', revision]),
        throwsExceptionWith('Test failed because files found with the wrong entitlements'),
      );
      expect(processManager.hasRemainingExpectations, false);
    });

    test('does not check signatures or entitlements if --no-$kSignatures specified', () async {
      createRunner(commands: <FakeCommand>[
        const FakeCommand(command: <String>[
          'git',
          'clone',
          '--',
          'file://$flutterRoot/',
          '${checkoutsParentDirectory}flutter_conductor_checkouts/framework',
        ]),
        const FakeCommand(command: <String>[
          'git',
          'rev-parse',
          'HEAD',
        ], stdout: revision),
        const FakeCommand(command: <String>[
          'git',
          'checkout',
          revision,
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'help',
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'help',
        ]),
        const FakeCommand(command: <String>[
          flutterBin,
          'precache',
          '--android',
          '--ios',
          '--macos',
        ]),
        FakeCommand(
          command: const <String>[
            'find',
            '${checkoutsParentDirectory}flutter_conductor_checkouts/framework/bin/cache',
            '-type',
            'f',
          ],
          stdout: allBinaries.join('\n'),
        ),
        for (String bin in allBinaries)
          FakeCommand(
            command: <String>['file', '--mime-type', '-b', bin],
            stdout: 'application/x-mach-binary',
          ),
      ]);
      try {
        await runner.run(<String>[
          'codesign',
          '--$kVerify',
          '--no-$kSignatures',
          '--$kRevision',
          revision,
        ]);
      } on ConductorException {
        //print(stdio.error);
        rethrow;
      }
      expect(
        processManager.hasRemainingExpectations,
        false,
      );
    });
  });
}

class FakeCodesignCommand extends CodesignCommand {
  FakeCodesignCommand({
    @required Checkouts checkouts,
    @required this.binariesWithEntitlements,
    @required this.binariesWithoutEntitlements,
    @required Directory flutterRoot,
  }) : super(checkouts: checkouts, flutterRoot: flutterRoot);

  @override
  final List<String> binariesWithEntitlements;

  @override
  final List<String> binariesWithoutEntitlements;
}
