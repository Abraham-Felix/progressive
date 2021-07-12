// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/bot_detector.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/dart/pub.dart';
import 'package:flutter_tools/src/reporting/reporting.dart';
import 'package:fake_async/fake_async.dart';

import '../../src/common.dart';
import '../../src/fake_process_manager.dart';
import '../../src/mocks.dart' as mocks;

void main() {
  setUpAll(() {
    Cache.flutterRoot = '';
  });

  testWithoutContext('Throws a tool exit if pub cannot be run', () async {
    final FakeProcessManager processManager = FakeProcessManager.any();
    final BufferLogger logger = BufferLogger.test();
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();
    processManager.excludedExecutables.add('bin/cache/dart-sdk/bin/pub');

    fileSystem.file('pubspec.yaml').createSync();

    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    await expectLater(() => pub.get(
      context: PubContext.pubGet,
      checkUpToDate: true,
    ), throwsToolExit(message: 'Your Flutter SDK download may be corrupt or missing permissions to run'));
  });

  testWithoutContext('checkUpToDate skips pub get if the package config is newer than the pubspec '
    'and the current framework version is the same as the last version', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[]);
    final BufferLogger logger = BufferLogger.test();
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('pubspec.lock').createSync();
    fileSystem.file('.dart_tool/package_config.json').createSync(recursive: true);
    fileSystem.file('.dart_tool/version').writeAsStringSync('a');
    fileSystem.file('version').writeAsStringSync('a');

    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    await pub.get(
      context: PubContext.pubGet,
      checkUpToDate: true,
    );

    expect(logger.traceText, contains('Skipping pub get: version match.'));
  });

  testWithoutContext('checkUpToDate does not skip pub get if the package config is newer than the pubspec '
    'but the current framework version is not the same as the last version', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(command: <String>[
        'bin/cache/dart-sdk/bin/pub',
        '--verbosity=warning',
        'get',
        '--no-precompile',
      ])
    ]);
    final BufferLogger logger = BufferLogger.test();
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('pubspec.lock').createSync();
    fileSystem.file('.dart_tool/package_config.json').createSync(recursive: true);
    fileSystem.file('.dart_tool/version').writeAsStringSync('a');
    fileSystem.file('version').writeAsStringSync('b');

    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    await pub.get(
      context: PubContext.pubGet,
      checkUpToDate: true,
    );

    expect(processManager, hasNoRemainingExpectations);
    expect(fileSystem.file('.dart_tool/version').readAsStringSync(), 'b');
  });

  testWithoutContext('checkUpToDate does not skip pub get if the package config is newer than the pubspec '
    'but the current framework version does not exist yet', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(command: <String>[
        'bin/cache/dart-sdk/bin/pub',
        '--verbosity=warning',
        'get',
        '--no-precompile',
      ])
    ]);
    final BufferLogger logger = BufferLogger.test();
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('pubspec.lock').createSync();
    fileSystem.file('.dart_tool/package_config.json').createSync(recursive: true);
    fileSystem.file('version').writeAsStringSync('b');

    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    await pub.get(
      context: PubContext.pubGet,
      checkUpToDate: true,
    );

    expect(processManager, hasNoRemainingExpectations);
    expect(fileSystem.file('.dart_tool/version').readAsStringSync(), 'b');
  });

  testWithoutContext('checkUpToDate does not skip pub get if the package config does not exist', () async {
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      FakeCommand(command: const <String>[
        'bin/cache/dart-sdk/bin/pub',
        '--verbosity=warning',
        'get',
        '--no-precompile',
      ], onRun: () {
        fileSystem.file('.dart_tool/package_config.json').createSync(recursive: true);
      })
    ]);
    final BufferLogger logger = BufferLogger.test();

    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('pubspec.lock').createSync();
    fileSystem.file('version').writeAsStringSync('b');

    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    await pub.get(
      context: PubContext.pubGet,
      checkUpToDate: true,
    );

    expect(processManager, hasNoRemainingExpectations);
    expect(fileSystem.file('.dart_tool/version').readAsStringSync(), 'b');
  });

  testWithoutContext('checkUpToDate does not skip pub get if the pubspec.lock does not exist', () async {
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(command: <String>[
        'bin/cache/dart-sdk/bin/pub',
        '--verbosity=warning',
        'get',
        '--no-precompile',
      ]),
    ]);
    final BufferLogger logger = BufferLogger.test();

    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('version').writeAsStringSync('b');
    fileSystem.file('.dart_tool/package_config.json').createSync(recursive: true);
    fileSystem.file('.dart_tool/version').writeAsStringSync('b');

    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    await pub.get(
      context: PubContext.pubGet,
      checkUpToDate: true,
    );

    expect(processManager, hasNoRemainingExpectations);
    expect(fileSystem.file('.dart_tool/version').readAsStringSync(), 'b');
  });

  testWithoutContext('checkUpToDate does not skip pub get if the package config is older that the pubspec', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(command: <String>[
        'bin/cache/dart-sdk/bin/pub',
        '--verbosity=warning',
        'get',
        '--no-precompile',
      ])
    ]);
    final BufferLogger logger = BufferLogger.test();
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('pubspec.lock').createSync();
    fileSystem.file('.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..setLastModifiedSync(DateTime(1991));
    fileSystem.file('version').writeAsStringSync('b');

    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    await pub.get(
      context: PubContext.pubGet,
      checkUpToDate: true,
    );

    expect(processManager, hasNoRemainingExpectations);
    expect(fileSystem.file('.dart_tool/version').readAsStringSync(), 'b');
  });

  testWithoutContext('checkUpToDate does not skip pub get if the pubspec.lock is older that the pubspec', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(command: <String>[
        'bin/cache/dart-sdk/bin/pub',
        '--verbosity=warning',
        'get',
        '--no-precompile',
      ])
    ]);
    final BufferLogger logger = BufferLogger.test();
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();

    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('pubspec.lock')
      ..createSync()
      ..setLastModifiedSync(DateTime(1991));
    fileSystem.file('.dart_tool/package_config.json')
      .createSync(recursive: true);
    fileSystem.file('version').writeAsStringSync('b');
    fileSystem.file('.dart_tool/version').writeAsStringSync('b');

    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    await pub.get(
      context: PubContext.pubGet,
      checkUpToDate: true,
    );

    expect(processManager, hasNoRemainingExpectations);
    expect(fileSystem.file('.dart_tool/version').readAsStringSync(), 'b');
  });

  testWithoutContext('pub get 69', () async {
    String error;

    final MockProcessManager processMock = MockProcessManager(69);
    final BufferLogger logger = BufferLogger.test();
    final FileSystem fileSystem = MemoryFileSystem.test();
    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: logger,
      processManager: processMock,
      usage: TestUsage(),
      platform: FakePlatform(
        environment: const <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo(),
    );

    FakeAsync().run((FakeAsync time) {
      expect(processMock.lastPubEnvironment, isNull);
      expect(logger.statusText, '');
      pub.get(context: PubContext.flutterTests).then((void value) {
        error = 'test completed unexpectedly';
      }, onError: (dynamic thrownError) {
        error = 'test failed unexpectedly: $thrownError';
      });
      time.elapse(const Duration(milliseconds: 500));
      expect(logger.statusText,
        'Running "flutter pub get" in /...\n'
        'pub get failed (server unavailable) -- attempting retry 1 in 1 second...\n',
      );
      expect(processMock.lastPubEnvironment, contains('flutter_cli:flutter_tests'));
      expect(processMock.lastPubCache, isNull);
      time.elapse(const Duration(milliseconds: 500));
      expect(logger.statusText,
        'Running "flutter pub get" in /...\n'
        'pub get failed (server unavailable) -- attempting retry 1 in 1 second...\n'
        'pub get failed (server unavailable) -- attempting retry 2 in 2 seconds...\n',
      );
      time.elapse(const Duration(seconds: 1));
      expect(logger.statusText,
        'Running "flutter pub get" in /...\n'
        'pub get failed (server unavailable) -- attempting retry 1 in 1 second...\n'
        'pub get failed (server unavailable) -- attempting retry 2 in 2 seconds...\n',
      );
      time.elapse(const Duration(seconds: 100)); // from t=0 to t=100
      expect(logger.statusText,
        'Running "flutter pub get" in /...\n'
        'pub get failed (server unavailable) -- attempting retry 1 in 1 second...\n'
        'pub get failed (server unavailable) -- attempting retry 2 in 2 seconds...\n'
        'pub get failed (server unavailable) -- attempting retry 3 in 4 seconds...\n' // at t=1
        'pub get failed (server unavailable) -- attempting retry 4 in 8 seconds...\n' // at t=5
        'pub get failed (server unavailable) -- attempting retry 5 in 16 seconds...\n' // at t=13
        'pub get failed (server unavailable) -- attempting retry 6 in 32 seconds...\n' // at t=29
        'pub get failed (server unavailable) -- attempting retry 7 in 64 seconds...\n', // at t=61
      );
      time.elapse(const Duration(seconds: 200)); // from t=0 to t=200
      expect(logger.statusText,
        'Running "flutter pub get" in /...\n'
        'pub get failed (server unavailable) -- attempting retry 1 in 1 second...\n'
        'pub get failed (server unavailable) -- attempting retry 2 in 2 seconds...\n'
        'pub get failed (server unavailable) -- attempting retry 3 in 4 seconds...\n'
        'pub get failed (server unavailable) -- attempting retry 4 in 8 seconds...\n'
        'pub get failed (server unavailable) -- attempting retry 5 in 16 seconds...\n'
        'pub get failed (server unavailable) -- attempting retry 6 in 32 seconds...\n'
        'pub get failed (server unavailable) -- attempting retry 7 in 64 seconds...\n'
        'pub get failed (server unavailable) -- attempting retry 8 in 64 seconds...\n' // at t=39
        'pub get failed (server unavailable) -- attempting retry 9 in 64 seconds...\n' // at t=103
        'pub get failed (server unavailable) -- attempting retry 10 in 64 seconds...\n', // at t=167
      );
    });
    expect(logger.errorText, isEmpty);
    expect(error, isNull);
  });

  testWithoutContext('pub get 66 shows message from pub', () async {
    final BufferLogger logger = BufferLogger.test();
    final FileSystem fileSystem = MemoryFileSystem.test();
    final Pub pub = Pub(
      platform: FakePlatform(environment: const <String, String>{}),
      fileSystem: fileSystem,
      logger: logger,
      usage: TestUsage(),
      botDetector: const BotDetectorAlwaysNo(),
      processManager: MockProcessManager(66, stderr: 'err1\nerr2\nerr3\n', stdout: 'out1\nout2\nout3\n'),
    );
    try {
      await pub.get(context: PubContext.flutterTests);
      throw AssertionError('pubGet did not fail');
    } on ToolExit catch (error) {
      expect(error.message, 'pub get failed (66; err3)');
    }
    expect(logger.statusText,
      'Running "flutter pub get" in /...\n'
      'out1\n'
      'out2\n'
      'out3\n'
    );
    expect(logger.errorText,
      'err1\n'
      'err2\n'
      'err3\n'
    );
  });

  testWithoutContext('pub cache in root is used', () async {
    String error;
    final MockProcessManager processMock = MockProcessManager(69);
    final FileSystem fileSystem = MemoryFileSystem.test();
    fileSystem.directory(Cache.flutterRoot).childDirectory('.pub-cache').createSync();

    final Pub pub = Pub(
      platform: FakePlatform(environment: const <String, String>{}),
      usage: TestUsage(),
      fileSystem: fileSystem,
      logger: BufferLogger.test(),
      processManager: processMock,
      botDetector: const BotDetectorAlwaysNo(),
    );

    FakeAsync().run((FakeAsync time) {
      expect(processMock.lastPubEnvironment, isNull);
      expect(processMock.lastPubCache, isNull);
      pub.get(context: PubContext.flutterTests).then((void value) {
        error = 'test completed unexpectedly';
      }, onError: (dynamic thrownError) {
        error = 'test failed unexpectedly: $thrownError';
      });
      time.elapse(const Duration(milliseconds: 500));

      expect(processMock.lastPubCache, equals(fileSystem.path.join(Cache.flutterRoot, '.pub-cache')));
      expect(error, isNull);
    });
  });

  testWithoutContext('pub cache in environment is used', () async {
    final FileSystem fileSystem = MemoryFileSystem.test();
    fileSystem.directory('custom/pub-cache/path').createSync(recursive: true);
    final MockProcessManager processMock = MockProcessManager(69);
    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: BufferLogger.test(),
      processManager: processMock,
      usage: TestUsage(),
      botDetector: const BotDetectorAlwaysNo(),
      platform: FakePlatform(
        environment: const <String, String>{
          'PUB_CACHE': 'custom/pub-cache/path',
        },
      ),
    );

    FakeAsync().run((FakeAsync time) {
      expect(processMock.lastPubEnvironment, isNull);
      expect(processMock.lastPubCache, isNull);

      String error;
      pub.get(context: PubContext.flutterTests).then((void value) {
        error = 'test completed unexpectedly';
      }, onError: (dynamic thrownError) {
        error = 'test failed unexpectedly: $thrownError';
      });
      time.elapse(const Duration(milliseconds: 500));

      expect(processMock.lastPubCache, equals('custom/pub-cache/path'));
      expect(error, isNull);
    });
  });

  testWithoutContext('analytics sent on success', () async {
    final FileSystem fileSystem = MemoryFileSystem.test();
    final TestUsage usage = TestUsage();
    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: BufferLogger.test(),
      processManager: MockProcessManager(0),
      botDetector: const BotDetectorAlwaysNo(),
      usage: usage,
      platform: FakePlatform(
        environment: const <String, String>{
          'PUB_CACHE': 'custom/pub-cache/path',
        }
      ),
    );
    fileSystem.file('version').createSync();
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"configVersion": 2,"packages": []}');

    await pub.get(
      context: PubContext.flutterTests,
      generateSyntheticPackage: true,
    );
    expect(usage.events, contains(
      const TestUsageEvent('pub-result', 'flutter-tests', label: 'success'),
    ));
  });

  testWithoutContext('package_config_subset file is generated from packages and not timestamp', () async {
    final FileSystem fileSystem = MemoryFileSystem.test();
    final TestUsage usage = TestUsage();
    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: BufferLogger.test(),
      processManager: MockProcessManager(0),
      botDetector: const BotDetectorAlwaysNo(),
      usage: usage,
      platform: FakePlatform(
        environment: const <String, String>{
          'PUB_CACHE': 'custom/pub-cache/path',
        }
      ),
    );
    fileSystem.file('version').createSync();
    fileSystem.file('pubspec.yaml').createSync();
    fileSystem.file('.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
      {"configVersion": 2,"packages": [
        {
          "name": "flutter_tools",
          "rootUri": "../",
          "packageUri": "lib/",
          "languageVersion": "2.7"
        }
      ],"generated":"some-time"}
''');

    await pub.get(
      context: PubContext.flutterTests,
      generateSyntheticPackage: true,
    );

    expect(
      fileSystem.file('.dart_tool/package_config_subset').readAsStringSync(),
      'flutter_tools\n'
      '2.7\n'
      'file:///\n'
      'file:///lib/\n'
      '2\n',
    );
  });

  testWithoutContext('analytics sent on failure', () async {
    final FileSystem fileSystem = MemoryFileSystem.test();
    fileSystem.directory('custom/pub-cache/path').createSync(recursive: true);
    final TestUsage usage = TestUsage();
    final Pub pub = Pub(
      usage: usage,
      fileSystem: fileSystem,
      logger: BufferLogger.test(),
      processManager: MockProcessManager(1),
      botDetector: const BotDetectorAlwaysNo(),
      platform: FakePlatform(
        environment: const <String, String>{
          'PUB_CACHE': 'custom/pub-cache/path',
        },
      ),
    );
    try {
      await pub.get(context: PubContext.flutterTests);
    } on ToolExit {
      // Ignore.
    }

    expect(usage.events, contains(
      const TestUsageEvent('pub-result', 'flutter-tests', label: 'failure'),
    ));
  });

  testWithoutContext('analytics sent on failed version solve', () async {
    final TestUsage usage = TestUsage();
    final FileSystem fileSystem = MemoryFileSystem.test();
    final Pub pub = Pub(
      fileSystem: fileSystem,
      logger: BufferLogger.test(),
      processManager: MockProcessManager(
        1,
        stderr: 'version solving failed',
      ),
      platform: FakePlatform(
        environment: <String, String>{
          'PUB_CACHE': 'custom/pub-cache/path',
        },
      ),
      usage: usage,
      botDetector: const BotDetectorAlwaysNo(),
    );
    fileSystem.file('pubspec.yaml').writeAsStringSync('name: foo');

    try {
      await pub.get(context: PubContext.flutterTests);
    } on ToolExit {
      // Ignore.
    }

    expect(usage.events, contains(
      const TestUsageEvent('pub-result', 'flutter-tests', label: 'version-solving-failed'),
    ));
  });

  testWithoutContext('Pub error handling', () async {
    final BufferLogger logger = BufferLogger.test();
    final MemoryFileSystem fileSystem = MemoryFileSystem.test();
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      FakeCommand(
        command: const <String>[
          'bin/cache/dart-sdk/bin/pub',
          '--verbosity=warning',
          'get',
          '--no-precompile',
        ],
        onRun: () {
          fileSystem.file('.dart_tool/package_config.json')
            .setLastModifiedSync(DateTime(2002));
        }
      ),
      const FakeCommand(
        command: <String>[
          'bin/cache/dart-sdk/bin/pub',
          '--verbosity=warning',
          'get',
          '--no-precompile',
        ],
      ),
      FakeCommand(
        command: const <String>[
          'bin/cache/dart-sdk/bin/pub',
          '--verbosity=warning',
          'get',
          '--no-precompile',
        ],
        onRun: () {
          fileSystem.file('pubspec.yaml')
            .setLastModifiedSync(DateTime(2002));
        }
      ),
      const FakeCommand(
        command: <String>[
          'bin/cache/dart-sdk/bin/pub',
          '--verbosity=warning',
          'get',
          '--no-precompile',
        ],
      ),
    ]);
    final Pub pub = Pub(
      usage: TestUsage(),
      fileSystem: fileSystem,
      logger: logger,
      processManager: processManager,
      platform: FakePlatform(
        operatingSystem: 'linux', // so that the command executed is consistent
        environment: <String, String>{},
      ),
      botDetector: const BotDetectorAlwaysNo()
    );

    fileSystem.file('version').createSync();
    // the good scenario: .packages is old, pub updates the file.
    fileSystem.file('.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..setLastModifiedSync(DateTime(2000));
    fileSystem.file('pubspec.yaml')
      ..createSync()
      ..setLastModifiedSync(DateTime(2001));
    await pub.get(context: PubContext.flutterTests); // pub sets date of .packages to 2002

    expect(logger.statusText, 'Running "flutter pub get" in /...\n');
    expect(logger.errorText, isEmpty);
    expect(fileSystem.file('pubspec.yaml').lastModifiedSync(), DateTime(2001)); // because nothing should touch it
    logger.clear();

    // bad scenario 1: pub doesn't update file; doesn't matter, because we do instead
    fileSystem.file('.dart_tool/package_config.json')
      .setLastModifiedSync(DateTime(2000));
    fileSystem.file('pubspec.yaml')
      .setLastModifiedSync(DateTime(2001));
    await pub.get(context: PubContext.flutterTests); // pub does nothing

    expect(logger.statusText, 'Running "flutter pub get" in /...\n');
    expect(logger.errorText, isEmpty);
    expect(fileSystem.file('pubspec.yaml').lastModifiedSync(), DateTime(2001)); // because nothing should touch it
    logger.clear();
  });
}

class BotDetectorAlwaysNo implements BotDetector {
  const BotDetectorAlwaysNo();

  @override
  Future<bool> get isRunningOnBot async => false;
}

typedef StartCallback = void Function(List<dynamic> command);

class MockProcessManager implements ProcessManager {
  MockProcessManager(this.fakeExitCode, {
    this.stdout = '',
    this.stderr = '',
  });

  final int fakeExitCode;
  final String stdout;
  final String stderr;

  String lastPubEnvironment;
  String lastPubCache;

  @override
  Future<Process> start(
    List<dynamic> command, {
    String workingDirectory,
    Map<String, String> environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    lastPubEnvironment = environment['PUB_ENVIRONMENT'];
    lastPubCache = environment['PUB_CACHE'];
    return Future<Process>.value(mocks.createMockProcess(
      exitCode: fakeExitCode,
      stdout: stdout,
      stderr: stderr,
    ));
  }

  @override
  bool canRun(dynamic executable, {String workingDirectory}) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
