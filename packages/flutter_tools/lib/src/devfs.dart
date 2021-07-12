// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

import 'asset.dart';
import 'base/context.dart';
import 'base/file_system.dart';
import 'base/io.dart';
import 'base/logger.dart';
import 'base/net.dart';
import 'base/os.dart';
import 'build_info.dart';
import 'compile.dart';
import 'convert.dart' show base64, utf8;
import 'vmservice.dart';

class DevFSConfig {
  /// Should DevFS assume that symlink targets are stable?
  bool cacheSymlinks = false;
  /// Should DevFS assume that there are no symlinks to directories?
  bool noDirectorySymlinks = false;
}

DevFSConfig get devFSConfig => context.get<DevFSConfig>();

/// Common superclass for content copied to the device.
abstract class DevFSContent {
  /// Return true if this is the first time this method is called
  /// or if the entry has been modified since this method was last called.
  bool get isModified;

  /// Return true if this is the first time this method is called
  /// or if the entry has been modified after the given time
  /// or if the given time is null.
  bool isModifiedAfter(DateTime time);

  int get size;

  Future<List<int>> contentsAsBytes();

  Stream<List<int>> contentsAsStream();

  Stream<List<int>> contentsAsCompressedStream(
    OperatingSystemUtils osUtils,
  ) {
    return osUtils.gzipLevel1Stream(contentsAsStream());
  }
}

// File content to be copied to the device.
class DevFSFileContent extends DevFSContent {
  DevFSFileContent(this.file);

  final FileSystemEntity file;
  File _linkTarget;
  FileStat _fileStat;

  File _getFile() {
    if (_linkTarget != null) {
      return _linkTarget;
    }
    if (file is Link) {
      // The link target.
      return file.fileSystem.file(file.resolveSymbolicLinksSync());
    }
    return file as File;
  }

  void _stat() {
    if (_linkTarget != null) {
      // Stat the cached symlink target.
      final FileStat fileStat = _linkTarget.statSync();
      if (fileStat.type == FileSystemEntityType.notFound) {
        _linkTarget = null;
      } else {
        _fileStat = fileStat;
        return;
      }
    }
    final FileStat fileStat = file.statSync();
    _fileStat = fileStat.type == FileSystemEntityType.notFound ? null : fileStat;
    if (_fileStat != null && _fileStat.type == FileSystemEntityType.link) {
      // Resolve, stat, and maybe cache the symlink target.
      final String resolved = file.resolveSymbolicLinksSync();
      final File linkTarget = file.fileSystem.file(resolved);
      // Stat the link target.
      final FileStat fileStat = linkTarget.statSync();
      if (fileStat.type == FileSystemEntityType.notFound) {
        _fileStat = null;
        _linkTarget = null;
      } else if (devFSConfig.cacheSymlinks) {
        _linkTarget = linkTarget;
      }
    }
  }

  @override
  bool get isModified {
    final FileStat _oldFileStat = _fileStat;
    _stat();
    if (_oldFileStat == null && _fileStat == null) {
      return false;
    }
    return _oldFileStat == null || _fileStat == null || _fileStat.modified.isAfter(_oldFileStat.modified);
  }

  @override
  bool isModifiedAfter(DateTime time) {
    final FileStat _oldFileStat = _fileStat;
    _stat();
    if (_oldFileStat == null && _fileStat == null) {
      return false;
    }
    return time == null
        || _oldFileStat == null
        || _fileStat == null
        || _fileStat.modified.isAfter(time);
  }

  @override
  int get size {
    if (_fileStat == null) {
      _stat();
    }
    // Can still be null if the file wasn't found.
    return _fileStat?.size ?? 0;
  }

  @override
  Future<List<int>> contentsAsBytes() => _getFile().readAsBytes();

  @override
  Stream<List<int>> contentsAsStream() => _getFile().openRead();
}

/// Byte content to be copied to the device.
class DevFSByteContent extends DevFSContent {
  DevFSByteContent(this._bytes);

  List<int> _bytes;

  bool _isModified = true;
  DateTime _modificationTime = DateTime.now();

  List<int> get bytes => _bytes;

  set bytes(List<int> value) {
    _bytes = value;
    _isModified = true;
    _modificationTime = DateTime.now();
  }

  /// Return true only once so that the content is written to the device only once.
  @override
  bool get isModified {
    final bool modified = _isModified;
    _isModified = false;
    return modified;
  }

  @override
  bool isModifiedAfter(DateTime time) {
    return time == null || _modificationTime.isAfter(time);
  }

  @override
  int get size => _bytes.length;

  @override
  Future<List<int>> contentsAsBytes() async => _bytes;

  @override
  Stream<List<int>> contentsAsStream() =>
      Stream<List<int>>.fromIterable(<List<int>>[_bytes]);
}

/// String content to be copied to the device.
class DevFSStringContent extends DevFSByteContent {
  DevFSStringContent(String string)
    : _string = string,
      super(utf8.encode(string));

  String _string;

  String get string => _string;

  set string(String value) {
    _string = value;
    super.bytes = utf8.encode(_string);
  }

  @override
  set bytes(List<int> value) {
    string = utf8.decode(value);
  }
}

class DevFSException implements Exception {
  DevFSException(this.message, [this.error, this.stackTrace]);
  final String message;
  final dynamic error;
  final StackTrace stackTrace;

  @override
  String toString() => 'DevFSException($message, $error, $stackTrace)';
}

/// Interface responsible for syncing asset files to a development device.
abstract class DevFSWriter {
  /// Write the assets in [entries] to the target device.
  ///
  /// The keys of the map are relative from the [baseUri].
  ///
  /// Throws a [DevFSException] if the process fails to complete.
  Future<void> write(Map<Uri, DevFSContent> entries, Uri baseUri, DevFSWriter parent);
}

class _DevFSHttpWriter implements DevFSWriter {
  _DevFSHttpWriter(
    this.fsName,
    FlutterVmService serviceProtocol, {
    @required OperatingSystemUtils osUtils,
    @required HttpClient httpClient,
    @required Logger logger,
    Duration uploadRetryThrottle,
  })
    : httpAddress = serviceProtocol.httpAddress,
      _client = httpClient,
      _osUtils = osUtils,
      _uploadRetryThrottle = uploadRetryThrottle,
      _logger = logger;

  final HttpClient _client;
  final OperatingSystemUtils _osUtils;
  final Logger _logger;
  final Duration _uploadRetryThrottle;

  final String fsName;
  final Uri httpAddress;

  // 3 was chosen to try to limit the variance in the time it takes to execute
  // `await request.close()` since there is a known bug in Dart where it doesn't
  // always return a status code in response to a PUT request:
  // https://github.com/dart-lang/sdk/issues/43525.
  static const int kMaxInFlight = 3;

  int _inFlight = 0;
  Map<Uri, DevFSContent> _outstanding;
  Completer<void> _completer;

  @override
  Future<void> write(Map<Uri, DevFSContent> entries, Uri devFSBase, [DevFSWriter parent]) async {
    try {
      _client.maxConnectionsPerHost = kMaxInFlight;
      _completer = Completer<void>();
      _outstanding = Map<Uri, DevFSContent>.of(entries);
      _scheduleWrites();
      await _completer.future;
    } on SocketException catch (socketException, stackTrace) {
      _logger.printTrace('DevFS sync failed. Lost connection to device: $socketException');
      throw DevFSException('Lost connection to device.', socketException, stackTrace);
    } on Exception catch (exception, stackTrace) {
      _logger.printError('Could not update files on device: $exception');
      throw DevFSException('Sync failed', exception, stackTrace);
    }
  }

  void _scheduleWrites() {
    while ((_inFlight < kMaxInFlight) && (!_completer.isCompleted) && _outstanding.isNotEmpty) {
      final Uri deviceUri = _outstanding.keys.first;
      final DevFSContent content = _outstanding.remove(deviceUri);
      _startWrite(deviceUri, content, retry: 10);
      _inFlight += 1;
    }
    if ((_inFlight == 0) && (!_completer.isCompleted) && _outstanding.isEmpty) {
      _completer.complete();
    }
  }

  Future<void> _startWrite(
    Uri deviceUri,
    DevFSContent content, {
    int retry = 0,
  }) async {
    while(true) {
      try {
        final HttpClientRequest request = await _client.putUrl(httpAddress);
        request.headers.removeAll(HttpHeaders.acceptEncodingHeader);
        request.headers.add('dev_fs_name', fsName);
        request.headers.add('dev_fs_uri_b64', base64.encode(utf8.encode('$deviceUri')));
        final Stream<List<int>> contents = content.contentsAsCompressedStream(
          _osUtils,
        );
        await request.addStream(contents);
        // Once the bug in Dart is solved we can remove the timeout
        // (https://github.com/dart-lang/sdk/issues/43525).
        try {
          final HttpClientResponse response = await request.close().timeout(
            const Duration(seconds: 60));
          response.listen((_) {},
            onError: (dynamic error) {
              _logger.printTrace('error: $error');
            },
            cancelOnError: true,
          );
        } on TimeoutException {
          request.abort();
          // This should throw "HttpException: Request has been aborted".
          await request.done;
          // Just to be safe we rethrow the TimeoutException.
          rethrow;
        }
        break;
      } on Exception catch (error, trace) {
        if (!_completer.isCompleted) {
          _logger.printTrace('Error writing "$deviceUri" to DevFS: $error');
          if (retry > 0) {
            retry--;
            _logger.printTrace('trying again in a few - $retry more attempts left');
            await Future<void>.delayed(_uploadRetryThrottle ?? const Duration(milliseconds: 500));
            continue;
          }
          _completer.completeError(error, trace);
        }
      }
    }
    _inFlight -= 1;
    _scheduleWrites();
  }
}

// Basic statistics for DevFS update operation.
class UpdateFSReport {
  UpdateFSReport({
    bool success = false,
    int invalidatedSourcesCount = 0,
    int syncedBytes = 0,
    this.fastReassembleClassName,
  }) : _success = success,
       _invalidatedSourcesCount = invalidatedSourcesCount,
       _syncedBytes = syncedBytes;

  bool get success => _success;
  int get invalidatedSourcesCount => _invalidatedSourcesCount;
  int get syncedBytes => _syncedBytes;

  bool _success;
  String fastReassembleClassName;
  int _invalidatedSourcesCount;
  int _syncedBytes;

  void incorporateResults(UpdateFSReport report) {
    if (!report._success) {
      _success = false;
    }
    fastReassembleClassName ??= report.fastReassembleClassName;
    _invalidatedSourcesCount += report._invalidatedSourcesCount;
    _syncedBytes += report._syncedBytes;
  }
}

class DevFS {
  /// Create a [DevFS] named [fsName] for the local files in [rootDirectory].
  ///
  /// Failed uploads are retried after [uploadRetryThrottle] duration, defaults to 500ms.
  DevFS(
    FlutterVmService serviceProtocol,
    this.fsName,
    this.rootDirectory, {
    @required OperatingSystemUtils osUtils,
    @required Logger logger,
    @required FileSystem fileSystem,
    HttpClient httpClient,
    Duration uploadRetryThrottle,
  }) : _vmService = serviceProtocol,
       _logger = logger,
       _fileSystem = fileSystem,
       _httpWriter = _DevFSHttpWriter(
        fsName,
        serviceProtocol,
        osUtils: osUtils,
        logger: logger,
        uploadRetryThrottle: uploadRetryThrottle,
        httpClient: httpClient ?? ((context.get<HttpClientFactory>() == null)
          ? HttpClient()
          : context.get<HttpClientFactory>()())
      );

  final FlutterVmService _vmService;
  final _DevFSHttpWriter _httpWriter;
  final Logger _logger;
  final FileSystem _fileSystem;

  final String fsName;
  final Directory rootDirectory;
  final Set<String> assetPathsToEvict = <String>{};

  List<Uri> sources = <Uri>[];
  DateTime lastCompiled;
  DateTime _previousCompiled;
  PackageConfig lastPackageConfig;
  File _widgetCacheOutputFile;

  Uri _baseUri;
  Uri get baseUri => _baseUri;

  Uri deviceUriToHostUri(Uri deviceUri) {
    final String deviceUriString = deviceUri.toString();
    final String baseUriString = baseUri.toString();
    if (deviceUriString.startsWith(baseUriString)) {
      final String deviceUriSuffix = deviceUriString.substring(baseUriString.length);
      return rootDirectory.uri.resolve(deviceUriSuffix);
    }
    return deviceUri;
  }

  Future<Uri> create() async {
    _logger.printTrace('DevFS: Creating new filesystem on the device ($_baseUri)');
    try {
      final vm_service.Response response = await _vmService.createDevFS(fsName);
      _baseUri = Uri.parse(response.json['uri'] as String);
    } on vm_service.RPCError catch (rpcException) {
      if (rpcException.code == RPCErrorCodes.kServiceDisappeared) {
        // This can happen if the device has been disconnected, so translate to
        // a DevFSException, which the caller will handle.
        throw DevFSException('Service disconnected', rpcException);
      }
      // 1001 is kFileSystemAlreadyExists in //dart/runtime/vm/json_stream.h
      if (rpcException.code != 1001) {
        // Other RPCErrors are unexpected. Rethrow so it will hit crash
        // logging.
        rethrow;
      }
      _logger.printTrace('DevFS: Creating failed. Destroying and trying again');
      await destroy();
      final vm_service.Response response = await _vmService.createDevFS(fsName);
      _baseUri = Uri.parse(response.json['uri'] as String);
    }
    _logger.printTrace('DevFS: Created new filesystem on the device ($_baseUri)');
    return _baseUri;
  }

  Future<void> destroy() async {
    _logger.printTrace('DevFS: Deleting filesystem on the device ($_baseUri)');
    await _vmService.deleteDevFS(fsName);
    _logger.printTrace('DevFS: Deleted filesystem on the device ($_baseUri)');
  }

  /// Mark the [lastCompiled] time to the previous successful compile.
  ///
  /// Sometimes a hot reload will be rejected by the VM due to a change in the
  /// structure of the code not supporting the hot reload. In these cases,
  /// the best resolution is a hot restart. However, the resident runner
  /// will not recognize this file as having been changed since the delta
  /// will already have been accepted. Instead, reset the compile time so
  /// that the last updated files are included in subsequent compilations until
  /// a reload is accepted.
  void resetLastCompiled() {
    lastCompiled = _previousCompiled;
  }


  /// If the build method of a single widget was modified, return the widget name.
  ///
  /// If any other changes were made, or there is an error scanning the file,
  /// return `null`.
  String _checkIfSingleWidgetReloadApplied() {
    if (_widgetCacheOutputFile != null && _widgetCacheOutputFile.existsSync()) {
      final String widget = _widgetCacheOutputFile.readAsStringSync().trim();
      if (widget.isNotEmpty) {
        return widget;
      }
    }
    return null;
  }

  /// Updates files on the device.
  ///
  /// Returns the number of bytes synced.
  Future<UpdateFSReport> update({
    @required Uri mainUri,
    @required ResidentCompiler generator,
    @required bool trackWidgetCreation,
    @required String pathToReload,
    @required List<Uri> invalidatedFiles,
    @required PackageConfig packageConfig,
    @required String dillOutputPath,
    DevFSWriter devFSWriter,
    String target,
    AssetBundle bundle,
    DateTime firstBuildTime,
    bool bundleFirstUpload = false,
    bool fullRestart = false,
    String projectRootPath,
  }) async {
    assert(trackWidgetCreation != null);
    assert(generator != null);
    final DateTime candidateCompileTime = DateTime.now();
    lastPackageConfig = packageConfig;
    _widgetCacheOutputFile = _fileSystem.file('$dillOutputPath.incremental.dill.widget_cache');

    // Update modified files
    final Map<Uri, DevFSContent> dirtyEntries = <Uri, DevFSContent>{};
    int syncedBytes = 0;
    if (fullRestart) {
      generator.reset();
    }
    // On a full restart, or on an initial compile for the attach based workflow,
    // this will produce a full dill. Subsequent invocations will produce incremental
    // dill files that depend on the invalidated files.
    _logger.printTrace('Compiling dart to kernel with ${invalidatedFiles.length} updated files');

    // Await the compiler response after checking if the bundle is updated. This allows the file
    // stating to be done while waiting for the frontend_server response.
    final Future<CompilerOutput> pendingCompilerOutput = generator.recompile(
      mainUri,
      invalidatedFiles,
      outputPath: dillOutputPath,
      packageConfig: packageConfig,
    );
    if (bundle != null) {
      // The tool writes the assets into the AssetBundle working dir so that they
      // are in the same location in DevFS and the iOS simulator.
      final String assetBuildDirPrefix = _asUriPath(getAssetBuildDirectory());
      final String assetDirectory = getAssetBuildDirectory();
      bundle.entries.forEach((String archivePath, DevFSContent content) {
        // If the content is backed by a real file, isModified will file stat and return true if
        // it was modified since the last time this was called.
        if (!content.isModified || bundleFirstUpload) {
          return;
        }
        final Uri deviceUri = _fileSystem.path.toUri(_fileSystem.path.join(assetDirectory, archivePath));
        if (deviceUri.path.startsWith(assetBuildDirPrefix)) {
          archivePath = deviceUri.path.substring(assetBuildDirPrefix.length);
        }
        dirtyEntries[deviceUri] = content;
        syncedBytes += content.size;
        if (archivePath != null && !bundleFirstUpload) {
          assetPathsToEvict.add(archivePath);
        }
      });
    }
    final CompilerOutput compilerOutput = await pendingCompilerOutput;
    if (compilerOutput == null || compilerOutput.errorCount > 0) {
      return UpdateFSReport(success: false);
    }
    // Only update the last compiled time if we successfully compiled.
    _previousCompiled = lastCompiled;
    lastCompiled = candidateCompileTime;
    // list of sources that needs to be monitored are in [compilerOutput.sources]
    sources = compilerOutput.sources;
    //
    // Don't send full kernel file that would overwrite what VM already
    // started loading from.
    if (!bundleFirstUpload) {
      final String compiledBinary = compilerOutput?.outputFilename;
      if (compiledBinary != null && compiledBinary.isNotEmpty) {
        final Uri entryUri = _fileSystem.path.toUri(pathToReload);
        final DevFSFileContent content = DevFSFileContent(_fileSystem.file(compiledBinary));
        syncedBytes += content.size;
        dirtyEntries[entryUri] = content;
      }
    }
    _logger.printTrace('Updating files.');
    if (dirtyEntries.isNotEmpty) {
      await (devFSWriter ?? _httpWriter).write(dirtyEntries, _baseUri, _httpWriter);
    }
    _logger.printTrace('DevFS: Sync finished');
    return UpdateFSReport(
      success: true,
      syncedBytes: syncedBytes,
      invalidatedSourcesCount: invalidatedFiles.length,
      fastReassembleClassName: _checkIfSingleWidgetReloadApplied(),
    );
  }

  /// Converts a platform-specific file path to a platform-independent URL path.
  String _asUriPath(String filePath) => _fileSystem.path.toUri(filePath).path + '/';
}

/// An implementation of a devFS writer which copies physical files for devices
/// running on the same host.
///
/// DevFS entries which correspond to physical files are copied using [File.copySync],
/// while entries that correspond to arbitrary string/byte values are written from
/// memory.
///
/// Requires that the file system is the same for both the tool and application.
class LocalDevFSWriter implements DevFSWriter {
  LocalDevFSWriter({
    @required FileSystem fileSystem,
  }) : _fileSystem = fileSystem;

  final FileSystem _fileSystem;

  @override
  Future<void> write(Map<Uri, DevFSContent> entries, Uri baseUri, [DevFSWriter parent]) async {
    try {
      for (final Uri uri in entries.keys) {
        final DevFSContent devFSContent = entries[uri];
        final File destination = _fileSystem.file(baseUri.resolveUri(uri));
        if (!destination.parent.existsSync()) {
          destination.parent.createSync(recursive: true);
        }
        if (devFSContent is DevFSFileContent) {
          final File content = devFSContent.file as File;
          content.copySync(destination.path);
          continue;
        }
        destination.writeAsBytesSync(await devFSContent.contentsAsBytes());
      }
    } on FileSystemException catch (err) {
      throw DevFSException(err.toString());
    }
  }
}
