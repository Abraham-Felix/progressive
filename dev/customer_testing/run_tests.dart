// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as path;

import 'lib/runner.dart';

Future<void> main(List<String> arguments) async {
  exit(await run(arguments) ? 0 : 1);
}

Future<bool> run(List<String> arguments) async {
  final ArgParser argParser = ArgParser(
    allowTrailingOptions: false,
    usageLineLength: 72,
  )
    ..addOption(
      'repeat',
      defaultsTo: '1',
      help: 'How many times to run each test. Set to a high value to look for flakes.',
      valueHelp: 'count',
    )
    ..addOption(
      'shards',
      defaultsTo: '1',
      help: 'How many shards to split the tests into. Used in continuous integration.',
      valueHelp: 'count',
    )
    ..addOption(
      'shard-index',
      defaultsTo: '0',
      help: 'The current shard to run the tests with the range [0 .. shards - 1]. Used in continuous integration.',
      valueHelp: 'count',
    )
    ..addFlag(
      'skip-on-fetch-failure',
      defaultsTo: false,
      help: 'Whether to skip tests that we fail to download.',
    )
    ..addFlag(
      'skip-template',
      defaultsTo: false,
      help: 'Whether to skip tests named "template.test".',
    )
    ..addFlag(
      'verbose',
      defaultsTo: false,
      help: 'Describe what is happening in detail.',
    )
    ..addFlag(
      'help',
      defaultsTo: false,
      negatable: false,
      help: 'Print this help message.',
    );

  void printHelp() {
    print('run_tests.dart [options...] path/to/file1.test path/to/file2.test...');
    print('For details on the test registry format, see:');
    print('  https://github.com/flutter/tests/blob/master/registry/template.test');
    print('');
    print(argParser.usage);
    print('');
  }

  ArgResults parsedArguments;
  try {
    parsedArguments = argParser.parse(arguments);
  } on ArgParserException catch (error) {
    printHelp();
    print('Error: ${error.message} Use --help for usage information.');
    exit(1);
  }

  final int repeat = int.tryParse(parsedArguments['repeat'] as String);
  final bool skipOnFetchFailure = parsedArguments['skip-on-fetch-failure'] as bool;
  final bool skipTemplate = parsedArguments['skip-template'] as bool;
  final bool verbose = parsedArguments['verbose'] as bool;
  final bool help = parsedArguments['help'] as bool;
  final int numberShards = int.tryParse(parsedArguments['shards'] as String);
  final int shardIndex = int.tryParse(parsedArguments['shard-index'] as String);
  final List<File> files = parsedArguments
    .rest
    .expand((String path) => Glob(path).listFileSystemSync(const LocalFileSystem()))
    .whereType<File>()
    .where((File file) => !skipTemplate || path.basename(file.path) != 'template.test')
    .toList();

  if (help || repeat == null || files.isEmpty) {
    printHelp();
    if (verbose) {
      if (repeat == null)
        print('Error: Could not parse repeat count ("${parsedArguments['repeat']}")');
      if (parsedArguments.rest.isEmpty) {
        print('Error: No file arguments specified.');
      } else if (files.isEmpty) {
        print('Error: File arguments ("${parsedArguments.rest.join('", "')}") did not identify any real files.');
      }
    }
    return help;
  }

  if (files.length < shardIndex)
    print('Warning: There are more shards than tests. Some shards will not run any tests.');

  if (numberShards <= shardIndex) {
    print('Error: There are more shard indexes than shards.');
    return help;
  }

  return runTests(
    repeat: repeat,
    skipOnFetchFailure: skipOnFetchFailure,
    verbose: verbose,
    numberShards: numberShards,
    shardIndex: shardIndex,
    files: files,
  );
}
