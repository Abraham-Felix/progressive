// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../rendering/mock_canvas.dart';

void main() {
  test('ContinuousRectangleBorder defaults', () {
    const ContinuousRectangleBorder border = ContinuousRectangleBorder();
    expect(border.side, BorderSide.none);
    expect(border.borderRadius, BorderRadius.zero);
  });

  test('ContinuousRectangleBorder copyWith, ==, hashCode', () {
    expect(const ContinuousRectangleBorder(), const ContinuousRectangleBorder().copyWith());
    expect(const ContinuousRectangleBorder().hashCode, const ContinuousRectangleBorder().copyWith().hashCode);
    const BorderSide side = BorderSide(width: 10.0, color: Color(0xff123456));
    const BorderRadius radius = BorderRadius.all(Radius.circular(16.0));
    expect(
      const ContinuousRectangleBorder().copyWith(side: side, borderRadius: radius),
      const ContinuousRectangleBorder(side: side, borderRadius: radius),
    );
  });

  test('ContinuousRectangleBorder scale and lerp', () {
    final ContinuousRectangleBorder c10 = ContinuousRectangleBorder(side: const BorderSide(width: 10.0), borderRadius: BorderRadius.circular(100.0));
    final ContinuousRectangleBorder c15 = ContinuousRectangleBorder(side: const BorderSide(width: 15.0), borderRadius: BorderRadius.circular(150.0));
    final ContinuousRectangleBorder c20 = ContinuousRectangleBorder(side: const BorderSide(width: 20.0), borderRadius: BorderRadius.circular(200.0));
    expect(c10.dimensions, const EdgeInsets.all(10.0));
    expect(c10.scale(2.0), c20);
    expect(c20.scale(0.5), c10);
    expect(ShapeBorder.lerp(c10, c20, 0.0), c10);
    expect(ShapeBorder.lerp(c10, c20, 0.5), c15);
    expect(ShapeBorder.lerp(c10, c20, 1.0), c20);
  });

  test('ContinuousRectangleBorder BorderRadius.zero', () {
    const Rect rect1 = Rect.fromLTRB(10.0, 20.0, 30.0, 40.0);
    final Matcher looksLikeRect1 = isPathThat(
      includes: const <Offset>[ Offset(10.0, 20.0), Offset(20.0, 30.0) ],
      excludes: const <Offset>[ Offset(9.0, 19.0), Offset(31.0, 41.0) ],
    );

    // Default border radius and border side are zero, i.e. just a rectangle.
    expect(const ContinuousRectangleBorder().getOuterPath(rect1), looksLikeRect1);
    expect(const ContinuousRectangleBorder().getInnerPath(rect1), looksLikeRect1);

    // Represents the inner path when borderSide.width = 4, which is just rect1
    // inset by 4 on all sides.
    final Matcher looksLikeInnerPath = isPathThat(
      includes: const <Offset>[ Offset(14.0, 24.0), Offset(16.0, 26.0) ],
      excludes: const <Offset>[ Offset(9.0, 23.0), Offset(27.0, 37.0) ],
    );

    const BorderSide side = BorderSide(width: 4.0);
    expect(const ContinuousRectangleBorder(side: side).getOuterPath(rect1), looksLikeRect1);
    expect(const ContinuousRectangleBorder(side: side).getInnerPath(rect1), looksLikeInnerPath);
  });

  test('ContinuousRectangleBorder non-zero BorderRadius', () {
    const Rect rect = Rect.fromLTRB(10.0, 20.0, 30.0, 40.0);
    final Matcher looksLikeRect = isPathThat(
      includes: const <Offset>[ Offset(15.0, 25.0), Offset(20.0, 30.0) ],
      excludes: const <Offset>[ Offset(10.0, 20.0), Offset(30.0, 40.0) ],
    );
    const ContinuousRectangleBorder border = ContinuousRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(5.0))
    );
    expect(border.getOuterPath(rect), looksLikeRect);
    expect(border.getInnerPath(rect), looksLikeRect);
  });

  testWidgets('Golden test even radii', (WidgetTester tester) async {
    await tester.pumpWidget(RepaintBoundary(
      child: Material(
        color: Colors.blueAccent[400],
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(28.0),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('continuous_rectangle_border.golden_test_even_radii.png'),
    );
  });

  testWidgets('Golden test varying radii', (WidgetTester tester) async {
    await tester.pumpWidget(RepaintBoundary(
      child: Material(
        color: Colors.green[100],
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.elliptical(100.0, 200.0),
            topRight: Radius.circular(350.0),
            bottomLeft: Radius.elliptical(2000.0, 100.0),
            bottomRight: Radius.circular(700.0),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('continuous_rectangle_border.golden_test_varying_radii.png'),
    );
  });

  testWidgets('Golden test topLeft radii', (WidgetTester tester) async {
    await tester.pumpWidget(RepaintBoundary(
      child: Material(
        color: Colors.green[200],
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.elliptical(100.0, 200.0),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('continuous_rectangle_border.golden_test_topLeft_radii.png'),
    );
  });

  testWidgets('Golden test topRight radii', (WidgetTester tester) async {
    await tester.pumpWidget(RepaintBoundary(
      child: Material(
        color: Colors.green[300],
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(350.0),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('continuous_rectangle_border.golden_test_topRight_radii.png'),
    );
  });

  testWidgets('Golden test bottomLeft radii', (WidgetTester tester) async {
    await tester.pumpWidget(RepaintBoundary(
      child: Material(
        color: Colors.green[400],
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.elliptical(2000.0, 100.0),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('continuous_rectangle_border.golden_test_bottomLeft_radii.png'),
    );
  });

  testWidgets('Golden test bottomRight radii', (WidgetTester tester) async {
    await tester.pumpWidget(RepaintBoundary(
      child: Material(
        color: Colors.green[500],
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomRight: Radius.circular(700.0),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('continuous_rectangle_border.golden_test_bottomRight_radii.png'),
    );
  });

  testWidgets('Golden test large radii', (WidgetTester tester) async {
    await tester.pumpWidget(RepaintBoundary(
      child: Material(
        color: Colors.redAccent[400],
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(50.0),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary),
      matchesGoldenFile('continuous_rectangle_border.golden_test_large_radii.png'),
    );
  });

}
