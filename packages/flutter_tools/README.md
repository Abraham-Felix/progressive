# Flutter Tools

This section of the Flutter repository contains the command line developer tools
for building Flutter applications.

## Working on Flutter Tools

Be sure to follow the instructions on [CONTRIBUTING.md](../../CONTRIBUTING.md)
to set up your development environment. Further, familiarize yourself with the
[style guide](https://github.com/flutter/flutter/wiki/Style-guide-for-Flutter-repo),
which we follow.

### Setting up

First, ensure that the Dart SDK and other necessary artifacts are available by
invoking the Flutter Tools wrapper script. In this directory run:
```shell
$ flutter --version
```

### Running the Tool

To run Flutter Tools from source, in this directory run:
```shell
$ dart bin/flutter_tools.dart
```
followed by command-line arguments, as usual.


### Running the analyzer

To run the analyzer on Flutter Tools, in this directory run:
```shell
$ flutter analyze
```

### Writing tests

As with other parts of the Flutter repository, all changes in behavior [must be
tested](https://github.com/flutter/flutter/wiki/Style-guide-for-Flutter-repo#write-test-find-bug).
Tests live under the `test/` subdirectory.
- Hermetic unit tests of tool internals go under `test/general.shard`.
- Tests of tool commands go under `test/commands.shard`. Hermetic tests go under
  its `hermetic/` subdirectory. Non-hermetic tests go under its `permeable`
  sub-directory.
- Integration tests (e.g. tests that run the tool in a subprocess) go under
  `test/integration.shard`.

In general, the tests for the code in a file called `file.dart` should go in a
file called `file_test.dart` in the subdirectory that matches the behavior of
the test.

#### Using local engine builds in integration tests

The integration tests can be configured to use a specific local engine
variant by setting the `FLUTTER_LOCAL_ENGINE` environment variable to the
name of the local engine (e.g. "android_debug_unopt"). If the local engine build
requires a source path, this can be provided by setting the `FLUTTER_LOCAL_ENGINE_SRC_PATH`
environment variable. This second variable is not necessary if the `flutter` and
`engine` checkouts are in adjacent directories.

```shell
export FLUTTER_LOCAL_ENGINE=android_debug_unopt
flutter test test/integration.shard/some_test_case
```

### Running the tests

To run the tests in the `test/` directory:

```shell
$ flutter test
```

The tests in `test/integration.shard` are slower to run than the tests in
`test/general.shard`. They also require the `FLUTTER_ROOT` environment variable
to be set and pointing to the root of the Flutter SDK. To run only the tests in `test/general.shard`, in this
directory run:
```shell
$ flutter test test/general.shard
```

To run the tests in a specific file, run:
```shell
$ flutter test test/general.shard/utils_test.dart
```

### Forcing snapshot regeneration

To force the Flutter Tools snapshot to be regenerated, delete the following
files:
```shell
$ rm ../../bin/cache/flutter_tools.stamp ../../bin/cache/flutter_tools.snapshot
```
