// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show LineSplitter, json, utf8;
import 'dart:io';
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import 'package:flutter_devicelab/framework/adb.dart';
import 'package:flutter_devicelab/framework/framework.dart';
import 'package:flutter_devicelab/framework/host_agent.dart';
import 'package:flutter_devicelab/framework/task_result.dart';
import 'package:flutter_devicelab/framework/utils.dart';

/// Must match flutter_driver/lib/src/common.dart.
///
/// Redefined here to avoid taking a dependency on flutter_driver.
String _testOutputDirectory(String testDirectory) {
  return Platform.environment['FLUTTER_TEST_OUTPUTS_DIR'] ?? '$testDirectory/build';
}

TaskFunction createComplexLayoutScrollPerfTest({bool measureCpuGpu = true}) {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/complex_layout',
    'test_driver/scroll_perf.dart',
    'complex_layout_scroll_perf',
    measureCpuGpu: measureCpuGpu,
  ).run;
}

TaskFunction createTilesScrollPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/complex_layout',
    'test_driver/scroll_perf.dart',
    'tiles_scroll_perf',
  ).run;
}

TaskFunction createUiKitViewScrollPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/platform_views_layout',
    'test_driver/uikit_view_scroll_perf.dart',
    'platform_views_scroll_perf',
    testDriver: 'test_driver/scroll_perf_test.dart',
    needsFullTimeline: false,
  ).run;
}

TaskFunction createAndroidTextureScrollPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/platform_views_layout',
    'test_driver/android_view_scroll_perf.dart',
    'platform_views_scroll_perf',
    testDriver: 'test_driver/scroll_perf_test.dart',
  ).run;
}

TaskFunction createAndroidViewScrollPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/platform_views_layout_hybrid_composition',
    'test_driver/android_view_scroll_perf.dart',
    'platform_views_scroll_perf_hybrid_composition',
    testDriver: 'test_driver/scroll_perf_test.dart',
  ).run;
}

TaskFunction createHomeScrollPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/integration_tests/flutter_gallery',
    'test_driver/scroll_perf.dart',
    'home_scroll_perf',
  ).run;
}

TaskFunction createCullOpacityPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'cull_opacity_perf',
    testDriver: 'test_driver/cull_opacity_perf_test.dart',
  ).run;
}

TaskFunction createCullOpacityPerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/cull_opacity_perf_e2e.dart',
  ).run;
}

TaskFunction createCubicBezierPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'cubic_bezier_perf',
    testDriver: 'test_driver/cubic_bezier_perf_test.dart',
  ).run;
}

TaskFunction createCubicBezierPerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/cubic_bezier_perf_e2e.dart',
  ).run;
}

TaskFunction createCubicBezierPerfSkSlWarmupE2ETest() {
  return PerfTestWithSkSL.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/cubic_bezier_perf_e2e.dart',
  ).run;
}

TaskFunction createCubicBezierPerfSkSLWarmupTest() {
  return PerfTestWithSkSL(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'cubic_bezier_perf',
    testDriver: 'test_driver/cubic_bezier_perf_test.dart',
  ).run;
}

TaskFunction createFlutterGalleryTransitionsPerfSkSLWarmupTest() {
  return PerfTestWithSkSL(
    '${flutterDirectory.path}/dev/integration_tests/flutter_gallery',
    'test_driver/transitions_perf.dart',
    'transitions',
  ).run;
}

TaskFunction createFlutterGalleryTransitionsPerfSkSLWarmupE2ETest() {
  return PerfTestWithSkSL.e2e(
    '${flutterDirectory.path}/dev/integration_tests/flutter_gallery',
    'test_driver/transitions_perf_e2e.dart',
    testDriver: 'test_driver/transitions_perf_e2e_test.dart',
  ).run;
}

TaskFunction createBackdropFilterPerfTest({bool measureCpuGpu = true}) {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'backdrop_filter_perf',
    measureCpuGpu: measureCpuGpu,
    testDriver: 'test_driver/backdrop_filter_perf_test.dart',
    saveTraceFile: true,
  ).run;
}

TaskFunction createAnimationWithMicrotasksPerfTest({bool measureCpuGpu = true}) {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'animation_with_microtasks_perf',
    measureCpuGpu: measureCpuGpu,
    testDriver: 'test_driver/animation_with_microtasks_perf_test.dart',
    saveTraceFile: true,
  ).run;
}

TaskFunction createBackdropFilterPerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/backdrop_filter_perf_e2e.dart',
  ).run;
}

TaskFunction createPostBackdropFilterPerfTest({bool measureCpuGpu = true}) {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'post_backdrop_filter_perf',
    measureCpuGpu: measureCpuGpu,
    testDriver: 'test_driver/post_backdrop_filter_perf_test.dart',
    saveTraceFile: true,
  ).run;
}

TaskFunction createSimpleAnimationPerfTest({bool measureCpuGpu = true}) {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'simple_animation_perf',
    measureCpuGpu: measureCpuGpu,
    testDriver: 'test_driver/simple_animation_perf_test.dart',
    saveTraceFile: true,
  ).run;
}

TaskFunction createAnimatedPlaceholderPerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/animated_placeholder_perf_e2e.dart',
  ).run;
}

TaskFunction createPictureCachePerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'picture_cache_perf',
    testDriver: 'test_driver/picture_cache_perf_test.dart',
  ).run;
}

TaskFunction createPictureCachePerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/picture_cache_perf_e2e.dart',
  ).run;
}

TaskFunction createFlutterGalleryStartupTest() {
  return StartupTest(
    '${flutterDirectory.path}/dev/integration_tests/flutter_gallery',
  ).run;
}

TaskFunction createComplexLayoutStartupTest() {
  return StartupTest(
    '${flutterDirectory.path}/dev/benchmarks/complex_layout',
  ).run;
}

TaskFunction createFlutterGalleryCompileTest() {
  return CompileTest('${flutterDirectory.path}/dev/integration_tests/flutter_gallery').run;
}

TaskFunction createHelloWorldCompileTest() {
  return CompileTest('${flutterDirectory.path}/examples/hello_world', reportPackageContentSizes: true).run;
}

TaskFunction createWebCompileTest() {
  return const WebCompileTest().run;
}

TaskFunction createComplexLayoutCompileTest() {
  return CompileTest('${flutterDirectory.path}/dev/benchmarks/complex_layout').run;
}

TaskFunction createFlutterViewStartupTest() {
  return StartupTest(
      '${flutterDirectory.path}/examples/flutter_view',
      reportMetrics: false,
  ).run;
}

TaskFunction createPlatformViewStartupTest() {
  return StartupTest(
    '${flutterDirectory.path}/examples/platform_view',
    reportMetrics: false,
  ).run;
}

TaskFunction createBasicMaterialCompileTest() {
  return () async {
    const String sampleAppName = 'sample_flutter_app';
    final Directory sampleDir = dir('${Directory.systemTemp.path}/$sampleAppName');

    rmTree(sampleDir);

    await inDirectory<void>(Directory.systemTemp, () async {
      await flutter('create', options: <String>['--template=app', sampleAppName]);
    });

    if (!sampleDir.existsSync())
      throw 'Failed to create default Flutter app in ${sampleDir.path}';

    return CompileTest(sampleDir.path).run();
  };
}

TaskFunction createTextfieldPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'textfield_perf',
    testDriver: 'test_driver/textfield_perf_test.dart',
  ).run;
}

TaskFunction createTextfieldPerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/textfield_perf_e2e.dart',
  ).run;
}

TaskFunction createStackSizeTest() {
  final String testDirectory =
      '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks';
  const String testTarget = 'test_driver/run_app.dart';
  const String testDriver = 'test_driver/stack_size_perf_test.dart';
  return () {
    return inDirectory<TaskResult>(testDirectory, () async {
      final Device device = await devices.workingDevice;
      await device.unlock();
      final String deviceId = device.deviceId;
      await flutter('packages', options: <String>['get']);

      await flutter('drive', options: <String>[
        '--no-android-gradle-daemon',
        '-v',
        '--verbose-system-logs',
        '--profile',
        '-t', testTarget,
        '--driver', testDriver,
        '-d',
        deviceId,
        '--screenshot',
        hostAgent.dumpDirectory.path,
      ]);
      final Map<String, dynamic> data = json.decode(
        file('${_testOutputDirectory(testDirectory)}/stack_size.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final Map<String, dynamic> result = <String, dynamic>{
        'stack_size_per_nesting_level': data['stack_size'],
      };
      return TaskResult.success(
        result,
        benchmarkScoreKeys: result.keys.toList(),
      );
    });
  };
}

TaskFunction createFullscreenTextfieldPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'fullscreen_textfield_perf',
    testDriver: 'test_driver/fullscreen_textfield_perf_test.dart',
  ).run;
}

TaskFunction createFullscreenTextfieldPerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/fullscreen_textfield_perf_e2e.dart',
  ).run;
}

TaskFunction createColorFilterAndFadePerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'color_filter_and_fade_perf',
    testDriver: 'test_driver/color_filter_and_fade_perf_test.dart',
    saveTraceFile: true,
  ).run;
}

TaskFunction createColorFilterAndFadePerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/color_filter_and_fade_perf_e2e.dart',
  ).run;
}

TaskFunction createFadingChildAnimationPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'fading_child_animation_perf',
    testDriver: 'test_driver/fading_child_animation_perf_test.dart',
    saveTraceFile: true,
  ).run;
}

TaskFunction createImageFilteredTransformAnimationPerfTest() {
  return PerfTest(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test_driver/run_app.dart',
    'imagefiltered_transform_animation_perf',
    testDriver: 'test_driver/imagefiltered_transform_animation_perf_test.dart',
    saveTraceFile: true,
  ).run;
}

TaskFunction createsMultiWidgetConstructPerfE2ETest() {
  return PerfTest.e2e(
    '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks',
    'test/multi_widget_construction_perf_e2e.dart',
  ).run;
}

TaskFunction createsScrollSmoothnessPerfTest() {
  final String testDirectory =
      '${flutterDirectory.path}/dev/benchmarks/complex_layout';
  const String testTarget = 'test/measure_scroll_smoothness.dart';
  return () {
    return inDirectory<TaskResult>(testDirectory, () async {
      final Device device = await devices.workingDevice;
      await device.unlock();
      final String deviceId = device.deviceId;
      await flutter('packages', options: <String>['get']);

      await flutter('drive', options: <String>[
        '--no-android-gradle-daemon',
        '-v',
        '--verbose-system-logs',
        '--profile',
        '-t', testTarget,
        '-d',
        deviceId,
        '--screenshot',
        hostAgent.dumpDirectory.path,
      ]);
      final Map<String, dynamic> data = json.decode(
        file('${_testOutputDirectory(testDirectory)}/scroll_smoothness_test.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final Map<String, dynamic> result = <String, dynamic>{};
      void addResult(dynamic data, String suffix) {
        assert(data is Map<String, dynamic>);
        const List<String> metricKeys = <String>[
          'janky_count',
          'average_abs_jerk',
          'dropped_frame_count',
        ];
        for (final String key in metricKeys) {
          result[key+suffix] = data[key];
        }
      }
      addResult(data['resample on with 90Hz input'], '_with_resampler_90Hz');
      addResult(data['resample on with 59Hz input'], '_with_resampler_59Hz');
      addResult(data['resample off with 90Hz input'], '_without_resampler_90Hz');
      addResult(data['resample off with 59Hz input'], '_without_resampler_59Hz');

      return TaskResult.success(
        result,
        benchmarkScoreKeys: result.keys.toList(),
      );
    });
  };
}

TaskFunction createFramePolicyIntegrationTest() {
  final String testDirectory =
      '${flutterDirectory.path}/dev/benchmarks/macrobenchmarks';
  const String testTarget = 'test/frame_policy.dart';
  return () {
    return inDirectory<TaskResult>(testDirectory, () async {
      final Device device = await devices.workingDevice;
      await device.unlock();
      final String deviceId = device.deviceId;
      await flutter('packages', options: <String>['get']);

      await flutter('drive', options: <String>[
        '--no-android-gradle-daemon',
        '-v',
        '--verbose-system-logs',
        '--profile',
        '-t', testTarget,
        '-d',
        deviceId,
        '--screenshot',
        hostAgent.dumpDirectory.path,
      ]);
      final Map<String, dynamic> data = json.decode(
        file('${_testOutputDirectory(testDirectory)}/frame_policy_event_delay.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Map<String, dynamic> fullLiveData = data['fullyLive'] as Map<String, dynamic>;
      final Map<String, dynamic> benchmarkLiveData = data['benchmarkLive'] as Map<String, dynamic>;
      final Map<String, dynamic> dataFormated = <String, dynamic>{
        'average_delay_fullyLive_millis':
          fullLiveData['average_delay_millis'],
        'average_delay_benchmarkLive_millis':
          benchmarkLiveData['average_delay_millis'],
        '90th_percentile_delay_fullyLive_millis':
          fullLiveData['90th_percentile_delay_millis'],
        '90th_percentile_delay_benchmarkLive_millis':
          benchmarkLiveData['90th_percentile_delay_millis'],
      };

      return TaskResult.success(
        dataFormated,
        benchmarkScoreKeys: dataFormated.keys.toList(),
      );
    });
  };
}

Map<String, dynamic> _average(List<Map<String, dynamic>> results, int iterations) {
  final Map<String, dynamic> tally = <String, dynamic>{};
  for (final Map<String, dynamic> item in results) {
    item.forEach((String key, dynamic value) {
      if (tally.containsKey(key)) {
        tally[key] = (tally[key] as int) + (value as int);
      } else {
        tally[key] = value;
      }
    });
  }
  tally.forEach((String key, dynamic value) {
    tally[key] = (value as int) ~/ iterations;
  });
  return tally;
}

/// Measure application startup performance.
class StartupTest {
  const StartupTest(this.testDirectory, { this.reportMetrics = true });

  final String testDirectory;
  final bool reportMetrics;

  Future<TaskResult> run() async {
    return inDirectory<TaskResult>(testDirectory, () async {
      final Device device = await devices.workingDevice;
      const int iterations = 5;
      final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];

      section('Building application');
      String applicationBinaryPath;
      switch (deviceOperatingSystem) {
        case DeviceOperatingSystem.android:
          await flutter('build', options: <String>[
            'apk',
            '-v',
            '--profile',
            '--target-platform=android-arm,android-arm64',
          ]);
          applicationBinaryPath = '$testDirectory/build/app/outputs/flutter-apk/app-profile.apk';
          break;
        case DeviceOperatingSystem.androidArm:
          await flutter('build', options: <String>[
            'apk',
            '-v',
            '--profile',
            '--target-platform=android-arm',
          ]);
          applicationBinaryPath = '$testDirectory/build/app/outputs/flutter-apk/app-profile.apk';
          break;
        case DeviceOperatingSystem.androidArm64:
          await flutter('build', options: <String>[
            'apk',
            '-v',
            '--profile',
            '--target-platform=android-arm64',
          ]);
          applicationBinaryPath = '$testDirectory/build/app/outputs/flutter-apk/app-profile.apk';
          break;
        case DeviceOperatingSystem.ios:
          await flutter('build', options: <String>[
            'ios',
             '-v',
            '--profile',
          ]);
          applicationBinaryPath = _findIosAppInBuildDirectory('$testDirectory/build/ios/iphoneos');
          break;
        case DeviceOperatingSystem.fuchsia:
        case DeviceOperatingSystem.fake:
          break;
      }

      const int maxFailures = 3;
      int currentFailures = 0;
      for (int i = 0; i < iterations; i += 1) {
        final int result = await flutter('run', options: <String>[
          '--no-android-gradle-daemon',
          '--no-publish-port',
          '--verbose',
          '--profile',
          '--trace-startup',
          '-d',
          device.deviceId,
          if (applicationBinaryPath != null)
            '--use-application-binary=$applicationBinaryPath',
         ], canFail: true);
        if (result == 0) {
          final Map<String, dynamic> data = json.decode(
            file('${_testOutputDirectory(testDirectory)}/start_up_info.json').readAsStringSync(),
          ) as Map<String, dynamic>;
          results.add(data);
        } else {
          currentFailures += 1;
          await flutter(
            'screenshot',
            options: <String>[
              '-d',
              device.deviceId,
              '--out',
              hostAgent.dumpDirectory.childFile('screenshot_startup_failure_$currentFailures.png').path,
            ],
            canFail: true,
          );
          i -= 1;
          if (currentFailures == maxFailures) {
            return TaskResult.failure('Application failed to start $maxFailures times');
          }
        }

        await flutter('install', options: <String>[
          '--uninstall-only',
          '-d',
          device.deviceId,
        ]);
      }

      final Map<String, dynamic> averageResults = _average(results, iterations);

      if (!reportMetrics)
        return TaskResult.success(averageResults);

      return TaskResult.success(averageResults, benchmarkScoreKeys: <String>[
        'timeToFirstFrameMicros',
        'timeToFirstFrameRasterizedMicros',
      ]);
    });
  }
}

/// Measures application runtime performance, specifically per-frame
/// performance.
class PerfTest {
  const PerfTest(
    this.testDirectory,
    this.testTarget,
    this.timelineFileName, {
    this.measureCpuGpu = true,
    this.measureMemory = true,
    this.saveTraceFile = false,
    this.testDriver,
    this.needsFullTimeline = true,
    this.benchmarkScoreKeys,
    this.dartDefine = '',
    String resultFilename,
  }): _resultFilename = resultFilename;

  const PerfTest.e2e(
    this.testDirectory,
    this.testTarget, {
    this.measureCpuGpu = false,
    this.measureMemory = false,
    this.testDriver =  'test_driver/e2e_test.dart',
    this.needsFullTimeline = false,
    this.benchmarkScoreKeys = _kCommonScoreKeys,
    this.dartDefine = '',
    String resultFilename = 'e2e_perf_summary',
  }) : saveTraceFile = false, timelineFileName = null, _resultFilename = resultFilename;

  /// The directory where the app under test is defined.
  final String testDirectory;
  /// The main entry-point file of the application, as run on the device.
  final String testTarget;
  // The prefix name of the filename such as `<timelineFileName>.timeline_summary.json`.
  final String timelineFileName;
  String get traceFilename => '$timelineFileName.timeline';
  String get resultFilename => _resultFilename ?? '$timelineFileName.timeline_summary';
  final String _resultFilename;
  /// The test file to run on the host.
  final String testDriver;
  /// Whether to collect CPU and GPU metrics.
  final bool measureCpuGpu;
  /// Whether to collect memory metrics.
  final bool measureMemory;
  /// Whether to collect full timeline, meaning if `--trace-startup` flag is needed.
  final bool needsFullTimeline;
  /// Whether to save the trace timeline file `*.timeline.json`.
  final bool saveTraceFile;

  /// The keys of the values that need to be reported.
  ///
  /// If it's `null`, then report:
  /// ```Dart
  /// <String>[
  ///   'average_frame_build_time_millis',
  ///   'worst_frame_build_time_millis',
  ///   '90th_percentile_frame_build_time_millis',
  ///   '99th_percentile_frame_build_time_millis',
  ///   'average_frame_rasterizer_time_millis',
  ///   'worst_frame_rasterizer_time_millis',
  ///   '90th_percentile_frame_rasterizer_time_millis',
  ///   '99th_percentile_frame_rasterizer_time_millis',
  ///   'average_vsync_transitions_missed',
  ///   '90th_percentile_vsync_transitions_missed',
  ///   '99th_percentile_vsync_transitions_missed',
  ///   if (measureCpuGpu) 'average_cpu_usage',
  ///   if (measureCpuGpu) 'average_gpu_usage',
  /// ]
  /// ```
  final List<String> benchmarkScoreKeys;

  /// Additional flags for `--dart-define` to control the test
  final String dartDefine;

  Future<TaskResult> run() {
    return internalRun();
  }

  @protected
  Future<TaskResult> internalRun({
      bool cacheSkSL = false,
      String existingApp,
      String writeSkslFileName,
  }) {
    return inDirectory<TaskResult>(testDirectory, () async {
      final Device device = await devices.workingDevice;
      await device.unlock();
      final String deviceId = device.deviceId;

      await flutter('drive', options: <String>[
        '--no-android-gradle-daemon',
        '-v',
        '--verbose-system-logs',
        '--profile',
        if (needsFullTimeline)
          '--trace-startup', // Enables "endless" timeline event buffering.
        '-t', testTarget,
        if (testDriver != null)
          ...<String>['--driver', testDriver],
        if (existingApp != null)
          ...<String>['--use-existing-app', existingApp],
        if (writeSkslFileName != null)
          ...<String>['--write-sksl-on-exit', writeSkslFileName],
        if (cacheSkSL) '--cache-sksl',
        if (dartDefine.isNotEmpty)
          ...<String>['--dart-define', dartDefine],
        '-d',
        deviceId,
        '--screenshot',
        hostAgent.dumpDirectory.path,
      ]);
      final Map<String, dynamic> data = json.decode(
        file('${_testOutputDirectory(testDirectory)}/$resultFilename.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      if (data['frame_count'] as int < 5) {
        return TaskResult.failure(
          'Timeline contains too few frames: ${data['frame_count']}. Possibly '
          'trace events are not being captured.',
        );
      }

      // TODO(liyuqian): Remove isAndroid restriction once
      // https://github.com/flutter/flutter/issues/61567 is fixed.
      final bool isAndroid = deviceOperatingSystem == DeviceOperatingSystem.android;
      return TaskResult.success(
        data,
        detailFiles: <String>[
          if (saveTraceFile)
            '${_testOutputDirectory(testDirectory)}/$traceFilename.json',
        ],
        benchmarkScoreKeys: benchmarkScoreKeys ?? <String>[
          ..._kCommonScoreKeys,
          'average_vsync_transitions_missed',
          '90th_percentile_vsync_transitions_missed',
          '99th_percentile_vsync_transitions_missed',
          if (measureCpuGpu && !isAndroid) ...<String>[
            // See https://github.com/flutter/flutter/issues/68888
            if (data['average_cpu_usage'] != null) 'average_cpu_usage',
            if (data['average_gpu_usage'] != null) 'average_gpu_usage',
          ],
          if (measureMemory && !isAndroid) ...<String>[
            // See https://github.com/flutter/flutter/issues/68888
            if (data['average_memory_usage'] != null) 'average_memory_usage',
            if (data['90th_percentile_memory_usage'] != null) '90th_percentile_memory_usage',
            if (data['99th_percentile_memory_usage'] != null) '99th_percentile_memory_usage',
          ],
        ],
      );
    });
  }
}

const List<String> _kCommonScoreKeys = <String>[
  'average_frame_build_time_millis',
  'worst_frame_build_time_millis',
  '90th_percentile_frame_build_time_millis',
  '99th_percentile_frame_build_time_millis',
  'average_frame_rasterizer_time_millis',
  'worst_frame_rasterizer_time_millis',
  '90th_percentile_frame_rasterizer_time_millis',
  '99th_percentile_frame_rasterizer_time_millis',
];

class PerfTestWithSkSL extends PerfTest {
  PerfTestWithSkSL(
    String testDirectory,
    String testTarget,
    String timelineFileName, {
    bool measureCpuGpu = false,
    String testDriver,
    bool needsFullTimeline = true,
    List<String> benchmarkScoreKeys,
  }) : super(
    testDirectory,
    testTarget,
    timelineFileName,
    measureCpuGpu: measureCpuGpu,
    testDriver: testDriver,
    needsFullTimeline: needsFullTimeline,
    benchmarkScoreKeys: benchmarkScoreKeys,
  );


  PerfTestWithSkSL.e2e(
    String testDirectory,
    String testTarget, {
    String testDriver =  'test_driver/e2e_test.dart',
    String resultFilename = 'e2e_perf_summary',
  }) : super.e2e(
    testDirectory,
    testTarget,
    testDriver: testDriver,
    needsFullTimeline: false,
    resultFilename: resultFilename,
  );

  @override
  Future<TaskResult> run() async {
    return inDirectory<TaskResult>(testDirectory, () async {
      // Some initializations
      _device = await devices.workingDevice;
      _flutterPath = path.join(flutterDirectory.path, 'bin', 'flutter');

      // Prepare the SkSL by running the driver test.
      await _generateSkSL();

      // Build the app with SkSL artifacts and run that app
      final String observatoryUri = await _buildAndRun();

      // Attach to the running app and run the final driver test to get metrics.
      final TaskResult result = await internalRun(
        existingApp: observatoryUri,
      );

      _runProcess.kill();
      await _runProcess.exitCode;

      return result;
    });
  }

  Future<void> _generateSkSL() async {
    // `flutter drive` without `flutter run`, and `flutter drive --existing-app`
    // with `flutter run` may generate different SkSLs. Hence we run both
    // versions to generate as many SkSLs as possible.
    //
    // 1st, `flutter drive --existing-app` with `flutter run`. The
    // `--write-sksl-on-exit` option doesn't seem to be compatible with
    // `flutter drive --existing-app` as it will complain web socket connection
    // issues.
    final String observatoryUri = await _runApp(cacheSkSL: true);
    await super.internalRun(cacheSkSL: true, existingApp: observatoryUri);
    _runProcess.kill();
    await _runProcess.exitCode;

    // 2nd, `flutter drive` without `flutter run`. The --no-build option ensures
    // that we won't remove the SkSLs generated earlier.
    await super.internalRun(
      cacheSkSL: true,
      writeSkslFileName: _skslJsonFileName,
    );
  }

  Future<String> _runApp({String appBinary, bool cacheSkSL = false}) async {
    if (File(_vmserviceFileName).existsSync()) {
      File(_vmserviceFileName).deleteSync();
    }

    _runProcess = await startProcess(
      _flutterPath,
      <String>[
        'run',
        if (deviceOperatingSystem == DeviceOperatingSystem.ios)
          ...<String>[
            '--device-timeout', '5',
          ],
        '--verbose',
        '--verbose-system-logs',
        '--purge-persistent-cache',
        '--no-publish-port',
        '--profile',
        if (cacheSkSL) '--cache-sksl',
        '-d', _device.deviceId,
        '-t', testTarget,
        '--endless-trace-buffer',
        if (appBinary != null) ...<String>['--use-application-binary', _appBinary],
        '--vmservice-out-file', _vmserviceFileName,
      ],
    );

    final Stream<List<int>> broadcastOut = _runProcess.stdout.asBroadcastStream();
    _forwardStream(broadcastOut, 'run stdout');
    _forwardStream(_runProcess.stderr, 'run stderr');

    final File file = await waitForFile(_vmserviceFileName);
    return file.readAsStringSync();
  }

  // Return the VMService URI.
  Future<String> _buildAndRun() async {
    await flutter('build', options: <String>[
      if (_isAndroid) 'apk' else 'ios',
      '--profile',
      '--bundle-sksl-path', _skslJsonFileName,
      '-t', testTarget,
    ]);

    return _runApp(appBinary: _appBinary);
  }

  String get _skslJsonFileName => '$testDirectory/flutter_01.sksl.json';
  String get _vmserviceFileName => '$testDirectory/$_kVmserviceOutFileName';

  bool get _isAndroid => deviceOperatingSystem == DeviceOperatingSystem.android;

  String get _appBinary {
    if (_isAndroid) {
      return '$testDirectory/build/app/outputs/flutter-apk/app-profile.apk';
    }
    for (final FileSystemEntity entry in Directory('$testDirectory/build/ios/iphoneos/').listSync()) {
      if (entry.path.endsWith('.app')) {
        return entry.path;
      }
    }
    throw 'No app found.';
  }

  Stream<String> _transform(Stream<List<int>> stream) =>
      stream.transform<String>(utf8.decoder).transform<String>(const LineSplitter());

  void _forwardStream(Stream<List<int>> stream, String label) {
    _transform(stream).listen((String line) {
      print('$label: $line');
    });
  }

  String _flutterPath;
  Device _device;
  Process _runProcess;

  static const String _kVmserviceOutFileName = 'vmservice.out';
}

/// Measures how long it takes to compile a Flutter app to JavaScript and how
/// big the compiled code is.
class WebCompileTest {
  const WebCompileTest();

  Future<TaskResult> run() async {
    final Map<String, Object> metrics = <String, Object>{};

    metrics.addAll(await runSingleBuildTest(
      directory: '${flutterDirectory.path}/examples/hello_world',
      metric: 'hello_world',
    ));

    metrics.addAll(await runSingleBuildTest(
      directory: '${flutterDirectory.path}/dev/integration_tests/flutter_gallery',
      metric: 'flutter_gallery',
    ));

    const String sampleAppName = 'sample_flutter_app';
    final Directory sampleDir = dir('${Directory.systemTemp.path}/$sampleAppName');

    rmTree(sampleDir);

    await inDirectory<void>(Directory.systemTemp, () async {
      await flutter('create', options: <String>['--template=app', sampleAppName]);
    });

    metrics.addAll(await runSingleBuildTest(
      directory: sampleDir.path,
      metric: 'basic_material_app',
    ));

    return TaskResult.success(metrics, benchmarkScoreKeys: metrics.keys.toList());
  }

  /// Run a single web compile test and return its metrics.
  ///
  /// Run a single web compile test for the app under [directory], and store
  /// its metrics with prefix [metric].
  static Future<Map<String, int>> runSingleBuildTest({String directory, String metric, bool measureBuildTime = false}) {
    return inDirectory<Map<String, int>>(directory, () async {
      final Map<String, int> metrics = <String, int>{};

      await flutter('packages', options: <String>['get']);
      final Stopwatch watch = measureBuildTime ? Stopwatch() : null;
      watch?.start();
      await evalFlutter('build', options: <String>[
        'web',
        '-v',
        '--release',
        '--no-pub',
      ]);
      watch?.stop();
      final String outputFileName = path.join(directory, 'build/web/main.dart.js');
      metrics.addAll(await getSize(outputFileName, metric: metric));

      if (measureBuildTime) {
        metrics['${metric}_dart2js_millis'] = watch.elapsedMilliseconds;
      }

      return metrics;
    });
  }

  /// Obtains the size and gzipped size of a file given by [fileName].
  static Future<Map<String, int>> getSize(String fileName, {String metric}) async {
    final Map<String, int> sizeMetrics = <String, int>{};

    final ProcessResult result = await Process.run('du', <String>['-k', fileName]);
    sizeMetrics['${metric}_dart2js_size'] = _parseDu(result.stdout as String);

    await Process.run('gzip',<String>['-k', '9', fileName]);
    final ProcessResult resultGzip = await Process.run('du', <String>['-k', fileName + '.gz']);
    sizeMetrics['${metric}_dart2js_size_gzip'] = _parseDu(resultGzip.stdout as String);

    return sizeMetrics;
  }

  static int _parseDu(String source) {
    return int.parse(source.split(RegExp(r'\s+')).first.trim());
  }
}

/// Measures how long it takes to compile a Flutter app and how big the compiled
/// code is.
class CompileTest {
  const CompileTest(this.testDirectory, { this.reportPackageContentSizes = false });

  final String testDirectory;
  final bool reportPackageContentSizes;

  Future<TaskResult> run() async {
    return inDirectory<TaskResult>(testDirectory, () async {
      final Device device = await devices.workingDevice;
      await device.unlock();
      await flutter('packages', options: <String>['get']);

      final Map<String, dynamic> compileRelease = await _compileApp(reportPackageContentSizes: reportPackageContentSizes);
      final Map<String, dynamic> compileDebug = await _compileDebug(
        clean: true,
        metricKey: 'debug_full_compile_millis',
      );
      // Build again without cleaning, should be faster.
      final Map<String, dynamic> compileSecondDebug = await _compileDebug(
        clean: false,
        metricKey: 'debug_second_compile_millis',
      );

      final Map<String, dynamic> metrics = <String, dynamic>{
        ...compileRelease,
        ...compileDebug,
        ...compileSecondDebug,
      };

      return TaskResult.success(metrics, benchmarkScoreKeys: metrics.keys.toList());
    });
  }

  static Future<Map<String, dynamic>> _compileApp({ bool reportPackageContentSizes = false }) async {
    await flutter('clean');
    final Stopwatch watch = Stopwatch();
    int releaseSizeInBytes;
    final List<String> options = <String>['--release'];
    final Map<String, dynamic> metrics = <String, dynamic>{};

    switch (deviceOperatingSystem) {
      case DeviceOperatingSystem.ios:
        options.insert(0, 'ios');
        options.add('--tree-shake-icons');
        options.add('--split-debug-info=infos/');
        watch.start();
        await flutter('build', options: options);
        watch.stop();
        final Directory appBuildDirectory = dir(path.join(cwd, 'build/ios/Release-iphoneos'));
        final Directory appBundle = appBuildDirectory
            .listSync()
            .whereType<Directory>()
            .singleWhere((Directory directory) => path.extension(directory.path) == '.app', orElse: () => null);
        if (appBundle == null) {
          throw 'Failed to find app bundle in ${appBuildDirectory.path}';
        }
        final String appPath =  appBundle.path;
        // IPAs are created manually, https://flutter.dev/ios-release/
        await exec('tar', <String>['-zcf', 'build/app.ipa', appPath]);
        releaseSizeInBytes = await file('$cwd/build/app.ipa').length();
        if (reportPackageContentSizes)
          metrics.addAll(await getSizesFromIosApp(appPath));
        break;
      case DeviceOperatingSystem.android:
      case DeviceOperatingSystem.androidArm:
        options.insert(0, 'apk');
        options.add('--target-platform=android-arm');
        options.add('--tree-shake-icons');
        options.add('--split-debug-info=infos/');
        watch.start();
        await flutter('build', options: options);
        watch.stop();
        final String apkPath = '$cwd/build/app/outputs/flutter-apk/app-release.apk';
        final File apk = file(apkPath);
        releaseSizeInBytes = apk.lengthSync();
        if (reportPackageContentSizes)
          metrics.addAll(await getSizesFromApk(apkPath));
        break;
      case DeviceOperatingSystem.androidArm64:
        options.insert(0, 'apk');
        options.add('--target-platform=android-arm64');
        options.add('--tree-shake-icons');
        options.add('--split-debug-info=infos/');
        watch.start();
        await flutter('build', options: options);
        watch.stop();
        final String apkPath = '$cwd/build/app/outputs/flutter-apk/app-release.apk';
        final File apk = file(apkPath);
        releaseSizeInBytes = apk.lengthSync();
        if (reportPackageContentSizes)
          metrics.addAll(await getSizesFromApk(apkPath));
        break;
      case DeviceOperatingSystem.fuchsia:
        throw Exception('Unsupported option for Fuchsia devices');
      case DeviceOperatingSystem.fake:
        throw Exception('Unsupported option for fake devices');
    }

    metrics.addAll(<String, dynamic>{
      'release_full_compile_millis': watch.elapsedMilliseconds,
      'release_size_bytes': releaseSizeInBytes,
    });

    return metrics;
  }

  static Future<Map<String, dynamic>> _compileDebug({
    @required bool clean,
    @required String metricKey,
  }) async {
    if (clean) {
      await flutter('clean');
    }
    final Stopwatch watch = Stopwatch();
    final List<String> options = <String>['--debug'];
    switch (deviceOperatingSystem) {
      case DeviceOperatingSystem.ios:
        options.insert(0, 'ios');
        break;
      case DeviceOperatingSystem.android:
      case DeviceOperatingSystem.androidArm:
        options.insert(0, 'apk');
        options.add('--target-platform=android-arm');
        break;
      case DeviceOperatingSystem.androidArm64:
        options.insert(0, 'apk');
        options.add('--target-platform=android-arm64');
        break;
      case DeviceOperatingSystem.fuchsia:
        throw Exception('Unsupported option for Fuchsia devices');
      case DeviceOperatingSystem.fake:
        throw Exception('Unsupported option for fake devices');
    }
    watch.start();
    await flutter('build', options: options);
    watch.stop();

    return <String, dynamic>{
      metricKey: watch.elapsedMilliseconds,
    };
  }

  static Future<Map<String, dynamic>> getSizesFromIosApp(String appPath) async {
    // Thin the binary to only contain one architecture.
    final String xcodeBackend = path.join(flutterDirectory.path, 'packages', 'flutter_tools', 'bin', 'xcode_backend.sh');
    await exec(xcodeBackend, <String>['thin'], environment: <String, String>{
      'ARCHS': 'arm64',
      'WRAPPER_NAME': path.basename(appPath),
      'TARGET_BUILD_DIR': path.dirname(appPath),
    });

    final File appFramework = File(path.join(appPath, 'Frameworks', 'App.framework', 'App'));
    final File flutterFramework = File(path.join(appPath, 'Frameworks', 'Flutter.framework', 'Flutter'));

    return <String, dynamic>{
      'app_framework_uncompressed_bytes': await appFramework.length(),
      'flutter_framework_uncompressed_bytes': await flutterFramework.length(),
    };
  }

  static Future<Map<String, dynamic>> getSizesFromApk(String apkPath) async {
    final  String output = await eval('unzip', <String>['-v', apkPath]);
    final List<String> lines = output.split('\n');
    final Map<String, _UnzipListEntry> fileToMetadata = <String, _UnzipListEntry>{};

    // First three lines are header, last two lines are footer.
    for (int i = 3; i < lines.length - 2; i++) {
      final _UnzipListEntry entry = _UnzipListEntry.fromLine(lines[i]);
      fileToMetadata[entry.path] = entry;
    }

    final _UnzipListEntry libflutter = fileToMetadata['lib/armeabi-v7a/libflutter.so'];
    final _UnzipListEntry libapp = fileToMetadata['lib/armeabi-v7a/libapp.so'];
    final _UnzipListEntry license = fileToMetadata['assets/flutter_assets/NOTICES'];

    return <String, dynamic>{
      'libflutter_uncompressed_bytes': libflutter.uncompressedSize,
      'libflutter_compressed_bytes': libflutter.compressedSize,
      'libapp_uncompressed_bytes': libapp.uncompressedSize,
      'libapp_compressed_bytes': libapp.compressedSize,
      'license_uncompressed_bytes': license.uncompressedSize,
      'license_compressed_bytes': license.compressedSize,
    };
  }
}

/// Measure application memory usage.
class MemoryTest {
  MemoryTest(this.project, this.test, this.package);

  final String project;
  final String test;
  final String package;

  /// Completes when the log line specified in the last call to
  /// [prepareForNextMessage] is seen by `adb logcat`.
  Future<void> get receivedNextMessage => _receivedNextMessage?.future;
  Completer<void> _receivedNextMessage;
  String _nextMessage;

  /// Prepares the [receivedNextMessage] future such that it will complete
  /// when `adb logcat` sees a log line with the given `message`.
  void prepareForNextMessage(String message) {
    _nextMessage = message;
    _receivedNextMessage = Completer<void>();
  }

  int get iterationCount => 10;

  Device get device => _device;
  Device _device;

  Future<TaskResult> run() {
    return inDirectory<TaskResult>(project, () async {
      // This test currently only works on Android, because device.logcat,
      // device.getMemoryStats, etc, aren't implemented for iOS.

      _device = await devices.workingDevice;
      await device.unlock();
      await flutter('packages', options: <String>['get']);

      final StreamSubscription<String> adb = device.logcat.listen(
        (String data) {
          if (data.contains('==== MEMORY BENCHMARK ==== $_nextMessage ===='))
            _receivedNextMessage.complete();
        },
      );

      for (int iteration = 0; iteration < iterationCount; iteration += 1) {
        print('running memory test iteration $iteration...');
        _startMemoryUsage = null;
        await useMemory();
        assert(_startMemoryUsage != null);
        assert(_startMemory.length == iteration + 1);
        assert(_endMemory.length == iteration + 1);
        assert(_diffMemory.length == iteration + 1);
        print('terminating...');
        await device.stop(package);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      await adb.cancel();
      await flutter('install', options: <String>['--uninstall-only', '-d', device.deviceId]);

      final ListStatistics startMemoryStatistics = ListStatistics(_startMemory);
      final ListStatistics endMemoryStatistics = ListStatistics(_endMemory);
      final ListStatistics diffMemoryStatistics = ListStatistics(_diffMemory);

      final Map<String, dynamic> memoryUsage = <String, dynamic>{
        ...startMemoryStatistics.asMap('start'),
        ...endMemoryStatistics.asMap('end'),
        ...diffMemoryStatistics.asMap('diff'),
      };

      _device = null;
      _startMemory.clear();
      _endMemory.clear();
      _diffMemory.clear();

      return TaskResult.success(memoryUsage, benchmarkScoreKeys: memoryUsage.keys.toList());
    });
  }

  /// Starts the app specified by [test] on the [device].
  ///
  /// The [run] method will terminate it by its package name ([package]).
  Future<void> launchApp() async {
    prepareForNextMessage('READY');
    print('launching $project$test on device...');
    await flutter('run', options: <String>[
      '--verbose',
      '--release',
      '--no-resident',
      '-d', device.deviceId,
      test,
    ]);
    print('awaiting "ready" message...');
    await receivedNextMessage;
  }

  /// To change the behavior of the test, override this.
  ///
  /// Make sure to call recordStart() and recordEnd() once each in that order.
  ///
  /// By default it just launches the app, records memory usage, taps the device,
  /// awaits a DONE notification, and records memory usage again.
  Future<void> useMemory() async {
    await launchApp();
    await recordStart();

    prepareForNextMessage('DONE');
    print('tapping device...');
    await device.tap(100, 100);
    print('awaiting "done" message...');
    await receivedNextMessage;

    await recordEnd();
  }

  final List<int> _startMemory = <int>[];
  final List<int> _endMemory = <int>[];
  final List<int> _diffMemory = <int>[];

  Map<String, dynamic> _startMemoryUsage;

  @protected
  Future<void> recordStart() async {
    assert(_startMemoryUsage == null);
    print('snapshotting memory usage...');
    _startMemoryUsage = await device.getMemoryStats(package);
  }

  @protected
  Future<void> recordEnd() async {
    assert(_startMemoryUsage != null);
    print('snapshotting memory usage...');
    final Map<String, dynamic> endMemoryUsage = await device.getMemoryStats(package);
    _startMemory.add(_startMemoryUsage['total_kb'] as int);
    _endMemory.add(endMemoryUsage['total_kb'] as int);
    _diffMemory.add((endMemoryUsage['total_kb'] as int) - (_startMemoryUsage['total_kb'] as int));
  }
}

class DevToolsMemoryTest {
  DevToolsMemoryTest(this.project, this.driverTest);

  final String project;
  final String driverTest;

  Future<TaskResult> run() {
    return inDirectory<TaskResult>(project, () async {
      _device = await devices.workingDevice;
      await _device.unlock();

      await _launchApp();
      if (_observatoryUri == null) {
        return  TaskResult.failure('Observatory URI not found.');
      }

      await _launchDevTools();

      await flutter(
        'drive',
        options: <String>[
          '--use-existing-app', _observatoryUri,
          '-d', _device.deviceId,
          '--screenshot',
          hostAgent.dumpDirectory.path,
          '--profile',
          driverTest,
        ],
      );

      _devToolsProcess.kill();
      await _devToolsProcess.exitCode;

      _runProcess.kill();
      await _runProcess.exitCode;

      final Map<String, dynamic> data = json.decode(
        file('$project/$_kJsonFileName').readAsStringSync(),
      ) as Map<String, dynamic>;
      final List<dynamic> samples = data['samples']['data'] as List<dynamic>;
      int maxRss = 0;
      int maxAdbTotal = 0;
      for (final dynamic sample in samples) {
        if (sample['rss'] != null) {
          maxRss = math.max(maxRss, sample['rss'] as int);
        }
        if (sample['adb_memoryInfo'] != null) {
          maxAdbTotal = math.max(maxAdbTotal, sample['adb_memoryInfo']['Total'] as int);
        }
      }

      await flutter('install', options: <String>[
        '--uninstall-only',
      ]);

      return TaskResult.success(
        <String, dynamic>{'maxRss': maxRss, 'maxAdbTotal': maxAdbTotal},
        benchmarkScoreKeys: <String>['maxRss', 'maxAdbTotal'],
      );
    });
  }

  Future<void> _launchApp() async {
    print('launching $project$driverTest on device...');
    final String flutterPath = path.join(flutterDirectory.path, 'bin', 'flutter');
    _runProcess = await startProcess(
      flutterPath,
      <String>[
        'run',
        '--verbose',
        '--profile',
        '--no-publish-port',
        '-d', _device.deviceId,
        driverTest,
      ],
    );

    // Listen for Observatory URI and forward stdout/stderr
    final Completer<String> observatoryUri = Completer<String>();
    _runProcess.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen((String line) {
          print('run stdout: $line');
          final RegExpMatch match = RegExp(r'An Observatory debugger and profiler on .+ is available at: ((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)').firstMatch(line);
          if (match != null && !observatoryUri.isCompleted) {
            observatoryUri.complete(match[1]);
            _observatoryUri = match[1];
          }
        }, onDone: () {
          if (!observatoryUri.isCompleted) {
            observatoryUri.complete();
          }
        });
    _forwardStream(_runProcess.stderr, 'run stderr');

    _observatoryUri = await observatoryUri.future;
  }

  Future<void> _launchDevTools() async {
    // The version of devtools is pinned. If we pub global activate devtools and an
    // upstream devtools release breaks our CI, it will manifest on an unrelated
    // commit, making it more difficult to determine the cause.
    //
    // Also, for release branches, all external test dependencies need to be pinned.
    await exec(pubBin, <String>[
      'global',
      'activate',
      'devtools',
      '2.0.0',
    ]);
    _devToolsProcess = await startProcess(
      pubBin,
      <String>[
        'global',
        'run',
        'devtools',
        '--vm-uri', _observatoryUri,
        '--profile-memory', _kJsonFileName,
      ],
    );
    _forwardStream(_devToolsProcess.stdout, 'devtools stdout');
    _forwardStream(_devToolsProcess.stderr, 'devtools stderr');
  }

  void _forwardStream(Stream<List<int>> stream, String label) {
    stream
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .listen((String line) {
          print('$label: $line');
        });
  }

  Device _device;
  String _observatoryUri;
  Process _runProcess;
  Process _devToolsProcess;

  static const String _kJsonFileName = 'devtools_memory.json';
}

enum ReportedDurationTestFlavor {
  debug, profile, release
}

String _reportedDurationTestToString(ReportedDurationTestFlavor flavor) {
  switch (flavor) {
    case ReportedDurationTestFlavor.debug:
      return 'debug';
    case ReportedDurationTestFlavor.profile:
      return 'profile';
    case ReportedDurationTestFlavor.release:
      return 'release';
  }
  throw ArgumentError('Unexpected value for enum $flavor');
}

class ReportedDurationTest {
  ReportedDurationTest(this.flavor, this.project, this.test, this.package, this.durationPattern);

  final ReportedDurationTestFlavor flavor;
  final String project;
  final String test;
  final String package;
  final RegExp durationPattern;

  final Completer<int> durationCompleter = Completer<int>();

  int get iterationCount => 10;

  Device get device => _device;
  Device _device;

  Future<TaskResult> run() {
    return inDirectory<TaskResult>(project, () async {
      // This test currently only works on Android, because device.logcat,
      // device.getMemoryStats, etc, aren't implemented for iOS.

      _device = await devices.workingDevice;
      await device.unlock();
      await flutter('packages', options: <String>['get']);

      final StreamSubscription<String> adb = device.logcat.listen(
        (String data) {
          if (durationPattern.hasMatch(data))
            durationCompleter.complete(int.parse(durationPattern.firstMatch(data).group(1)));
        },
      );
      print('launching $project$test on device...');
      await flutter('run', options: <String>[
        '--verbose',
        '--no-publish-port',
        '--no-fast-start',
        '--${_reportedDurationTestToString(flavor)}',
        '--no-resident',
        '-d', device.deviceId,
        test,
      ]);

      final int duration = await durationCompleter.future;
      print('terminating...');
      await device.stop(package);
      await adb.cancel();

      _device = null;

      final Map<String, dynamic> reportedDuration = <String, dynamic>{
        'duration': duration,
      };
      _device = null;

      return TaskResult.success(reportedDuration, benchmarkScoreKeys: reportedDuration.keys.toList());
    });
  }
}

/// Holds simple statistics of an odd-lengthed list of integers.
class ListStatistics {
  factory ListStatistics(Iterable<int> data) {
    assert(data.isNotEmpty);
    assert(data.length.isOdd);
    final List<int> sortedData = data.toList()..sort();
    return ListStatistics._(
      sortedData.first,
      sortedData.last,
      sortedData[(sortedData.length - 1) ~/ 2],
    );
  }

  const ListStatistics._(this.min, this.max, this.median);

  final int min;
  final int max;
  final int median;

  Map<String, int> asMap(String prefix) {
    return <String, int>{
      '$prefix-min': min,
      '$prefix-max': max,
      '$prefix-median': median,
    };
  }
}

class _UnzipListEntry {
  factory _UnzipListEntry.fromLine(String line) {
    final List<String> data = line.trim().split(RegExp(r'\s+'));
    assert(data.length == 8);
    return _UnzipListEntry._(
      uncompressedSize:  int.parse(data[0]),
      compressedSize: int.parse(data[2]),
      path: data[7],
    );
  }

  _UnzipListEntry._({
    @required this.uncompressedSize,
    @required this.compressedSize,
    @required this.path,
  }) : assert(uncompressedSize != null),
       assert(compressedSize != null),
       assert(compressedSize <= uncompressedSize),
       assert(path != null);

  final int uncompressedSize;
  final int compressedSize;
  final String path;
}

/// Wait for up to 400 seconds for the file to appear.
Future<File> waitForFile(String path) async {
  for (int i = 0; i < 20; i += 1) {
    final File file = File(path);
    print('looking for ${file.path}');
    if (file.existsSync()) {
      return file;
    }
    await Future<void>.delayed(const Duration(seconds: 20));
  }
  throw StateError('Did not find vmservice out file after 400 seconds');
}

String _findIosAppInBuildDirectory(String searchDirectory) {
  for (final FileSystemEntity entity in Directory(searchDirectory).listSync()) {
    if (entity.path.endsWith('.app')) {
      return entity.path;
    }
  }
  return null;
}
