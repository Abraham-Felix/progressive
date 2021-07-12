// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../rendering/mock_canvas.dart';
import 'editable_text_utils.dart';
import 'semantics_tester.dart';

Matcher matchesMethodCall(String method, { dynamic args }) => _MatchesMethodCall(method, arguments: args == null ? null : wrapMatcher(args));

class _MatchesMethodCall extends Matcher {
  const _MatchesMethodCall(this.name, {this.arguments});

  final String name;
  final Matcher? arguments;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is MethodCall && item.method == name)
      return arguments?.matches(item.arguments, matchState) ?? true;
    return false;
  }

  @override
  Description describe(Description description) {
    final Description newDescription = description.add('has method name: ').addDescriptionOf(name);
    if (arguments != null)
        newDescription.add(' with arguments: ').addDescriptionOf(arguments);
    return newDescription;
  }
}

late TextEditingController controller;
final FocusNode focusNode = FocusNode(debugLabel: 'EditableText Node');
final FocusScopeNode focusScopeNode = FocusScopeNode(debugLabel: 'EditableText Scope Node');
const TextStyle textStyle = TextStyle();
const Color cursorColor = Color.fromARGB(0xFF, 0xFF, 0x00, 0x00);

enum HandlePositionInViewport {
  leftEdge, rightEdge, within,
}

class MockClipboard {
  Object _clipboardData = <String, dynamic>{
    'text': null,
  };

  Future<dynamic> handleMethodCall(MethodCall methodCall) async {
    switch (methodCall.method) {
      case 'Clipboard.getData':
        return _clipboardData;
      case 'Clipboard.setData':
        _clipboardData = methodCall.arguments as Object;
        break;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final MockClipboard mockClipboard = MockClipboard();
  SystemChannels.platform.setMockMethodCallHandler(mockClipboard.handleMethodCall);

  setUp(() async {
    debugResetSemanticsIdCounter();
    controller = TextEditingController();
    // Fill the clipboard so that the Paste option is available in the text
    // selection menu.
    await Clipboard.setData(const ClipboardData(text: 'Clipboard data'));
  });

  tearDown(() {
    controller.dispose();
  });

  // Tests that the desired keyboard action button is requested.
  //
  // More technically, when an EditableText is given a particular [action], Flutter
  // requests [serializedActionName] when attaching to the platform's input
  // system.
  Future<void> _desiredKeyboardActionIsRequested({
    required WidgetTester tester,
    TextInputAction? action,
    String serializedActionName = '',
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              textInputAction: action,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals(serializedActionName));
  }

  // Regression test for https://github.com/flutter/flutter/issues/34538.
  testWidgets('RTL arabic correct caret placement after trailing whitespace', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.blue,
              controller: controller,
              focusNode: focusNode,
              maxLines: 1, // Sets text keyboard implicitly.
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    await tester.idle();

    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

    // Simulates Gboard Persian input.
    state.updateEditingValue(const TextEditingValue(text: 'گ', selection: TextSelection.collapsed(offset: 1)));
    await tester.pump();
    double previousCaretXPosition = state.renderEditable.getLocalRectForCaret(state.textEditingValue.selection.base).left;

    state.updateEditingValue(const TextEditingValue(text: 'گی', selection: TextSelection.collapsed(offset: 2)));
    await tester.pump();
    double caretXPosition = state.renderEditable.getLocalRectForCaret(state.textEditingValue.selection.base).left;
    expect(caretXPosition, lessThan(previousCaretXPosition));
    previousCaretXPosition = caretXPosition;

    state.updateEditingValue(const TextEditingValue(text: 'گیگ', selection: TextSelection.collapsed(offset: 3)));
    await tester.pump();
    caretXPosition = state.renderEditable.getLocalRectForCaret(state.textEditingValue.selection.base).left;
    expect(caretXPosition, lessThan(previousCaretXPosition));
    previousCaretXPosition = caretXPosition;

    // Enter a whitespace in a RTL input field moves the caret to the left.
    state.updateEditingValue(const TextEditingValue(text: 'گیگ ', selection: TextSelection.collapsed(offset: 4)));
    await tester.pump();
    caretXPosition = state.renderEditable.getLocalRectForCaret(state.textEditingValue.selection.base).left;
    expect(caretXPosition, lessThan(previousCaretXPosition));

    expect(state.currentTextEditingValue.text, equals('گیگ '));
  }, skip: isBrowser); // https://github.com/flutter/flutter/issues/78550.

  testWidgets('has expected defaults', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: EditableText(
            controller: controller,
            backgroundCursorColor: Colors.grey,
            focusNode: focusNode,
            style: textStyle,
            cursorColor: cursorColor,
          ),
        ),
      ),
    );

    final EditableText editableText =
        tester.firstWidget(find.byType(EditableText));
    expect(editableText.maxLines, equals(1));
    expect(editableText.obscureText, isFalse);
    expect(editableText.autocorrect, isTrue);
    expect(editableText.enableSuggestions, isTrue);
    expect(editableText.textAlign, TextAlign.start);
    expect(editableText.cursorWidth, 2.0);
    expect(editableText.cursorHeight, isNull);
    expect(editableText.textHeightBehavior, isNull);
  });

  testWidgets('text keyboard is requested when maxLines is default', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              controller: controller,
              backgroundCursorColor: Colors.grey,
              focusNode: focusNode,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    final EditableText editableText =
        tester.firstWidget(find.byType(EditableText));
    expect(editableText.maxLines, equals(1));
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputType']['name'],
        equals('TextInputType.text'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals('TextInputAction.done'));
  });

  testWidgets('Keyboard is configured for "unspecified" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.unspecified,
      serializedActionName: 'TextInputAction.unspecified',
    );
  });

  testWidgets('Keyboard is configured for "none" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.none,
      serializedActionName: 'TextInputAction.none',
    );
  });

  testWidgets('Keyboard is configured for "done" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.done,
      serializedActionName: 'TextInputAction.done',
    );
  });

  testWidgets('Keyboard is configured for "send" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.send,
      serializedActionName: 'TextInputAction.send',
    );
  });

  testWidgets('Keyboard is configured for "go" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.go,
      serializedActionName: 'TextInputAction.go',
    );
  });

  testWidgets('Keyboard is configured for "search" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.search,
      serializedActionName: 'TextInputAction.search',
    );
  });

  testWidgets('Keyboard is configured for "send" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.send,
      serializedActionName: 'TextInputAction.send',
    );
  });

  testWidgets('Keyboard is configured for "next" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.next,
      serializedActionName: 'TextInputAction.next',
    );
  });

  testWidgets('Keyboard is configured for "previous" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.previous,
      serializedActionName: 'TextInputAction.previous',
    );
  });

  testWidgets('Keyboard is configured for "continue" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.continueAction,
      serializedActionName: 'TextInputAction.continueAction',
    );
  });

  testWidgets('Keyboard is configured for "join" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.join,
      serializedActionName: 'TextInputAction.join',
    );
  });

  testWidgets('Keyboard is configured for "route" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.route,
      serializedActionName: 'TextInputAction.route',
    );
  });

  testWidgets('Keyboard is configured for "emergencyCall" action when explicitly requested', (WidgetTester tester) async {
    await _desiredKeyboardActionIsRequested(
      tester: tester,
      action: TextInputAction.emergencyCall,
      serializedActionName: 'TextInputAction.emergencyCall',
    );
  });

  group('Infer keyboardType from autofillHints', () {
    testWidgets('infer keyboard types from autofillHints: ios',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 1.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FocusScope(
                node: focusScopeNode,
                autofocus: true,
                child: EditableText(
                  controller: controller,
                  backgroundCursorColor: Colors.grey,
                  focusNode: focusNode,
                  style: textStyle,
                  cursorColor: cursorColor,
                  autofillHints: const <String>[AutofillHints.streetAddressLine1],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(EditableText));
        await tester.showKeyboard(find.byType(EditableText));
        controller.text = 'test';
        await tester.idle();
        expect(tester.testTextInput.editingState!['text'], equals('test'));
        expect(
          tester.testTextInput.setClientArgs!['inputType']['name'],
          // On web, we don't infer the keyboard type as "name". We only infer
          // on iOS and macOS.
          kIsWeb ? equals('TextInputType.address') : equals('TextInputType.name'),
        );
    }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

    testWidgets('infer keyboard types from autofillHints: non-ios',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 1.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FocusScope(
                node: focusScopeNode,
                autofocus: true,
                child: EditableText(
                  controller: controller,
                  backgroundCursorColor: Colors.grey,
                  focusNode: focusNode,
                  style: textStyle,
                  cursorColor: cursorColor,
                  autofillHints: const <String>[AutofillHints.streetAddressLine1],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(EditableText));
        await tester.showKeyboard(find.byType(EditableText));
        controller.text = 'test';
        await tester.idle();
        expect(tester.testTextInput.editingState!['text'], equals('test'));
        expect(tester.testTextInput.setClientArgs!['inputType']['name'], equals('TextInputType.address'));
      });

    testWidgets('inferred keyboard types can be overridden: ios',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 1.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FocusScope(
                node: focusScopeNode,
                autofocus: true,
                child: EditableText(
                  controller: controller,
                  backgroundCursorColor: Colors.grey,
                  focusNode: focusNode,
                  style: textStyle,
                  cursorColor: cursorColor,
                  keyboardType: TextInputType.text,
                  autofillHints: const <String>[AutofillHints.streetAddressLine1],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(EditableText));
        await tester.showKeyboard(find.byType(EditableText));
        controller.text = 'test';
        await tester.idle();
        expect(tester.testTextInput.editingState!['text'], equals('test'));
        expect(tester.testTextInput.setClientArgs!['inputType']['name'], equals('TextInputType.text'));
    }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

    testWidgets('inferred keyboard types can be overridden: non-ios',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 1.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FocusScope(
                node: focusScopeNode,
                autofocus: true,
                child: EditableText(
                  controller: controller,
                  backgroundCursorColor: Colors.grey,
                  focusNode: focusNode,
                  style: textStyle,
                  cursorColor: cursorColor,
                  keyboardType: TextInputType.text,
                  autofillHints: const <String>[AutofillHints.streetAddressLine1],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(EditableText));
        await tester.showKeyboard(find.byType(EditableText));
        controller.text = 'test';
        await tester.idle();
        expect(tester.testTextInput.editingState!['text'], equals('test'));
        expect(tester.testTextInput.setClientArgs!['inputType']['name'], equals('TextInputType.text'));
    });
  });

  testWidgets('multiline keyboard is requested when set explicitly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              controller: controller,
              backgroundCursorColor: Colors.grey,
              focusNode: focusNode,
              keyboardType: TextInputType.multiline,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputType']['name'],
        equals('TextInputType.multiline'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals('TextInputAction.newline'));
  });

  testWidgets('visiblePassword keyboard is requested when set explicitly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              controller: controller,
              backgroundCursorColor: Colors.grey,
              focusNode: focusNode,
              keyboardType: TextInputType.visiblePassword,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputType']['name'],
        equals('TextInputType.visiblePassword'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals('TextInputAction.done'));
  });

  testWidgets('enableSuggestions flag is sent to the engine properly', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();
    const bool enableSuggestions = false;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              controller: controller,
              backgroundCursorColor: Colors.grey,
              focusNode: focusNode,
              enableSuggestions: enableSuggestions,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    await tester.idle();
    expect(tester.testTextInput.setClientArgs!['enableSuggestions'], enableSuggestions);
  });

  group('smartDashesType and smartQuotesType', () {
    testWidgets('sent to the engine properly', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      const SmartDashesType smartDashesType = SmartDashesType.disabled;
      const SmartQuotesType smartQuotesType = SmartQuotesType.disabled;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1.0),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FocusScope(
              node: focusScopeNode,
              autofocus: true,
              child: EditableText(
                controller: controller,
                backgroundCursorColor: Colors.grey,
                focusNode: focusNode,
                smartDashesType: smartDashesType,
                smartQuotesType: smartQuotesType,
                style: textStyle,
                cursorColor: cursorColor,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(EditableText));
      await tester.showKeyboard(find.byType(EditableText));
      await tester.idle();
      expect(tester.testTextInput.setClientArgs!['smartDashesType'], smartDashesType.index.toString());
      expect(tester.testTextInput.setClientArgs!['smartQuotesType'], smartQuotesType.index.toString());
    });

    testWidgets('default to true when obscureText is false', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1.0),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FocusScope(
              node: focusScopeNode,
              autofocus: true,
              child: EditableText(
                controller: controller,
                backgroundCursorColor: Colors.grey,
                focusNode: focusNode,
                style: textStyle,
                cursorColor: cursorColor,
                obscureText: false,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(EditableText));
      await tester.showKeyboard(find.byType(EditableText));
      await tester.idle();
      expect(tester.testTextInput.setClientArgs!['smartDashesType'], '1');
      expect(tester.testTextInput.setClientArgs!['smartQuotesType'], '1');
    });

    testWidgets('default to false when obscureText is true', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1.0),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FocusScope(
              node: focusScopeNode,
              autofocus: true,
              child: EditableText(
                controller: controller,
                backgroundCursorColor: Colors.grey,
                focusNode: focusNode,
                style: textStyle,
                cursorColor: cursorColor,
                obscureText: true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(EditableText));
      await tester.showKeyboard(find.byType(EditableText));
      await tester.idle();
      expect(tester.testTextInput.setClientArgs!['smartDashesType'], '0');
      expect(tester.testTextInput.setClientArgs!['smartQuotesType'], '0');
    });
  });

  testWidgets('selection overlay will update when text grow bigger', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'initial value',
        ),
    );
    Future<void> pumpEditableTextWithTextStyle(TextStyle style) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditableText(
            backgroundCursorColor: Colors.grey,
            controller: controller,
            focusNode: focusNode,
            style: style,
            cursorColor: cursorColor,
            selectionControls: materialTextSelectionControls,
            showSelectionHandles: true,
          ),
        ),
      );
    }

    await pumpEditableTextWithTextStyle(const TextStyle(fontSize: 18));
    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
    state.renderEditable.selectWordsInRange(
      from: Offset.zero,
      cause: SelectionChangedCause.longPress,
    );
    await tester.pumpAndSettle();
    await tester.idle();

    List<RenderBox> handles = List<RenderBox>.from(
      tester.renderObjectList<RenderBox>(
        find.descendant(
          of: find.byType(CompositedTransformFollower),
          matching: find.byType(GestureDetector),
        ),
      ),
    );

    expect(handles[0].localToGlobal(Offset.zero), const Offset(-35.0, 5.0));
    expect(handles[1].localToGlobal(Offset.zero), const Offset(113.0, 5.0));

    await pumpEditableTextWithTextStyle(const TextStyle(fontSize: 30));
    await tester.pumpAndSettle();

    // Handles should be updated with bigger font size.
    handles = List<RenderBox>.from(
      tester.renderObjectList<RenderBox>(
        find.descendant(
          of: find.byType(CompositedTransformFollower),
          matching: find.byType(GestureDetector),
        ),
      ),
    );
    // First handle should have the same dx but bigger dy.
    expect(handles[0].localToGlobal(Offset.zero), const Offset(-35.0, 17.0));
    expect(handles[1].localToGlobal(Offset.zero), const Offset(197.0, 17.0));
  });

  testWidgets('can update style of previous activated EditableText', (WidgetTester tester) async {
    final Key key1 = UniqueKey();
    final Key key2 = UniqueKey();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: Column(
              children: <Widget>[
                EditableText(
                  key: key1,
                  controller: TextEditingController(),
                  backgroundCursorColor: Colors.grey,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 9),
                  cursorColor: cursorColor,
                ),
                EditableText(
                  key: key2,
                  controller: TextEditingController(),
                  backgroundCursorColor: Colors.grey,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 9),
                  cursorColor: cursorColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(key1));
    await tester.showKeyboard(find.byKey(key1));
    controller.text = 'test';
    await tester.idle();
    RenderBox renderEditable = tester.renderObject(find.byKey(key1));
    expect(renderEditable.size.height, 9.0);
    // Taps the other EditableText to deactivate the first one.
    await tester.tap(find.byKey(key2));
    await tester.showKeyboard(find.byKey(key2));
    // Updates the style.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: Column(
              children: <Widget>[
                EditableText(
                  key: key1,
                  controller: TextEditingController(),
                  backgroundCursorColor: Colors.grey,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 20),
                  cursorColor: cursorColor,
                ),
                EditableText(
                  key: key2,
                  controller: TextEditingController(),
                  backgroundCursorColor: Colors.grey,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 9),
                  cursorColor: cursorColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    renderEditable = tester.renderObject(find.byKey(key1));
    expect(renderEditable.size.height, 20.0);
    expect(tester.takeException(), null);
  });

  testWidgets('Multiline keyboard with newline action is requested when maxLines = null', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              controller: controller,
              backgroundCursorColor: Colors.grey,
              focusNode: focusNode,
              maxLines: null,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputType']['name'],
        equals('TextInputType.multiline'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals('TextInputAction.newline'));
  });

  testWidgets('Text keyboard is requested when explicitly set and maxLines = null', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
              keyboardType: TextInputType.text,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputType']['name'],
        equals('TextInputType.text'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals('TextInputAction.done'));
  });

  testWidgets('Correct keyboard is requested when set explicitly and maxLines > 1', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.phone,
              maxLines: 3,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputType']['name'],
        equals('TextInputType.phone'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals('TextInputAction.done'));
  });

  testWidgets('multiline keyboard is requested when set implicitly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              maxLines: 3, // Sets multiline keyboard implicitly.
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputType']['name'],
        equals('TextInputType.multiline'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals('TextInputAction.newline'));
  });

  testWidgets('single line inputs have correct default keyboard', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              maxLines: 1, // Sets text keyboard implicitly.
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(tester.testTextInput.setClientArgs!['inputType']['name'],
        equals('TextInputType.text'));
    expect(tester.testTextInput.setClientArgs!['inputAction'],
        equals('TextInputAction.done'));
  });

  testWidgets('connection is closed when TextInputClient.onConnectionClosed message received', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              maxLines: 1, // Sets text keyboard implicitly.
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(state.wantKeepAlive, true);

    tester.testTextInput.log.clear();
    tester.testTextInput.closeConnection();
    await tester.idle();

    // Widget does not have focus anymore.
    expect(state.wantKeepAlive, false);
    // No method calls are sent from the framework.
    // This makes sure hide/clearClient methods are not called after connection
    // closed.
    expect(tester.testTextInput.log, isEmpty);
  });

  testWidgets('closed connection reopened when user focused', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              maxLines: 1, // Sets text keyboard implicitly.
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test3';
    await tester.idle();

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));
    expect(tester.testTextInput.editingState!['text'], equals('test3'));
    expect(state.wantKeepAlive, true);

    tester.testTextInput.log.clear();
    tester.testTextInput.closeConnection();
    await tester.pumpAndSettle();

    // Widget does not have focus anymore.
    expect(state.wantKeepAlive, false);
    // No method calls are sent from the framework.
    // This makes sure hide/clearClient methods are not called after connection
    // closed.
    expect(tester.testTextInput.log, isEmpty);

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump();
    controller.text = 'test2';
    expect(tester.testTextInput.editingState!['text'], equals('test2'));
    // Widget regained the focus.
    expect(state.wantKeepAlive, true);
  });

  testWidgets('closed connection reopened when user focused on another field', (WidgetTester tester) async {
    final EditableText testNameField =
      EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        maxLines: null,
        keyboardType: TextInputType.text,
        style: textStyle,
        cursorColor: cursorColor,
      );

    final EditableText testPhoneField =
      EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.phone,
        maxLines: 3,
        style: textStyle,
        cursorColor: cursorColor,
      );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: ListView(
              children: <Widget>[
                testNameField,
                testPhoneField,
              ],
            ),
          ),
        ),
      ),
    );

    // Tap, enter text.
    await tester.tap(find.byWidget(testNameField));
    await tester.showKeyboard(find.byWidget(testNameField));
    controller.text = 'test';
    await tester.idle();

    expect(tester.testTextInput.editingState!['text'], equals('test'));
    final EditableTextState state =
        tester.state<EditableTextState>(find.byWidget(testNameField));
    expect(state.wantKeepAlive, true);

    tester.testTextInput.log.clear();
    tester.testTextInput.closeConnection();
    // A pump is needed to allow the focus change (unfocus) to be resolved.
    await tester.pump();

    // Widget does not have focus anymore.
    expect(state.wantKeepAlive, false);
    // No method calls are sent from the framework.
    // This makes sure hide/clearClient methods are not called after connection
    // closed.
    expect(tester.testTextInput.log, isEmpty);

    // For the next fields, tap, enter text.
    await tester.tap(find.byWidget(testPhoneField));
    await tester.showKeyboard(find.byWidget(testPhoneField));
    controller.text = '650123123';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('650123123'));
    // Widget regained the focus.
    expect(state.wantKeepAlive, true);
  });

  /// Toolbar is not used in Flutter Web. Skip this check.
  ///
  /// Web is using native DOM elements (it is also used as platform input)
  /// to enable clipboard functionality of the toolbar: copy, paste, select,
  /// cut. It might also provide additional functionality depending on the
  /// browser (such as translation). Due to this, in browsers, we should not
  /// show a Flutter toolbar for the editable text elements.
  testWidgets('can show toolbar when there is text and a selection', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: controller,
          focusNode: focusNode,
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: materialTextSelectionControls,
        ),
      ),
    );

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));

    // Can't show the toolbar when there's no focus.
    expect(state.showToolbar(), false);
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsNothing);

    // Can show the toolbar when focused even though there's no text.
    state.renderEditable.selectWordsInRange(
      from: Offset.zero,
      cause: SelectionChangedCause.tap,
    );
    await tester.pump();
    // On web, we don't let Flutter show the toolbar.
    expect(state.showToolbar(), kIsWeb ? isFalse : isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Paste'), kIsWeb ? findsNothing : findsOneWidget);

    // Hide the menu again.
    state.hideToolbar();
    await tester.pump();
    expect(find.text('Paste'), findsNothing);

    // Can show the menu with text and a selection.
    controller.text = 'blah';
    await tester.pump();
    // On web, we don't let Flutter show the toolbar.
    expect(state.showToolbar(), kIsWeb ? isFalse : isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Paste'), kIsWeb ? findsNothing : findsOneWidget);
  });

  testWidgets('can show the toolbar after clearing all text', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/35998.
    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: controller,
          focusNode: focusNode,
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: materialTextSelectionControls,
        ),
      ),
    );

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));

    // Add text and an empty selection.
    controller.text = 'blah';
    await tester.pump();
    state.renderEditable.selectWordsInRange(
      from: Offset.zero,
      cause: SelectionChangedCause.tap,
    );
    await tester.pump();

    // Clear the text and selection.
    expect(find.text('Paste'), findsNothing);
    state.updateEditingValue(TextEditingValue.empty);
    await tester.pump();

    // Should be able to show the toolbar.
    // On web, we don't let Flutter show the toolbar.
    expect(state.showToolbar(), kIsWeb ? isFalse : isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Paste'), kIsWeb ? findsNothing : findsOneWidget);
  });

  testWidgets('can dynamically disable options in toolbar', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: TextEditingController(text: 'blah blah'),
          focusNode: focusNode,
          toolbarOptions: const ToolbarOptions(
            copy: true,
            selectAll: true,
          ),
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: materialTextSelectionControls,
        ),
      ),
    );

    final EditableTextState state =
    tester.state<EditableTextState>(find.byType(EditableText));

    // Select something. Doesn't really matter what.
    state.renderEditable.selectWordsInRange(
      from: Offset.zero,
      cause: SelectionChangedCause.tap,
    );
    await tester.pump();
    // On web, we don't let Flutter show the toolbar.
    expect(state.showToolbar(), kIsWeb ? isFalse : isTrue);
    await tester.pump();
    expect(find.text('Select all'), kIsWeb ? findsNothing : findsOneWidget);
    expect(find.text('Copy'), kIsWeb ? findsNothing : findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Cut'), findsNothing);
  });

  testWidgets('can dynamically disable select all option in toolbar - cupertino', (WidgetTester tester) async {
    // Regression test: https://github.com/flutter/flutter/issues/40711
    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: TextEditingController(text: 'blah blah'),
          focusNode: focusNode,
          toolbarOptions: const ToolbarOptions(
            selectAll: false,
          ),
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: cupertinoTextSelectionControls,
        ),
      ),
    );

    final EditableTextState state =
      tester.state<EditableTextState>(find.byType(EditableText));
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    // On web, we don't let Flutter show the toolbar.
    expect(state.showToolbar(), kIsWeb ? isFalse : isTrue);
    await tester.pump();
    expect(find.text('Select All'), findsNothing);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Cut'), findsNothing);
  });

  testWidgets('can dynamically disable select all option in toolbar - material', (WidgetTester tester) async {
    // Regression test: https://github.com/flutter/flutter/issues/40711
    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: TextEditingController(text: 'blah blah'),
          focusNode: focusNode,
          toolbarOptions: const ToolbarOptions(
            copy: true,
            selectAll: false,
          ),
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: materialTextSelectionControls,
        ),
      ),
    );

    final EditableTextState state =
      tester.state<EditableTextState>(find.byType(EditableText));

    // Select something. Doesn't really matter what.
    state.renderEditable.selectWordsInRange(
      from: Offset.zero,
      cause: SelectionChangedCause.tap,
    );
    await tester.pump();
    // On web, we don't let Flutter show the toolbar.
    expect(state.showToolbar(),  kIsWeb ? isFalse : isTrue);
    await tester.pump();
    expect(find.text('Select all'), findsNothing);
    expect(find.text('Copy'),  kIsWeb ? findsNothing : findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Cut'), findsNothing);
  });

  testWidgets('cut and paste are disabled in read only mode even if explicit set', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: TextEditingController(text: 'blah blah'),
          focusNode: focusNode,
          readOnly: true,
          toolbarOptions: const ToolbarOptions(
            paste: true,
            cut: true,
            selectAll: true,
            copy: true,
          ),
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: materialTextSelectionControls,
        ),
      ),
    );

    final EditableTextState state =
    tester.state<EditableTextState>(find.byType(EditableText));

    // Select something. Doesn't really matter what.
    state.renderEditable.selectWordsInRange(
      from: Offset.zero,
      cause: SelectionChangedCause.tap,
    );
    await tester.pump();
    // On web, we don't let Flutter show the toolbar.
    expect(state.showToolbar(), kIsWeb ? isFalse : isTrue);
    await tester.pump();
    expect(find.text('Select all'), kIsWeb ? findsNothing : findsOneWidget);
    expect(find.text('Copy'), kIsWeb ? findsNothing : findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Cut'), findsNothing);
  });

  testWidgets('Handles the read-only flag correctly', (WidgetTester tester) async {
    final TextEditingController controller =
        TextEditingController(text: 'Lorem ipsum dolor sit amet');
    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          readOnly: true,
          controller: controller,
          backgroundCursorColor: Colors.grey,
          focusNode: focusNode,
          style: textStyle,
          cursorColor: cursorColor,
        ),
      ),
    );

    // Interact with the field to establish the input connection.
    final Offset topLeft = tester.getTopLeft(find.byType(EditableText));
    await tester.tapAt(topLeft + const Offset(0.0, 5.0));
    await tester.pump();

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    if (kIsWeb) {
      // On the web, a regular connection to the platform should've been made
      // with the `readOnly` flag set to true.
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.setClientArgs!['readOnly'], isTrue);
      expect(
        tester.testTextInput.editingState!['text'],
        'Lorem ipsum dolor sit amet',
      );
      expect(tester.testTextInput.editingState!['selectionBase'], 0);
      expect(tester.testTextInput.editingState!['selectionExtent'], 5);
    } else {
      // On non-web platforms, a read-only field doesn't need a connection with
      // the platform.
      expect(tester.testTextInput.hasAnyClients, isFalse);
    }
  });

  testWidgets('Does not accept updates when read-only', (WidgetTester tester) async {
    final TextEditingController controller =
        TextEditingController(text: 'Lorem ipsum dolor sit amet');
    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          readOnly: true,
          controller: controller,
          backgroundCursorColor: Colors.grey,
          focusNode: focusNode,
          style: textStyle,
          cursorColor: cursorColor,
        ),
      ),
    );

    // Interact with the field to establish the input connection.
    final Offset topLeft = tester.getTopLeft(find.byType(EditableText));
    await tester.tapAt(topLeft + const Offset(0.0, 5.0));
    await tester.pump();

    expect(tester.testTextInput.hasAnyClients, kIsWeb ? isTrue : isFalse);
    if (kIsWeb) {
      // On the web, the input connection exists, but text updates should be
      // ignored.
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'Foo bar',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
        composing: TextRange(start: 3, end: 4),
      ));
      // Only selection should change.
      expect(
        controller.value,
        const TextEditingValue(
          text: 'Lorem ipsum dolor sit amet',
          selection: TextSelection(baseOffset: 0, extentOffset: 3),
          composing: TextRange.empty,
        ),
      );
    }
  });

  testWidgets('Read-only fields do not format text', (WidgetTester tester) async {
    late SelectionChangedCause selectionCause;

    final TextEditingController controller =
        TextEditingController(text: 'Lorem ipsum dolor sit amet');

    await tester.pumpWidget(
      MaterialApp(
        home: EditableText(
          readOnly: true,
          controller: controller,
          backgroundCursorColor: Colors.grey,
          focusNode: focusNode,
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: materialTextSelectionControls,
          onSelectionChanged: (TextSelection selection, SelectionChangedCause? cause) {
            selectionCause = cause!;
          },
        ),
      ),
    );

    // Interact with the field to establish the input connection.
    final Offset topLeft = tester.getTopLeft(find.byType(EditableText));
    await tester.tapAt(topLeft + const Offset(0.0, 5.0));
    await tester.pump();

    expect(tester.testTextInput.hasAnyClients, kIsWeb ? isTrue : isFalse);
    if (kIsWeb) {
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'Foo bar',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
      ));
      // On web, the only way a text field can be updated from the engine is if
      // a keyboard is used.
      expect(selectionCause, SelectionChangedCause.keyboard);
    }
  });

  testWidgets('Sends "updateConfig" when read-only flag is flipped', (WidgetTester tester) async {
    bool readOnly = true;
    late StateSetter setState;
    final TextEditingController controller = TextEditingController(text: 'Lorem ipsum dolor sit amet');

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(builder: (BuildContext context, StateSetter stateSetter) {
          setState = stateSetter;
          return EditableText(
            readOnly: readOnly,
            controller: controller,
            backgroundCursorColor: Colors.grey,
            focusNode: focusNode,
            style: textStyle,
            cursorColor: cursorColor,
          );
        }),
      ),
    );

    // Interact with the field to establish the input connection.
    final Offset topLeft = tester.getTopLeft(find.byType(EditableText));
    await tester.tapAt(topLeft + const Offset(0.0, 5.0));
    await tester.pump();

    expect(tester.testTextInput.hasAnyClients, kIsWeb ? isTrue : isFalse);
    if (kIsWeb) {
      expect(tester.testTextInput.setClientArgs!['readOnly'], isTrue);
    }

    setState(() { readOnly = false; });
    await tester.pump();

    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.setClientArgs!['readOnly'], isFalse);
  });

  testWidgets('Fires onChanged when text changes via TextSelectionOverlay', (WidgetTester tester) async {
    late String changedValue;
    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: TextEditingController(),
        focusNode: FocusNode(),
        style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
        cursorColor: Colors.blue,
        selectionControls: materialTextSelectionControls,
        keyboardType: TextInputType.text,
        onChanged: (String value) {
          changedValue = value;
        },
      ),
    );
    await tester.pumpWidget(widget);

    // Populate a fake clipboard.
    const String clipboardContent = 'Dobunezumi mitai ni utsukushiku naritai';
    Clipboard.setData(const ClipboardData(text: clipboardContent));

    // Long-press to bring up the text editing controls.
    final Finder textFinder = find.byType(EditableText);
    await tester.longPress(textFinder);
    tester.state<EditableTextState>(textFinder).showToolbar();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paste'));
    await tester.pump();

    expect(changedValue, clipboardContent);

    // On web, we don't show the Flutter toolbar and instead rely on the browser
    // toolbar. Until we change that, this test should remain skipped.
  }, skip: kIsWeb);

  // The variants to test in the focus handling test.
  final ValueVariant<TextInputAction> focusVariants = ValueVariant<
      TextInputAction>(
    TextInputAction.values.toSet(),
  );

  testWidgets('Handles focus correctly when action is invoked', (WidgetTester tester) async {
    // The expectations for each of the types of TextInputAction.
    const Map<TextInputAction, bool> actionShouldLoseFocus = <TextInputAction, bool>{
      TextInputAction.none: false,
      TextInputAction.unspecified: false,
      TextInputAction.done: true,
      TextInputAction.go: true,
      TextInputAction.search: true,
      TextInputAction.send: true,
      TextInputAction.continueAction: false,
      TextInputAction.join: false,
      TextInputAction.route: false,
      TextInputAction.emergencyCall: false,
      TextInputAction.newline: true,
      TextInputAction.next: true,
      TextInputAction.previous: true,
    };

    final TextInputAction action = focusVariants.currentValue!;
    expect(actionShouldLoseFocus.containsKey(action), isTrue);

    Future<void> _ensureCorrectFocusHandlingForAction(
        TextInputAction action, {
          required bool shouldLoseFocus,
          bool shouldFocusNext = false,
          bool shouldFocusPrevious = false,
        }) async {
      final FocusNode focusNode = FocusNode();
      final GlobalKey previousKey = GlobalKey();
      final GlobalKey nextKey = GlobalKey();

      final Widget widget = MaterialApp(
        home: Column(
          children: <Widget>[
            TextButton(
                child: Text('Previous Widget', key: previousKey),
                onPressed: () {}),
            EditableText(
              backgroundCursorColor: Colors.grey,
              controller: TextEditingController(),
              focusNode: focusNode,
              style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
              cursorColor: Colors.blue,
              selectionControls: materialTextSelectionControls,
              keyboardType: TextInputType.text,
              autofocus: true,
            ),
            TextButton(
                child: Text('Next Widget', key: nextKey), onPressed: () {}),
          ],
        ),
      );
      await tester.pumpWidget(widget);

      assert(focusNode.hasFocus);

      await tester.testTextInput.receiveAction(action);
      await tester.pump();

      expect(Focus.of(nextKey.currentContext!).hasFocus, equals(shouldFocusNext));
      expect(Focus.of(previousKey.currentContext!).hasFocus, equals(shouldFocusPrevious));
      expect(focusNode.hasFocus, equals(!shouldLoseFocus));
    }

    try {
      await _ensureCorrectFocusHandlingForAction(
        action,
        shouldLoseFocus: actionShouldLoseFocus[action]!,
        shouldFocusNext: action == TextInputAction.next,
        shouldFocusPrevious: action == TextInputAction.previous,
      );
    } on PlatformException {
      // on Android, continueAction isn't supported.
      expect(action, equals(TextInputAction.continueAction));
    }
  }, variant: focusVariants);

  testWidgets('Does not lose focus by default when "done" action is pressed and onEditingComplete is provided', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();

    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: TextEditingController(),
        focusNode: focusNode,
        style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
        cursorColor: Colors.blue,
        selectionControls: materialTextSelectionControls,
        keyboardType: TextInputType.text,
        onEditingComplete: () {
          // This prevents the default focus change behavior on submission.
        },
      ),
    );
    await tester.pumpWidget(widget);

    // Select EditableText to give it focus.
    final Finder textFinder = find.byType(EditableText);
    await tester.tap(textFinder);
    await tester.pump();

    assert(focusNode.hasFocus);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Still has focus even though "done" was pressed because onEditingComplete
    // was provided and it overrides the default behavior.
    expect(focusNode.hasFocus, true);
  });

  testWidgets('When "done" is pressed callbacks are invoked: onEditingComplete > onSubmitted', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();

    bool onEditingCompleteCalled = false;
    bool onSubmittedCalled = false;

    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: TextEditingController(),
        focusNode: focusNode,
        style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
        cursorColor: Colors.blue,
        onEditingComplete: () {
          onEditingCompleteCalled = true;
          expect(onSubmittedCalled, false);
        },
        onSubmitted: (String value) {
          onSubmittedCalled = true;
          expect(onEditingCompleteCalled, true);
        },
      ),
    );
    await tester.pumpWidget(widget);

    // Select EditableText to give it focus.
    final Finder textFinder = find.byType(EditableText);
    await tester.tap(textFinder);
    await tester.pump();

    assert(focusNode.hasFocus);

    // The execution path starting with receiveAction() will trigger the
    // onEditingComplete and onSubmission callbacks.
    await tester.testTextInput.receiveAction(TextInputAction.done);

    // The expectations we care about are up above in the onEditingComplete
    // and onSubmission callbacks.
  });

  testWidgets('When "next" is pressed callbacks are invoked: onEditingComplete > onSubmitted', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();

    bool onEditingCompleteCalled = false;
    bool onSubmittedCalled = false;

    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: TextEditingController(),
        focusNode: focusNode,
        style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
        cursorColor: Colors.blue,
        onEditingComplete: () {
          onEditingCompleteCalled = true;
          assert(!onSubmittedCalled);
        },
        onSubmitted: (String value) {
          onSubmittedCalled = true;
          assert(onEditingCompleteCalled);
        },
      ),
    );
    await tester.pumpWidget(widget);

    // Select EditableText to give it focus.
    final Finder textFinder = find.byType(EditableText);
    await tester.tap(textFinder);
    await tester.pump();

    assert(focusNode.hasFocus);

    // The execution path starting with receiveAction() will trigger the
    // onEditingComplete and onSubmission callbacks.
    await tester.testTextInput.receiveAction(TextInputAction.done);

    // The expectations we care about are up above in the onEditingComplete
    // and onSubmission callbacks.
  });

  testWidgets('When "newline" action is called on a Editable text with maxLines == 1 callbacks are invoked: onEditingComplete > onSubmitted', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();

    bool onEditingCompleteCalled = false;
    bool onSubmittedCalled = false;

    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: TextEditingController(),
        focusNode: focusNode,
        style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
        cursorColor: Colors.blue,
        maxLines: 1,
        onEditingComplete: () {
          onEditingCompleteCalled = true;
          assert(!onSubmittedCalled);
        },
        onSubmitted: (String value) {
          onSubmittedCalled = true;
          assert(onEditingCompleteCalled);
        },
      ),
    );
    await tester.pumpWidget(widget);

    // Select EditableText to give it focus.
    final Finder textFinder = find.byType(EditableText);
    await tester.tap(textFinder);
    await tester.pump();

    assert(focusNode.hasFocus);

    // The execution path starting with receiveAction() will trigger the
    // onEditingComplete and onSubmission callbacks.
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    // The expectations we care about are up above in the onEditingComplete
    // and onSubmission callbacks.
  });

  testWidgets('When "newline" action is called on a Editable text with maxLines != 1, onEditingComplete and onSubmitted callbacks are not invoked.', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();

    bool onEditingCompleteCalled = false;
    bool onSubmittedCalled = false;

    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: TextEditingController(),
        focusNode: focusNode,
        style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
        cursorColor: Colors.blue,
        maxLines: 3,
        onEditingComplete: () {
          onEditingCompleteCalled = true;
        },
        onSubmitted: (String value) {
          onSubmittedCalled = true;
        },
      ),
    );
    await tester.pumpWidget(widget);

    // Select EditableText to give it focus.
    final Finder textFinder = find.byType(EditableText);
    await tester.tap(textFinder);
    await tester.pump();

    assert(focusNode.hasFocus);

    // The execution path starting with receiveAction() will trigger the
    // onEditingComplete and onSubmission callbacks.
    await tester.testTextInput.receiveAction(TextInputAction.newline);

    // These callbacks shouldn't have been triggered.
    assert(!onSubmittedCalled);
    assert(!onEditingCompleteCalled);
  });

  testWidgets(
    'iOS autocorrection rectangle should appear on demand and dismiss when the text changes or when focus is lost',
    (WidgetTester tester) async {
      const Color rectColor = Color(0xFFFF0000);

      void verifyAutocorrectionRectVisibility({ required bool expectVisible }) {
        PaintPattern evaluate() {
          if (expectVisible) {
            return paints..something(((Symbol method, List<dynamic> arguments) {
              if (method != #drawRect)
                return false;
              final Paint paint = arguments[1] as Paint;
              return paint.color == rectColor;
            }));
          } else {
            return paints..everything(((Symbol method, List<dynamic> arguments) {
              if (method != #drawRect)
                return true;
              final Paint paint = arguments[1] as Paint;
              if (paint.color != rectColor)
                return true;
              throw 'Expected: autocorrection rect not visible, found: ${arguments[0]}';
            }));
          }
        }

        expect(findRenderEditable(tester), evaluate());
      }

      final FocusNode focusNode = FocusNode();
      final TextEditingController controller = TextEditingController(text: 'ABCDEFG');

      final Widget widget = MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: controller,
          focusNode: focusNode,
          style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
          cursorColor: Colors.blue,
          autocorrect: true,
          autocorrectionTextRectColor: rectColor,
          showCursor: false,
          onEditingComplete: () { },
        ),
      );

      await tester.pumpWidget(widget);

      await tester.tap(find.byType(EditableText));
      await tester.pump();
      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

      assert(focusNode.hasFocus);

      // The prompt rect should be invisible initially.
      verifyAutocorrectionRectVisibility(expectVisible: false);

      state.showAutocorrectionPromptRect(0, 1);
      await tester.pump();

      // Show prompt rect when told to.
      verifyAutocorrectionRectVisibility(expectVisible: true);

      // Text changed, prompt rect goes away.
      controller.text = '12345';
      await tester.pump();
      verifyAutocorrectionRectVisibility(expectVisible: false);

      state.showAutocorrectionPromptRect(0, 1);
      await tester.pump();

      verifyAutocorrectionRectVisibility(expectVisible: true);

      // Unfocus, prompt rect should go away.
      focusNode.unfocus();
      await tester.pump();
      verifyAutocorrectionRectVisibility(expectVisible: false);
  });

  testWidgets('Changing controller updates EditableText', (WidgetTester tester) async {
    final TextEditingController controller1 =
        TextEditingController(text: 'Wibble');
    final TextEditingController controller2 =
        TextEditingController(text: 'Wobble');
    TextEditingController currentController = controller1;
    late StateSetter setState;

    final FocusNode focusNode = FocusNode(debugLabel: 'EditableText Focus Node');
    Widget builder() {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setter) {
          setState = setter;
          return MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 1.0),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: Material(
                    child: EditableText(
                      backgroundCursorColor: Colors.grey,
                      controller: currentController,
                      focusNode: focusNode,
                      style: Typography.material2018(platform: TargetPlatform.android)
                          .black
                          .subtitle1!,
                      cursorColor: Colors.blue,
                      selectionControls: materialTextSelectionControls,
                      keyboardType: TextInputType.text,
                      onChanged: (String value) { },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    await tester.pumpWidget(builder());
    await tester.pump(); // An extra pump to allow focus request to go through.

    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });

    await tester.showKeyboard(find.byType(EditableText));

    // Verify TextInput.setEditingState and TextInput.setEditableSizeAndTransform are
    // both fired with updated text when controller is replaced.
    setState(() {
      currentController = controller2;
    });
    await tester.pump();

    expect(
      log.lastWhere((MethodCall m) => m.method == 'TextInput.setEditingState'),
      isMethodCall(
        'TextInput.setEditingState',
        arguments: const <String, dynamic>{
          'text': 'Wobble',
          'selectionBase': -1,
          'selectionExtent': -1,
          'selectionAffinity': 'TextAffinity.downstream',
          'selectionIsDirectional': false,
          'composingBase': -1,
          'composingExtent': -1,
        },
      ),
    );
    expect(
      log.lastWhere((MethodCall m) => m.method == 'TextInput.setEditableSizeAndTransform'),
      isMethodCall(
        'TextInput.setEditableSizeAndTransform',
        arguments: <String, dynamic>{
          'width': 800,
          'height': 14,
          'transform': Matrix4.translationValues(0.0, 293.0, 0.0).storage.toList(),
        },
      ),
    );
  });

  testWidgets('EditableText identifies as text field (w/ focus) in semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
        textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    expect(semantics, includesNodeWith(flags: <SemanticsFlag>[SemanticsFlag.isTextField]));

    await tester.tap(find.byType(EditableText));
    await tester.idle();
    await tester.pump();

    expect(
      semantics,
      includesNodeWith(flags: <SemanticsFlag>[
        SemanticsFlag.isTextField,
        SemanticsFlag.isFocused,
      ]),
    );

    semantics.dispose();
  });

  testWidgets('EditableText sets multi-line flag in semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
        textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              style: textStyle,
              cursorColor: cursorColor,
              maxLines: 1,
            ),
          ),
        ),
      ),
    );

    expect(
      semantics,
      includesNodeWith(flags: <SemanticsFlag>[SemanticsFlag.isTextField]),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              style: textStyle,
              cursorColor: cursorColor,
              maxLines: 3,
            ),
          ),
        ),
      ),
    );

    expect(
      semantics,
      includesNodeWith(flags: <SemanticsFlag>[
        SemanticsFlag.isTextField,
        SemanticsFlag.isMultiline,
      ]),
    );

    semantics.dispose();
  });

  testWidgets('EditableText includes text as value in semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    const String value1 = 'EditableText content';

    controller.text = value1;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    );

    expect(
      semantics,
      includesNodeWith(
        flags: <SemanticsFlag>[SemanticsFlag.isTextField],
        value: value1,
      ),
    );

    const String value2 = 'Changed the EditableText content';
    controller.text = value2;
    await tester.idle();
    await tester.pump();

    expect(
      semantics,
      includesNodeWith(
        flags: <SemanticsFlag>[SemanticsFlag.isTextField],
        value: value2,
      ),
    );

    semantics.dispose();
  });

  testWidgets('exposes correct cursor movement semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    controller.text = 'test';

    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    focusNode.requestFocus();
    await tester.pump();

    expect(
      semantics,
      includesNodeWith(
        value: 'test',
      ),
    );

    controller.selection =
        TextSelection.collapsed(offset:controller.text.length);
    await tester.pumpAndSettle();

    // At end, can only go backwards.
    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    controller.selection =
        TextSelection.collapsed(offset:controller.text.length - 2);
    await tester.pumpAndSettle();

    // Somewhere in the middle, can go in both directions.
    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();

    // At beginning, can only go forward.
    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    semantics.dispose();
  });

  testWidgets('can move cursor with a11y means - character', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    const bool doNotExtendSelection = false;

    controller.text = 'test';
    controller.selection =
        TextSelection.collapsed(offset:controller.text.length);

    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
        ],
      ),
    );

    final RenderEditable render = tester.allRenderObjects.whereType<RenderEditable>().first;
    final int semanticsId = render.debugSemantics!.id;

    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 4);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByCharacter, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 3);
    expect(controller.selection.extentOffset, 3);

    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByCharacter, doNotExtendSelection);
    await tester.pumpAndSettle();
    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByCharacter, doNotExtendSelection);
    await tester.pumpAndSettle();
    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByCharacter, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, 0);

    await tester.pumpAndSettle();
    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorForwardByCharacter, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 1);
    expect(controller.selection.extentOffset, 1);

    semantics.dispose();
  });

  testWidgets('can move cursor with a11y means - word', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    const bool doNotExtendSelection = false;

    controller.text = 'test for words';
    controller.selection =
    TextSelection.collapsed(offset:controller.text.length);

    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    expect(
      semantics,
      includesNodeWith(
        value: 'test for words',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
        ],
      ),
    );

    final RenderEditable render = tester.allRenderObjects.whereType<RenderEditable>().first;
    final int semanticsId = render.debugSemantics!.id;

    expect(controller.selection.baseOffset, 14);
    expect(controller.selection.extentOffset, 14);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByWord, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 9);
    expect(controller.selection.extentOffset, 9);

    expect(
      semantics,
      includesNodeWith(
        value: 'test for words',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByWord, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 5);
    expect(controller.selection.extentOffset, 5);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByWord, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, 0);

    await tester.pumpAndSettle();
    expect(
      semantics,
      includesNodeWith(
        value: 'test for words',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorForwardByWord, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 5);
    expect(controller.selection.extentOffset, 5);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorForwardByWord, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 9);
    expect(controller.selection.extentOffset, 9);

    semantics.dispose();
  });

  testWidgets('can extend selection with a11y means - character', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    const bool extendSelection = true;
    const bool doNotExtendSelection = false;

    controller.text = 'test';
    controller.selection =
        TextSelection.collapsed(offset:controller.text.length);

    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
        ],
      ),
    );

    final RenderEditable render = tester.allRenderObjects.whereType<RenderEditable>().first;
    final int semanticsId = render.debugSemantics!.id;

    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 4);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByCharacter, extendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 3);

    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByCharacter, extendSelection);
    await tester.pumpAndSettle();
    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByCharacter, extendSelection);
    await tester.pumpAndSettle();
    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByCharacter, extendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 0);

    await tester.pumpAndSettle();
    expect(
      semantics,
      includesNodeWith(
        value: 'test',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorForwardByCharacter, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 1);
    expect(controller.selection.extentOffset, 1);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorForwardByCharacter, extendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 1);
    expect(controller.selection.extentOffset, 2);

    semantics.dispose();
  });

  testWidgets('can extend selection with a11y means - word', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    const bool extendSelection = true;
    const bool doNotExtendSelection = false;

    controller.text = 'test for words';
    controller.selection =
    TextSelection.collapsed(offset:controller.text.length);

    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    expect(
      semantics,
      includesNodeWith(
        value: 'test for words',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
        ],
      ),
    );

    final RenderEditable render = tester.allRenderObjects.whereType<RenderEditable>().first;
    final int semanticsId = render.debugSemantics!.id;

    expect(controller.selection.baseOffset, 14);
    expect(controller.selection.extentOffset, 14);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByWord, extendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 14);
    expect(controller.selection.extentOffset, 9);

    expect(
      semantics,
      includesNodeWith(
        value: 'test for words',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorBackwardByCharacter,
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorBackwardByWord,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByWord, extendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 14);
    expect(controller.selection.extentOffset, 5);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorBackwardByWord, extendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 14);
    expect(controller.selection.extentOffset, 0);

    await tester.pumpAndSettle();
    expect(
      semantics,
      includesNodeWith(
        value: 'test for words',
        actions: <SemanticsAction>[
          SemanticsAction.moveCursorForwardByCharacter,
          SemanticsAction.moveCursorForwardByWord,
          SemanticsAction.setSelection,
          SemanticsAction.setText,
        ],
      ),
    );

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorForwardByWord, doNotExtendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 5);
    expect(controller.selection.extentOffset, 5);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(semanticsId,
        SemanticsAction.moveCursorForwardByWord, extendSelection);
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 5);
    expect(controller.selection.extentOffset, 9);

    semantics.dispose();
  });

  testWidgets('password fields have correct semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    controller.text = 'super-secret-password!!1';

    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        obscureText: true,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    final String expectedValue = '•' *controller.text.length;

    expect(
      semantics,
      hasSemantics(
        TestSemantics(
          children: <TestSemantics>[
            TestSemantics.rootChild(
              children: <TestSemantics>[
                TestSemantics(
                  children: <TestSemantics>[
                    TestSemantics(
                      flags: <SemanticsFlag>[SemanticsFlag.scopesRoute],
                      children: <TestSemantics>[
                        TestSemantics(
                          flags: <SemanticsFlag>[
                            SemanticsFlag.isTextField,
                            SemanticsFlag.isObscured,
                          ],
                          value: expectedValue,
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    )
                  ],
                )
              ],
            ),
          ],
        ),
        ignoreTransform: true,
        ignoreRect: true,
        ignoreId: true,
      ),
    );

    semantics.dispose();
  });

  testWidgets('password fields become obscured with the right semantics when set', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    const String originalText = 'super-secret-password!!1';
    controller.text = originalText;

    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    final String expectedValue = '•' * originalText.length;

    expect(
      semantics,
      hasSemantics(
        TestSemantics(
          children: <TestSemantics>[
            TestSemantics.rootChild(
              children: <TestSemantics>[
                TestSemantics(
                  children:<TestSemantics>[
                    TestSemantics(
                      flags: <SemanticsFlag>[SemanticsFlag.scopesRoute],
                      children: <TestSemantics>[
                        TestSemantics(
                          flags: <SemanticsFlag>[
                            SemanticsFlag.isTextField,
                          ],
                          value: originalText,
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ]
                ),
              ],
            ),
          ],
        ),
        ignoreTransform: true,
        ignoreRect: true,
        ignoreId: true,
      ),
    );

    focusNode.requestFocus();

    // Now change it to make it obscure text.
    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        obscureText: true,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    expect(findRenderEditable(tester).text!.text, expectedValue);

    expect(
      semantics,
      hasSemantics(
        TestSemantics(
          children: <TestSemantics>[
            TestSemantics.rootChild(
              children: <TestSemantics>[
                TestSemantics(
                  children:<TestSemantics>[
                    TestSemantics(
                      flags: <SemanticsFlag>[SemanticsFlag.scopesRoute],
                      children: <TestSemantics>[
                        TestSemantics(
                          flags: <SemanticsFlag>[
                            SemanticsFlag.isTextField,
                            SemanticsFlag.isObscured,
                            SemanticsFlag.isFocused,
                          ],
                          actions: <SemanticsAction>[
                            SemanticsAction.moveCursorBackwardByCharacter,
                            SemanticsAction.setSelection,
                            SemanticsAction.setText,
                            SemanticsAction.moveCursorBackwardByWord,
                          ],
                          value: expectedValue,
                          textDirection: TextDirection.ltr,
                          textSelection: const TextSelection.collapsed(offset: 24),
                        ),
                      ],
                    ),
                  ]
                )
              ],
            ),
          ],
        ),
        ignoreTransform: true,
        ignoreRect: true,
        ignoreId: true,
      ),
    );

    semantics.dispose();
  });

  testWidgets('password fields can have their obscuring character customized', (WidgetTester tester) async {
    const String originalText = 'super-secret-password!!1';
    controller.text = originalText;

    const String obscuringCharacter = '#';
    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        obscuringCharacter: obscuringCharacter,
        obscureText: true,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    final String expectedValue = obscuringCharacter * originalText.length;
    expect(findRenderEditable(tester).text!.text, expectedValue);
  });

  group('a11y copy/cut/paste', () {
    Future<void> _buildApp(MockTextSelectionControls controls, WidgetTester tester) {
      return tester.pumpWidget(MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: controller,
          focusNode: focusNode,
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: controls,
        ),
      ));
    }

    late MockTextSelectionControls controls;

    setUp(() {
      controller.text = 'test';
      controller.selection =
          TextSelection.collapsed(offset:controller.text.length);

      controls = MockTextSelectionControls();
    });

    testWidgets('are exposed', (WidgetTester tester) async {
      final SemanticsTester semantics = SemanticsTester(tester);
      addTearDown(semantics.dispose);

      controls.testCanCopy = false;
      controls.testCanCut = false;
      controls.testCanPaste = false;

      await _buildApp(controls, tester);
      await tester.tap(find.byType(EditableText));
      await tester.pump();

      expect(
        semantics,
        includesNodeWith(
          value: 'test',
          actions: <SemanticsAction>[
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
          ],
        ),
      );

      controls.testCanCopy = true;
      await _buildApp(controls, tester);
      expect(
        semantics,
        includesNodeWith(
          value: 'test',
          actions: <SemanticsAction>[
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.copy,
          ],
        ),
      );

      controls.testCanCopy = false;
      controls.testCanPaste = true;
      await _buildApp(controls, tester);
      await tester.pumpAndSettle();
      expect(
        semantics,
        includesNodeWith(
          value: 'test',
          actions: <SemanticsAction>[
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
          ],
        ),
      );

      controls.testCanPaste = false;
      controls.testCanCut = true;
      await _buildApp(controls, tester);
      expect(
        semantics,
        includesNodeWith(
          value: 'test',
          actions: <SemanticsAction>[
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.cut,
          ],
        ),
      );

      controls.testCanCopy = true;
      controls.testCanCut = true;
      controls.testCanPaste = true;
      await _buildApp(controls, tester);
      expect(
        semantics,
        includesNodeWith(
          value: 'test',
          actions: <SemanticsAction>[
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.cut,
            SemanticsAction.copy,
            SemanticsAction.paste,
          ],
        ),
      );
    });

    testWidgets('can copy/cut/paste with a11y', (WidgetTester tester) async {
      final SemanticsTester semantics = SemanticsTester(tester);

      controls.testCanCopy = true;
      controls.testCanCut = true;
      controls.testCanPaste = true;
      await _buildApp(controls, tester);
      await tester.tap(find.byType(EditableText));
      await tester.pump();

      final SemanticsOwner owner = tester.binding.pipelineOwner.semanticsOwner!;
      const int expectedNodeId = 5;

      expect(
        semantics,
        hasSemantics(
          TestSemantics.root(
            children: <TestSemantics>[
              TestSemantics.rootChild(
                id: 1,
                children: <TestSemantics>[
                  TestSemantics(
                    id: 2,
                    children: <TestSemantics>[
                      TestSemantics(
                        id: 3,
                        flags: <SemanticsFlag>[SemanticsFlag.scopesRoute],
                        children: <TestSemantics>[
                          TestSemantics.rootChild(
                            id: expectedNodeId,
                            flags: <SemanticsFlag>[
                              SemanticsFlag.isTextField,
                              SemanticsFlag.isFocused,
                            ],
                            actions: <SemanticsAction>[
                              SemanticsAction.moveCursorBackwardByCharacter,
                              SemanticsAction.moveCursorBackwardByWord,
                              SemanticsAction.setSelection,
                              SemanticsAction.setText,
                              SemanticsAction.copy,
                              SemanticsAction.cut,
                              SemanticsAction.paste,
                            ],
                            value: 'test',
                            textSelection: TextSelection.collapsed(
                              offset: controller.text.length),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    ]
                  )
                ],
              ),
            ],
          ),
          ignoreRect: true,
          ignoreTransform: true,
        ),
      );

      owner.performAction(expectedNodeId, SemanticsAction.copy);
      expect(controls.copyCount, 1);

      owner.performAction(expectedNodeId, SemanticsAction.cut);
      expect(controls.cutCount, 1);

      owner.performAction(expectedNodeId, SemanticsAction.paste);
      expect(controls.pasteCount, 1);

      semantics.dispose();
    });
  });

  testWidgets('can set text with a11y', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));
    await tester.tap(find.byType(EditableText));
    await tester.pump();

    final SemanticsOwner owner = tester.binding.pipelineOwner.semanticsOwner!;
    const int expectedNodeId = 4;

    expect(
      semantics,
      hasSemantics(
        TestSemantics.root(
          children: <TestSemantics>[
            TestSemantics.rootChild(
              id: 1,
              children: <TestSemantics>[
                TestSemantics(
                  id: 2,
                  children: <TestSemantics>[
                    TestSemantics(
                      id: 3,
                      flags: <SemanticsFlag>[SemanticsFlag.scopesRoute],
                      children: <TestSemantics>[
                        TestSemantics.rootChild(
                          id: expectedNodeId,
                          flags: <SemanticsFlag>[
                            SemanticsFlag.isTextField,
                            SemanticsFlag.isFocused,
                          ],
                          actions: <SemanticsAction>[
                            SemanticsAction.setSelection,
                            SemanticsAction.setText,
                          ],
                          value: '',
                          textSelection: TextSelection.collapsed(
                              offset: controller.text.length),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        ignoreRect: true,
        ignoreTransform: true,
      ),
    );

    expect(controller.text, '');
    owner.performAction(expectedNodeId, SemanticsAction.setText, 'how are you');
    expect(controller.text, 'how are you');

    semantics.dispose();
  });

  testWidgets('allows customizing text style in subclasses', (WidgetTester tester) async {
    controller.text = 'Hello World';

    await tester.pumpWidget(MaterialApp(
      home: CustomStyleEditableText(
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
      ),
    ));

    // Simulate selection change via tap to show handles.
    final RenderEditable render = tester.allRenderObjects.whereType<RenderEditable>().first;
    expect(render.text!.style!.fontStyle, FontStyle.italic);
  });

  testWidgets('Formatters are skipped if text has not changed', (WidgetTester tester) async {
    int called = 0;
    final TextInputFormatter formatter = TextInputFormatter.withFunction((TextEditingValue oldValue, TextEditingValue newValue) {
      called += 1;
      return newValue;
    });
    final TextEditingController controller = TextEditingController();
    final MediaQuery mediaQuery = MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 1.0),
      child: EditableText(
        controller: controller,
        backgroundCursorColor: Colors.red,
        cursorColor: Colors.red,
        focusNode: FocusNode(),
        style: textStyle,
        inputFormatters: <TextInputFormatter>[
          formatter,
        ],
        textDirection: TextDirection.ltr,
      ),
    );
    await tester.pumpWidget(mediaQuery);
    final EditableTextState state = tester.firstState(find.byType(EditableText));
    state.updateEditingValue(const TextEditingValue(
      text: 'a',
    ));
    expect(called, 1);
    // same value.
    state.updateEditingValue(const TextEditingValue(
      text: 'a',
    ));
    expect(called, 1);
    // same value with different selection.
    state.updateEditingValue(const TextEditingValue(
      text: 'a',
      selection: TextSelection.collapsed(offset: 1),
    ));
    // different value.
    state.updateEditingValue(const TextEditingValue(
      text: 'b',
    ));
    expect(called, 2);
  });

  testWidgets('default keyboardAppearance is respected', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/22212.

    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });

    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          devicePixelRatio: 1.0
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: EditableText(
            controller: controller,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
          ),
        ),
      ),
    );

    await tester.showKeyboard(find.byType(EditableText));
    final MethodCall setClient = log.first;
    expect(setClient.method, 'TextInput.setClient');
    expect(setClient.arguments.last['keyboardAppearance'], 'Brightness.light');
  });

  testWidgets('location of widget is sent on show keyboard', (WidgetTester tester) async {
    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });

    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
            devicePixelRatio: 1.0
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: EditableText(
            controller: controller,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
          ),
        ),
      ),
    );

    await tester.showKeyboard(find.byType(EditableText));
    final MethodCall methodCall = log.firstWhere((MethodCall m) => m.method == 'TextInput.setEditableSizeAndTransform');
    expect(
      methodCall,
      isMethodCall('TextInput.setEditableSizeAndTransform', arguments: <String, dynamic>{
        'width': 800,
        'height': 600,
        'transform': Matrix4.identity().storage.toList(),
      }),
    );
  });

  testWidgets('transform and size is reset when text connection opens', (WidgetTester tester) async {
    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });

    final TextEditingController controller1 = TextEditingController();
    final TextEditingController controller2 = TextEditingController();
    controller1.text = 'Text1';
    controller2.text = 'Text2';

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
            devicePixelRatio: 1.0
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children:  <Widget>[
              EditableText(
                key: ValueKey<String>(controller1.text),
                controller: controller1,
                focusNode: FocusNode(),
                style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
                cursorColor: Colors.blue,
                backgroundCursorColor: Colors.grey,
              ),
              const SizedBox(height: 200.0),
              EditableText(
                key: ValueKey<String>(controller2.text),
                controller: controller2,
                focusNode: FocusNode(),
                style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
                cursorColor: Colors.blue,
                backgroundCursorColor: Colors.grey,
                minLines: 10,
                maxLines: 20,
              ),
              const SizedBox(height: 100.0),
            ],
          ),
        ),
      ),
    );

    await tester.showKeyboard(find.byKey(ValueKey<String>(controller1.text)));
    final MethodCall methodCall = log.firstWhere((MethodCall m) => m.method == 'TextInput.setEditableSizeAndTransform');
    expect(
      methodCall,
      isMethodCall('TextInput.setEditableSizeAndTransform', arguments: <String, dynamic>{
        'width': 800,
        'height': 14,
        'transform': Matrix4.identity().storage.toList(),
      }),
    );

    log.clear();

    // Move to the next editable text.
    await tester.showKeyboard(find.byKey(ValueKey<String>(controller2.text)));
    final MethodCall methodCall2 = log.firstWhere((MethodCall m) => m.method == 'TextInput.setEditableSizeAndTransform');
    expect(
      methodCall2,
      isMethodCall('TextInput.setEditableSizeAndTransform', arguments: <String, dynamic>{
        'width': 800,
        'height': 140.0,
        'transform': <double>[1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 214.0, 0.0, 1.0],
      }),
    );

    log.clear();

    // Move back to the first editable text.
    await tester.showKeyboard(find.byKey(ValueKey<String>(controller1.text)));
    final MethodCall methodCall3 = log.firstWhere((MethodCall m) => m.method == 'TextInput.setEditableSizeAndTransform');
    expect(
      methodCall3,
      isMethodCall('TextInput.setEditableSizeAndTransform', arguments: <String, dynamic>{
        'width': 800,
        'height': 14,
        'transform': Matrix4.identity().storage.toList(),
      }),
    );
  });

  testWidgets('size and transform are sent when they change', (WidgetTester tester) async {
    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });

    const Offset offset = Offset(10.0, 20.0);
    const Key transformButtonKey = Key('transformButton');
    await tester.pumpWidget(
      const TransformedEditableText(
        offset: offset,
        transformButtonKey: transformButtonKey,
      ),
    );

    await tester.showKeyboard(find.byType(EditableText));
    MethodCall methodCall = log.firstWhere((MethodCall m) => m.method == 'TextInput.setEditableSizeAndTransform');
    expect(
      methodCall,
      isMethodCall('TextInput.setEditableSizeAndTransform', arguments: <String, dynamic>{
        'width': 800,
        'height': 14,
        'transform': Matrix4.identity().storage.toList(),
      }),
    );

    log.clear();
    await tester.tap(find.byKey(transformButtonKey));
    await tester.pumpAndSettle();

    // There should be a new platform message updating the transform.
    methodCall = log.firstWhere((MethodCall m) => m.method == 'TextInput.setEditableSizeAndTransform');
    expect(
      methodCall,
      isMethodCall('TextInput.setEditableSizeAndTransform', arguments: <String, dynamic>{
        'width': 800,
        'height': 14,
        'transform': Matrix4.translationValues(offset.dx, offset.dy, 0.0).storage.toList(),
      }),
    );
  });

  testWidgets('text styling info is sent on show keyboard', (WidgetTester tester) async {
    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });

    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: EditableText(
          textDirection: TextDirection.rtl,
          controller: controller,
          focusNode: FocusNode(),
          style: const TextStyle(
            fontSize: 20.0,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
          ),
          cursorColor: Colors.blue,
          backgroundCursorColor: Colors.grey,
        ),
      ),
    );

    await tester.showKeyboard(find.byType(EditableText));
    final MethodCall setStyle = log.firstWhere((MethodCall m) => m.method == 'TextInput.setStyle');
    expect(
      setStyle,
      isMethodCall('TextInput.setStyle', arguments: <String, dynamic>{
        'fontSize': 20.0,
        'fontFamily': 'Roboto',
        'fontWeightIndex': 5,
        'textAlignIndex': 4,
        'textDirectionIndex': 0,
      }),
    );
  });

  testWidgets('text styling info is sent on style update', (WidgetTester tester) async {
    final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();
    late StateSetter setState;
    const TextStyle textStyle1 = TextStyle(
      fontSize: 20.0,
      fontFamily: 'RobotoMono',
      fontWeight: FontWeight.w600,
    );
    const TextStyle textStyle2 = TextStyle(
      fontSize: 20.0,
      fontFamily: 'Raleway',
      fontWeight: FontWeight.w700,
    );
    TextStyle currentTextStyle = textStyle1;

    Widget builder() {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setter) {
          setState = setter;
          return MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 1.0),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: Material(
                    child: EditableText(
                      backgroundCursorColor: Colors.grey,
                      key: editableTextKey,
                      controller: controller,
                      focusNode: FocusNode(),
                      style: currentTextStyle,
                      cursorColor: Colors.blue,
                      selectionControls: materialTextSelectionControls,
                      keyboardType: TextInputType.text,
                      onChanged: (String value) {},
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    await tester.pumpWidget(builder());
    await tester.showKeyboard(find.byType(EditableText));

    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });
    setState(() {
      currentTextStyle = textStyle2;
    });
    await tester.pump();

    // Updated styling information should be sent via TextInput.setStyle method.
    final MethodCall setStyle = log.firstWhere((MethodCall m) => m.method == 'TextInput.setStyle');
    expect(
      setStyle,
      isMethodCall('TextInput.setStyle', arguments: <String, dynamic>{
        'fontSize': 20.0,
        'fontFamily': 'Raleway',
        'fontWeightIndex': 6,
        'textAlignIndex': 4,
        'textDirectionIndex': 1,
      }),
    );
  });

  group('setCaretRect', () {
    Widget builder() {
      return MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1.0),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Material(
                child: EditableText(
                  backgroundCursorColor: Colors.grey,
                  controller: controller,
                  focusNode: FocusNode(),
                  style: textStyle,
                  cursorColor: Colors.blue,
                  selectionControls: materialTextSelectionControls,
                  keyboardType: TextInputType.text,
                  onChanged: (String value) {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'called with proper coordinates',
      (WidgetTester tester) async {
        controller.value = TextEditingValue(text: 'a' * 50);
        await tester.pumpWidget(builder());
        await tester.showKeyboard(find.byType(EditableText));

        expect(tester.testTextInput.log, contains(
          matchesMethodCall(
            'TextInput.setCaretRect',
            args: allOf(
              // No composing text so the width should not be too wide because
              // it's empty.
              containsPair('x', equals(700)),
              containsPair('y', equals(0)),
              containsPair('width', equals(2)),
              containsPair('height', equals(14)),
            ),
          ),
        ));

        tester.testTextInput.log.clear();

        controller.value = TextEditingValue(
          text: 'a' * 50, selection: const TextSelection(baseOffset: 0, extentOffset: 0));
        await tester.pump();

        expect(tester.testTextInput.log, contains(
          matchesMethodCall(
            'TextInput.setCaretRect',
            // Now the composing range is not empty.
            args: allOf(
              containsPair('x', equals(0)),
              containsPair('y', equals(0)),
            )
          ),
        ));
    }, skip: isBrowser); // Related to https://github.com/flutter/flutter/issues/66089

    testWidgets(
      'only send updates when necessary',
      (WidgetTester tester) async {
        controller.value = TextEditingValue(text: 'a' * 100);
        await tester.pumpWidget(builder());
        await tester.showKeyboard(find.byType(EditableText));

        expect(tester.testTextInput.log, contains(matchesMethodCall('TextInput.setCaretRect')));

        tester.testTextInput.log.clear();

        // Should not send updates every frame.
        await tester.pump();

        expect(tester.testTextInput.log, isNot(contains(matchesMethodCall('TextInput.setCaretRect'))));
    });

    testWidgets(
      'not sent with selection',
      (WidgetTester tester) async {
        controller.value = TextEditingValue(
          text: 'a' * 100, selection: const TextSelection(baseOffset: 0, extentOffset: 10));
        await tester.pumpWidget(builder());
        await tester.showKeyboard(find.byType(EditableText));

        expect(tester.testTextInput.log, isNot(contains(matchesMethodCall('TextInput.setCaretRect'))));
    });
  });

  group('setMarkedTextRect', () {
    Widget builder() {
      return MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1.0),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Material(
                child: EditableText(
                  backgroundCursorColor: Colors.grey,
                  controller: controller,
                  focusNode: FocusNode(),
                  style: textStyle,
                  cursorColor: Colors.blue,
                  selectionControls: materialTextSelectionControls,
                  keyboardType: TextInputType.text,
                  onChanged: (String value) {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'called when the composing range changes',
      (WidgetTester tester) async {
        controller.value = TextEditingValue(text: 'a' * 100);
        await tester.pumpWidget(builder());
        await tester.showKeyboard(find.byType(EditableText));

        expect(tester.testTextInput.log, contains(
          matchesMethodCall(
            'TextInput.setMarkedTextRect',
            args: allOf(
              // No composing text so the width should not be too wide because
              // it's empty.
              containsPair('width', lessThanOrEqualTo(5)),
              containsPair('x', lessThanOrEqualTo(1)),
            ),
          ),
        ));

        tester.testTextInput.log.clear();

        controller.value = TextEditingValue(text: 'a' * 100, composing: const TextRange(start: 0, end: 10));
        await tester.pump();

        expect(tester.testTextInput.log, contains(
          matchesMethodCall(
            'TextInput.setMarkedTextRect',
            // Now the composing range is not empty.
            args: containsPair('width', greaterThanOrEqualTo(10)),
          ),
        ));
    }, skip: isBrowser); // Related to https://github.com/flutter/flutter/issues/66089

    testWidgets(
      'only send updates when necessary',
      (WidgetTester tester) async {
        controller.value = TextEditingValue(text: 'a' * 100, composing: const TextRange(start: 0, end: 10));
        await tester.pumpWidget(builder());
        await tester.showKeyboard(find.byType(EditableText));

        expect(tester.testTextInput.log, contains(matchesMethodCall('TextInput.setMarkedTextRect')));

        tester.testTextInput.log.clear();

        // Should not send updates every frame.
        await tester.pump();

        expect(tester.testTextInput.log, isNot(contains(matchesMethodCall('TextInput.setMarkedTextRect'))));
    });

    testWidgets(
      'zero matrix paint transform',
      (WidgetTester tester) async {
        controller.value = TextEditingValue(text: 'a' * 100, composing: const TextRange(start: 0, end: 10));
        // Use a FittedBox with an zero-sized child to set the paint transform
        // to the zero matrix.
        await tester.pumpWidget(FittedBox(child: SizedBox.fromSize(size: Size.zero, child: builder())));
        await tester.showKeyboard(find.byType(EditableText));
        expect(tester.testTextInput.log, contains(matchesMethodCall(
          'TextInput.setMarkedTextRect',
          args: allOf(
            containsPair('width', isNotNaN),
            containsPair('height', isNotNaN),
            containsPair('x', isNotNaN),
            containsPair('y', isNotNaN),
          ),
        )));
    });
  });


  testWidgets('custom keyboardAppearance is respected', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/22212.

    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });

    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
            devicePixelRatio: 1.0
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: EditableText(
            controller: controller,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            keyboardAppearance: Brightness.dark,
          ),
        ),
      ),
    );

    await tester.showKeyboard(find.byType(EditableText));
    final MethodCall setClient = log.first;
    expect(setClient.method, 'TextInput.setClient');
    expect(setClient.arguments.last['keyboardAppearance'], 'Brightness.dark');
  });

  testWidgets('Composing text is underlined and underline is cleared when losing focus', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'text composing text',
        selection: TextSelection.collapsed(offset: 14),
        composing: TextRange(start: 5, end: 14),
      ),
    );
    final FocusNode focusNode = FocusNode(debugLabel: 'Test Focus Node');

    await tester.pumpWidget(MaterialApp( // So we can show overlays.
      home: EditableText(
        autofocus: true,
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
        selectionControls: materialTextSelectionControls,
        keyboardType: TextInputType.text,
        onEditingComplete: () {
          // This prevents the default focus change behavior on submission.
        },
      ),
    ));

    assert(focusNode.hasFocus);

    final RenderEditable renderEditable = findRenderEditable(tester);
    // The actual text span is split into 3 parts with the middle part underlined.
    expect(renderEditable.text!.children!.length, 3);
    final TextSpan textSpan = renderEditable.text!.children![1] as TextSpan;
    expect(textSpan.text, 'composing');
    expect(textSpan.style!.decoration, TextDecoration.underline);

    focusNode.unfocus();
    await tester.pump();

    expect(renderEditable.text!.children, isNull);
    // Everything's just formated the same way now.
    expect(renderEditable.text!.text, 'text composing text');
    expect(renderEditable.text!.style!.decoration, isNull);
  });

  testWidgets('text selection handle visibility', (WidgetTester tester) async {
    // Text with two separate words to select.
    const String testText = 'XXXXX          XXXXX';
    final TextEditingController controller = TextEditingController(text: testText);

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          child: EditableText(
            showSelectionHandles: true,
            controller: controller,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            selectionControls: materialTextSelectionControls,
            keyboardType: TextInputType.text,
          ),
        ),
      ),
    ));

    final EditableTextState state =
      tester.state<EditableTextState>(find.byType(EditableText));
    final RenderEditable renderEditable = state.renderEditable;
    final Scrollable scrollable = tester.widget<Scrollable>(find.byType(Scrollable));

    bool expectedLeftVisibleBefore = false;
    bool expectedRightVisibleBefore = false;

    Future<void> verifyVisibility(
      HandlePositionInViewport leftPosition,
      bool expectedLeftVisible,
      HandlePositionInViewport rightPosition,
      bool expectedRightVisible,
    ) async {
      await tester.pump();

      // Check the signal from RenderEditable about whether they're within the
      // viewport.

      expect(renderEditable.selectionStartInViewport.value, equals(expectedLeftVisible));
      expect(renderEditable.selectionEndInViewport.value, equals(expectedRightVisible));

      // Check that the animations are functional and going in the right
      // direction.

      final List<FadeTransition> transitions = find.descendant(
        of: find.byWidgetPredicate((Widget w) => '${w.runtimeType}' == '_TextSelectionHandleOverlay'),
        matching: find.byType(FadeTransition),
      ).evaluate().map((Element e) => e.widget).cast<FadeTransition>().toList();
      expect(transitions.length, 2);
      final FadeTransition left = transitions[0];
      final FadeTransition right = transitions[1];

      if (expectedLeftVisibleBefore)
        expect(left.opacity.value, equals(1.0));
      if (expectedRightVisibleBefore)
        expect(right.opacity.value, equals(1.0));

      await tester.pump(TextSelectionOverlay.fadeDuration ~/ 2);

      if (expectedLeftVisible != expectedLeftVisibleBefore)
        expect(left.opacity.value, equals(0.5));
      if (expectedRightVisible != expectedRightVisibleBefore)
        expect(right.opacity.value, equals(0.5));

      await tester.pump(TextSelectionOverlay.fadeDuration ~/ 2);

      if (expectedLeftVisible)
        expect(left.opacity.value, equals(1.0));
      if (expectedRightVisible)
        expect(right.opacity.value, equals(1.0));

      expectedLeftVisibleBefore = expectedLeftVisible;
      expectedRightVisibleBefore = expectedRightVisible;

      // Check that the handles' positions are correct.

      final List<RenderBox> handles = List<RenderBox>.from(
        tester.renderObjectList<RenderBox>(
          find.descendant(
            of: find.byType(CompositedTransformFollower),
            matching: find.byType(GestureDetector),
          ),
        ),
      );

      final Size viewport = renderEditable.size;

      void testPosition(double pos, HandlePositionInViewport expected) {
        switch (expected) {
          case HandlePositionInViewport.leftEdge:
            expect(
              pos,
              inExclusiveRange(
                0 - kMinInteractiveDimension,
                0 + kMinInteractiveDimension,
              ),
            );
            break;
          case HandlePositionInViewport.rightEdge:
            expect(
              pos,
              inExclusiveRange(
                viewport.width - kMinInteractiveDimension,
                viewport.width + kMinInteractiveDimension,
              ),
            );
            break;
          case HandlePositionInViewport.within:
            expect(
              pos,
              inExclusiveRange(
                0 - kMinInteractiveDimension,
                viewport.width + kMinInteractiveDimension,
              ),
            );
            break;
        }
      }
      expect(state.selectionOverlay!.handlesAreVisible, isTrue);
      testPosition(handles[0].localToGlobal(Offset.zero).dx, leftPosition);
      testPosition(handles[1].localToGlobal(Offset.zero).dx, rightPosition);
    }

    // Select the first word. Both handles should be visible.
    await tester.tapAt(const Offset(20, 10));
    renderEditable.selectWord(cause: SelectionChangedCause.longPress);
    await tester.pump();
    await verifyVisibility(HandlePositionInViewport.leftEdge, true, HandlePositionInViewport.within, true);

    // Drag the text slightly so the first word is partially visible. Only the
    // right handle should be visible.
    scrollable.controller!.jumpTo(20.0);
    await verifyVisibility(HandlePositionInViewport.leftEdge, false, HandlePositionInViewport.within, true);

    // Drag the text all the way to the left so the first word is not visible at
    // all (and the second word is fully visible). Both handles should be
    // invisible now.
    scrollable.controller!.jumpTo(200.0);
    await verifyVisibility(HandlePositionInViewport.leftEdge, false, HandlePositionInViewport.leftEdge, false);

    // Tap to unselect.
    await tester.tap(find.byType(EditableText));
    await tester.pump();

    // Now that the second word has been dragged fully into view, select it.
    await tester.tapAt(const Offset(80, 10));
    renderEditable.selectWord(cause: SelectionChangedCause.longPress);
    await tester.pump();
    await verifyVisibility(HandlePositionInViewport.within, true, HandlePositionInViewport.within, true);

    // Drag the text slightly to the right. Only the left handle should be
    // visible.
    scrollable.controller!.jumpTo(150);
    await verifyVisibility(HandlePositionInViewport.within, true, HandlePositionInViewport.rightEdge, false);

    // Drag the text all the way to the right, so the second word is not visible
    // at all. Again, both handles should be invisible.
    scrollable.controller!.jumpTo(0);
    await verifyVisibility(HandlePositionInViewport.rightEdge, false, HandlePositionInViewport.rightEdge, false);

    // On web, we don't show the Flutter toolbar and instead rely on the browser
    // toolbar. Until we change that, this test should remain skipped.
  }, skip: kIsWeb);

  testWidgets('text selection handle visibility RTL', (WidgetTester tester) async {
    // Text with two separate words to select.
    const String testText = 'XXXXX          XXXXX';
    final TextEditingController controller = TextEditingController(text: testText);

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          child: EditableText(
            controller: controller,
            showSelectionHandles: true,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            selectionControls: materialTextSelectionControls,
            keyboardType: TextInputType.text,
            textAlign: TextAlign.right,
          ),
        ),
      ),
    ));

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));

    // Select the first word. Both handles should be visible.
    await tester.tapAt(const Offset(20, 10));
    state.renderEditable.selectWord(cause: SelectionChangedCause.longPress);
    await tester.pump();
    final List<RenderBox> handles = List<RenderBox>.from(
      tester.renderObjectList<RenderBox>(
        find.descendant(
          of: find.byType(CompositedTransformFollower),
          matching: find.byType(GestureDetector),
        ),
      ),
    );
    expect(
      handles[0].localToGlobal(Offset.zero).dx,
      inExclusiveRange(
        -kMinInteractiveDimension,
        kMinInteractiveDimension,
      ),
    );
    expect(
      handles[1].localToGlobal(Offset.zero).dx,
      inExclusiveRange(
        70.0 - kMinInteractiveDimension,
        70.0 + kMinInteractiveDimension,
      ),
    );
    expect(state.selectionOverlay!.handlesAreVisible, isTrue);
    expect(controller.selection.base.offset, 0);
    expect(controller.selection.extent.offset, 5);

    // On web, we don't show the Flutter toolbar and instead rely on the browser
    // toolbar. Until we change that, this test should remain skipped.
  }, skip: kIsWeb);

  const String testText = 'Now is the time for\n'
      'all good people\n'
      'to come to the aid\n'
      'of their country.';

  Future<void> sendKeys(
      WidgetTester tester,
      List<LogicalKeyboardKey> keys, {
        bool shift = false,
        bool wordModifier = false,
        bool lineModifier = false,
        bool shortcutModifier = false,
        required String platform,
      }) async {
    if (shift) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft, platform: platform);
    }
    if (shortcutModifier) {
      await tester.sendKeyDownEvent(
          platform == 'macos' ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
          platform: platform);
    }
    if (wordModifier) {
      await tester.sendKeyDownEvent(
          platform == 'macos' ? LogicalKeyboardKey.altLeft : LogicalKeyboardKey.controlLeft,
          platform: platform);
    }
    if (lineModifier) {
      await tester.sendKeyDownEvent(
          platform == 'macos' ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.altLeft,
          platform: platform);
    }
    for (final LogicalKeyboardKey key in keys) {
      await tester.sendKeyEvent(key, platform: platform);
      await tester.pump();
    }
    if (lineModifier) {
      await tester.sendKeyUpEvent(
          platform == 'macos' ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.altLeft,
          platform: platform);
    }
    if (wordModifier) {
      await tester.sendKeyUpEvent(
          platform == 'macos' ? LogicalKeyboardKey.altLeft : LogicalKeyboardKey.controlLeft,
          platform: platform);
    }
    if (shortcutModifier) {
      await tester.sendKeyUpEvent(
          platform == 'macos' ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
          platform: platform);
    }
    if (shift) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft, platform: platform);
    }
    if (shift || wordModifier || lineModifier) {
      await tester.pump();
    }
  }

  Future<void> testTextEditing(WidgetTester tester, {required String platform}) async {
    final TextEditingController controller = TextEditingController(text: testText);
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 0,
      affinity: TextAffinity.upstream,
    );
    late TextSelection selection;
    late SelectionChangedCause cause;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: EditableText(
            maxLines: 10,
            controller: controller,
            showSelectionHandles: true,
            autofocus: true,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            selectionControls: materialTextSelectionControls,
            keyboardType: TextInputType.text,
            textAlign: TextAlign.right,
            onSelectionChanged: (TextSelection newSelection, SelectionChangedCause? newCause) {
              selection = newSelection;
              cause = newCause!;
            },
          ),
        ),
      ),
    ));

    await tester.pump(); // Wait for autofocus to take effect.

    // Select a few characters using shift right arrow
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
      ],
      shift: true,
      platform: platform,
    );

    expect(cause, equals(SelectionChangedCause.keyboard), reason: 'on $platform');
    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 3,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select fewer characters using shift left arrow
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowLeft,
      ],
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 0,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Try to select before the first character, nothing should change.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
      ],
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 0,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select the first two words.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
      ],
      shift: true,
      wordModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 6,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Unselect the second word.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
      ],
      shift: true,
      wordModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 4,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select the next line.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowDown,
      ],
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 20,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );

    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
      ],
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 20,
          extentOffset: 20,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select the next line.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowDown,
      ],
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 20,
          extentOffset: 39,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select to the end of the string by going down.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
      ],
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 20,
          extentOffset: testText.length,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Go back up one line to set selection up to part of the last line.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowUp,
      ],
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 20,
          extentOffset: 57,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select to the end of the selection.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
      ],
      lineModifier: true,
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 20,
          extentOffset: 72,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select to the beginning of the first line.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
      ],
      lineModifier: true,
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 72,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select All
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyA,
      ],
      shortcutModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: testText.length,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Jump to beginning of selection.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
      ],
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 0,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Jump to end.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowDown,
      ],
      shift: false,
      lineModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection.collapsed(
          offset: testText.length,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');

    // Jump to start.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowUp,
      ],
      shift: false,
      lineModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection.collapsed(
          offset: 0,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');

    // Move forward a few letters
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
      ],
      shift: false,
      lineModifier: false,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection.collapsed(
          offset: 3,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select to end.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowDown,
      ],
      shift: true,
      lineModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 3,
          extentOffset: testText.length,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select to start, which extends the selection.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowUp,
      ],
      shift: true,
      lineModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: testText.length,
          extentOffset: 0,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Move to start again.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowUp,
      ],
      shift: false,
      lineModifier: false,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection.collapsed(
          offset: 0,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Jump forward three words.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
      ],
      wordModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 10,
          extentOffset: 10,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select some characters backward.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowLeft,
      ],
      shift: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 10,
          extentOffset: 7,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );

    // Select a word backward.
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowLeft,
      ],
      shift: true,
      wordModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 10,
          extentOffset: 4,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');

    // Cut
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyX,
      ],
      shortcutModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 4,
          extentOffset: 4,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(
      controller.text,
      equals('Now  time for\n'
          'all good people\n'
          'to come to the aid\n'
          'of their country.'),
      reason: 'on $platform',
    );
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))!.text,
      equals('is the'),
      reason: 'on $platform',
    );

    // Paste
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyV,
      ],
      shortcutModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 10,
          extentOffset: 10,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');

    // Copy All
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyC,
      ],
      shortcutModifier: true,
      platform: platform,
    );

    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: testText.length,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');
    expect((await Clipboard.getData(Clipboard.kTextPlain))!.text, equals(testText));

    // Delete
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.delete,
      ],
      platform: platform,
    );
    expect(
      selection,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 0,
          affinity: TextAffinity.downstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, isEmpty, reason: 'on $platform');
  }

  testWidgets('keyboard text selection works', (WidgetTester tester) async {
    final String targetPlatform = defaultTargetPlatform.toString();
    final String platform = targetPlatform.substring(targetPlatform.indexOf('.') + 1).toLowerCase();
    await testTextEditing(tester, platform: platform);
    // On web, using keyboard for selection is handled by the browser.
  }, skip: kIsWeb, variant: TargetPlatformVariant.all());

  testWidgets('keyboard shortcuts respect read-only', (WidgetTester tester) async {
    final String platform = describeEnum(defaultTargetPlatform).toLowerCase();
    final TextEditingController controller = TextEditingController(text: testText);
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: testText.length ~/2,
      affinity: TextAffinity.upstream,
    );
    TextSelection? selection;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: EditableText(
            readOnly: true,
            controller: controller,
            autofocus: true,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            selectionControls: materialTextSelectionControls,
            keyboardType: TextInputType.text,
            textAlign: TextAlign.right,
            onSelectionChanged: (TextSelection newSelection, SelectionChangedCause? newCause) {
              selection = newSelection;
            },
          ),
        ),
      ),
    ));

    await tester.pump(); // Wait for autofocus to take effect.

    const String clipboardContent = 'read-only';
    await Clipboard.setData(const ClipboardData(text: clipboardContent));

    // Paste
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyV,
      ],
      shortcutModifier: true,
      platform: platform,
    );

    expect(selection, isNull, reason: 'on $platform');
    expect(controller.text, equals(testText), reason: 'on $platform');

    // Select All
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyA,
      ],
      shortcutModifier: true,
      platform: platform,
    );

    expect(
      selection!,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: testText.length,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');

    // Cut
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyX,
      ],
      shortcutModifier: true,
      platform: platform,
    );

    expect(
      selection!,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: testText.length,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))!.text,
      equals(clipboardContent),
      reason: 'on $platform',
    );

    // Copy
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyC,
      ],
      shortcutModifier: true,
      platform: platform,
    );

    expect(
      selection!,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: testText.length,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))!.text,
      equals(testText),
      reason: 'on $platform',
    );

    // Delete
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.delete,
      ],
      platform: platform,
    );
    expect(
      selection!,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: testText.length,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');

    // Backspace
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.backspace,
      ],
      platform: platform,
    );
    expect(
      selection!,
      equals(
        const TextSelection(
          baseOffset: 0,
          extentOffset: testText.length,
          affinity: TextAffinity.upstream,
        ),
      ),
      reason: 'on $platform',
    );
    expect(controller.text, equals(testText), reason: 'on $platform');
  },
  skip: kIsWeb,
  variant: TargetPlatformVariant.all());

  // Regression test for https://github.com/flutter/flutter/issues/31287
  testWidgets('text selection handle visibility', (WidgetTester tester) async {
    // Text with two separate words to select.
    const String testText = 'XXXXX          XXXXX';
    final TextEditingController controller = TextEditingController(text: testText);

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          child: EditableText(
            showSelectionHandles: true,
            controller: controller,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.iOS).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            selectionControls: cupertinoTextSelectionControls,
            keyboardType: TextInputType.text,
          ),
        ),
      ),
    ));

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));
    final RenderEditable renderEditable = state.renderEditable;
    final Scrollable scrollable = tester.widget<Scrollable>(find.byType(Scrollable));

    bool expectedLeftVisibleBefore = false;
    bool expectedRightVisibleBefore = false;

    Future<void> verifyVisibility(
      HandlePositionInViewport leftPosition,
      bool expectedLeftVisible,
      HandlePositionInViewport rightPosition,
      bool expectedRightVisible,
    ) async {
      await tester.pump();

      // Check the signal from RenderEditable about whether they're within the
      // viewport.

      expect(renderEditable.selectionStartInViewport.value, equals(expectedLeftVisible));
      expect(renderEditable.selectionEndInViewport.value, equals(expectedRightVisible));

      // Check that the animations are functional and going in the right
      // direction.

      final List<FadeTransition> transitions =
        find.byType(FadeTransition).evaluate().map((Element e) => e.widget).cast<FadeTransition>().toList();
      final FadeTransition left = transitions[0];
      final FadeTransition right = transitions[1];

      if (expectedLeftVisibleBefore)
        expect(left.opacity.value, equals(1.0));
      if (expectedRightVisibleBefore)
        expect(right.opacity.value, equals(1.0));

      await tester.pump(TextSelectionOverlay.fadeDuration ~/ 2);

      if (expectedLeftVisible != expectedLeftVisibleBefore)
        expect(left.opacity.value, equals(0.5));
      if (expectedRightVisible != expectedRightVisibleBefore)
        expect(right.opacity.value, equals(0.5));

      await tester.pump(TextSelectionOverlay.fadeDuration ~/ 2);

      if (expectedLeftVisible)
        expect(left.opacity.value, equals(1.0));
      if (expectedRightVisible)
        expect(right.opacity.value, equals(1.0));

      expectedLeftVisibleBefore = expectedLeftVisible;
      expectedRightVisibleBefore = expectedRightVisible;

      // Check that the handles' positions are correct.

      final List<RenderBox> handles = List<RenderBox>.from(
        tester.renderObjectList<RenderBox>(
          find.descendant(
            of: find.byType(CompositedTransformFollower),
            matching: find.byType(GestureDetector),
          ),
        ),
      );

      final Size viewport = renderEditable.size;

      void testPosition(double pos, HandlePositionInViewport expected) {
        switch (expected) {
          case HandlePositionInViewport.leftEdge:
            expect(
              pos,
              inExclusiveRange(
                0 - kMinInteractiveDimension,
                0 + kMinInteractiveDimension,
              ),
            );
            break;
          case HandlePositionInViewport.rightEdge:
            expect(
              pos,
              inExclusiveRange(
                viewport.width - kMinInteractiveDimension,
                viewport.width + kMinInteractiveDimension,
              ),
            );
            break;
          case HandlePositionInViewport.within:
            expect(
              pos,
              inExclusiveRange(
                0 - kMinInteractiveDimension,
                viewport.width + kMinInteractiveDimension,
              ),
            );
            break;
        }
      }
      expect(state.selectionOverlay!.handlesAreVisible, isTrue);
      testPosition(handles[0].localToGlobal(Offset.zero).dx, leftPosition);
      testPosition(handles[1].localToGlobal(Offset.zero).dx, rightPosition);
    }

    // Select the first word. Both handles should be visible.
    await tester.tapAt(const Offset(20, 10));
    renderEditable.selectWord(cause: SelectionChangedCause.longPress);
    await tester.pump();
    await verifyVisibility(HandlePositionInViewport.leftEdge, true, HandlePositionInViewport.within, true);

    // Drag the text slightly so the first word is partially visible. Only the
    // right handle should be visible.
    scrollable.controller!.jumpTo(20.0);
    await verifyVisibility(HandlePositionInViewport.leftEdge, false, HandlePositionInViewport.within, true);

    // Drag the text all the way to the left so the first word is not visible at
    // all (and the second word is fully visible). Both handles should be
    // invisible now.
    scrollable.controller!.jumpTo(200.0);
    await verifyVisibility(HandlePositionInViewport.leftEdge, false, HandlePositionInViewport.leftEdge, false);

    // Tap to unselect.
    await tester.tap(find.byType(EditableText));
    await tester.pump();

    // Now that the second word has been dragged fully into view, select it.
    await tester.tapAt(const Offset(80, 10));
    renderEditable.selectWord(cause: SelectionChangedCause.longPress);
    await tester.pump();
    await verifyVisibility(HandlePositionInViewport.within, true, HandlePositionInViewport.within, true);

    // Drag the text slightly to the right. Only the left handle should be
    // visible.
    scrollable.controller!.jumpTo(150);
    await verifyVisibility(HandlePositionInViewport.within, true, HandlePositionInViewport.rightEdge, false);

    // Drag the text all the way to the right, so the second word is not visible
    // at all. Again, both handles should be invisible.
    scrollable.controller!.jumpTo(0);
    await verifyVisibility(HandlePositionInViewport.rightEdge, false, HandlePositionInViewport.rightEdge, false);

    // On web, we don't show the Flutter toolbar and instead rely on the browser
    // toolbar. Until we change that, this test should remain skipped.
  }, skip: kIsWeb, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets("scrolling doesn't bounce", (WidgetTester tester) async {
    // 3 lines of text, where the last line overflows and requires scrolling.
    const String testText = 'XXXXX\nXXXXX\nXXXXX';
    final TextEditingController controller = TextEditingController(text: testText);

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          child: EditableText(
            showSelectionHandles: true,
            maxLines: 2,
            controller: controller,
            focusNode: FocusNode(),
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            selectionControls: materialTextSelectionControls,
            keyboardType: TextInputType.text,
          ),
        ),
      ),
    ));

    final EditableTextState state =
      tester.state<EditableTextState>(find.byType(EditableText));
    final RenderEditable renderEditable = state.renderEditable;
    final Scrollable scrollable = tester.widget<Scrollable>(find.byType(Scrollable));

    expect(scrollable.controller!.position.viewportDimension, equals(28));
    expect(scrollable.controller!.position.pixels, equals(0));

    expect(renderEditable.maxScrollExtent, equals(14));

    scrollable.controller!.jumpTo(20.0);
    await tester.pump();
    expect(scrollable.controller!.position.pixels, equals(20));

    state.bringIntoView(const TextPosition(offset: 0));
    await tester.pump();
    expect(scrollable.controller!.position.pixels, equals(0));


    state.bringIntoView(const TextPosition(offset: 13));
    await tester.pump();
    expect(scrollable.controller!.position.pixels, equals(14));
    expect(scrollable.controller!.position.pixels, equals(renderEditable.maxScrollExtent));
  });

  testWidgets('bringIntoView brings the caret into view when in a viewport', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/55547.
    final TextEditingController controller = TextEditingController(text: testText * 20);
    final ScrollController editableScrollController = ScrollController();
    final ScrollController outerController = ScrollController();

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          height: 200,
          child: SingleChildScrollView(
            controller: outerController,
            child: EditableText(
              maxLines: null,
              controller: controller,
              scrollController: editableScrollController,
              focusNode: FocusNode(),
              style: textStyle,
              cursorColor: Colors.blue,
              backgroundCursorColor: Colors.grey,
            ),
          ),
        ),
      ),
    ));


    expect(outerController.offset, 0);
    expect(editableScrollController.offset, 0);

    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
    state.bringIntoView(TextPosition(offset: controller.text.length));

    await tester.pumpAndSettle();
    // The SingleChildScrollView is scrolled instead of the EditableText to
    // reveal the caret.
    expect(outerController.offset, outerController.position.maxScrollExtent);
    expect(editableScrollController.offset, 0);
  });

  testWidgets('bringIntoView does nothing if the physics prohibits implicit scrolling', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: testText * 20);
    final ScrollController scrollController = ScrollController();

    Future<void> buildWithPhysics({ ScrollPhysics? physics }) async {
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 200,
            child: EditableText(
              maxLines: null,
              controller: controller,
              scrollController: scrollController,
              focusNode: FocusNode(),
              style: textStyle,
              cursorColor: Colors.blue,
              backgroundCursorColor: Colors.grey,
              scrollPhysics: physics,
            ),
          ),
        ),
      ));
    }


    await buildWithPhysics();
    expect(scrollController.offset, 0);

    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
    state.bringIntoView(TextPosition(offset: controller.text.length));

    await tester.pumpAndSettle();
    // Scrolled to the maxScrollExtent to reveal to caret.
    expect(scrollController.offset, scrollController.position.maxScrollExtent);

    scrollController.jumpTo(0);
    await buildWithPhysics(physics: const NoImplicitScrollPhysics());
    expect(scrollController.offset, 0);

    state.bringIntoView(TextPosition(offset: controller.text.length));

    await tester.pumpAndSettle();
    expect(scrollController.offset, 0);
  });

  testWidgets('getLocalRectForCaret does not throw when it sees an infinite point', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SkipPainting(
          child: Transform(
            transform: Matrix4.zero(),
            child: EditableText(
              controller: TextEditingController(),
              focusNode: FocusNode(),
              style: textStyle,
              cursorColor: Colors.blue,
              backgroundCursorColor: Colors.grey,
            ),
          ),
        ),
      ),
    );

    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
    final Rect rect = state.renderEditable.getLocalRectForCaret(const TextPosition(offset: 0));
    expect(rect.isFinite, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('obscured multiline fields throw an exception', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();
    expect(
      () {
        EditableText(
          backgroundCursorColor: cursorColor,
          controller: controller,
          cursorColor: cursorColor,
          focusNode: focusNode,
          maxLines: 1,
          obscureText: true,
          style: textStyle,
        );
      },
      returnsNormally,
    );
    expect(
      () {
        EditableText(
          backgroundCursorColor: cursorColor,
          controller: controller,
          cursorColor: cursorColor,
          focusNode: focusNode,
          maxLines: 2,
          obscureText: true,
          style: textStyle,
        );
      },
      throwsAssertionError,
    );
  });

  group('batch editing', () {
    final TextEditingController controller = TextEditingController(text: testText);
    final EditableText editableText = EditableText(
      showSelectionHandles: true,
      maxLines: 2,
      controller: controller,
      focusNode: FocusNode(),
      cursorColor: Colors.red,
      backgroundCursorColor: Colors.blue,
      style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
      keyboardType: TextInputType.text,
    );

    final Widget widget = MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: editableText,
      ),
    );

    testWidgets('batch editing works', (WidgetTester tester) async {
      await tester.pumpWidget(widget);

      // Connect.
      await tester.showKeyboard(find.byType(EditableText));

      final EditableTextState state = tester.state<EditableTextState>(find.byWidget(editableText));
      state.updateEditingValue(const TextEditingValue(text: 'remote value'));
      tester.testTextInput.log.clear();

      state.beginBatchEdit();

      controller.text = 'new change 1';
      expect(state.currentTextEditingValue.text, 'new change 1');
      expect(tester.testTextInput.log, isEmpty);

      // Nesting.
      state.beginBatchEdit();
      controller.text = 'new change 2';
      expect(state.currentTextEditingValue.text, 'new change 2');
      expect(tester.testTextInput.log, isEmpty);

      // End the innermost batch edit. Not yet.
      state.endBatchEdit();
      expect(tester.testTextInput.log, isEmpty);

      controller.text = 'new change 3';
      expect(state.currentTextEditingValue.text, 'new change 3');
      expect(tester.testTextInput.log, isEmpty);

      // Finish the outermost batch edit.
      state.endBatchEdit();
      expect(tester.testTextInput.log, hasLength(1));
      expect(
        tester.testTextInput.log,
        contains(matchesMethodCall('TextInput.setEditingState', args: containsPair('text', 'new change 3'))),
      );
    });

    testWidgets('batch edits need to be nested properly', (WidgetTester tester) async {
      await tester.pumpWidget(widget);

      // Connect.
      await tester.showKeyboard(find.byType(EditableText));

      final EditableTextState state = tester.state<EditableTextState>(find.byWidget(editableText));
      state.updateEditingValue(const TextEditingValue(text: 'remote value'));
      tester.testTextInput.log.clear();

      String? errorString;
      try {
        state.endBatchEdit();
      } catch (e) {
        errorString = e.toString();
      }

      expect(errorString, contains('Unbalanced call to endBatchEdit'));
    });

     testWidgets('catch unfinished batch edits on disposal', (WidgetTester tester) async {
      await tester.pumpWidget(widget);

      // Connect.
      await tester.showKeyboard(find.byType(EditableText));

      final EditableTextState state = tester.state<EditableTextState>(find.byWidget(editableText));
      state.updateEditingValue(const TextEditingValue(text: 'remote value'));
      tester.testTextInput.log.clear();

      state.beginBatchEdit();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(Container());
      expect(tester.takeException(), isNotNull);
    });
  });

  group('EditableText does not send editing values more than once', () {
    final TextEditingController controller = TextEditingController(text: testText);
    final EditableText editableText = EditableText(
      showSelectionHandles: true,
      maxLines: 2,
      controller: controller,
      focusNode: FocusNode(),
      cursorColor: Colors.red,
      backgroundCursorColor: Colors.blue,
      style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
      keyboardType: TextInputType.text,
      inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(6)],
      onChanged: (String s) => controller.text += ' onChanged',
    );

    final Widget widget = MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: editableText,
      ),
    );

    controller.addListener(() {
      if (!controller.text.endsWith('listener'))
        controller.text += ' listener';
    });

    testWidgets('input from text input plugin', (WidgetTester tester) async {
      await tester.pumpWidget(widget);

      // Connect.
      await tester.showKeyboard(find.byType(EditableText));
      tester.testTextInput.log.clear();

      final EditableTextState state = tester.state<EditableTextState>(find.byWidget(editableText));
      state.updateEditingValue(const TextEditingValue(text: 'remoteremoteremote'));

      // Apply in order: length formatter -> listener -> onChanged -> listener.
      expect(controller.text, 'remote listener onChanged listener');
      final List<TextEditingValue> updates = tester.testTextInput.log
        .where((MethodCall call) => call.method == 'TextInput.setEditingState')
        .map((MethodCall call) => TextEditingValue.fromJSON(call.arguments as Map<String, dynamic>))
        .toList(growable: false);

      expect(updates, const <TextEditingValue>[TextEditingValue(text: 'remote listener onChanged listener')]);

      tester.testTextInput.log.clear();

      // If by coincidence the text input plugin sends the same value back,
      // do nothing.
      state.updateEditingValue(const TextEditingValue(text: 'remote listener onChanged listener'));
      expect(controller.text, 'remote listener onChanged listener');
      expect(tester.testTextInput.log, isEmpty);
    });

    testWidgets('input from text selection menu', (WidgetTester tester) async {
      await tester.pumpWidget(widget);

      // Connect.
      await tester.showKeyboard(find.byType(EditableText));
      tester.testTextInput.log.clear();

      final EditableTextState state = tester.state<EditableTextState>(find.byWidget(editableText));
      state.userUpdateTextEditingValue(const TextEditingValue(text: 'remoteremoteremote'), SelectionChangedCause.keyboard);

      // Apply in order: length formatter -> listener -> onChanged -> listener.
      expect(controller.text, 'remote listener onChanged listener');
      final List<TextEditingValue> updates = tester.testTextInput.log
        .where((MethodCall call) => call.method == 'TextInput.setEditingState')
        .map((MethodCall call) => TextEditingValue.fromJSON(call.arguments as Map<String, dynamic>))
        .toList(growable: false);

      expect(updates, const <TextEditingValue>[TextEditingValue(text: 'remote listener onChanged listener')]);

      tester.testTextInput.log.clear();
    });

    testWidgets('input from controller', (WidgetTester tester) async {
      await tester.pumpWidget(widget);

      // Connect.
      await tester.showKeyboard(find.byType(EditableText));
      tester.testTextInput.log.clear();

      controller.text = 'remoteremoteremote';
      final List<TextEditingValue> updates = tester.testTextInput.log
        .where((MethodCall call) => call.method == 'TextInput.setEditingState')
        .map((MethodCall call) => TextEditingValue.fromJSON(call.arguments as Map<String, dynamic>))
        .toList(growable: false);

      expect(updates, const <TextEditingValue>[TextEditingValue(text: 'remoteremoteremote listener')]);
    });

    testWidgets('input from changing controller', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(text: testText);
      Widget build({ TextEditingController? textEditingController }) {
        return MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: EditableText(
              showSelectionHandles: true,
              maxLines: 2,
              controller: textEditingController ?? controller,
              focusNode: FocusNode(),
              cursorColor: Colors.red,
              backgroundCursorColor: Colors.blue,
              style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
              keyboardType: TextInputType.text,
              inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(6)],
            ),
          ),
        );
      }

      await tester.pumpWidget(build());

      // Connect.
      await tester.showKeyboard(find.byType(EditableText));
      tester.testTextInput.log.clear();
      await tester.pumpWidget(build(textEditingController: TextEditingController(text: 'new text')));

      List<TextEditingValue> updates = tester.testTextInput.log
        .where((MethodCall call) => call.method == 'TextInput.setEditingState')
        .map((MethodCall call) => TextEditingValue.fromJSON(call.arguments as Map<String, dynamic>))
        .toList(growable: false);

      expect(updates, const <TextEditingValue>[TextEditingValue(text: 'new text')]);

      tester.testTextInput.log.clear();
      await tester.pumpWidget(build(textEditingController: TextEditingController(text: 'new new text')));

      updates = tester.testTextInput.log
        .where((MethodCall call) => call.method == 'TextInput.setEditingState')
        .map((MethodCall call) => TextEditingValue.fromJSON(call.arguments as Map<String, dynamic>))
        .toList(growable: false);

      expect(updates, const <TextEditingValue>[TextEditingValue(text: 'new new text')]);
    });
  });

  testWidgets('input imm channel calls are ordered correctly', (WidgetTester tester) async {
    const String testText = 'flutter is the best!';
    final TextEditingController controller = TextEditingController(text: testText);
    final EditableText et = EditableText(
      showSelectionHandles: true,
      maxLines: 2,
      controller: controller,
      focusNode: FocusNode(),
      cursorColor: Colors.red,
      backgroundCursorColor: Colors.blue,
      style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
      keyboardType: TextInputType.text,
    );

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          child: et,
        ),
      ),
    ));

    await tester.showKeyboard(find.byType(EditableText));
    // TextInput.show should be before TextInput.setEditingState
    final List<String> logOrder = <String>[
      'TextInput.setClient',
      'TextInput.show',
      'TextInput.setEditableSizeAndTransform',
      'TextInput.setMarkedTextRect',
      'TextInput.setStyle',
      'TextInput.setEditingState',
      'TextInput.setEditingState',
      'TextInput.show',
      'TextInput.setCaretRect',
    ];
    expect(
      tester.testTextInput.log.map((MethodCall m) => m.method),
      logOrder,
    );
  });

  testWidgets('setEditingState is not called when text changes', (WidgetTester tester) async {
    // We shouldn't get a message here because this change is owned by the platform side.
    const String testText = 'flutter is the best!';
    final TextEditingController controller = TextEditingController(text: testText);
    final EditableText et = EditableText(
      showSelectionHandles: true,
      maxLines: 2,
      controller: controller,
      focusNode: FocusNode(),
      cursorColor: Colors.red,
      backgroundCursorColor: Colors.blue,
      style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
      keyboardType: TextInputType.text,
    );

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          child: et,
        ),
      ),
    ));

    await tester.enterText(find.byType(EditableText), '...');

    final List<String> logOrder = <String>[
      'TextInput.setClient',
      'TextInput.show',
      'TextInput.setEditableSizeAndTransform',
      'TextInput.setMarkedTextRect',
      'TextInput.setStyle',
      'TextInput.setEditingState',
      'TextInput.setEditingState',
      'TextInput.show',
      'TextInput.setCaretRect',
      'TextInput.show',
    ];
    expect(tester.testTextInput.log.length, logOrder.length);
    int index = 0;
    for (final MethodCall m in tester.testTextInput.log) {
      expect(m.method, logOrder[index]);
      index++;
    }
    expect(tester.testTextInput.editingState!['text'], 'flutter is the best!');
  });

  testWidgets('setEditingState is called when text changes on controller', (WidgetTester tester) async {
    // We should get a message here because this change is owned by the framework side.
    const String testText = 'flutter is the best!';
    final TextEditingController controller = TextEditingController(text: testText);
    final EditableText et = EditableText(
      showSelectionHandles: true,
      maxLines: 2,
      controller: controller,
      focusNode: FocusNode(),
      cursorColor: Colors.red,
      backgroundCursorColor: Colors.blue,
      style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
      keyboardType: TextInputType.text,
    );

    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          child: et,
        ),
      ),
    ));

    await tester.showKeyboard(find.byType(EditableText));
    controller.text += '...';
    await tester.idle();

    final List<String> logOrder = <String>[
      'TextInput.setClient',
      'TextInput.show',
      'TextInput.setEditableSizeAndTransform',
      'TextInput.setMarkedTextRect',
      'TextInput.setStyle',
      'TextInput.setEditingState',
      'TextInput.setEditingState',
      'TextInput.show',
      'TextInput.setCaretRect',
      'TextInput.setEditingState',
    ];

    expect(
      tester.testTextInput.log.map((MethodCall m) => m.method),
      logOrder,
    );
    expect(tester.testTextInput.editingState!['text'], 'flutter is the best!...');
  });

  testWidgets('Synchronous test of local and remote editing values', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/65059
    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });
    final TextInputFormatter formatter = TextInputFormatter.withFunction((TextEditingValue oldValue, TextEditingValue newValue) {
      if (newValue.text == 'I will be modified by the formatter.') {
        newValue = const TextEditingValue(text: 'Flutter is the best!');
      }
      return newValue;
    });
    final TextEditingController controller = TextEditingController();
    late StateSetter setState;

    final FocusNode focusNode = FocusNode(debugLabel: 'EditableText Focus Node');
    Widget builder() {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setter) {
          setState = setter;
          return MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 1.0),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: Material(
                    child: EditableText(
                      controller: controller,
                      focusNode: focusNode,
                      style: textStyle,
                      cursorColor: Colors.red,
                      backgroundCursorColor: Colors.red,
                      keyboardType: TextInputType.multiline,
                      inputFormatters: <TextInputFormatter>[
                        formatter,
                      ],
                      onChanged: (String value) { },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    await tester.pumpWidget(builder());
    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump();

    log.clear();

    final EditableTextState state = tester.firstState(find.byType(EditableText));
    // setEditingState is not called when only the remote changes
    state.updateEditingValue(TextEditingValue(
      text: 'a',
      selection: controller.selection,
    ));

    expect(log.length, 0);

    // setEditingState is called when remote value modified by the formatter.
    state.updateEditingValue(TextEditingValue(
      text: 'I will be modified by the formatter.',
      selection: controller.selection,
    ));
    expect(log.length, 1);
    MethodCall methodCall = log[0];
    expect(
      methodCall,
      isMethodCall('TextInput.setEditingState', arguments: <String, dynamic>{
        'text': 'Flutter is the best!',
        'selectionBase': -1,
        'selectionExtent': -1,
        'selectionAffinity': 'TextAffinity.downstream',
        'selectionIsDirectional': false,
        'composingBase': -1,
        'composingExtent': -1,
      }),
    );

    log.clear();

    // setEditingState is called when the [controller.value] is modified by local.
    setState(() {
      controller.text = 'I love flutter!';
    });
    expect(log.length, 1);
    methodCall = log[0];
    expect(
      methodCall,
      isMethodCall('TextInput.setEditingState', arguments: <String, dynamic>{
        'text': 'I love flutter!',
        'selectionBase': -1,
        'selectionExtent': -1,
        'selectionAffinity': 'TextAffinity.downstream',
        'selectionIsDirectional': false,
        'composingBase': -1,
        'composingExtent': -1,
      }),
    );

    log.clear();

    // Currently `_receivedRemoteTextEditingValue` equals 'I will be modified by the formatter.',
    // setEditingState will be called when set the [controller.value] to `_receivedRemoteTextEditingValue` by local.
    setState(() {
      controller.text = 'I will be modified by the formatter.';
    });
    expect(log.length, 1);
    methodCall = log[0];
    expect(
      methodCall,
      isMethodCall('TextInput.setEditingState', arguments: <String, dynamic>{
        'text': 'I will be modified by the formatter.',
        'selectionBase': -1,
        'selectionExtent': -1,
        'selectionAffinity': 'TextAffinity.downstream',
        'selectionIsDirectional': false,
        'composingBase': -1,
        'composingExtent': -1,
      }),
    );
  });

  testWidgets('Send text input state to engine when the input formatter rejects user input', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/67828
    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });
    final TextInputFormatter formatter = TextInputFormatter.withFunction((TextEditingValue oldValue, TextEditingValue newValue) {
      return const TextEditingValue(text: 'Flutter is the best!');
    });
    final TextEditingController controller = TextEditingController();

    final FocusNode focusNode = FocusNode(debugLabel: 'EditableText Focus Node');
    Widget builder() {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setter) {
          return MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 1.0),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: Material(
                    child: EditableText(
                      controller: controller,
                      focusNode: focusNode,
                      style: textStyle,
                      cursorColor: Colors.red,
                      backgroundCursorColor: Colors.red,
                      keyboardType: TextInputType.multiline,
                      inputFormatters: <TextInputFormatter>[
                        formatter,
                      ],
                      onChanged: (String value) { },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    await tester.pumpWidget(builder());
    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump();

    log.clear();

    final EditableTextState state = tester.firstState(find.byType(EditableText));

    // setEditingState is called when remote value modified by the formatter.
    state.updateEditingValue(TextEditingValue(
      text: 'I will be modified by the formatter.',
      selection: controller.selection,
    ));
    expect(log.length, 1);
    expect(log, contains(matchesMethodCall(
      'TextInput.setEditingState',
      args: allOf(
        containsPair('text', 'Flutter is the best!'),
      ),
    )));

    log.clear();

    state.updateEditingValue(const TextEditingValue(
      text: 'I will be modified by the formatter.',
    ));
    expect(log.length, 1);
    expect(log, contains(matchesMethodCall(
      'TextInput.setEditingState',
      args: allOf(
        containsPair('text', 'Flutter is the best!'),
      ),
    )));
  });

  testWidgets('Repeatedly receiving [TextEditingValue] will not trigger a keyboard request', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/66036
    final List<MethodCall> log = <MethodCall>[];
    SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
      log.add(methodCall);
    });
    final TextEditingController controller = TextEditingController();

    final FocusNode focusNode = FocusNode(debugLabel: 'EditableText Focus Node');
    Widget builder() {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setter) {
          return MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 1.0),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: Material(
                    child: EditableText(
                      controller: controller,
                      focusNode: focusNode,
                      style: textStyle,
                      cursorColor: Colors.red,
                      backgroundCursorColor: Colors.red,
                      keyboardType: TextInputType.multiline,
                      onChanged: (String value) { },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    await tester.pumpWidget(builder());
    await tester.tap(find.byType(EditableText));
    await tester.pump();

    // The keyboard is shown after tap the EditableText.
    expect(focusNode.hasFocus, true);

    log.clear();

    final EditableTextState state = tester.firstState(find.byType(EditableText));

    state.updateEditingValue(TextEditingValue(
      text: 'a',
      selection: controller.selection,
    ));
    await tester.pump();

    // Nothing called when only the remote changes.
    expect(log.length, 0);

    // Hide the keyboard.
    focusNode.unfocus();
    await tester.pump();

    expect(log.length, 2);
    MethodCall methodCall = log[0];
    // Close the InputConnection.
    expect(methodCall, isMethodCall('TextInput.clearClient', arguments: null));
    methodCall = log[1];
    expect(methodCall, isMethodCall('TextInput.hide', arguments: null));
    // The keyboard loses focus.
    expect(focusNode.hasFocus, false);

    log.clear();

    // Send repeat value from the engine.
    state.updateEditingValue(TextEditingValue(
      text: 'a',
      selection: controller.selection,
    ));
    await tester.pump();

    // Nothing called when only the remote changes.
    expect(log.length, 0);
    // The keyboard is not be requested after a repeat value from the engine.
    expect(focusNode.hasFocus, false);
  });

  group('TextEditingController', () {
    testWidgets('TextEditingController.text set to empty string clears field', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 1.0),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: Material(
                  child: EditableText(
                    controller: controller,
                    focusNode: focusNode,
                    style: textStyle,
                    cursorColor: Colors.red,
                    backgroundCursorColor: Colors.red,
                    keyboardType: TextInputType.multiline,
                    onChanged: (String value) { },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      controller.text = '...';
      await tester.pump();
      expect(find.text('...'), findsOneWidget);

      controller.text = '';
      await tester.pump();
      expect(find.text('...'), findsNothing);
    });

    testWidgets('TextEditingController.clear() behavior test', (WidgetTester tester) async {
      // Regression test for https://github.com/flutter/flutter/issues/66316
      final List<MethodCall> log = <MethodCall>[];
      SystemChannels.textInput.setMockMethodCallHandler((MethodCall methodCall) async {
        log.add(methodCall);
      });
      final TextEditingController controller = TextEditingController();

      final FocusNode focusNode = FocusNode(debugLabel: 'EditableText Focus Node');
      Widget builder() {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setter) {
            return MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(devicePixelRatio: 1.0),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Center(
                    child: Material(
                      child: EditableText(
                        controller: controller,
                        focusNode: focusNode,
                        style: textStyle,
                        cursorColor: Colors.red,
                        backgroundCursorColor: Colors.red,
                        keyboardType: TextInputType.multiline,
                        onChanged: (String value) { },
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }

      await tester.pumpWidget(builder());
      await tester.tap(find.byType(EditableText));
      await tester.pump();

      // The keyboard is shown after tap the EditableText.
      expect(focusNode.hasFocus, true);

      log.clear();

      final EditableTextState state = tester.firstState(find.byType(EditableText));

      state.updateEditingValue(TextEditingValue(
        text: 'a',
        selection: controller.selection,
      ));
      await tester.pump();

      // Nothing called when only the remote changes.
      expect(log, isEmpty);

      controller.clear();

      expect(log.length, 1);
      expect(
        log[0],
        isMethodCall('TextInput.setEditingState', arguments: <String, dynamic>{
          'text': '',
          'selectionBase': 0,
          'selectionExtent': 0,
          'selectionAffinity': 'TextAffinity.downstream',
          'selectionIsDirectional': false,
          'composingBase': -1,
          'composingExtent': -1,
        }),
      );
    });

    testWidgets('TextEditingController.buildTextSpan receives build context', (WidgetTester tester) async {
      final _AccentColorTextEditingController controller = _AccentColorTextEditingController('a');
      const Color color = Color.fromARGB(255, 1, 2, 3);
      final ThemeData lightTheme = ThemeData.light();
      await tester.pumpWidget(MaterialApp(
        theme: lightTheme.copyWith(
          colorScheme: lightTheme.colorScheme.copyWith(secondary: color),
        ),
        home: EditableText(
          controller: controller,
          focusNode: FocusNode(),
          style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
          cursorColor: Colors.blue,
          backgroundCursorColor: Colors.grey,
        ),
      ));

      final RenderEditable renderEditable = findRenderEditable(tester);
      final TextSpan textSpan = renderEditable.text!;
      expect(textSpan.style!.color, color);
    });
  });

  testWidgets('autofocus:true on first frame does not throw', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: testText);
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 0,
      affinity: TextAffinity.upstream,
    );

    await tester.pumpWidget(MaterialApp(
      home: EditableText(
        maxLines: 10,
        controller: controller,
        showSelectionHandles: true,
        autofocus: true,
        focusNode: FocusNode(),
        style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
        cursorColor: Colors.blue,
        backgroundCursorColor: Colors.grey,
        selectionControls: materialTextSelectionControls,
        keyboardType: TextInputType.text,
        textAlign: TextAlign.right,
      ),
    ));


    await tester.pumpAndSettle(); // Wait for autofocus to take effect.

    final dynamic exception = tester.takeException();
    expect(exception, isNull);
  });

  testWidgets('updateEditingValue filters multiple calls from formatter', (WidgetTester tester) async {
    final MockTextFormatter formatter = MockTextFormatter();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              maxLines: 1, // Sets text keyboard implicitly.
              style: textStyle,
              cursorColor: cursorColor,
              inputFormatters: <TextInputFormatter>[formatter],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = '';
    await tester.idle();

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));
    expect(tester.testTextInput.editingState!['text'], equals(''));
    expect(state.wantKeepAlive, true);

    state.updateEditingValue(TextEditingValue.empty);
    state.updateEditingValue(const TextEditingValue(text: 'a'));
    state.updateEditingValue(const TextEditingValue(text: 'aa'));
    state.updateEditingValue(const TextEditingValue(text: 'aaa'));
    state.updateEditingValue(const TextEditingValue(text: 'aa'));
    state.updateEditingValue(const TextEditingValue(text: 'aaa'));
    state.updateEditingValue(const TextEditingValue(text: 'aaaa'));
    state.updateEditingValue(const TextEditingValue(text: 'aa'));
    state.updateEditingValue(const TextEditingValue(text: 'aaaaaaa'));
    state.updateEditingValue(const TextEditingValue(text: 'aa'));
    state.updateEditingValue(const TextEditingValue(text: 'aaaaaaaaa'));
    state.updateEditingValue(const TextEditingValue(text: 'aaaaaaaaa')); // Skipped

    const List<String> referenceLog = <String>[
      '[1]: , a',
      '[1]: normal aa',
      '[2]: a, aa',
      '[2]: normal aaaa',
      '[3]: aa, aaa',
      '[3]: normal aaaaaa',
      '[4]: aaa, aa',
      '[4]: deleting aa',
      '[5]: aa, aaa',
      '[5]: normal aaaaaaaaaa',
      '[6]: aaa, aaaa',
      '[6]: normal aaaaaaaaaaaa',
      '[7]: aaaa, aa',
      '[7]: deleting aaaaa',
      '[8]: aa, aaaaaaa',
      '[8]: normal aaaaaaaaaaaaaaaa',
      '[9]: aaaaaaa, aa',
      '[9]: deleting aaaaaaa',
      '[10]: aa, aaaaaaaaa',
      '[10]: normal aaaaaaaaaaaaaaaaaaaa'
    ];

    expect(formatter.log, referenceLog);
  });

  testWidgets('formatter logic handles repeat filtering', (WidgetTester tester) async {
    final MockTextFormatter formatter = MockTextFormatter();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              maxLines: 1, // Sets text keyboard implicitly.
              style: textStyle,
              cursorColor: cursorColor,
              inputFormatters: <TextInputFormatter>[formatter],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = '';
    await tester.idle();

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));
    expect(tester.testTextInput.editingState!['text'], equals(''));
    expect(state.wantKeepAlive, true);

    // We no longer perform full repeat filtering in framework, it is now left
    // to the engine to prevent repeat calls from being sent in the first place.
    // Engine preventing repeats is far more reliable and avoids many of the ambiguous
    // filtering we performed before.
    expect(formatter.formatCallCount, 0);
    state.updateEditingValue(const TextEditingValue(text: '01'));
    expect(formatter.formatCallCount, 1);
    state.updateEditingValue(const TextEditingValue(text: '012'));
    expect(formatter.formatCallCount, 2);
    state.updateEditingValue(const TextEditingValue(text: '0123')); // Text change causes reformat
    expect(formatter.formatCallCount, 3);
    state.updateEditingValue(const TextEditingValue(text: '0123')); // No text change, does not format
    expect(formatter.formatCallCount, 3);
    state.updateEditingValue(const TextEditingValue(text: '0123')); // No text change, does not format
    expect(formatter.formatCallCount, 3);
    state.updateEditingValue(const TextEditingValue(text: '0123', selection: TextSelection.collapsed(offset: 2))); // Selection change does not reformat
    expect(formatter.formatCallCount, 3);
    state.updateEditingValue(const TextEditingValue(text: '0123', selection: TextSelection.collapsed(offset: 2))); // No text change, does not format
    expect(formatter.formatCallCount, 3);
    state.updateEditingValue(const TextEditingValue(text: '0123', selection: TextSelection.collapsed(offset: 2))); // No text change, does not format
    expect(formatter.formatCallCount, 3);

    // Composing changes should not trigger reformat, as it could cause infinite loops on some IMEs.
    state.updateEditingValue(const TextEditingValue(text: '0123', selection: TextSelection.collapsed(offset: 2), composing: TextRange(start: 1, end: 2)));
    expect(formatter.formatCallCount, 3);
    expect(formatter.lastOldValue.composing, TextRange.empty);
    expect(formatter.lastNewValue.composing, TextRange.empty); // The new composing was registered in formatter.
    // Clearing composing region should trigger reformat.
    state.updateEditingValue(const TextEditingValue(text: '01234', selection: TextSelection.collapsed(offset: 2))); // Formats, with oldValue containing composing region.
    expect(formatter.formatCallCount, 4);
    expect(formatter.lastOldValue.composing, const TextRange(start: 1, end: 2));
    expect(formatter.lastNewValue.composing, TextRange.empty);

    const List<String> referenceLog = <String>[
      '[1]: , 01',
      '[1]: normal aa',
      '[2]: 01, 012',
      '[2]: normal aaaa',
      '[3]: 012, 0123',
      '[3]: normal aaaaaa',
      '[4]: 0123, 01234',
      '[4]: normal aaaaaaaa',
    ];

    expect(formatter.log, referenceLog);
  });

  // Regression test for https://github.com/flutter/flutter/issues/53612
  testWidgets('formatter logic handles initial repeat edge case', (WidgetTester tester) async {
    final MockTextFormatter formatter = MockTextFormatter();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            autofocus: true,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              maxLines: 1, // Sets text keyboard implicitly.
              style: textStyle,
              cursorColor: cursorColor,
              inputFormatters: <TextInputFormatter>[formatter],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(EditableText));
    await tester.showKeyboard(find.byType(EditableText));
    controller.text = 'test';
    await tester.idle();

    final EditableTextState state =
        tester.state<EditableTextState>(find.byType(EditableText));
    expect(tester.testTextInput.editingState!['text'], equals('test'));
    expect(state.wantKeepAlive, true);

    expect(formatter.formatCallCount, 0);
    state.updateEditingValue(const TextEditingValue(text: 'test'));
    state.updateEditingValue(const TextEditingValue(text: 'test', composing: TextRange(start: 1, end: 2)));
    state.updateEditingValue(const TextEditingValue(text: '0')); // pass to formatter once to check the values.
    expect(formatter.lastOldValue.composing, const TextRange(start: 1, end: 2));
    expect(formatter.lastOldValue.text, 'test');
  });

  testWidgets('EditableText changes mouse cursor when hovered', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            child: MouseRegion(
              cursor: SystemMouseCursors.forbidden,
              child: EditableText(
                controller: controller,
                backgroundCursorColor: Colors.grey,
                focusNode: focusNode,
                style: textStyle,
                cursorColor: cursorColor,
                mouseCursor: SystemMouseCursors.click,
              ),
            ),
          ),
        ),
      ),
    );

    final TestGesture gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
    await gesture.addPointer(location: tester.getCenter(find.byType(EditableText)));
    addTearDown(gesture.removePointer);

    await tester.pump();

    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);

    // Test default cursor
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: FocusScope(
            node: focusScopeNode,
            child: MouseRegion(
              cursor: SystemMouseCursors.forbidden,
              child: EditableText(
                controller: controller,
                backgroundCursorColor: Colors.grey,
                focusNode: focusNode,
                style: textStyle,
                cursorColor: cursorColor,
              ),
            ),
          ),
        ),
      ),
    );

    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);
  });

  testWidgets('Can access characters on editing string', (WidgetTester tester) async {
    late int charactersLength;
    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: TextEditingController(),
        focusNode: FocusNode(),
        style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
        cursorColor: Colors.blue,
        selectionControls: materialTextSelectionControls,
        keyboardType: TextInputType.text,
        onChanged: (String value) {
          charactersLength = value.characters.length;
        },
      ),
    );
    await tester.pumpWidget(widget);

    // Enter an extended grapheme cluster whose string length is different than
    // its characters length.
    await tester.enterText(find.byType(EditableText), '👨‍👩‍👦');
    await tester.pump();

    expect(charactersLength, 1);
  });

  testWidgets('EditableText can set and update clipBehavior', (WidgetTester tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 1.0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FocusScope(
          node: focusScopeNode,
          autofocus: true,
          child: EditableText(
            backgroundCursorColor: Colors.grey,
            controller: controller,
            focusNode: focusNode,
            style: textStyle,
            cursorColor: cursorColor,
          ),
        ),
      ),
    ));
    final RenderEditable renderObject = tester.allRenderObjects.whereType<RenderEditable>().first;
    expect(renderObject.clipBehavior, equals(Clip.hardEdge));

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 1.0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FocusScope(
          node: focusScopeNode,
          autofocus: true,
          child: EditableText(
            backgroundCursorColor: Colors.grey,
            controller: controller,
            focusNode: focusNode,
            style: textStyle,
            cursorColor: cursorColor,
            clipBehavior: Clip.antiAlias,
          ),
        ),
      ),
    ));
    expect(renderObject.clipBehavior, equals(Clip.antiAlias));
  });

  testWidgets('EditableText inherits DefaultTextHeightBehavior', (WidgetTester tester) async {
    const TextHeightBehavior customTextHeightBehavior = TextHeightBehavior(
      applyHeightToLastDescent: true,
      applyHeightToFirstAscent: false,
    );
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 1.0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FocusScope(
          node: focusScopeNode,
          autofocus: true,
          child: DefaultTextHeightBehavior(
            textHeightBehavior: customTextHeightBehavior,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              style: textStyle,
              cursorColor: cursorColor,
            ),
          ),
        ),
      ),
    ));
    final RenderEditable renderObject = tester.allRenderObjects.whereType<RenderEditable>().first;
    expect(renderObject.textHeightBehavior, equals(customTextHeightBehavior));
  });

  testWidgets('EditableText defaultTextHeightBehavior is used over inherited widget', (WidgetTester tester) async {
    const TextHeightBehavior inheritedTextHeightBehavior = TextHeightBehavior(
      applyHeightToLastDescent: true,
      applyHeightToFirstAscent: false,
    );
    const TextHeightBehavior customTextHeightBehavior = TextHeightBehavior(
      applyHeightToLastDescent: false,
      applyHeightToFirstAscent: false,
    );
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 1.0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FocusScope(
          node: focusScopeNode,
          autofocus: true,
          child: DefaultTextHeightBehavior(
            textHeightBehavior: inheritedTextHeightBehavior,
            child: EditableText(
              backgroundCursorColor: Colors.grey,
              controller: controller,
              focusNode: focusNode,
              style: textStyle,
              cursorColor: cursorColor,
              textHeightBehavior: customTextHeightBehavior,
            ),
          ),
        ),
      ),
    ));
    final RenderEditable renderObject = tester.allRenderObjects.whereType<RenderEditable>().first;
    expect(renderObject.textHeightBehavior, isNot(equals(inheritedTextHeightBehavior)));
    expect(renderObject.textHeightBehavior, equals(customTextHeightBehavior));
  });

  test('Asserts if composing text is not valid', () async {
    void expectToAssert(TextEditingValue value, bool shouldAssert) {
      dynamic initException;
      dynamic updateException;
      controller = TextEditingController();
      try {
        controller = TextEditingController.fromValue(value);
      } catch (e) {
        initException = e;
      }

      controller = TextEditingController();
      try {
        controller.value = value;
      } catch (e) {
        updateException = e;
      }

      expect(initException?.toString(), shouldAssert ? contains('composing range'): isNull);
      expect(updateException?.toString(), shouldAssert ? contains('composing range'): isNull);
    }

    expectToAssert(TextEditingValue.empty, false);
    expectToAssert(const TextEditingValue(text: 'test', composing: TextRange(start: 1, end: 0)), true);
    expectToAssert(const TextEditingValue(text: 'test', composing: TextRange(start: 1, end: 9)), true);
    expectToAssert(const TextEditingValue(text: 'test', composing: TextRange(start: -1, end: 9)), false);
  });

  testWidgets('Preserves composing range if cursor moves within that range', (WidgetTester tester) async {
    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
        selectionControls: materialTextSelectionControls,
      ),
    );
    await tester.pumpWidget(widget);

    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      composing: TextRange(start: 4, end: 12),
    ));
    controller.selection = const TextSelection.collapsed(offset: 5);
    expect(state.currentTextEditingValue.composing, const TextRange(start: 4, end: 12));
  });

  testWidgets('Clears composing range if cursor moves outside that range', (WidgetTester tester) async {
    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
        selectionControls: materialTextSelectionControls,
      ),
    );
    await tester.pumpWidget(widget);

    // Positioning cursor before the composing range should clear the composing range.
    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 4, end: 12),
    ));
    controller.selection = const TextSelection.collapsed(offset: 2);
    expect(state.currentTextEditingValue.composing, TextRange.empty);

    // Reset the composing range.
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 4, end: 12),
    ));
    expect(state.currentTextEditingValue.composing, const TextRange(start: 4, end: 12));

    // Positioning cursor after the composing range should clear the composing range.
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 4, end: 12),
    ));
    controller.selection = const TextSelection.collapsed(offset: 14);
    expect(state.currentTextEditingValue.composing, TextRange.empty);
  });

  testWidgets('Clears composing range if cursor moves outside that range - case two', (WidgetTester tester) async {
    final Widget widget = MaterialApp(
      home: EditableText(
        backgroundCursorColor: Colors.grey,
        controller: controller,
        focusNode: focusNode,
        style: textStyle,
        cursorColor: cursorColor,
        selectionControls: materialTextSelectionControls,
      ),
    );
    await tester.pumpWidget(widget);

    // Setting a selection before the composing range clears the composing range.
    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 4, end: 12),
    ));
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    expect(state.currentTextEditingValue.composing, TextRange.empty);

    // Reset the composing range.
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 4, end: 12),
    ));
    expect(state.currentTextEditingValue.composing, const TextRange(start: 4, end: 12));

    // Setting a selection within the composing range clears the composing range.
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 4, end: 12),
    ));
    controller.selection = const TextSelection(baseOffset: 5, extentOffset: 7);
    expect(state.currentTextEditingValue.composing, TextRange.empty);

    // Reset the composing range.
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 4, end: 12),
    ));
    expect(state.currentTextEditingValue.composing, const TextRange(start: 4, end: 12));

    // Setting a selection after the composing range clears the composing range.
    state.updateEditingValue(const TextEditingValue(
      text: 'foo composing bar',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 4, end: 12),
    ));
    controller.selection = const TextSelection(baseOffset: 13, extentOffset: 15);
    expect(state.currentTextEditingValue.composing, TextRange.empty);
  });

  group('Length formatter', () {
    const int maxLength = 5;

    Future<void> setupWidget(
      WidgetTester tester,
      LengthLimitingTextInputFormatter formatter,
    ) async {
      final Widget widget = MaterialApp(
        home: EditableText(
          backgroundCursorColor: Colors.grey,
          controller: controller,
          focusNode: focusNode,
          inputFormatters: <TextInputFormatter>[formatter],
          style: textStyle,
          cursorColor: cursorColor,
          selectionControls: materialTextSelectionControls,
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
    }

    // Regression test for https://github.com/flutter/flutter/issues/65374.
    testWidgets('will not cause crash while the TextEditingValue is composing', (WidgetTester tester) async {
      await setupWidget(
        tester,
        LengthLimitingTextInputFormatter(
          maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
        ),
      );

      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
      state.updateEditingValue(const TextEditingValue(text: 'abcde'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);
      state.updateEditingValue(const TextEditingValue(text: 'abcde', composing: TextRange(start: 2, end: 4)));
      expect(state.currentTextEditingValue.composing, const TextRange(start: 2, end: 4));

      // Formatter will not update format while the editing value is composing.
      state.updateEditingValue(const TextEditingValue(text: 'abcdef', composing: TextRange(start: 2, end: 5)));
      expect(state.currentTextEditingValue.text, 'abcdef');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 2, end: 5));

      // After composing ends, formatter will update.
      state.updateEditingValue(const TextEditingValue(text: 'abcdef'));
      expect(state.currentTextEditingValue.text, 'abcde');
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });

    testWidgets('handles composing text correctly, continued', (WidgetTester tester) async {
      await setupWidget(
        tester,
        LengthLimitingTextInputFormatter(
          maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
        ),
      );

      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

      // Initially we're at maxLength with no composing text.
      controller.text = 'abcde' ;
      assert(state.currentTextEditingValue == const TextEditingValue(text: 'abcde'));

      // Should be able to change the editing value if the new value is still shorter
      // than maxLength.
      state.updateEditingValue(const TextEditingValue(text: 'abcde', composing: TextRange(start: 2, end: 4)));
      expect(state.currentTextEditingValue.composing, const TextRange(start: 2, end: 4));

      // Reset.
      controller.text = 'abcde' ;
      assert(state.currentTextEditingValue == const TextEditingValue(text: 'abcde'));

      // The text should not change when trying to insert when the text is already
      // at maxLength.
      state.updateEditingValue(const TextEditingValue(text: 'abcdef', composing: TextRange(start: 5, end: 6)));
      expect(state.currentTextEditingValue.text, 'abcde');
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });

    // Regression test for https://github.com/flutter/flutter/issues/68086.
    testWidgets('enforced composing truncated', (WidgetTester tester) async {
      await setupWidget(
        tester,
        LengthLimitingTextInputFormatter(
          maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
        ),
      );

      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

      // Initially we're at maxLength with no composing text.
      state.updateEditingValue(const TextEditingValue(text: 'abcde'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // When it's not longer than `maxLength`, it can still start composing.
      state.updateEditingValue(const TextEditingValue(text: 'abcde', composing: TextRange(start: 3, end: 5)));
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      // `newValue` will be truncated if `composingMaxLengthEnforced`.
      state.updateEditingValue(const TextEditingValue(text: 'abcdef', composing: TextRange(start: 3, end: 6)));
      expect(state.currentTextEditingValue.text, 'abcde');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      // Reset the value.
      state.updateEditingValue(const TextEditingValue(text: 'abcde'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Change the value in order to take effects on web test.
      state.updateEditingValue(const TextEditingValue(text: '你好啊朋友'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Start composing with a longer value, it should be the same state.
      state.updateEditingValue(const TextEditingValue(text: '你好啊朋友们', composing: TextRange(start: 3, end: 6)));
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });

    // Regression test for https://github.com/flutter/flutter/issues/68086.
    testWidgets('default truncate behaviors with different platforms', (WidgetTester tester) async {
      await setupWidget(tester, LengthLimitingTextInputFormatter(maxLength));

      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

      // Initially we're at maxLength with no composing text.
      state.updateEditingValue(const TextEditingValue(text: '你好啊朋友'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // When it's not longer than `maxLength`, it can still start composing.
      state.updateEditingValue(const TextEditingValue(text: '你好啊朋友', composing: TextRange(start: 3, end: 5)));
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      state.updateEditingValue(const TextEditingValue(text: '你好啊朋友们', composing: TextRange(start: 3, end: 6)));
      if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.fuchsia
      ) {
        // `newValue` will will not be truncated on couple platforms.
        expect(state.currentTextEditingValue.text, '你好啊朋友们');
        expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 6));
      } else {
        // `newValue` on other platforms will be truncated.
        expect(state.currentTextEditingValue.text, '你好啊朋友');
        expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));
      }

      // Reset the value.
      state.updateEditingValue(const TextEditingValue(text: '你好啊朋友'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Start composing with a longer value, it should be the same state.
      state.updateEditingValue(const TextEditingValue(text: '你好啊朋友们', composing: TextRange(start: 3, end: 6)));
      expect(state.currentTextEditingValue.text, '你好啊朋友');
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });

    // Regression test for https://github.com/flutter/flutter/issues/68086.
    testWidgets('composing range removed if it\'s overflowed the truncated value\'s length', (WidgetTester tester) async {
      await setupWidget(
        tester,
        LengthLimitingTextInputFormatter(
          maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
        ),
      );

      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

      // Initially we're not at maxLength with no composing text.
      state.updateEditingValue(const TextEditingValue(text: 'abc'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Start composing.
      state.updateEditingValue(const TextEditingValue(text: 'abcde', composing: TextRange(start: 3, end: 5)));
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      // Reset the value.
      state.updateEditingValue(const TextEditingValue(text: 'abc'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Start composing with a range already overflowed the truncated length.
      state.updateEditingValue(const TextEditingValue(text: 'abcdefgh', composing: TextRange(start: 5, end: 7)));
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });

    // Regression test for https://github.com/flutter/flutter/issues/68086.
    testWidgets('composing range removed with different platforms', (WidgetTester tester) async {
      await setupWidget(tester, LengthLimitingTextInputFormatter(maxLength));

      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

      // Initially we're not at maxLength with no composing text.
      state.updateEditingValue(const TextEditingValue(text: 'abc'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Start composing.
      state.updateEditingValue(const TextEditingValue(text: 'abcde', composing: TextRange(start: 3, end: 5)));
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      // Reset the value.
      state.updateEditingValue(const TextEditingValue(text: 'abc'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Start composing with a range already overflowed the truncated length.
      state.updateEditingValue(const TextEditingValue(text: 'abcdefgh', composing: TextRange(start: 5, end: 7)));
      if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.fuchsia
      ) {
        expect(state.currentTextEditingValue.composing, const TextRange(start: 5, end: 7));
      } else {
        expect(state.currentTextEditingValue.composing, TextRange.empty);
      }
    });

    testWidgets('composing range handled correctly when it\'s overflowed', (WidgetTester tester) async {
      const String string = '👨‍👩‍👦0123456';

      await setupWidget(tester, LengthLimitingTextInputFormatter(maxLength));

      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

      // Initially we're not at maxLength with no composing text.
      state.updateEditingValue(const TextEditingValue(text: string));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Clearing composing range if collapsed.
      state.updateEditingValue(const TextEditingValue(text: string, composing: TextRange(start: 10, end: 10)));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Clearing composing range if overflowed.
      state.updateEditingValue(const TextEditingValue(text: string, composing: TextRange(start: 10, end: 11)));
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });

    // Regression test for https://github.com/flutter/flutter/issues/68086.
    testWidgets('typing in the middle with different platforms.', (WidgetTester tester) async {
      await setupWidget(tester, LengthLimitingTextInputFormatter(maxLength));

      final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));

      // Initially we're not at maxLength with no composing text.
      state.updateEditingValue(const TextEditingValue(text: 'abc'));
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      // Start typing in the middle.
      state.updateEditingValue(const TextEditingValue(text: 'abDEc', composing: TextRange(start: 3, end: 4)));
      expect(state.currentTextEditingValue.text, 'abDEc');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 4));

      // Keep typing when the value has exceed the limitation.
      state.updateEditingValue(const TextEditingValue(text: 'abDEFc', composing: TextRange(start: 3, end: 5)));
      if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.fuchsia
      ) {
        expect(state.currentTextEditingValue.text, 'abDEFc');
        expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));
      } else {
        expect(state.currentTextEditingValue.text, 'abDEc');
        expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 4));
      }

      // Reset the value according to the limit.
      state.updateEditingValue(const TextEditingValue(text: 'abDEc'));
      expect(state.currentTextEditingValue.text, 'abDEc');
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      state.updateEditingValue(const TextEditingValue(text: 'abDEFc', composing: TextRange(start: 4, end: 5)));
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });
  });

  group('callback errors', () {
    const String errorText = 'Test EditableText callback error';

    testWidgets('onSelectionChanged can throw errors', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: EditableText(
          showSelectionHandles: true,
          maxLines: 2,
          controller: TextEditingController(
            text: 'flutter is the best!',
          ),
          focusNode: FocusNode(),
          cursorColor: Colors.red,
          backgroundCursorColor: Colors.blue,
          style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
          keyboardType: TextInputType.text,
          selectionControls: materialTextSelectionControls,
          onSelectionChanged: (TextSelection selection, SelectionChangedCause? cause) {
            throw FlutterError(errorText);
          },
        ),
      ));

      // Interact with the field to establish the input connection.
      await tester.tap(find.byType(EditableText));
      final dynamic error = tester.takeException();
      expect(error, isFlutterError);
      expect(error.toString(), contains(errorText));
    });

    testWidgets('onChanged can throw errors', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: EditableText(
          showSelectionHandles: true,
          maxLines: 2,
          controller: TextEditingController(
            text: 'flutter is the best!',
          ),
          focusNode: FocusNode(),
          cursorColor: Colors.red,
          backgroundCursorColor: Colors.blue,
          style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
          keyboardType: TextInputType.text,
          onChanged: (String text) {
            throw FlutterError(errorText);
          },
        ),
      ));

      // Modify the text and expect an error from onChanged.
      await tester.enterText(find.byType(EditableText), '...');
      final dynamic error = tester.takeException();
      expect(error, isFlutterError);
      expect(error.toString(), contains(errorText));
    });

    testWidgets('onEditingComplete can throw errors', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: EditableText(
          showSelectionHandles: true,
          maxLines: 2,
          controller: TextEditingController(
            text: 'flutter is the best!',
          ),
          focusNode: FocusNode(),
          cursorColor: Colors.red,
          backgroundCursorColor: Colors.blue,
          style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
          keyboardType: TextInputType.text,
          onEditingComplete: () {
            throw FlutterError(errorText);
          },
        ),
      ));

      // Interact with the field to establish the input connection.
      final Offset topLeft = tester.getTopLeft(find.byType(EditableText));
      await tester.tapAt(topLeft + const Offset(0.0, 5.0));
      await tester.pump();

      // Submit and expect an error from onEditingComplete.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      final dynamic error = tester.takeException();
      expect(error, isFlutterError);
      expect(error.toString(), contains(errorText));
    });

    testWidgets('onSubmitted can throw errors', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: EditableText(
          showSelectionHandles: true,
          maxLines: 2,
          controller: TextEditingController(
            text: 'flutter is the best!',
          ),
          focusNode: FocusNode(),
          cursorColor: Colors.red,
          backgroundCursorColor: Colors.blue,
          style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!.copyWith(fontFamily: 'Roboto'),
          keyboardType: TextInputType.text,
          onSubmitted: (String text) {
            throw FlutterError(errorText);
          },
        ),
      ));

      // Interact with the field to establish the input connection.
      final Offset topLeft = tester.getTopLeft(find.byType(EditableText));
      await tester.tapAt(topLeft + const Offset(0.0, 5.0));
      await tester.pump();

      // Submit and expect an error from onSubmitted.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      final dynamic error = tester.takeException();
      expect(error, isFlutterError);
      expect(error.toString(), contains(errorText));
    });
  });

  // Regression test for https://github.com/flutter/flutter/issues/72400.
  testWidgets("delete doesn't cause crash when selection is -1,-1", (WidgetTester tester) async {
    final UnsettableController unsettableController = UnsettableController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1.0),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: EditableText(
            autofocus: true,
            controller: unsettableController,
            backgroundCursorColor: Colors.grey,
            focusNode: focusNode,
            style: textStyle,
            cursorColor: cursorColor,
          ),
        ),
      ),
    );

    await tester.pump(); // Wait for the autofocus to take effect.

    // Delete
    await sendKeys(
      tester,
      <LogicalKeyboardKey>[
        LogicalKeyboardKey.delete,
      ],
      platform: 'android',
    );

    expect(tester.takeException(), null);
  });

  testWidgets('can change behavior by overriding text editing shortcuts', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: testText);
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 0,
      affinity: TextAffinity.upstream,
    );
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: Shortcuts(
            shortcuts: <LogicalKeySet, Intent>{
              LogicalKeySet(LogicalKeyboardKey.arrowLeft): const MoveSelectionRightTextIntent(),
            },
            child: EditableText(
              maxLines: 10,
              controller: controller,
              showSelectionHandles: true,
              autofocus: true,
              focusNode: focusNode,
              style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
              cursorColor: Colors.blue,
              backgroundCursorColor: Colors.grey,
              selectionControls: materialTextSelectionControls,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ),
    ));

    await tester.pump(); // Wait for autofocus to take effect.

    // The right arrow key moves to the right as usual.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, 1);

    // And the left arrow also moves to the right due to the Shortcuts override.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, 2);

    // On web, using keyboard for selection is handled by the browser.
  }, skip: kIsWeb);

  testWidgets('navigating by word', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: 'word word word');
    // word wo|rd| word
    controller.selection = const TextSelection(
      baseOffset: 7,
      extentOffset: 9,
      affinity: TextAffinity.upstream,
    );
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: EditableText(
            maxLines: 10,
            controller: controller,
            autofocus: true,
            focusNode: focusNode,
            style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            keyboardType: TextInputType.text,
          ),
        ),
      ),
    ));

    await tester.pump(); // Wait for autofocus to take effect.
    expect(controller.selection.isCollapsed, false);
    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 9);

    final String targetPlatform = defaultTargetPlatform.toString();
    final String platform = targetPlatform.substring(targetPlatform.indexOf('.') + 1).toLowerCase();

    await sendKeys(
      tester,
      <LogicalKeyboardKey>[LogicalKeyboardKey.arrowRight],
      shift: true,
      wordModifier: true,
      platform: platform,
    );
    await tester.pump();
    // word wo|rd word|
    expect(controller.selection.isCollapsed, false);
    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 14);

    await sendKeys(
      tester,
      <LogicalKeyboardKey>[LogicalKeyboardKey.arrowLeft],
      shift: true,
      wordModifier: true,
      platform: platform,
    );
    // word wo|rd |word
    expect(controller.selection.isCollapsed, false);
    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 10);

    await sendKeys(
      tester,
      <LogicalKeyboardKey>[LogicalKeyboardKey.arrowLeft],
      shift: true,
      wordModifier: true,
      platform: platform,
    );
    if (platform == 'macos') {
      // word wo|rd word
      expect(controller.selection.isCollapsed, true);
      expect(controller.selection.baseOffset, 7);
      expect(controller.selection.extentOffset, 7);

      await sendKeys(
        tester,
        <LogicalKeyboardKey>[LogicalKeyboardKey.arrowLeft],
        shift: true,
        wordModifier: true,
        platform: platform,
      );
    }

    // word |wo|rd word
    expect(controller.selection.isCollapsed, false);
    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 5);

    await sendKeys(
      tester,
      <LogicalKeyboardKey>[LogicalKeyboardKey.arrowLeft],
      shift: true,
      wordModifier: true,
      platform: platform,
    );
    // |word wo|rd word
    expect(controller.selection.isCollapsed, false);
    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 0);

    await sendKeys(
      tester,
      <LogicalKeyboardKey>[LogicalKeyboardKey.arrowRight],
      shift: true,
      wordModifier: true,
      platform: platform,
    );
    // word| wo|rd word
    expect(controller.selection.isCollapsed, false);
    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 4);

    await sendKeys(
      tester,
      <LogicalKeyboardKey>[LogicalKeyboardKey.arrowRight],
      shift: true,
      wordModifier: true,
      platform: platform,
    );
    if (platform == 'macos') {
      // word wo|rd word
      expect(controller.selection.isCollapsed, true);
      expect(controller.selection.baseOffset, 7);
      expect(controller.selection.extentOffset, 7);

      await sendKeys(
        tester,
        <LogicalKeyboardKey>[LogicalKeyboardKey.arrowRight],
        shift: true,
        wordModifier: true,
        platform: platform,
      );
    }

    // word wo|rd| word
    expect(controller.selection.isCollapsed, false);
    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 9);

    // On web, using keyboard for selection is handled by the browser.
  }, skip: kIsWeb, variant: TargetPlatformVariant.all());

  testWidgets('can change behavior by overriding text editing actions', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: testText);
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 0,
      affinity: TextAffinity.upstream,
    );
    late final bool myIntentWasCalled;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: Actions(
            actions: <Type, Action<Intent>>{
              MoveSelectionLeftTextIntent: _MyMoveSelectionRightTextAction(
                onInvoke: () {
                  myIntentWasCalled = true;
                },
              ),
            },
            child: EditableText(
              maxLines: 10,
              controller: controller,
              showSelectionHandles: true,
              autofocus: true,
              focusNode: focusNode,
              style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
              cursorColor: Colors.blue,
              backgroundCursorColor: Colors.grey,
              selectionControls: materialTextSelectionControls,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ),
    ));

    await tester.pump(); // Wait for autofocus to take effect.

    // The right arrow key moves to the right as usual.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, 1);

    // And the left arrow also moves to the right due to the Actions override.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, 2);
    expect(myIntentWasCalled, isTrue);

    // On web, using keyboard for selection is handled by the browser.
  }, skip: kIsWeb);

  testWidgets('ignore key event from web platform', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'test\ntest',
    );
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 0,
      affinity: TextAffinity.upstream,
    );
    bool myIntentWasCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: Actions(
            actions: <Type, Action<Intent>>{
              MoveSelectionRightTextIntent: _MyMoveSelectionRightTextAction(
                onInvoke: () {
                  myIntentWasCalled = true;
                },
              ),
            },
            child: EditableText(
              maxLines: 10,
              controller: controller,
              showSelectionHandles: true,
              autofocus: true,
              focusNode: focusNode,
              style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
              cursorColor: Colors.blue,
              backgroundCursorColor: Colors.grey,
              selectionControls: materialTextSelectionControls,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ),
    ));

    await tester.pump(); // Wait for autofocus to take effect.

    if (kIsWeb) {
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight, platform: 'web');
      await tester.pump();
      expect(myIntentWasCalled, isFalse);
      expect(controller.selection.isCollapsed, true);
      expect(controller.selection.baseOffset, 0);
    } else {
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight, platform: 'android');
      await tester.pump();
      expect(myIntentWasCalled, isTrue);
      expect(controller.selection.isCollapsed, true);
      expect(controller.selection.baseOffset, 1);
    }
  });
}

class UnsettableController extends TextEditingController {
  @override
  set value(TextEditingValue v) {
    // Do nothing for set, which causes selection to remain as -1, -1.
  }
}

class MockTextFormatter extends TextInputFormatter {
  MockTextFormatter() : formatCallCount = 0, log = <String>[];

  int formatCallCount;
  List<String> log;
  late TextEditingValue lastOldValue;
  late TextEditingValue lastNewValue;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    lastOldValue = oldValue;
    lastNewValue = newValue;
    formatCallCount++;
    log.add('[$formatCallCount]: ${oldValue.text}, ${newValue.text}');
    TextEditingValue finalValue;
    if (newValue.text.length < oldValue.text.length) {
      finalValue = _handleTextDeletion(oldValue, newValue);
    } else {
      finalValue = _formatText(newValue);
    }
    return finalValue;
  }


  TextEditingValue _handleTextDeletion(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final String result = 'a' * (formatCallCount - 2);
    log.add('[$formatCallCount]: deleting $result');
    return TextEditingValue(text: newValue.text, selection: newValue.selection, composing: newValue.composing);
  }

  TextEditingValue _formatText(TextEditingValue value) {
    final String result = 'a' * formatCallCount * 2;
    log.add('[$formatCallCount]: normal $result');
    return TextEditingValue(text: value.text, selection: value.selection, composing: value.composing);
  }
}

class MockTextSelectionControls extends Fake implements TextSelectionControls {
  @override
  Widget buildToolbar(BuildContext context, Rect globalEditableRegion, double textLineHeight, Offset position, List<TextSelectionPoint> endpoints, TextSelectionDelegate delegate, ClipboardStatusNotifier clipboardStatus, Offset? lastSecondaryTapDownPosition) {
    return Container();
  }

  @override
  Widget buildHandle(BuildContext context, TextSelectionHandleType type, double textLineHeight) {
    return Container();
  }

  @override
  Size getHandleSize(double textLineHeight) {
    return Size.zero;
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    return Offset.zero;
  }

  bool testCanCut = false;
  bool testCanCopy = false;
  bool testCanPaste = false;

  int cutCount = 0;
  int pasteCount = 0;
  int copyCount = 0;

  @override
  void handleCopy(TextSelectionDelegate delegate, ClipboardStatusNotifier? clipboardStatus) {
    copyCount += 1;
  }

  @override
  Future<void> handlePaste(TextSelectionDelegate delegate) async {
    pasteCount += 1;
  }

  @override
  void handleCut(TextSelectionDelegate delegate) {
    cutCount += 1;
  }

  @override
  bool canCut(TextSelectionDelegate delegate) {
    return testCanCut;
  }

  @override
  bool canCopy(TextSelectionDelegate delegate) {
    return testCanCopy;
  }

  @override
  bool canPaste(TextSelectionDelegate delegate) {
    return testCanPaste;
  }
}

class CustomStyleEditableText extends EditableText {
  CustomStyleEditableText({
    Key? key,
    required TextEditingController controller,
    required Color cursorColor,
    required FocusNode focusNode,
    required TextStyle style,
  }) : super(
          key: key,
          controller: controller,
          cursorColor: cursorColor,
          backgroundCursorColor: Colors.grey,
          focusNode: focusNode,
          style: style,
        );
  @override
  CustomStyleEditableTextState createState() =>
      CustomStyleEditableTextState();
}

class CustomStyleEditableTextState extends EditableTextState {
  @override
  TextSpan buildTextSpan() {
    return TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      text: widget.controller.value.text,
    );
  }
}

class TransformedEditableText extends StatefulWidget {
  const TransformedEditableText({
    Key? key,
    required this.offset,
    required this.transformButtonKey,
  }) : super(key: key);

  final Offset offset;
  final Key transformButtonKey;

  @override
  _TransformedEditableTextState createState() => _TransformedEditableTextState();
}

class _TransformedEditableTextState extends State<TransformedEditableText> {
  bool _isTransformed = false;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(
          devicePixelRatio: 1.0
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Transform.translate(
              offset: _isTransformed ? widget.offset : Offset.zero,
              child: EditableText(
                controller: TextEditingController(),
                focusNode: FocusNode(),
                style: Typography.material2018(platform: TargetPlatform.android).black.subtitle1!,
                cursorColor: Colors.blue,
                backgroundCursorColor: Colors.grey,
              ),
            ),
            ElevatedButton(
              key: widget.transformButtonKey,
              onPressed: () {
                setState(() {
                  _isTransformed = !_isTransformed;
                });
              },
              child: const Text('Toggle Transform'),
            ),
          ],
        ),
      ),
    );
  }
}

class NoImplicitScrollPhysics extends AlwaysScrollableScrollPhysics {
  const NoImplicitScrollPhysics({ ScrollPhysics? parent }) : super(parent: parent);

  @override
  bool get allowImplicitScrolling => false;

  @override
  NoImplicitScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return NoImplicitScrollPhysics(parent: buildParent(ancestor)!);
  }
}

class SkipPainting extends SingleChildRenderObjectWidget {
  const SkipPainting({ Key? key, required Widget child }): super(key: key, child: child);

  @override
  SkipPaintingRenderObject createRenderObject(BuildContext context) => SkipPaintingRenderObject();
}

class SkipPaintingRenderObject extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) { }
}

class _AccentColorTextEditingController extends TextEditingController {
  _AccentColorTextEditingController(String text) : super(text: text);

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final Color color = Theme.of(context).colorScheme.secondary;
    return super.buildTextSpan(context: context, style: TextStyle(color: color), withComposing: withComposing);
  }
}

class _MyMoveSelectionRightTextAction extends TextEditingAction<Intent> {
  _MyMoveSelectionRightTextAction({
    required this.onInvoke,
  }) : super();

  final VoidCallback onInvoke;

  @override
  Object? invoke(Intent intent, [BuildContext? context]) {
    textEditingActionTarget!.renderEditable.moveSelectionRight(SelectionChangedCause.keyboard);
    onInvoke();
  }
}
