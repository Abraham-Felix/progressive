// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TextSpan equals', () {
    const TextSpan a1 = TextSpan(text: 'a');
    const TextSpan a2 = TextSpan(text: 'a');
    const TextSpan b1 = TextSpan(children: <TextSpan>[ a1 ]);
    const TextSpan b2 = TextSpan(children: <TextSpan>[ a2 ]);
    const TextSpan c1 = TextSpan(text: null);
    const TextSpan c2 = TextSpan(text: null);

    expect(a1 == a2, isTrue);
    expect(b1 == b2, isTrue);
    expect(c1 == c2, isTrue);

    expect(a1 == b2, isFalse);
    expect(b1 == c2, isFalse);
    expect(c1 == a2, isFalse);

    expect(a1 == c2, isFalse);
    expect(b1 == a2, isFalse);
    expect(c1 == b2, isFalse);

    void callback1(PointerEnterEvent _) {}
    void callback2(PointerEnterEvent _) {}

    final TextSpan d1 = TextSpan(text: 'a', onEnter: callback1);
    final TextSpan d2 = TextSpan(text: 'a', onEnter: callback1);
    final TextSpan d3 = TextSpan(text: 'a', onEnter: callback2);
    final TextSpan e1 = TextSpan(text: 'a', onEnter: callback2, mouseCursor: SystemMouseCursors.forbidden);
    final TextSpan e2 = TextSpan(text: 'a', onEnter: callback2, mouseCursor: SystemMouseCursors.forbidden);

    expect(a1 == d1, isFalse);
    expect(d1 == d2, isTrue);
    expect(d2 == d3, isFalse);
    expect(d3 == e1, isFalse);
    expect(e1 == e2, isTrue);
  });

  test('TextSpan toStringDeep', () {
    const TextSpan test = TextSpan(
      text: 'a',
      style: TextStyle(
        fontSize: 10.0,
      ),
      children: <TextSpan>[
        TextSpan(
          text: 'b',
          children: <TextSpan>[
            TextSpan(),
          ],
        ),
        TextSpan(
          text: 'c',
        ),
      ],
    );
    expect(test.toStringDeep(), equals(
      'TextSpan:\n'
      '  inherit: true\n'
      '  size: 10.0\n'
      '  "a"\n'
      '  TextSpan:\n'
      '    "b"\n'
      '    TextSpan:\n'
      '      (empty)\n'
      '  TextSpan:\n'
      '    "c"\n'
    ));
  });

  test('TextSpan toStringDeep for mouse', () {
    const TextSpan test1 = TextSpan(
      text: 'a',
    );
    expect(test1.toStringDeep(), equals(
      'TextSpan:\n'
      '  "a"\n'
    ));

    final TextSpan test2 = TextSpan(
      text: 'a',
      onEnter: (_) {},
      onExit: (_) {},
      mouseCursor: SystemMouseCursors.forbidden,
    );
    expect(test2.toStringDeep(), equals(
      'TextSpan:\n'
      '  "a"\n'
      '  callbacks: enter, exit\n'
      '  mouseCursor: SystemMouseCursor(forbidden)\n'
    ));
  });


  test('TextSpan toPlainText', () {
    const TextSpan textSpan = TextSpan(
      text: 'a',
      children: <TextSpan>[
        TextSpan(text: 'b'),
        TextSpan(text: 'c'),
      ],
    );
    expect(textSpan.toPlainText(), 'abc');
  });

  test('WidgetSpan toPlainText', () {
    const TextSpan textSpan = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(child: SizedBox(width: 10, height: 10)),
        TextSpan(text: 'c'),
      ],
    );
    expect(textSpan.toPlainText(), 'ab\uFFFCc');
  });

  test('TextSpan toPlainText with semanticsLabel', () {
    const TextSpan textSpan = TextSpan(
      text: 'a',
      children: <TextSpan>[
        TextSpan(text: 'b', semanticsLabel: 'foo'),
        TextSpan(text: 'c'),
      ],
    );
    expect(textSpan.toPlainText(), 'afooc');
    expect(textSpan.toPlainText(includeSemanticsLabels: false), 'abc');
  });

  test('TextSpan widget change test', () {
    const TextSpan textSpan1 = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(child: SizedBox(width: 10, height: 10)),
        TextSpan(text: 'c'),
      ],
    );

    const TextSpan textSpan2 = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(child: SizedBox(width: 10, height: 10)),
        TextSpan(text: 'c'),
      ],
    );

    const TextSpan textSpan3 = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(child: SizedBox(width: 11, height: 10)),
        TextSpan(text: 'c'),
      ],
    );

    const TextSpan textSpan4 = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(child: Text('test')),
        TextSpan(text: 'c'),
      ],
    );

    const TextSpan textSpan5 = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(child: Text('different!')),
        TextSpan(text: 'c'),
      ],
    );

    const TextSpan textSpan6 = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(
          child: SizedBox(width: 10, height: 10),
          alignment: PlaceholderAlignment.top,
        ),
        TextSpan(text: 'c'),
      ],
    );

    expect(textSpan1.compareTo(textSpan3), RenderComparison.layout);
    expect(textSpan1.compareTo(textSpan4), RenderComparison.layout);
    expect(textSpan1.compareTo(textSpan1), RenderComparison.identical);
    expect(textSpan2.compareTo(textSpan2), RenderComparison.identical);
    expect(textSpan3.compareTo(textSpan3), RenderComparison.identical);
    expect(textSpan2.compareTo(textSpan3), RenderComparison.layout);
    expect(textSpan4.compareTo(textSpan5), RenderComparison.layout);
    expect(textSpan3.compareTo(textSpan5), RenderComparison.layout);
    expect(textSpan2.compareTo(textSpan5), RenderComparison.layout);
    expect(textSpan1.compareTo(textSpan5), RenderComparison.layout);
    expect(textSpan1.compareTo(textSpan6), RenderComparison.layout);
  });

  test('TextSpan nested widget change test', () {
    const TextSpan textSpan1 = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                WidgetSpan(child: SizedBox(width: 10, height: 10)),
                TextSpan(text: 'The sky is falling :)'),
              ],
            ),
          ),
        ),
        TextSpan(text: 'c'),
      ],
    );

    const TextSpan textSpan2 = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                WidgetSpan(child: SizedBox(width: 10, height: 11)),
                TextSpan(text: 'The sky is falling :)'),
              ],
            ),
          ),
        ),
        TextSpan(text: 'c'),
      ],
    );

    expect(textSpan1.compareTo(textSpan2), RenderComparison.layout);
    expect(textSpan1.compareTo(textSpan1), RenderComparison.identical);
    expect(textSpan2.compareTo(textSpan2), RenderComparison.identical);
  });

  test('GetSpanForPosition with WidgetSpan', () {
    const TextSpan textSpan = TextSpan(
      text: 'a',
      children: <InlineSpan>[
        TextSpan(text: 'b'),
        WidgetSpan(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                WidgetSpan(child: SizedBox(width: 10, height: 10)),
                TextSpan(text: 'The sky is falling :)'),
              ],
            ),
          ),
        ),
        TextSpan(text: 'c'),
      ],
    );

    expect(textSpan.getSpanForPosition(const TextPosition(offset: 0)).runtimeType, TextSpan);
    expect(textSpan.getSpanForPosition(const TextPosition(offset: 1)).runtimeType, TextSpan);
    expect(textSpan.getSpanForPosition(const TextPosition(offset: 2)).runtimeType, WidgetSpan);
    expect(textSpan.getSpanForPosition(const TextPosition(offset: 3)).runtimeType, TextSpan);
  });

  test('TextSpan computeSemanticsInformation', () {
    final List<InlineSpanSemanticsInformation> collector = <InlineSpanSemanticsInformation>[];
    const TextSpan(text: 'aaa', semanticsLabel: 'bbb').computeSemanticsInformation(collector);
    expect(collector[0].text, 'aaa');
    expect(collector[0].semanticsLabel, 'bbb');
  });

  testWidgets('handles mouse cursor', (WidgetTester tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Text.rich(
            TextSpan(
              text: 'xxxxx',
              children: <InlineSpan>[
                TextSpan(
                  text: 'yyyyy',
                  mouseCursor: SystemMouseCursors.forbidden,
                ),
                TextSpan(
                  text: 'xxxxx',
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );

    final TestGesture gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(RichText)) - const Offset(40, 0));
    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);

    await gesture.moveTo(tester.getCenter(find.byType(RichText)));
    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.forbidden);

    await gesture.moveTo(tester.getCenter(find.byType(RichText)) + const Offset(40, 0));
    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
  });

  testWidgets('handles onEnter and onExit', (WidgetTester tester) async {
    final List<PointerEvent> logEvents = <PointerEvent>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Text.rich(
            TextSpan(
              text: 'xxxxx',
              children: <InlineSpan>[
                TextSpan(
                  text: 'yyyyy',
                  onEnter: (PointerEnterEvent event) {
                    logEvents.add(event);
                  },
                  onExit: (PointerExitEvent event) {
                    logEvents.add(event);
                  }
                ),
                const TextSpan(
                  text: 'xxxxx',
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );

    final TestGesture gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(RichText)) - const Offset(40, 0));
    expect(logEvents, isEmpty);

    await gesture.moveTo(tester.getCenter(find.byType(RichText)));
    expect(logEvents.length, 1);
    expect(logEvents[0], isA<PointerEnterEvent>());

    await gesture.moveTo(tester.getCenter(find.byType(RichText)) + const Offset(40, 0));
    expect(logEvents.length, 2);
    expect(logEvents[1], isA<PointerExitEvent>());
  });

}
