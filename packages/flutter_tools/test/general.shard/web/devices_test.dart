// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/web/chrome.dart';
import 'package:flutter_tools/src/web/web_device.dart';

import '../../src/common.dart';
import '../../src/fake_process_manager.dart';
import '../../src/fakes.dart';

void main() {
  testWithoutContext('No web devices listed if feature is disabled', () async {
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: false),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'linux',
        environment: <String, String>{}
      ),
      processManager:  FakeProcessManager.any(),
    );

    expect(await webDevices.pollingGetDevices(), isEmpty);
  });

  testWithoutContext('GoogleChromeDevice defaults', () async {
    final GoogleChromeDevice chromeDevice = GoogleChromeDevice(
      chromiumLauncher: null,
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(operatingSystem: 'linux'),
      processManager: FakeProcessManager.any(),
    );

    expect(chromeDevice.name, 'Chrome');
    expect(chromeDevice.id, 'chrome');
    expect(chromeDevice.supportsHotReload, true);
    expect(chromeDevice.supportsHotRestart, true);
    expect(chromeDevice.supportsStartPaused, true);
    expect(chromeDevice.supportsFlutterExit, false);
    expect(chromeDevice.supportsScreenshot, false);
    expect(await chromeDevice.isLocalEmulator, false);
    expect(chromeDevice.getLogReader(), isA<NoOpDeviceLogReader>());
    expect(chromeDevice.getLogReader(), isA<NoOpDeviceLogReader>());
    expect(await chromeDevice.portForwarder.forward(1), 1);

    expect(chromeDevice.supportsRuntimeMode(BuildMode.debug), true);
    expect(chromeDevice.supportsRuntimeMode(BuildMode.profile), true);
    expect(chromeDevice.supportsRuntimeMode(BuildMode.release), true);
    expect(chromeDevice.supportsRuntimeMode(BuildMode.jitRelease), false);
  });

  testWithoutContext('MicrosoftEdge defaults', () async {
    final MicrosoftEdgeDevice chromeDevice = MicrosoftEdgeDevice(
      chromiumLauncher: null,
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.any(),
    );

    expect(chromeDevice.name, 'Edge');
    expect(chromeDevice.id, 'edge');
    expect(chromeDevice.supportsHotReload, true);
    expect(chromeDevice.supportsHotRestart, true);
    expect(chromeDevice.supportsStartPaused, true);
    expect(chromeDevice.supportsFlutterExit, false);
    expect(chromeDevice.supportsScreenshot, false);
    expect(await chromeDevice.isLocalEmulator, false);
    expect(chromeDevice.getLogReader(), isA<NoOpDeviceLogReader>());
    expect(chromeDevice.getLogReader(), isA<NoOpDeviceLogReader>());
    expect(await chromeDevice.portForwarder.forward(1), 1);

    expect(chromeDevice.supportsRuntimeMode(BuildMode.debug), true);
    expect(chromeDevice.supportsRuntimeMode(BuildMode.profile), true);
    expect(chromeDevice.supportsRuntimeMode(BuildMode.release), true);
    expect(chromeDevice.supportsRuntimeMode(BuildMode.jitRelease), false);
  });

  testWithoutContext('Server defaults', () async {
    final WebServerDevice device = WebServerDevice(
      logger: BufferLogger.test(),
    );

    expect(device.name, 'Web Server');
    expect(device.id, 'web-server');
    expect(device.supportsHotReload, true);
    expect(device.supportsHotRestart, true);
    expect(device.supportsStartPaused, true);
    expect(device.supportsFlutterExit, false);
    expect(device.supportsScreenshot, false);
    expect(await device.isLocalEmulator, false);
    expect(device.getLogReader(), isA<NoOpDeviceLogReader>());
    expect(device.getLogReader(), isA<NoOpDeviceLogReader>());
    expect(await device.portForwarder.forward(1), 1);

    expect(device.supportsRuntimeMode(BuildMode.debug), true);
    expect(device.supportsRuntimeMode(BuildMode.profile), true);
    expect(device.supportsRuntimeMode(BuildMode.release), true);
    expect(device.supportsRuntimeMode(BuildMode.jitRelease), false);
});

  testWithoutContext('Chrome device is listed when Chrome can be run', () async {
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'linux',
        environment: <String, String>{}
      ),
      processManager:  FakeProcessManager.any(),
    );

    expect(await webDevices.pollingGetDevices(),
      contains(isA<GoogleChromeDevice>()));
  });

  testWithoutContext('Chrome device is not listed when Chrome cannot be run', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[]);
    processManager.excludedExecutables = <String>{kLinuxExecutable};
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'linux',
        environment: <String, String>{}
      ),
      processManager: processManager,
    );

    expect(await webDevices.pollingGetDevices(),
      isNot(contains(isA<GoogleChromeDevice>())));
  });

  testWithoutContext('Web Server device is listed if enabled via showWebServerDevice', () async {
    WebServerDevice.showWebServerDevice = true;
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'linux',
        environment: <String, String>{}
      ),
      processManager: FakeProcessManager.any(),
    );

    expect(await webDevices.pollingGetDevices(),
      contains(isA<WebServerDevice>()));
  });

  testWithoutContext('Web Server device is not listed if disabled via showWebServerDevice', () async {
    WebServerDevice.showWebServerDevice = false;
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'linux',
        environment: <String, String>{}
      ),
      processManager: FakeProcessManager.any(),
    );

    expect(await webDevices.pollingGetDevices(),
      isNot(contains(isA<WebServerDevice>())));
  });

  testWithoutContext('Chrome invokes version command on non-Windows platforms', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(
        command: <String>[
          kLinuxExecutable,
          '--version',
        ],
        stdout: 'ABC'
      )
    ]);
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'linux',
        environment: <String, String>{}
      ),
      processManager: processManager,
    );


    final GoogleChromeDevice chromeDevice = (await webDevices.pollingGetDevices())
      .whereType<GoogleChromeDevice>().first;

    expect(chromeDevice.isSupported(), true);
    expect(await chromeDevice.sdkNameAndVersion, 'ABC');

    // Verify caching works correctly.
    expect(await chromeDevice.sdkNameAndVersion, 'ABC');
    expect(processManager, hasNoRemainingExpectations);
  });

  testWithoutContext('Chrome and Edge version check invokes registry query on windows.', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(
        command: <String>[
          'reg',
          'query',
          r'HKEY_CURRENT_USER\Software\Microsoft\Edge\BLBeacon',
          '/v',
          'version',
        ],
        stdout: r'HKEY_CURRENT_USER\Software\Microsoft\Edge\BLBeacon\ version REG_SZ 83.0.478.44 ',
      ),
      const FakeCommand(
        command: <String>[
          'reg',
          'query',
          r'HKEY_CURRENT_USER\Software\Google\Chrome\BLBeacon',
          '/v',
          'version',
        ],
        stdout: r'HKEY_CURRENT_USER\Software\Google\Chrome\BLBeacon\ version REG_SZ 74.0.0 A',
      )
    ]);
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'windows',
        environment: <String, String>{}
      ),
      processManager: processManager,
    );


    final GoogleChromeDevice chromeDevice = (await webDevices.pollingGetDevices())
      .whereType<GoogleChromeDevice>().first;

    expect(chromeDevice.isSupported(), true);
    expect(await chromeDevice.sdkNameAndVersion, 'Google Chrome 74.0.0');

    // Verify caching works correctly.
    expect(await chromeDevice.sdkNameAndVersion, 'Google Chrome 74.0.0');
    expect(processManager, hasNoRemainingExpectations);
  });

  testWithoutContext('Edge is not supported on versions less than 73', () async {
    final FakeProcessManager processManager = FakeProcessManager.list(<FakeCommand>[
      const FakeCommand(
        command: <String>[
          'reg',
          'query',
          r'HKEY_CURRENT_USER\Software\Microsoft\Edge\BLBeacon',
          '/v',
          'version',
        ],
        stdout: r'HKEY_CURRENT_USER\Software\Microsoft\Edge\BLBeacon\ version REG_SZ 72.0.478.44 ',
      ),
    ]);
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'windows',
        environment: <String, String>{}
      ),
      processManager: processManager,
    );

    expect((await webDevices.pollingGetDevices()).whereType<MicrosoftEdgeDevice>(), isEmpty);
  });

  testWithoutContext('Edge is not support on non-windows platform', () async {
    final WebDevices webDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'linux',
        environment: <String, String>{}
      ),
      processManager: FakeProcessManager.list(<FakeCommand>[]),
    );

    expect((await webDevices.pollingGetDevices()).whereType<MicrosoftEdgeDevice>(), isEmpty);

    final WebDevices macosWebDevices = WebDevices(
      featureFlags: TestFeatureFlags(isWebEnabled: true),
      fileSystem: MemoryFileSystem.test(),
      logger: BufferLogger.test(),
      platform: FakePlatform(
        operatingSystem: 'macos',
        environment: <String, String>{}
      ),
      processManager: FakeProcessManager.list(<FakeCommand>[]),
    );

    expect((await macosWebDevices.pollingGetDevices()).whereType<MicrosoftEdgeDevice>(), isEmpty);
  });
}
