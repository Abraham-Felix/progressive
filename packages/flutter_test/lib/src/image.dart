// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'test_async_utils.dart';

final Map<int, ui.Image> _cache = <int, ui.Image>{};

/// Creates an arbitrarily sized image for testing.
///
/// If the [cache] parameter is set to true, the image will be cached for the
/// rest of this suite. This is normally desirable, assuming a test suite uses
/// images with the same dimensions in most tests, as it will save on memory
/// usage and CPU time over the course of the suite. However, it should be
/// avoided for images that are used only once in a test suite, especially if
/// the image is large, as it will require holding on to the memory for that
/// image for the duration of the suite.
///
/// This method requires real async work, and will not work properly in the
/// [FakeAsync] zones set up by [testWidgets]. Typically, it should be invoked
/// as a setup step before [testWidgets] are run, such as [setUp] or [setUpAll].
/// If needed, it can be invoked using [WidgetTester.runAsync].
Future<ui.Image> createTestImage({
  int width = 1,
  int height = 1,
  bool cache = true,
}) => TestAsyncUtils.guard(() async {
  assert(width != null && width > 0);
  assert(height != null && height > 0);
  assert(cache != null);

  final int cacheKey = hashValues(width, height);
  if (cache && _cache.containsKey(cacheKey)) {
    return _cache[cacheKey]!.clone();
  }

  final ui.Image image = await _createImage(width, height);
  if (cache) {
    _cache[cacheKey] = image.clone();
  }
  return image;
});

Future<ui.Image> _createImage(int width, int height) async {
  if (kIsWeb) {
    return _webCreateTestImage(
      width: width,
      height: height,
    );
  }

  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(List<int>.filled(width * height * 4, 0, growable: false)),
    width,
    height,
    ui.PixelFormat.rgba8888,
    (ui.Image image) {
      completer.complete(image);
    },
  );
  return completer.future;
}

/// Web doesn't support [decodeImageFromPixels]. Instead, generate a 1bpp BMP
/// and just use [instantiateImageCodec].
// TODO(dnfield): Remove this when https://github.com/flutter/flutter/issues/49244
// is resolved.
Future<ui.Image> _webCreateTestImage({
  required int width,
  required int height,
}) async {
  // See https://en.wikipedia.org/wiki/BMP_file_format for format examples.
  final int bufferSize = 0x36 + (width * height);
  final ByteData bmpData = ByteData(bufferSize);
  // 'BM' header
  bmpData.setUint8(0x00, 0x42);
  bmpData.setUint8(0x01, 0x4D);
  // Size of data
  bmpData.setUint32(0x02, bufferSize, Endian.little);
  // Offset where pixel array begins
  bmpData.setUint32(0x0A, 0x36, Endian.little);
  // Bytes in DIB header
  bmpData.setUint32(0x0E, 0x28, Endian.little);
  // width
  bmpData.setUint32(0x12, width, Endian.little);
  // height
  bmpData.setUint32(0x16, height, Endian.little);
  // Color panes
  bmpData.setUint16(0x1A, 0x01, Endian.little);
  // bpp
  bmpData.setUint16(0x1C, 0x01, Endian.little);
  // no compression
  bmpData.setUint32(0x1E, 0x00, Endian.little);
  // raw bitmap data size
  bmpData.setUint32(0x22, width * height, Endian.little);
  // print DPI width
  bmpData.setUint32(0x26, width, Endian.little);
  // print DPI height
  bmpData.setUint32(0x2A, height, Endian.little);
  // colors in the palette
  bmpData.setUint32(0x2E, 0x00, Endian.little);
  // important colors
  bmpData.setUint32(0x32, 0x00, Endian.little);
  // rest of data is zeroed as black pixels.

  final ui.Codec codec = await ui.instantiateImageCodec(
    bmpData.buffer.asUint8List(),
  );
  final ui.FrameInfo frameInfo = await codec.getNextFrame();
  return frameInfo.image;
}
