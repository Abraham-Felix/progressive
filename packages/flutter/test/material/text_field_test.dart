// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'dart:ui' as ui show window, BoxHeightStyle, BoxWidthStyle;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../widgets/editable_text_utils.dart' show findRenderEditable, globalize, textOffsetToPosition;
import '../widgets/semantics_tester.dart';
import 'feedback_tester.dart';

typedef FormatEditUpdateCallback = void Function(TextEditingValue, TextEditingValue);

// On web, the context menu (aka toolbar) is provided by the browser.
final bool isContextMenuProvidedByPlatform = isBrowser;

// On web, key events in text fields are handled by the browser.
final bool areKeyEventsHandledByPlatform = isBrowser;

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

class MaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) => DefaultMaterialLocalizations.load(locale);

  @override
  bool shouldReload(MaterialLocalizationsDelegate old) => false;
}

class WidgetsLocalizationsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) => DefaultWidgetsLocalizations.load(locale);

  @override
  bool shouldReload(WidgetsLocalizationsDelegate old) => false;
}

Widget overlay({ required Widget child }) {
  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext context) {
      return Center(
        child: Material(
          child: child,
        ),
      );
    },
  );
  return overlayWithEntry(entry);
}

Widget overlayWithEntry(OverlayEntry entry) {
  return Localizations(
    locale: const Locale('en', 'US'),
    delegates: <LocalizationsDelegate<dynamic>>[
      WidgetsLocalizationsDelegate(),
      MaterialLocalizationsDelegate(),
    ],
    child: DefaultTextEditingShortcuts(
      child: DefaultTextEditingActions(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800.0, 600.0)),
            child: Overlay(
              initialEntries: <OverlayEntry>[
                entry,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget boilerplate({ required Widget child }) {
  return MaterialApp(
    home: Localizations(
      locale: const Locale('en', 'US'),
      delegates: <LocalizationsDelegate<dynamic>>[
        WidgetsLocalizationsDelegate(),
        MaterialLocalizationsDelegate(),
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800.0, 600.0)),
          child: Center(
            child: Material(
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> skipPastScrollingAnimation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

double getOpacity(WidgetTester tester, Finder finder) {
  return tester.widget<FadeTransition>(
    find.ancestor(
      of: finder,
      matching: find.byType(FadeTransition),
    ),
  ).opacity.value;
}

class TestFormatter extends TextInputFormatter {
  TestFormatter(this.onFormatEditUpdate);
  FormatEditUpdateCallback onFormatEditUpdate;
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    onFormatEditUpdate(oldValue, newValue);
    return newValue;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final MockClipboard mockClipboard = MockClipboard();

  const String kThreeLines =
    'First line of text is\n'
    'Second line goes until\n'
    'Third line of stuff';
  const String kMoreThanFourLines =
    kThreeLines +
    "\nFourth line won't display and ends at";
  // Gap between caret and edge of input, defined in editable.dart.
  const int kCaretGap = 1;

  setUp(() async {
    debugResetSemanticsIdCounter();
    SystemChannels.platform.setMockMethodCallHandler(mockClipboard.handleMethodCall);
    // Fill the clipboard so that the Paste option is available in the text
    // selection menu.
    await Clipboard.setData(const ClipboardData(text: 'Clipboard data'));
  });

  tearDown(() {
    SystemChannels.platform.setMockMethodCallHandler(null);
  });

  final Key textFieldKey = UniqueKey();
  Widget textFieldBuilder({
    int? maxLines = 1,
    int? minLines,
  }) {
    return boilerplate(
      child: TextField(
        key: textFieldKey,
        style: const TextStyle(color: Colors.black, fontSize: 34.0),
        maxLines: maxLines,
        minLines: minLines,
        decoration: const InputDecoration(
          hintText: 'Placeholder',
        ),
      ),
    );
  }

  testWidgets('can use the desktop cut/copy/paste buttons on Mac', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'blah1 blah2',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
          ),
        ),
      ),
    );

    // Initially, the menu is not shown and there is no selection.
    expect(find.byType(CupertinoButton), findsNothing);
    expect(controller.selection, const TextSelection(baseOffset: -1, extentOffset: -1));

    final Offset midBlah1 = textOffsetToPosition(tester, 2);

    // Right clicking shows the menu.
    final TestGesture gesture = await tester.startGesture(
      midBlah1,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);

    // Copy the first word.
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(controller.text, 'blah1 blah2');
    expect(controller.selection, const TextSelection(baseOffset: 5, extentOffset: 5));
    expect(find.byType(CupertinoButton), findsNothing);

    // Paste it at the end.
    await gesture.down(textOffsetToPosition(tester, controller.text.length));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection(baseOffset: 11, extentOffset: 11, affinity: TextAffinity.upstream));
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Paste'), findsOneWidget);
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(controller.text, 'blah1 blah2blah1');
    expect(controller.selection, const TextSelection(baseOffset: 16, extentOffset: 16));

    // Cut the first word.
    await gesture.down(midBlah1);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
    await tester.tap(find.text('Cut'));
    await tester.pumpAndSettle();
    expect(controller.text, ' blah2blah1');
    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 0));
    expect(find.byType(CupertinoButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux }), skip: isContextMenuProvidedByPlatform);

  testWidgets('Activates the text field when receives semantics focus on Mac', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final SemanticsOwner semanticsOwner = tester.binding.pipelineOwner.semanticsOwner!;
    final FocusNode focusNode = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(focusNode: focusNode),
        ),
      ),
    );
    expect(semantics, hasSemantics(
      TestSemantics.root(
        children: <TestSemantics>[
          TestSemantics(
            id: 1,
            textDirection: TextDirection.ltr,
            children: <TestSemantics>[
              TestSemantics(
                id: 2,
                children: <TestSemantics>[
                  TestSemantics(
                    id: 3,
                    flags: <SemanticsFlag>[SemanticsFlag.scopesRoute],
                    children: <TestSemantics>[
                      TestSemantics(
                        id: 4,
                        flags: <SemanticsFlag>[SemanticsFlag.isTextField],
                        actions: <SemanticsAction>[SemanticsAction.tap,
                          SemanticsAction.didGainAccessibilityFocus],
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
    ));

    expect(focusNode.hasFocus, isFalse);
    semanticsOwner.performAction(4, SemanticsAction.didGainAccessibilityFocus);
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
    semantics.dispose();
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.macOS }));

  testWidgets('TextField passes onEditingComplete to EditableText', (WidgetTester tester) async {
    void onEditingComplete() { }

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            onEditingComplete: onEditingComplete,
          ),
        ),
      ),
    );

    final Finder editableTextFinder = find.byType(EditableText);
    expect(editableTextFinder, findsOneWidget);

    final EditableText editableTextWidget = tester.widget(editableTextFinder);
    expect(editableTextWidget.onEditingComplete, onEditingComplete);
  });

  testWidgets('TextField has consistent size', (WidgetTester tester) async {
    final Key textFieldKey = UniqueKey();
    late String textFieldValue;

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: textFieldKey,
          decoration: const InputDecoration(
            hintText: 'Placeholder',
          ),
          onChanged: (String value) {
            textFieldValue = value;
          },
        ),
      ),
    );

    RenderBox findTextFieldBox() => tester.renderObject(find.byKey(textFieldKey));

    final RenderBox inputBox = findTextFieldBox();
    final Size emptyInputSize = inputBox.size;

    Future<void> checkText(String testValue) async {
      return TestAsyncUtils.guard(() async {
        await tester.enterText(find.byType(TextField), testValue);
        // Check that the onChanged event handler fired.
        expect(textFieldValue, equals(testValue));
        await skipPastScrollingAnimation(tester);
      });
    }

    await checkText(' ');

    expect(findTextFieldBox(), equals(inputBox));
    expect(inputBox.size, equals(emptyInputSize));

    await checkText('Test');
    expect(findTextFieldBox(), equals(inputBox));
    expect(inputBox.size, equals(emptyInputSize));
  });

  testWidgets('Cursor blinks', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const TextField(
          decoration: InputDecoration(
            hintText: 'Placeholder',
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));

    final EditableTextState editableText = tester.state(find.byType(EditableText));

    // Check that the cursor visibility toggles after each blink interval.
    Future<void> checkCursorToggle() async {
      final bool initialShowCursor = editableText.cursorCurrentlyVisible;
      await tester.pump(editableText.cursorBlinkInterval);
      expect(editableText.cursorCurrentlyVisible, equals(!initialShowCursor));
      await tester.pump(editableText.cursorBlinkInterval);
      expect(editableText.cursorCurrentlyVisible, equals(initialShowCursor));
      await tester.pump(editableText.cursorBlinkInterval ~/ 10);
      expect(editableText.cursorCurrentlyVisible, equals(initialShowCursor));
      await tester.pump(editableText.cursorBlinkInterval);
      expect(editableText.cursorCurrentlyVisible, equals(!initialShowCursor));
      await tester.pump(editableText.cursorBlinkInterval);
      expect(editableText.cursorCurrentlyVisible, equals(initialShowCursor));
    }

    await checkCursorToggle();
    await tester.showKeyboard(find.byType(TextField));

    // Try the test again with a nonempty EditableText.
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'X',
      selection: TextSelection.collapsed(offset: 1),
    ));
    await checkCursorToggle();
  });

  testWidgets('Cursor animates', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TextField(),
        ),
      ),
    );

    final Finder textFinder = find.byType(TextField);
    await tester.tap(textFinder);
    await tester.pump();

    final EditableTextState editableTextState = tester.firstState(find.byType(EditableText));
    final RenderEditable renderEditable = editableTextState.renderEditable;

    expect(renderEditable.cursorColor!.alpha, 255);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(renderEditable.cursorColor!.alpha, 255);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 100));

    expect(renderEditable.cursorColor!.alpha, 110);

    await tester.pump(const Duration(milliseconds: 100));

    expect(renderEditable.cursorColor!.alpha, 16);
    await tester.pump(const Duration(milliseconds: 50));

    expect(renderEditable.cursorColor!.alpha, 0);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  // Regression test for https://github.com/flutter/flutter/issues/78918.
  testWidgets('RenderEditable sets correct text editing value', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: 'how are you');
    final UniqueKey icon = UniqueKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                key: icon,
                icon: const Icon(Icons.cancel),
                onPressed: () => controller.clear(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(icon));
    await tester.pump();
    expect(controller.text, '');
    expect(controller.selection, const TextSelection.collapsed(offset: 0, affinity: TextAffinity.upstream));
  });

  testWidgets('Cursor radius is 2.0', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TextField(),
        ),
      ),
    );

    final EditableTextState editableTextState = tester.firstState(find.byType(EditableText));
    final RenderEditable renderEditable = editableTextState.renderEditable;

    expect(renderEditable.cursorRadius, const Radius.circular(2.0));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets('cursor has expected defaults', (WidgetTester tester) async {
    await tester.pumpWidget(
        overlay(
          child: const TextField(
          ),
        ),
    );

    final TextField textField = tester.firstWidget(find.byType(TextField));
    expect(textField.cursorWidth, 2.0);
    expect(textField.cursorHeight, null);
    expect(textField.cursorRadius, null);
  });

  testWidgets('cursor has expected radius value', (WidgetTester tester) async {
    await tester.pumpWidget(
        overlay(
          child: const TextField(
            cursorRadius: Radius.circular(3.0),
          ),
        ),
    );

    final TextField textField = tester.firstWidget(find.byType(TextField));
    expect(textField.cursorWidth, 2.0);
    expect(textField.cursorRadius, const Radius.circular(3.0));
  });

  testWidgets('Material cursor android golden', (WidgetTester tester) async {
    final Widget widget = overlay(
      child: const RepaintBoundary(
        key: ValueKey<int>(1),
        child: TextField(
          cursorColor: Colors.blue,
          cursorWidth: 15,
          cursorRadius: Radius.circular(3.0),
        ),
      ),
    );
    await tester.pumpWidget(widget);

    const String testValue = 'A short phrase';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    await tester.tapAt(textOffsetToPosition(tester, testValue.length));
    await tester.pump();

    await expectLater(
      find.byKey(const ValueKey<int>(1)),
      matchesGoldenFile('text_field_cursor_test.material.0.png'),
    );
  });

  testWidgets('Material cursor golden', (WidgetTester tester) async {
    final Widget widget = overlay(
      child: const RepaintBoundary(
        key: ValueKey<int>(1),
        child: TextField(
          cursorColor: Colors.blue,
          cursorWidth: 15,
          cursorRadius: Radius.circular(3.0),
        ),
      ),
    );
    await tester.pumpWidget(widget);

    const String testValue = 'A short phrase';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    await tester.tapAt(textOffsetToPosition(tester, testValue.length));
    await tester.pump();

    await expectLater(
      find.byKey(const ValueKey<int>(1)),
      matchesGoldenFile(
        'text_field_cursor_test_${describeEnum(debugDefaultTargetPlatformOverride!).toLowerCase()}.material.1.png',
      ),
    );
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets('TextInputFormatter gets correct selection value', (WidgetTester tester) async {
    late TextEditingValue actualOldValue;
    late TextEditingValue actualNewValue;
    void callBack(TextEditingValue oldValue, TextEditingValue newValue) {
      actualOldValue = oldValue;
      actualNewValue = newValue;
    }
    final FocusNode focusNode = FocusNode();
    final TextEditingController controller = TextEditingController(text: '123');
    await tester.pumpWidget(
      boilerplate(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          inputFormatters: <TextInputFormatter>[TestFormatter(callBack)],
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(
      actualOldValue,
      const TextEditingValue(
        text: '123',
        selection: TextSelection.collapsed(offset: 3, affinity: TextAffinity.upstream),
      ),
    );
    expect(
      actualNewValue,
      const TextEditingValue(
        text: '12',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('text field selection toolbar renders correctly inside opacity', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: Opacity(
                opacity: 0.5,
                child: TextField(
                  decoration: InputDecoration(hintText: 'Placeholder'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.showKeyboard(find.byType(TextField));

    const String testValue = 'A B C';
    tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: testValue
        )
    );
    await tester.pump();

    // The selectWordsInRange with SelectionChangedCause.tap seems to be needed to show the toolbar.
    // (This is true even if we provide selection parameter to the TextEditingValue above.)
    final EditableTextState state = tester.state<EditableTextState>(find.byType(EditableText));
    state.renderEditable.selectWordsInRange(from: Offset.zero, cause: SelectionChangedCause.tap);

    expect(state.showToolbar(), true);

    // This is needed for the AnimatedOpacity to turn from 0 to 1 so the toolbar is visible.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    // Sanity check that the toolbar widget exists.
    expect(find.text('Paste'), findsOneWidget);

    await expectLater(
      // The toolbar exists in the Overlay above the MaterialApp.
      find.byType(Overlay),
      matchesGoldenFile('text_field_opacity_test.0.png'),
    );
  }, skip: isContextMenuProvidedByPlatform);

  testWidgets('text field toolbar options correctly changes options',
      (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              controller: controller,
              toolbarOptions: const ToolbarOptions(copy: true),
            ),
          ),
        ),
      ),
    );

    final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

    // This tap just puts the cursor somewhere different than where the double
    // tap will occur to test that the double tap moves the existing cursor first.
    await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
    await tester.pump(const Duration(milliseconds: 50));
    // First tap moved the cursor.
    expect(
      controller.selection,
      const TextSelection.collapsed(
          offset: 8, affinity: TextAffinity.downstream),
    );
    await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
    await tester.pump();

    // Second tap selects the word around the cursor.
    expect(
      controller.selection,
      const TextSelection(baseOffset: 8, extentOffset: 12),
    );

    // Selected text shows 'Copy', and not 'Paste', 'Cut', 'Select All'.
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Select All'), findsNothing);
  },
    variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }),
    skip: isContextMenuProvidedByPlatform,
  );

  testWidgets('text selection style 1', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure\nhi\nwasssup!',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: RepaintBoundary(
              child: Container(
                width: 650.0,
                height: 600.0,
                decoration: const BoxDecoration(
                  color: Color(0xff00ff00),
                ),
                child: Column(
                  children: <Widget>[
                    TextField(
                      key: const Key('field0'),
                      controller: controller,
                      style: const TextStyle(height: 4, color: Colors.black45),
                      toolbarOptions: const ToolbarOptions(copy: true, selectAll: true),
                      selectionHeightStyle: ui.BoxHeightStyle.includeLineSpacingTop,
                      selectionWidthStyle: ui.BoxWidthStyle.max,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final Offset textfieldStart = tester.getTopLeft(find.byKey(const Key('field0')));

    await tester.longPressAt(textfieldStart + const Offset(50.0, 2.0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(textfieldStart + const Offset(100.0, 107.0));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('text_field_golden.TextSelectionStyle.1.png'),
    );
  });

  testWidgets('text selection style 2', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure\nhi\nwasssup!',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: RepaintBoundary(
              child: Container(
                width: 650.0,
                height: 600.0,
                decoration: const BoxDecoration(
                  color: Color(0xff00ff00),
                ),
                child: Column(
                  children: <Widget>[
                    TextField(
                      key: const Key('field0'),
                      controller: controller,
                      style: const TextStyle(height: 4, color: Colors.black45),
                      toolbarOptions: const ToolbarOptions(copy: true, selectAll: true),
                      selectionHeightStyle: ui.BoxHeightStyle.includeLineSpacingBottom,
                      selectionWidthStyle: ui.BoxWidthStyle.tight,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final Offset textfieldStart = tester.getTopLeft(find.byKey(const Key('field0')));

    await tester.longPressAt(textfieldStart + const Offset(50.0, 2.0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(textfieldStart + const Offset(100.0, 107.0));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('text_field_golden.TextSelectionStyle.2.png'),
    );
  });

  testWidgets('text field toolbar options correctly changes options',
      (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              controller: controller,
              toolbarOptions: const ToolbarOptions(copy: true),
            ),
          ),
        ),
      ),
    );

    final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

    await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
    await tester.pump();

    // Selected text shows 'Copy', and not 'Paste', 'Cut', 'Select all'.
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Select all'), findsNothing);
  },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
      TargetPlatform.fuchsia,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
    skip: isContextMenuProvidedByPlatform,
  );

  testWidgets('cursor layout has correct width', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController.fromValue(
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
    final FocusNode focusNode = FocusNode();
    EditableText.debugDeterministicCursor = true;
    await tester.pumpWidget(
        overlay(
          child: RepaintBoundary(
            child: TextField(
              cursorWidth: 15.0,
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        )
    );
    focusNode.requestFocus();
    await tester.pump();

    await expectLater(
      find.byType(TextField),
      matchesGoldenFile('text_field_cursor_width_test.0.png'),
    );
    EditableText.debugDeterministicCursor = false;
  });

  testWidgets('cursor layout has correct radius', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController.fromValue(
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
    final FocusNode focusNode = FocusNode();
    EditableText.debugDeterministicCursor = true;
    await tester.pumpWidget(
        overlay(
          child: RepaintBoundary(
            child: TextField(
              cursorWidth: 15.0,
              cursorRadius: const Radius.circular(3.0),
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        )
    );
    focusNode.requestFocus();
    await tester.pump();

    await expectLater(
      find.byType(TextField),
      matchesGoldenFile('text_field_cursor_width_test.1.png'),
    );
    EditableText.debugDeterministicCursor = false;
  });

  testWidgets('cursor layout has correct height', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController.fromValue(
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
    final FocusNode focusNode = FocusNode();
    EditableText.debugDeterministicCursor = true;
    await tester.pumpWidget(
        overlay(
          child: RepaintBoundary(
            child: TextField(
              cursorWidth: 15.0,
              cursorHeight: 30.0,
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        )
    );
    focusNode.requestFocus();
    await tester.pump();

    await expectLater(
      find.byType(TextField),
      matchesGoldenFile('text_field_cursor_width_test.2.png'),
    );
    EditableText.debugDeterministicCursor = false;
  });

  testWidgets('Overflowing a line with spaces stops the cursor at the end', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: textFieldKey,
          controller: controller,
          maxLines: null,
        ),
      ),
    );
    expect(controller.selection.baseOffset, -1);
    expect(controller.selection.extentOffset, -1);

    const String testValueOneLine = 'enough text to be exactly at the end of the line.';
    await tester.enterText(find.byType(TextField), testValueOneLine);
    await skipPastScrollingAnimation(tester);

    RenderBox findInputBox() => tester.renderObject(find.byKey(textFieldKey));

    RenderBox inputBox = findInputBox();
    final Size oneLineInputSize = inputBox.size;

    await tester.tapAt(textOffsetToPosition(tester, testValueOneLine.length));
    await tester.pump();

    const String testValueTwoLines = 'enough text to overflow the first line and go to the second';
    await tester.enterText(find.byType(TextField), testValueTwoLines);
    await skipPastScrollingAnimation(tester);

    expect(inputBox, findInputBox());
    inputBox = findInputBox();
    expect(inputBox.size.height, greaterThan(oneLineInputSize.height));
    final Size twoLineInputSize = inputBox.size;

    // Enter a string with the same number of characters as testValueTwoLines,
    // but where the overflowing part is all spaces. Assert that it only renders
    // on one line.
    const String testValueSpaces = testValueOneLine + '          ';
    expect(testValueSpaces.length, testValueTwoLines.length);
    await tester.enterText(find.byType(TextField), testValueSpaces);
    await skipPastScrollingAnimation(tester);

    expect(inputBox, findInputBox());
    inputBox = findInputBox();
    expect(inputBox.size.height, oneLineInputSize.height);

    // Swapping the final space for a letter causes it to wrap to 2 lines.
    const String testValueSpacesOverflow = testValueOneLine + '         a';
    expect(testValueSpacesOverflow.length, testValueTwoLines.length);
    await tester.enterText(find.byType(TextField), testValueSpacesOverflow);
    await skipPastScrollingAnimation(tester);

    expect(inputBox, findInputBox());
    inputBox = findInputBox();
    expect(inputBox.size.height, twoLineInputSize.height);

    // Positioning the cursor at the end of a line overflowing with spaces puts
    // it inside the input still.
    await tester.enterText(find.byType(TextField), testValueSpaces);
    await skipPastScrollingAnimation(tester);
    await tester.tapAt(textOffsetToPosition(tester, testValueSpaces.length));
    await tester.pump();

    final double inputWidth = findRenderEditable(tester).size.width;
    final Offset cursorOffsetSpaces = findRenderEditable(tester).getLocalRectForCaret(
      const TextPosition(offset: testValueSpaces.length),
    ).bottomRight;

    expect(cursorOffsetSpaces.dx, inputWidth - kCaretGap);
  });

  testWidgets('mobile obscureText control test', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const TextField(
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Placeholder',
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));

    const String testValue = 'ABC';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: testValue,
      selection: TextSelection.collapsed(offset: testValue.length),
    ));

    await tester.pump();

    // Enter a character into the obscured field and verify that the character
    // is temporarily shown to the user and then changed to a bullet.
    const String newChar = 'X';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: testValue + newChar,
      selection: TextSelection.collapsed(offset: testValue.length + 1),
    ));

    await tester.pump();

    String editText = findRenderEditable(tester).text!.text!;
    expect(editText.substring(editText.length - 1), newChar);

    await tester.pump(const Duration(seconds: 2));

    editText = findRenderEditable(tester).text!.text!;
    expect(editText.substring(editText.length - 1), '\u2022');
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.android }));

  testWidgets('desktop obscureText control test', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const TextField(
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Placeholder',
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));

    const String testValue = 'ABC';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: testValue,
      selection: TextSelection.collapsed(offset: testValue.length),
    ));

    await tester.pump();

    // Enter a character into the obscured field and verify that the character
    // isn't shown to the user.
    const String newChar = 'X';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: testValue + newChar,
      selection: TextSelection.collapsed(offset: testValue.length + 1),
    ));

    await tester.pump();

    final String editText = findRenderEditable(tester).text!.text!;
    expect(editText.substring(editText.length - 1), '\u2022');
  }, variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
  }));

  testWidgets('Caret position is updated on tap', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
        ),
      ),
    );
    expect(controller.selection.baseOffset, -1);
    expect(controller.selection.extentOffset, -1);

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    // Tap to reposition the caret.
    final int tapIndex = testValue.indexOf('e');
    final Offset ePos = textOffsetToPosition(tester, tapIndex);
    await tester.tapAt(ePos);
    await tester.pump();

    expect(controller.selection.baseOffset, tapIndex);
    expect(controller.selection.extentOffset, tapIndex);
  });

  testWidgets('enableInteractiveSelection = false, tap', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
          enableInteractiveSelection: false,
        ),
      ),
    );
    expect(controller.selection.baseOffset, -1);
    expect(controller.selection.extentOffset, -1);

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    // Tap would ordinarily reposition the caret.
    final int tapIndex = testValue.indexOf('e');
    final Offset ePos = textOffsetToPosition(tester, tapIndex);
    await tester.tapAt(ePos);
    await tester.pump();

    expect(controller.selection.baseOffset, testValue.length);
    expect(controller.selection.isCollapsed, isTrue);
  });

  testWidgets('Can long press to select', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    expect(controller.value.text, testValue);
    await skipPastScrollingAnimation(tester);

    expect(controller.selection.isCollapsed, true);

    // Long press the 'e' to select 'def'.
    final Offset ePos = textOffsetToPosition(tester, testValue.indexOf('e'));
    await tester.longPressAt(ePos, pointer: 7);
    await tester.pump();

    // 'def' is selected.
    expect(controller.selection.baseOffset, testValue.indexOf('d'));
    expect(controller.selection.extentOffset, testValue.indexOf('f')+1);

    // Tapping elsewhere immediately collapses and moves the cursor.
    await tester.tapAt(textOffsetToPosition(tester, testValue.indexOf('h')));
    await tester.pump();

    expect(controller.selection.isCollapsed, true);
    expect(controller.selection.baseOffset, testValue.indexOf('h'));
  });

  testWidgets("Slight movements in longpress don't hide/show handles", (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    expect(controller.value.text, testValue);
    await skipPastScrollingAnimation(tester);

    expect(controller.selection.isCollapsed, true);

    // Long press the 'e' to select 'def', but don't release the gesture.
    final Offset ePos = textOffsetToPosition(tester, testValue.indexOf('e'));
    final TestGesture gesture = await tester.startGesture(ePos, pointer: 7);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Handles are shown
    final Finder fadeFinder = find.byType(FadeTransition);
    expect(fadeFinder, findsNWidgets(2)); // 2 handles, 1 toolbar
    FadeTransition handle = tester.widget(fadeFinder.at(0));
    expect(handle.opacity.value, equals(1.0));

    // Move the gesture very slightly
    await gesture.moveBy(const Offset(1.0, 1.0));
    await tester.pump(TextSelectionOverlay.fadeDuration * 0.5);
    handle = tester.widget(fadeFinder.at(0));

    // The handle should still be fully opaque.
    expect(handle.opacity.value, equals(1.0));
  });


  testWidgets('Long pressing a field with selection 0,0 shows the selection menu', (WidgetTester tester) async {
    await tester.pumpWidget(overlay(
      child: TextField(
        controller: TextEditingController.fromValue(
          const TextEditingValue(
            selection: TextSelection(baseOffset: 0, extentOffset: 0),
          ),
        ),
      ),
    ));

    expect(find.text('Paste'), findsNothing);
    final Offset emptyPos = textOffsetToPosition(tester, 0);
    await tester.longPressAt(emptyPos, pointer: 7);
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsOneWidget);
  }, skip: isContextMenuProvidedByPlatform);

  testWidgets('Entering text hides selection handle caret', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abcdefghi';
    await tester.enterText(find.byType(TextField), testValue);
    expect(controller.value.text, testValue);
    await skipPastScrollingAnimation(tester);

    // Handle not shown.
    expect(controller.selection.isCollapsed, true);
    final Finder fadeFinder = find.byType(FadeTransition);
    expect(fadeFinder, findsNothing);

    // Tap on the text field to show the handle.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(controller.selection.isCollapsed, true);
    expect(fadeFinder, findsNWidgets(1));
    final FadeTransition handle = tester.widget(fadeFinder.at(0));
    expect(handle.opacity.value, equals(1.0));

    // Enter more text.
    const String testValueAddition = 'jklmni';
    await tester.enterText(find.byType(TextField), testValueAddition);
    expect(controller.value.text, testValueAddition);
    await skipPastScrollingAnimation(tester);

    // Handle not shown.
    expect(controller.selection.isCollapsed, true);
    expect(fadeFinder, findsNothing);
  });

  testWidgets('selection handles are excluded from the semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abcdefghi';
    await tester.enterText(find.byType(TextField), testValue);
    expect(controller.value.text, testValue);
    await skipPastScrollingAnimation(tester);
    // Tap on the text field to show the handle.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    // The semantics should only have the text field.
    expect(semantics, hasSemantics(
      TestSemantics.root(
        children: <TestSemantics>[
          TestSemantics(
            id: 1,
            flags: <SemanticsFlag>[SemanticsFlag.isTextField, SemanticsFlag.isFocused],
            actions: <SemanticsAction>[SemanticsAction.tap,
              SemanticsAction.moveCursorBackwardByCharacter, SemanticsAction.setSelection, SemanticsAction.paste,
              SemanticsAction.setText, SemanticsAction.moveCursorBackwardByWord],
            value: 'abcdefghi',
            textDirection: TextDirection.ltr,
            textSelection: const TextSelection.collapsed(offset: 9),
          ),
        ],
      ),
      ignoreRect: true,
      ignoreTransform: true,
    ));
    semantics.dispose();
  });

  testWidgets('Mouse long press is just like a tap', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    expect(controller.value.text, testValue);
    await skipPastScrollingAnimation(tester);

    expect(controller.selection.isCollapsed, true);

    // Long press the 'e' using a mouse device.
    final int eIndex = testValue.indexOf('e');
    final Offset ePos = textOffsetToPosition(tester, eIndex);
    final TestGesture gesture = await tester.startGesture(ePos, kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();

    // The cursor is placed just like a regular tap.
    expect(controller.selection.baseOffset, eIndex);
    expect(controller.selection.extentOffset, eIndex);
  });

  testWidgets('Read only text field basic', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: 'readonly');

    await tester.pumpWidget(
        overlay(
          child: TextField(
            controller: controller,
            readOnly: true,
          ),
        ),
    );
    // Read only text field cannot open keyboard.
    await tester.showKeyboard(find.byType(TextField));
    // On web, we always create a client connection to the engine.
    expect(tester.testTextInput.hasAnyClients, isBrowser ? isTrue : isFalse);
    await skipPastScrollingAnimation(tester);

    expect(controller.selection.isCollapsed, true);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    // On web, we always create a client connection to the engine.
    expect(tester.testTextInput.hasAnyClients, isBrowser ? isTrue : isFalse);
    final EditableTextState editableText = tester.state(find.byType(EditableText));
    // Collapse selection should not paint.
    expect(editableText.selectionOverlay!.handlesAreVisible, isFalse);
    // Long press on the 'd' character of text 'readOnly' to show context menu.
    const int dIndex = 3;
    final Offset dPos = textOffsetToPosition(tester, dIndex);
    await tester.longPressAt(dPos);
    await tester.pumpAndSettle();

    // Context menu should not have paste and cut.
    expect(find.text('Copy'), isContextMenuProvidedByPlatform ? findsNothing : findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Cut'), findsNothing);
  });

  testWidgets('does not paint toolbar when no options available', (WidgetTester tester) async {
    await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: TextField(
              readOnly: true,
            ),
          ),
        ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(TextField));
    // Wait for context menu to be built.
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTextSelectionToolbar), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets('text field build empty toolbar when no options available', (WidgetTester tester) async {
    await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: TextField(
              readOnly: true,
            ),
          ),
        ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(TextField));
    // Wait for context menu to be built.
    await tester.pumpAndSettle();
    final RenderBox container = tester.renderObject(find.descendant(
      of: find.byType(FadeTransition),
      matching: find.byType(SizedBox),
    ).first);
    expect(container.size, Size.zero);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.fuchsia, TargetPlatform.linux, TargetPlatform.windows }));

  testWidgets('Sawping controllers should update selection', (WidgetTester tester) async {
    TextEditingController controller = TextEditingController(text: 'readonly');
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) {
        return Center(
          child: Material(
            child: TextField(
              controller: controller,
              readOnly: true,
            ),
          ),
        );
      },
    );
    await tester.pumpWidget(overlayWithEntry(entry));
    const int dIndex = 3;
    final Offset dPos = textOffsetToPosition(tester, dIndex);
    await tester.longPressAt(dPos);
    await tester.pumpAndSettle();
    final EditableTextState state = tester.state(find.byType(EditableText));
    TextSelection currentOverlaySelection =
        state.selectionOverlay!.value.selection;
    expect(currentOverlaySelection.baseOffset, 0);
    expect(currentOverlaySelection.extentOffset, 8);

    // Update selection from [0 to 8] to [1 to 7].
    controller = TextEditingController.fromValue(
      controller.value.copyWith(selection: const TextSelection(
        baseOffset: 1,
        extentOffset: 7,
      )),
    );

    // Mark entry to be dirty in order to trigger overlay update.
    entry.markNeedsBuild();

    await tester.pump();
    currentOverlaySelection = state.selectionOverlay!.value.selection;
    expect(currentOverlaySelection.baseOffset, 1);
    expect(currentOverlaySelection.extentOffset, 7);
  });

  testWidgets('Read only text should not compose', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController.fromValue(
        const TextEditingValue(
            text: 'readonly',
            composing: TextRange(start: 0, end: 8), // Simulate text composing.
        ),
    );

    await tester.pumpWidget(
        overlay(
          child: TextField(
            controller: controller,
            readOnly: true,
          ),
        ),
    );

    final RenderEditable renderEditable = findRenderEditable(tester);
    // There should be no composing.
    expect(renderEditable.text, TextSpan(text:'readonly', style: renderEditable.text!.style));
  });

  testWidgets('Dynamically switching between read only and not read only should hide or show collapse cursor', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: 'readonly');
    bool readOnly = true;
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) {
        return Center(
          child: Material(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
            ),
          ),
        );
      },
    );
    await tester.pumpWidget(overlayWithEntry(entry));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    final EditableTextState editableText = tester.state(find.byType(EditableText));
    // Collapse selection should not paint.
    expect(editableText.selectionOverlay!.handlesAreVisible, isFalse);

    readOnly = false;
    // Mark entry to be dirty in order to trigger overlay update.
    entry.markNeedsBuild();
    await tester.pumpAndSettle();
    expect(editableText.selectionOverlay!.handlesAreVisible, isTrue);

    readOnly = true;
    entry.markNeedsBuild();
    await tester.pumpAndSettle();
    expect(editableText.selectionOverlay!.handlesAreVisible, isFalse);
  });

  testWidgets('Dynamically switching to read only should close input connection', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: 'readonly');
    bool readOnly = false;
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) {
        return Center(
          child: Material(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
            ),
          ),
        );
      },
    );
    await tester.pumpWidget(overlayWithEntry(entry));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, true);

    readOnly = true;
    // Mark entry to be dirty in order to trigger overlay update.
    entry.markNeedsBuild();
    await tester.pump();
    // On web, we always have a client connection to the engine.
    expect(tester.testTextInput.hasAnyClients, isBrowser ? isTrue : isFalse);
  });

  testWidgets('Dynamically switching to non read only should open input connection', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: 'readonly');
    bool readOnly = true;
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) {
        return Center(
          child: Material(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
            ),
          ),
        );
      },
    );
    await tester.pumpWidget(overlayWithEntry(entry));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    // On web, we always have a client connection to the engine.
    expect(tester.testTextInput.hasAnyClients, isBrowser ? isTrue : isFalse);

    readOnly = false;
    // Mark entry to be dirty in order to trigger overlay update.
    entry.markNeedsBuild();
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, true);
  });

  testWidgets('enableInteractiveSelection = false, long-press', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
          enableInteractiveSelection: false,
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    expect(controller.value.text, testValue);
    await skipPastScrollingAnimation(tester);

    expect(controller.selection.isCollapsed, true);

    // Long press the 'e' to select 'def'.
    final Offset ePos = textOffsetToPosition(tester, testValue.indexOf('e'));
    await tester.longPressAt(ePos, pointer: 7);
    await tester.pump();

    expect(controller.selection.isCollapsed, true);
    expect(controller.selection.baseOffset, testValue.length);
  });

  testWidgets('Can select text by dragging with a mouse', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            dragStartBehavior: DragStartBehavior.down,
            controller: controller,
          ),
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    final Offset ePos = textOffsetToPosition(tester, testValue.indexOf('e'));
    final Offset gPos = textOffsetToPosition(tester, testValue.indexOf('g'));

    final TestGesture gesture = await tester.startGesture(ePos, kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(gPos);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, testValue.indexOf('e'));
    expect(controller.selection.extentOffset, testValue.indexOf('g'));
  });

  testWidgets('Continuous dragging does not cause flickering', (WidgetTester tester) async {
    int selectionChangedCount = 0;
    const String testValue = 'abc def ghi';
    final TextEditingController controller = TextEditingController(text: testValue);

    controller.addListener(() {
      selectionChangedCount++;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            dragStartBehavior: DragStartBehavior.down,
            controller: controller,
            style: const TextStyle(fontFamily: 'Ahem', fontSize: 10.0),
          ),
        ),
      ),
    );

    final Offset cPos = textOffsetToPosition(tester, 2); // Index of 'c'.
    final Offset gPos = textOffsetToPosition(tester, 8); // Index of 'g'.
    final Offset hPos = textOffsetToPosition(tester, 9); // Index of 'h'.

    // Drag from 'c' to 'g'.
    final TestGesture gesture = await tester.startGesture(cPos, kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(gPos);
    await tester.pumpAndSettle();

    expect(selectionChangedCount, isNonZero);
    selectionChangedCount = 0;
    expect(controller.selection.baseOffset, 2);
    expect(controller.selection.extentOffset, 8);

    // Tiny movement shouldn't cause text selection to change.
    await gesture.moveTo(gPos + const Offset(4.0, 0.0));
    await tester.pumpAndSettle();
    expect(selectionChangedCount, 0);

    // Now a text selection change will occur after a significant movement.
    await gesture.moveTo(hPos);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selectionChangedCount, 1);
    expect(controller.selection.baseOffset, 2);
    expect(controller.selection.extentOffset, 9);
  });

  testWidgets('Dragging in opposite direction also works', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            dragStartBehavior: DragStartBehavior.down,
            controller: controller,
          ),
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    final Offset ePos = textOffsetToPosition(tester, testValue.indexOf('e'));
    final Offset gPos = textOffsetToPosition(tester, testValue.indexOf('g'));

    final TestGesture gesture = await tester.startGesture(gPos, kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(ePos);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, testValue.indexOf('g'));
    expect(controller.selection.extentOffset, testValue.indexOf('e'));
  });

  testWidgets('Slow mouse dragging also selects text', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            dragStartBehavior: DragStartBehavior.down,
            controller: controller,
          ),
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    final Offset ePos = textOffsetToPosition(tester, testValue.indexOf('e'));
    final Offset gPos = textOffsetToPosition(tester, testValue.indexOf('g'));

    final TestGesture gesture = await tester.startGesture(ePos, kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await tester.pump(const Duration(seconds: 2));
    await gesture.moveTo(gPos);
    await tester.pump();
    await gesture.up();

    expect(controller.selection.baseOffset, testValue.indexOf('e'));
    expect(controller.selection.extentOffset, testValue.indexOf('g'));
  });

  testWidgets('Can drag handles to change selection', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          dragStartBehavior: DragStartBehavior.down,
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    // Long press the 'e' to select 'def'.
    final Offset ePos = textOffsetToPosition(tester, testValue.indexOf('e'));
    TestGesture gesture = await tester.startGesture(ePos, pointer: 7);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero

    final TextSelection selection = controller.selection;
    expect(selection.baseOffset, 4);
    expect(selection.extentOffset, 7);

    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(selection),
      renderEditable,
    );
    expect(endpoints.length, 2);

    // Drag the right handle 2 letters to the right.
    // We use a small offset because the endpoint is on the very corner
    // of the handle.
    Offset handlePos = endpoints[1].point + const Offset(1.0, 1.0);
    Offset newHandlePos = textOffsetToPosition(tester, testValue.length);
    gesture = await tester.startGesture(handlePos, pointer: 7);
    await tester.pump();
    await gesture.moveTo(newHandlePos);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 11);

    // Drag the left handle 2 letters to the left.
    handlePos = endpoints[0].point + const Offset(-1.0, 1.0);
    newHandlePos = textOffsetToPosition(tester, 0);
    gesture = await tester.startGesture(handlePos, pointer: 7);
    await tester.pump();
    await gesture.moveTo(newHandlePos);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, 11);
  });

  testWidgets('Cannot drag one handle past the other', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          dragStartBehavior: DragStartBehavior.down,
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    // Long press the 'e' to select 'def'.
    final Offset ePos = textOffsetToPosition(tester, 5); // Position before 'e'.
    TestGesture gesture = await tester.startGesture(ePos, pointer: 7);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero

    final TextSelection selection = controller.selection;
    expect(selection.baseOffset, 4);
    expect(selection.extentOffset, 7);

    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(selection),
      renderEditable,
    );
    expect(endpoints.length, 2);

    // Drag the right handle until there's only 1 char selected.
    // We use a small offset because the endpoint is on the very corner
    // of the handle.
    final Offset handlePos = endpoints[1].point + const Offset(4.0, 0.0);
    Offset newHandlePos = textOffsetToPosition(tester, 5); // Position before 'e'.
    gesture = await tester.startGesture(handlePos, pointer: 7);
    await tester.pump();
    await gesture.moveTo(newHandlePos);
    await tester.pump();

    expect(controller.selection.baseOffset, 4);
    expect(controller.selection.extentOffset, 5);

    newHandlePos = textOffsetToPosition(tester, 2); // Position before 'c'.
    await gesture.moveTo(newHandlePos);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.selection.baseOffset, 4);
    // The selection doesn't move beyond the left handle. There's always at
    // least 1 char selected.
    expect(controller.selection.extentOffset, 5);
  });

  testWidgets('Can use selection toolbar', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    // Tap the selection handle to bring up the "paste / select all" menu.
    await tester.tapAt(textOffsetToPosition(tester, testValue.indexOf('e')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero
    RenderEditable renderEditable = findRenderEditable(tester);
    List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(controller.selection),
      renderEditable,
    );
    // Tapping on the part of the handle's GestureDetector where it overlaps
    // with the text itself does not show the menu, so add a small vertical
    // offset to tap below the text.
    await tester.tapAt(endpoints[0].point + const Offset(1.0, 13.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero

    // Select all should select all the text.
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, testValue.length);

    // Copy should reset the selection.
    await tester.tap(find.text('Copy'));
    await skipPastScrollingAnimation(tester);
    expect(controller.selection.isCollapsed, true);

    // Tap again to bring back the menu.
    await tester.tapAt(textOffsetToPosition(tester, testValue.indexOf('e')));
    await tester.pump();
    // Allow time for handle to appear and double tap to time out.
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.selection.isCollapsed, true);
    expect(controller.selection.baseOffset, testValue.indexOf('e'));
    expect(controller.selection.extentOffset, testValue.indexOf('e'));
    renderEditable = findRenderEditable(tester);
    endpoints = globalize(
      renderEditable.getEndpointsForSelection(controller.selection),
      renderEditable,
    );
    await tester.tapAt(endpoints[0].point + const Offset(1.0, 1.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero
    expect(controller.selection.isCollapsed, true);
    expect(controller.selection.baseOffset, testValue.indexOf('e'));
    expect(controller.selection.extentOffset, testValue.indexOf('e'));

    // Paste right before the 'e'.
    await tester.tap(find.text('Paste'));
    await tester.pump();
    expect(controller.text, 'abc d${testValue}ef ghi');
  }, skip: isContextMenuProvidedByPlatform);

  // Show the selection menu at the given index into the text by tapping to
  // place the cursor and then tapping on the handle.
  Future<void> _showSelectionMenuAt(WidgetTester tester, TextEditingController controller, int index) async {
    await tester.tapAt(tester.getCenter(find.byType(EditableText)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero
    expect(find.text('Select all'), findsNothing);

    // Tap the selection handle to bring up the "paste / select all" menu for
    // the last line of text.
    await tester.tapAt(textOffsetToPosition(tester, index));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero
    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(controller.selection),
      renderEditable,
    );
    // Tapping on the part of the handle's GestureDetector where it overlaps
    // with the text itself does not show the menu, so add a small vertical
    // offset to tap below the text.
    await tester.tapAt(endpoints[0].point + const Offset(1.0, 13.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero
  }

  testWidgets(
    'Check the toolbar appears below the TextField when there is not enough space above the TextField to show it',
    (WidgetTester tester) async {
      // This is a regression test for
      // https://github.com/flutter/flutter/issues/29808
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(30.0),
            child: TextField(
              controller: controller,
              ),
            ),
          ),
        ),
      );

      const String testValue = 'abc def ghi';
      await tester.enterText(find.byType(TextField), testValue);
      await skipPastScrollingAnimation(tester);

      await _showSelectionMenuAt(tester, controller, testValue.indexOf('e'));

      // Verify the selection toolbar position is below the text.
      Offset toolbarTopLeft = tester.getTopLeft(find.text('Select all'));
      Offset textFieldTopLeft = tester.getTopLeft(find.byType(TextField));
      expect(textFieldTopLeft.dy, lessThan(toolbarTopLeft.dy));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(150.0),
            child: TextField(
              controller: controller,
            ),
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), testValue);
      await skipPastScrollingAnimation(tester);

      await _showSelectionMenuAt(tester, controller, testValue.indexOf('e'));

      // Verify the selection toolbar position
      toolbarTopLeft = tester.getTopLeft(find.text('Select all'));
      textFieldTopLeft = tester.getTopLeft(find.byType(TextField));
      expect(toolbarTopLeft.dy, lessThan(textFieldTopLeft.dy));
    },
    skip: isContextMenuProvidedByPlatform,
  );

  testWidgets(
    'Toolbar appears in the right places in multiline inputs',
    (WidgetTester tester) async {
      // This is a regression test for
      // https://github.com/flutter/flutter/issues/36749
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(30.0),
            child: TextField(
              controller: controller,
              minLines: 6,
              maxLines: 6,
            ),
          ),
        ),
      ));

      expect(find.text('Select all'), findsNothing);
      const String testValue = 'abc\ndef\nghi\njkl\nmno\npqr';
      await tester.enterText(find.byType(TextField), testValue);
      await skipPastScrollingAnimation(tester);

      // Show the selection menu on the first line and verify the selection
      // toolbar position is below the first line.
      await _showSelectionMenuAt(tester, controller, testValue.indexOf('c'));
      expect(find.text('Select all'), findsOneWidget);
      final Offset firstLineToolbarTopLeft = tester.getTopLeft(find.text('Select all'));
      final Offset firstLineTopLeft = textOffsetToPosition(tester, testValue.indexOf('a'));
      expect(firstLineTopLeft.dy, lessThan(firstLineToolbarTopLeft.dy));

      // Show the selection menu on the second to last line and verify the
      // selection toolbar position is above that line and above the first
      // line's toolbar.
      await _showSelectionMenuAt(tester, controller, testValue.indexOf('o'));
      expect(find.text('Select all'), findsOneWidget);
      final Offset penultimateLineToolbarTopLeft = tester.getTopLeft(find.text('Select all'));
      final Offset penultimateLineTopLeft = textOffsetToPosition(tester, testValue.indexOf('p'));
      expect(penultimateLineToolbarTopLeft.dy, lessThan(penultimateLineTopLeft.dy));
      expect(penultimateLineToolbarTopLeft.dy, lessThan(firstLineToolbarTopLeft.dy));

      // Show the selection menu on the last line and verify the selection
      // toolbar position is above that line and below the position of the
      // second to last line's toolbar.
      await _showSelectionMenuAt(tester, controller, testValue.indexOf('r'));
      expect(find.text('Select all'), findsOneWidget);
      final Offset lastLineToolbarTopLeft = tester.getTopLeft(find.text('Select all'));
      final Offset lastLineTopLeft = textOffsetToPosition(tester, testValue.indexOf('p'));
      expect(lastLineToolbarTopLeft.dy, lessThan(lastLineTopLeft.dy));
      expect(lastLineToolbarTopLeft.dy, greaterThan(penultimateLineToolbarTopLeft.dy));
    },
    skip: isContextMenuProvidedByPlatform,
  );

  testWidgets('Selection toolbar fades in', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
        ),
      ),
    );

    const String testValue = 'abc def ghi';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    // Tap the selection handle to bring up the "paste / select all" menu.
    await tester.tapAt(textOffsetToPosition(tester, testValue.indexOf('e')));
    await tester.pump();
    // Allow time for the handle to appear and for a double tap to time out.
    await tester.pump(const Duration(milliseconds: 600));
    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(controller.selection),
      renderEditable,
    );
    await tester.tapAt(endpoints[0].point + const Offset(1.0, 1.0));
    // Pump an extra frame to allow the selection menu to read the clipboard.
    await tester.pump();
    await tester.pump();

    // Toolbar should fade in. Starting at 0% opacity.
    final Element target = tester.element(find.text('Select all'));
    final FadeTransition opacity = target.findAncestorWidgetOfExactType<FadeTransition>()!;
    expect(opacity.opacity.value, equals(0.0));

    // Still fading in.
    await tester.pump(const Duration(milliseconds: 50));
    final FadeTransition opacity2 = target.findAncestorWidgetOfExactType<FadeTransition>()!;
    expect(opacity, same(opacity2));
    expect(opacity.opacity.value, greaterThan(0.0));
    expect(opacity.opacity.value, lessThan(1.0));

    // End the test here to ensure the animation is properly disposed of.
  }, skip: isContextMenuProvidedByPlatform);

  testWidgets('An obscured TextField is selectable by default', (WidgetTester tester) async {
    // This is a regression test for
    // https://github.com/flutter/flutter/issues/32845

    final TextEditingController controller = TextEditingController();
    Widget buildFrame(bool obscureText) {
      return overlay(
        child: TextField(
          controller: controller,
          obscureText: obscureText,
        ),
      );
    }

    // Obscure text and don't enable or disable selection.
    await tester.pumpWidget(buildFrame(true));
    await tester.enterText(find.byType(TextField), 'abcdefghi');
    await skipPastScrollingAnimation(tester);
    expect(controller.selection.isCollapsed, true);

    // Long press does select text.
    final Offset ePos = textOffsetToPosition(tester, 1);
    await tester.longPressAt(ePos, pointer: 7);
    await tester.pump();
    expect(controller.selection.isCollapsed, false);
  });

  testWidgets('An obscured TextField is not selectable when disabled', (WidgetTester tester) async {
    // This is a regression test for
    // https://github.com/flutter/flutter/issues/32845

    final TextEditingController controller = TextEditingController();
    Widget buildFrame(bool obscureText, bool enableInteractiveSelection) {
      return overlay(
        child: TextField(
          controller: controller,
          obscureText: obscureText,
          enableInteractiveSelection: enableInteractiveSelection,
        ),
      );
    }

    // Explicitly disabled selection on obscured text.
    await tester.pumpWidget(buildFrame(true, false));
    await tester.enterText(find.byType(TextField), 'abcdefghi');
    await skipPastScrollingAnimation(tester);
    expect(controller.selection.isCollapsed, true);

    // Long press doesn't select text.
    final Offset ePos2 = textOffsetToPosition(tester, 1);
    await tester.longPressAt(ePos2, pointer: 7);
    await tester.pump();
    expect(controller.selection.isCollapsed, true);
  });

  testWidgets('An obscured TextField is selected as one word', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(overlay(
      child: TextField(
        controller: controller,
        obscureText: true,
      ),
    ));
    await tester.enterText(find.byType(TextField), 'abcde fghi');
    await skipPastScrollingAnimation(tester);

    // Long press does select text.
    final Offset bPos = textOffsetToPosition(tester, 1);
    await tester.longPressAt(bPos, pointer: 7);
    await tester.pump();
    final TextSelection selection = controller.selection;
    expect(selection.isCollapsed, false);
    expect(selection.baseOffset, 0);
    expect(selection.extentOffset, 10);
  });

  testWidgets('An obscured TextField has correct default context menu', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(overlay(
      child: TextField(
        controller: controller,
        obscureText: true,
      ),
    ));
    await tester.enterText(find.byType(TextField), 'abcde fghi');
    await skipPastScrollingAnimation(tester);

    // Long press to select text.
    final Offset bPos = textOffsetToPosition(tester, 1);
    await tester.longPressAt(bPos, pointer: 7);
    await tester.pumpAndSettle();

    // Should only have paste option when whole obscure text is selected.
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Select all'), findsNothing);

    // Long press at the end
    final Offset iPos = textOffsetToPosition(tester, 10);
    final Offset slightRight = iPos + const Offset(30.0, 0.0);
    await tester.longPressAt(slightRight, pointer: 7);
    await tester.pumpAndSettle();

    // Should have paste and select all options when collapse.
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Cut'), findsNothing);
  }, skip: isContextMenuProvidedByPlatform);

  testWidgets('TextField height with minLines unset', (WidgetTester tester) async {
    await tester.pumpWidget(textFieldBuilder());

    RenderBox findInputBox() => tester.renderObject(find.byKey(textFieldKey));

    final RenderBox inputBox = findInputBox();
    final Size emptyInputSize = inputBox.size;

    await tester.enterText(find.byType(TextField), 'No wrapping here.');
    await tester.pumpWidget(textFieldBuilder());
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size, equals(emptyInputSize));

    // Even when entering multiline text, TextField doesn't grow. It's a single
    // line input.
    await tester.enterText(find.byType(TextField), kThreeLines);
    await tester.pumpWidget(textFieldBuilder());
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size, equals(emptyInputSize));

    // maxLines: 3 makes the TextField 3 lines tall
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpWidget(textFieldBuilder(maxLines: 3));
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size.height, greaterThan(emptyInputSize.height));
    expect(inputBox.size.width, emptyInputSize.width);

    final Size threeLineInputSize = inputBox.size;

    // Filling with 3 lines of text stays the same size
    await tester.enterText(find.byType(TextField), kThreeLines);
    await tester.pumpWidget(textFieldBuilder(maxLines: 3));
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size, threeLineInputSize);

    // An extra line won't increase the size because we max at 3.
    await tester.enterText(find.byType(TextField), kMoreThanFourLines);
    await tester.pumpWidget(textFieldBuilder(maxLines: 3));
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size, threeLineInputSize);

    // But now it will... but it will max at four
    await tester.enterText(find.byType(TextField), kMoreThanFourLines);
    await tester.pumpWidget(textFieldBuilder(maxLines: 4));
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size.height, greaterThan(threeLineInputSize.height));
    expect(inputBox.size.width, threeLineInputSize.width);

    final Size fourLineInputSize = inputBox.size;

    // Now it won't max out until the end
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpWidget(textFieldBuilder(maxLines: null));
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size, equals(emptyInputSize));
    await tester.enterText(find.byType(TextField), kThreeLines);
    await tester.pump();
    expect(inputBox.size, equals(threeLineInputSize));
    await tester.enterText(find.byType(TextField), kMoreThanFourLines);
    await tester.pump();
    expect(inputBox.size.height, greaterThan(fourLineInputSize.height));
    expect(inputBox.size.width, fourLineInputSize.width);
  });

  testWidgets('TextField height with minLines and maxLines', (WidgetTester tester) async {
    await tester.pumpWidget(textFieldBuilder());

    RenderBox findInputBox() => tester.renderObject(find.byKey(textFieldKey));

    final RenderBox inputBox = findInputBox();
    final Size emptyInputSize = inputBox.size;

    await tester.enterText(find.byType(TextField), 'No wrapping here.');
    await tester.pumpWidget(textFieldBuilder());
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size, equals(emptyInputSize));

    // min and max set to same value locks height to value.
    await tester.pumpWidget(textFieldBuilder(minLines: 3, maxLines: 3));
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size.height, greaterThan(emptyInputSize.height));
    expect(inputBox.size.width, emptyInputSize.width);

    final Size threeLineInputSize = inputBox.size;

    // maxLines: null with minLines set grows beyond minLines
    await tester.pumpWidget(textFieldBuilder(minLines: 3, maxLines: null));
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size, threeLineInputSize);
    await tester.enterText(find.byType(TextField), kMoreThanFourLines);
    await tester.pump();
    expect(inputBox.size.height, greaterThan(threeLineInputSize.height));
    expect(inputBox.size.width, threeLineInputSize.width);

    // With minLines and maxLines set, input will expand through the range
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpWidget(textFieldBuilder(minLines: 3, maxLines: 4));
    expect(findInputBox(), equals(inputBox));
    expect(inputBox.size, equals(threeLineInputSize));
    await tester.enterText(find.byType(TextField), kMoreThanFourLines);
    await tester.pump();
    expect(inputBox.size.height, greaterThan(threeLineInputSize.height));
    expect(inputBox.size.width, threeLineInputSize.width);

    // minLines can't be greater than maxLines.
    expect(() async {
      await tester.pumpWidget(textFieldBuilder(minLines: 3, maxLines: 2));
    }, throwsAssertionError);

    // maxLines defaults to 1 and can't be less than minLines
    expect(() async {
      await tester.pumpWidget(textFieldBuilder(minLines: 3));
    }, throwsAssertionError);
  });

  testWidgets('Multiline text when wrapped in Expanded', (WidgetTester tester) async {
    Widget expandedTextFieldBuilder({
      int? maxLines = 1,
      int? minLines,
      bool expands = false,
    }) {
      return boilerplate(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: textFieldKey,
                style: const TextStyle(color: Colors.black, fontSize: 34.0),
                maxLines: maxLines,
                minLines: minLines,
                expands: expands,
                decoration: const InputDecoration(
                  hintText: 'Placeholder',
                ),
              ),
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(expandedTextFieldBuilder());

    RenderBox findBorder() {
      return tester.renderObject(find.descendant(
        of: find.byType(InputDecorator),
        matching: find.byWidgetPredicate((Widget w) => '${w.runtimeType}' == '_BorderContainer'),
      ));
    }
    final RenderBox border = findBorder();

    // Without expanded: true and maxLines: null, the TextField does not expand
    // to fill its parent when wrapped in an Expanded widget.
    final Size unexpandedInputSize = border.size;

    // It does expand to fill its parent when expands: true, maxLines: null, and
    // it's wrapped in an Expanded widget.
    await tester.pumpWidget(expandedTextFieldBuilder(expands: true, maxLines: null));
    expect(border.size.height, greaterThan(unexpandedInputSize.height));
    expect(border.size.width, unexpandedInputSize.width);

    // min/maxLines that is not null and expands: true contradict each other.
    expect(() async {
      await tester.pumpWidget(expandedTextFieldBuilder(expands: true, maxLines: 4));
    }, throwsAssertionError);
    expect(() async {
      await tester.pumpWidget(expandedTextFieldBuilder(expands: true, minLines: 1, maxLines: null));
    }, throwsAssertionError);
  });

  // Regression test for https://github.com/flutter/flutter/pull/29093
  testWidgets('Multiline text when wrapped in IntrinsicHeight', (WidgetTester tester) async {
    final Key intrinsicHeightKey = UniqueKey();
    Widget intrinsicTextFieldBuilder(bool wrapInIntrinsic) {
      final TextFormField textField = TextFormField(
        key: textFieldKey,
        style: const TextStyle(color: Colors.black, fontSize: 34.0),
        maxLines: null,
        decoration: const InputDecoration(
          counterText: 'I am counter',
        ),
      );
      final Widget widget = wrapInIntrinsic
        ? IntrinsicHeight(key: intrinsicHeightKey, child: textField)
        : textField;
      return boilerplate(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[widget],
        ),
      );
    }

    await tester.pumpWidget(intrinsicTextFieldBuilder(false));
    expect(find.byKey(intrinsicHeightKey), findsNothing);

    RenderBox findEditableText() => tester.renderObject(find.byType(EditableText));
    RenderBox editableText = findEditableText();
    final Size unwrappedEditableTextSize = editableText.size;

    // Wrapping in IntrinsicHeight should not affect the height of the input
    await tester.pumpWidget(intrinsicTextFieldBuilder(true));
    editableText = findEditableText();
    expect(editableText.size.height, unwrappedEditableTextSize.height);
    expect(editableText.size.width, unwrappedEditableTextSize.width);
  });

  // Regression test for https://github.com/flutter/flutter/pull/29093
  testWidgets('errorText empty string', (WidgetTester tester) async {
    Widget textFormFieldBuilder(String? errorText) {
      return boilerplate(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextFormField(
              key: textFieldKey,
              maxLength: 3,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              decoration: InputDecoration(
                counterText: '',
                errorText: errorText,
              ),
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(textFormFieldBuilder(null));

    RenderBox findInputBox() => tester.renderObject(find.byKey(textFieldKey));
    final RenderBox inputBox = findInputBox();
    final Size errorNullInputSize = inputBox.size;

    // Setting errorText causes the input's height to increase to accommodate it
    await tester.pumpWidget(textFormFieldBuilder('im errorText'));
    expect(inputBox, findInputBox());
    expect(inputBox.size.height, greaterThan(errorNullInputSize.height));
    expect(inputBox.size.width, errorNullInputSize.width);
    final Size errorInputSize = inputBox.size;

    // Setting errorText to an empty string causes the input's height to
    // increase to accommodate it, even though it's not displayed.
    // This may or may not be ideal behavior, but it is legacy behavior and
    // there are visual tests that rely on it (see Github issue referenced at
    // the top of this test). A counterText of empty string does not affect
    // input height, however.
    await tester.pumpWidget(textFormFieldBuilder(''));
    expect(inputBox, findInputBox());
    expect(inputBox.size.height, errorInputSize.height);
    expect(inputBox.size.width, errorNullInputSize.width);
  });

  testWidgets('Growable TextField when content height exceeds parent', (WidgetTester tester) async {
    const double height = 200.0;
    const double padding = 24.0;

    Widget containedTextFieldBuilder({
      Widget? counter,
      String? helperText,
      String? labelText,
      Widget? prefix,
    }) {
      return boilerplate(
        child: SizedBox(
          height: height,
          child: TextField(
            key: textFieldKey,
            maxLines: null,
            decoration: InputDecoration(
              counter: counter,
              helperText: helperText,
              labelText: labelText,
              prefix: prefix,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(containedTextFieldBuilder());
    RenderBox findEditableText() => tester.renderObject(find.byType(EditableText));

    final RenderBox inputBox = findEditableText();

    // With no decoration and when overflowing with content, the EditableText
    // takes up the full height minus the padding, so the input fits perfectly
    // inside the parent.
    await tester.enterText(find.byType(TextField), 'a\n' * 11);
    await tester.pump();
    expect(findEditableText(), equals(inputBox));
    expect(inputBox.size.height, height - padding);

    // Adding a counter causes the EditableText to shrink to fit the counter
    // inside the parent as well.
    const double counterHeight = 40.0;
    const double subtextGap = 8.0;
    const double counterSpace = counterHeight + subtextGap;
    await tester.pumpWidget(containedTextFieldBuilder(
      counter: Container(height: counterHeight),
    ));
    expect(findEditableText(), equals(inputBox));
    expect(inputBox.size.height, height - padding - counterSpace);

    // Including helperText causes the EditableText to shrink to fit the text
    // inside the parent as well.
    await tester.pumpWidget(containedTextFieldBuilder(
      helperText: 'I am helperText',
    ));
    expect(findEditableText(), equals(inputBox));
    const double helperTextSpace = 12.0;
    expect(inputBox.size.height, height - padding - helperTextSpace - subtextGap);

    // When both helperText and counter are present, EditableText shrinks by the
    // height of the taller of the two in order to fit both within the parent.
    await tester.pumpWidget(containedTextFieldBuilder(
      counter: Container(height: counterHeight),
      helperText: 'I am helperText',
    ));
    expect(findEditableText(), equals(inputBox));
    expect(inputBox.size.height, height - padding - counterSpace);

    // When a label is present, EditableText shrinks to fit it at the top so
    // that the bottom of the input still lines up perfectly with the parent.
    await tester.pumpWidget(containedTextFieldBuilder(
      labelText: 'I am labelText',
    ));
    const double labelSpace = 16.0;
    expect(findEditableText(), equals(inputBox));
    expect(inputBox.size.height, height - padding - labelSpace);

    // When decoration is present on the top and bottom, EditableText shrinks to
    // fit both inside the parent independently.
    await tester.pumpWidget(containedTextFieldBuilder(
      counter: Container(height: counterHeight),
      labelText: 'I am labelText',
    ));
    expect(findEditableText(), equals(inputBox));
    expect(inputBox.size.height, height - padding - counterSpace - labelSpace);

    // When a prefix or suffix is present in an input that's full of content,
    // it is ignored and allowed to expand beyond the top of the input. Other
    // top and bottom decoration is still respected.
    await tester.pumpWidget(containedTextFieldBuilder(
      counter: Container(height: counterHeight),
      labelText: 'I am labelText',
      prefix: const SizedBox(
        width: 10,
        height: 60,
      ),
    ));
    expect(findEditableText(), equals(inputBox));
    expect(
      inputBox.size.height,
      height
      - padding
      - labelSpace
      - counterSpace,
    );
  });

  testWidgets('Multiline hint text will wrap up to maxLines', (WidgetTester tester) async {
    final Key textFieldKey = UniqueKey();

    Widget builder(int? maxLines, final String hintMsg) {
      return boilerplate(
        child: TextField(
          key: textFieldKey,
          style: const TextStyle(color: Colors.black, fontSize: 34.0),
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hintMsg,
          ),
        ),
      );
    }

    const String hintPlaceholder = 'Placeholder';
    const String multipleLineText = "Here's a text, which is more than one line, to demostrate the multiple line hint text";
    await tester.pumpWidget(builder(null, hintPlaceholder));

    RenderBox findHintText(String hint) => tester.renderObject(find.text(hint));

    final RenderBox hintTextBox = findHintText(hintPlaceholder);
    final Size oneLineHintSize = hintTextBox.size;

    await tester.pumpWidget(builder(null, hintPlaceholder));
    expect(findHintText(hintPlaceholder), equals(hintTextBox));
    expect(hintTextBox.size, equals(oneLineHintSize));

    const int maxLines = 3;
    await tester.pumpWidget(builder(maxLines, multipleLineText));
    final Text hintTextWidget = tester.widget(find.text(multipleLineText));
    expect(hintTextWidget.maxLines, equals(maxLines));
    expect(findHintText(multipleLineText).size.width, greaterThanOrEqualTo(oneLineHintSize.width));
    expect(findHintText(multipleLineText).size.height, greaterThanOrEqualTo(oneLineHintSize.height));
  });

  testWidgets('Can drag handles to change selection in multiline', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          dragStartBehavior: DragStartBehavior.down,
          controller: controller,
          style: const TextStyle(color: Colors.black, fontSize: 34.0),
          maxLines: 3,
        ),
      ),
    );

    const String testValue = kThreeLines;
    const String cutValue = 'First line of stuff';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);

    // Check that the text spans multiple lines.
    final Offset firstPos = textOffsetToPosition(tester, testValue.indexOf('First'));
    final Offset secondPos = textOffsetToPosition(tester, testValue.indexOf('Second'));
    final Offset thirdPos = textOffsetToPosition(tester, testValue.indexOf('Third'));
    final Offset middleStringPos = textOffsetToPosition(tester, testValue.indexOf('irst'));
    expect(firstPos.dx, 0);
    expect(secondPos.dx, 0);
    expect(thirdPos.dx, 0);
    expect(middleStringPos.dx, 34);
    expect(firstPos.dx, secondPos.dx);
    expect(firstPos.dx, thirdPos.dx);
    expect(firstPos.dy, lessThan(secondPos.dy));
    expect(secondPos.dy, lessThan(thirdPos.dy));

    // Long press the 'n' in 'until' to select the word.
    final Offset untilPos = textOffsetToPosition(tester, testValue.indexOf('until')+1);
    TestGesture gesture = await tester.startGesture(untilPos, pointer: 7);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero

    expect(controller.selection.baseOffset, 39);
    expect(controller.selection.extentOffset, 44);

    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(controller.selection),
      renderEditable,
    );
    expect(endpoints.length, 2);

    // Drag the right handle to the third line, just after 'Third'.
    Offset handlePos = endpoints[1].point + const Offset(1.0, 1.0);
    Offset newHandlePos = textOffsetToPosition(tester, testValue.indexOf('Third') + 5);
    gesture = await tester.startGesture(handlePos, pointer: 7);
    await tester.pump();
    await gesture.moveTo(newHandlePos);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.selection.baseOffset, 39);
    expect(controller.selection.extentOffset, 50);

    // Drag the left handle to the first line, just after 'First'.
    handlePos = endpoints[0].point + const Offset(-1.0, 1.0);
    newHandlePos = textOffsetToPosition(tester, testValue.indexOf('First') + 5);
    gesture = await tester.startGesture(handlePos, pointer: 7);
    await tester.pump();
    await gesture.moveTo(newHandlePos);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.selection.baseOffset, 5);
    expect(controller.selection.extentOffset, 50);

    if (!isContextMenuProvidedByPlatform) {
      await tester.tap(find.text('Cut'));
      await tester.pump();
      expect(controller.selection.isCollapsed, true);
      expect(controller.text, cutValue);
    }
  });

  testWidgets('Can scroll multiline input', (WidgetTester tester) async {
    final Key textFieldKey = UniqueKey();
    final TextEditingController controller = TextEditingController(
      text: kMoreThanFourLines,
    );

    await tester.pumpWidget(
      overlay(
        child: TextField(
          dragStartBehavior: DragStartBehavior.down,
          key: textFieldKey,
          controller: controller,
          style: const TextStyle(color: Colors.black, fontSize: 34.0),
          maxLines: 2,
        ),
      ),
    );

    RenderBox findInputBox() => tester.renderObject(find.byKey(textFieldKey));
    final RenderBox inputBox = findInputBox();

    // Check that the last line of text is not displayed.
    final Offset firstPos = textOffsetToPosition(tester, kMoreThanFourLines.indexOf('First'));
    final Offset fourthPos = textOffsetToPosition(tester, kMoreThanFourLines.indexOf('Fourth'));
    expect(firstPos.dx, 0);
    expect(fourthPos.dx, 0);
    expect(firstPos.dx, fourthPos.dx);
    expect(firstPos.dy, lessThan(fourthPos.dy));
    expect(inputBox.hitTest(BoxHitTestResult(), position: inputBox.globalToLocal(firstPos)), isTrue);
    expect(inputBox.hitTest(BoxHitTestResult(), position: inputBox.globalToLocal(fourthPos)), isFalse);

    TestGesture gesture = await tester.startGesture(firstPos, pointer: 7);
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, -1000.0));
    await tester.pump(const Duration(seconds: 1));
    // Wait and drag again to trigger https://github.com/flutter/flutter/issues/6329
    // (No idea why this is necessary, but the bug wouldn't repro without it.)
    await gesture.moveBy(const Offset(0.0, -1000.0));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Now the first line is scrolled up, and the fourth line is visible.
    Offset newFirstPos = textOffsetToPosition(tester, kMoreThanFourLines.indexOf('First'));
    Offset newFourthPos = textOffsetToPosition(tester, kMoreThanFourLines.indexOf('Fourth'));

    expect(newFirstPos.dy, lessThan(firstPos.dy));
    expect(inputBox.hitTest(BoxHitTestResult(), position: inputBox.globalToLocal(newFirstPos)), isFalse);
    expect(inputBox.hitTest(BoxHitTestResult(), position: inputBox.globalToLocal(newFourthPos)), isTrue);

    // Now try scrolling by dragging the selection handle.
    // Long press the middle of the word "won't" in the fourth line.
    final Offset selectedWordPos = textOffsetToPosition(
      tester,
      kMoreThanFourLines.indexOf('Fourth line') + 14,
    );

    gesture = await tester.startGesture(selectedWordPos, pointer: 7);
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(controller.selection.base.offset, 77);
    expect(controller.selection.extent.offset, 82);
    // Sanity check for the word selected is the intended one.
    expect(
      controller.text.substring(controller.selection.baseOffset, controller.selection.extentOffset),
      "won't",
    );

    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(controller.selection),
      renderEditable,
    );
    expect(endpoints.length, 2);

    // Drag the left handle to the first line, just after 'First'.
    final Offset handlePos = endpoints[0].point + const Offset(-1, 1);
    final Offset newHandlePos = textOffsetToPosition(tester, kMoreThanFourLines.indexOf('First') + 5);
    gesture = await tester.startGesture(handlePos, pointer: 7);
    await tester.pump(const Duration(seconds: 1));
    await gesture.moveTo(newHandlePos + const Offset(0.0, -10.0));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    // The text should have scrolled up with the handle to keep the active
    // cursor visible, back to its original position.
    newFirstPos = textOffsetToPosition(tester, kMoreThanFourLines.indexOf('First'));
    newFourthPos = textOffsetToPosition(tester, kMoreThanFourLines.indexOf('Fourth'));
    expect(newFirstPos.dy, firstPos.dy);
    expect(inputBox.hitTest(BoxHitTestResult(), position: inputBox.globalToLocal(newFirstPos)), isTrue);
    expect(inputBox.hitTest(BoxHitTestResult(), position: inputBox.globalToLocal(newFourthPos)), isFalse);
  });

  testWidgets('TextField smoke test', (WidgetTester tester) async {
    late String textFieldValue;

    await tester.pumpWidget(
      overlay(
        child: TextField(
          decoration: null,
          onChanged: (String value) {
            textFieldValue = value;
          },
        ),
      ),
    );

    Future<void> checkText(String testValue) {
      return TestAsyncUtils.guard(() async {
        await tester.enterText(find.byType(TextField), testValue);

        // Check that the onChanged event handler fired.
        expect(textFieldValue, equals(testValue));

        await tester.pump();
      });
    }

    await checkText('Hello World');
  });

  testWidgets('TextField with global key', (WidgetTester tester) async {
    final GlobalKey textFieldKey = GlobalKey(debugLabel: 'textFieldKey');
    late String textFieldValue;

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: textFieldKey,
          decoration: const InputDecoration(
            hintText: 'Placeholder',
          ),
          onChanged: (String value) { textFieldValue = value; },
        ),
      ),
    );

    Future<void> checkText(String testValue) async {
      return TestAsyncUtils.guard(() async {
        await tester.enterText(find.byType(TextField), testValue);

        // Check that the onChanged event handler fired.
        expect(textFieldValue, equals(testValue));

        await tester.pump();
      });
    }

    await checkText('Hello World');
  });

  testWidgets('TextField errorText trumps helperText', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const TextField(
          decoration: InputDecoration(
            errorText: 'error text',
            helperText: 'helper text',
          ),
        ),
      ),
    );
    expect(find.text('helper text'), findsNothing);
    expect(find.text('error text'), findsOneWidget);
  });

  testWidgets('TextField with default helperStyle', (WidgetTester tester) async {
    final ThemeData themeData = ThemeData(hintColor: Colors.blue[500]);
    await tester.pumpWidget(
      overlay(
        child: Theme(
          data: themeData,
          child: const TextField(
            decoration: InputDecoration(
              helperText: 'helper text',
            ),
          ),
        ),
      ),
    );
    final Text helperText = tester.widget(find.text('helper text'));
    expect(helperText.style!.color, themeData.hintColor);
    expect(helperText.style!.fontSize, Typography.englishLike2014.caption!.fontSize);
  });

  testWidgets('TextField with specified helperStyle', (WidgetTester tester) async {
    final TextStyle style = TextStyle(
      inherit: false,
      color: Colors.pink[500],
      fontSize: 10.0,
    );

    await tester.pumpWidget(
      overlay(
        child: TextField(
          decoration: InputDecoration(
            helperText: 'helper text',
            helperStyle: style,
          ),
        ),
      ),
    );
    final Text helperText = tester.widget(find.text('helper text'));
    expect(helperText.style, style);
  });

  testWidgets('TextField with default hintStyle', (WidgetTester tester) async {
    final TextStyle style = TextStyle(
      color: Colors.pink[500],
      fontSize: 10.0,
    );
    final ThemeData themeData = ThemeData(
      hintColor: Colors.blue[500],
    );

    await tester.pumpWidget(
      overlay(
        child: Theme(
          data: themeData,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Placeholder',
            ),
            style: style,
          ),
        ),
      ),
    );

    final Text hintText = tester.widget(find.text('Placeholder'));
    expect(hintText.style!.color, themeData.hintColor);
    expect(hintText.style!.fontSize, style.fontSize);
  });

  testWidgets('TextField with specified hintStyle', (WidgetTester tester) async {
    final TextStyle hintStyle = TextStyle(
      inherit: false,
      color: Colors.pink[500],
      fontSize: 10.0,
    );

    await tester.pumpWidget(
      overlay(
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Placeholder',
            hintStyle: hintStyle,
          ),
        ),
      ),
    );

    final Text hintText = tester.widget(find.text('Placeholder'));
    expect(hintText.style, hintStyle);
  });

  testWidgets('TextField with specified prefixStyle', (WidgetTester tester) async {
    final TextStyle prefixStyle = TextStyle(
      inherit: false,
      color: Colors.pink[500],
      fontSize: 10.0,
    );

    await tester.pumpWidget(
      overlay(
        child: TextField(
          decoration: InputDecoration(
            prefixText: 'Prefix:',
            prefixStyle: prefixStyle,
          ),
        ),
      ),
    );

    final Text prefixText = tester.widget(find.text('Prefix:'));
    expect(prefixText.style, prefixStyle);
  });

  testWidgets('TextField with specified suffixStyle', (WidgetTester tester) async {
    final TextStyle suffixStyle = TextStyle(
      color: Colors.pink[500],
      fontSize: 10.0,
    );

    await tester.pumpWidget(
      overlay(
        child: TextField(
          decoration: InputDecoration(
            suffixText: '.com',
            suffixStyle: suffixStyle,
          ),
        ),
      ),
    );

    final Text suffixText = tester.widget(find.text('.com'));
    expect(suffixText.style, suffixStyle);
  });

  testWidgets('TextField prefix and suffix appear correctly with no hint or label', (WidgetTester tester) async {
    final Key secondKey = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: Column(
          children: <Widget>[
            const TextField(
              decoration: InputDecoration(
                labelText: 'First',
              ),
            ),
            TextField(
              key: secondKey,
              decoration: const InputDecoration(
                prefixText: 'Prefix',
                suffixText: 'Suffix',
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Prefix'), findsOneWidget);
    expect(find.text('Suffix'), findsOneWidget);

    // Focus the Input. The prefix should still display.
    await tester.tap(find.byKey(secondKey));
    await tester.pump();

    expect(find.text('Prefix'), findsOneWidget);
    expect(find.text('Suffix'), findsOneWidget);

    // Enter some text, and the prefix should still display.
    await tester.enterText(find.byKey(secondKey), 'Hi');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Prefix'), findsOneWidget);
    expect(find.text('Suffix'), findsOneWidget);
  });

  testWidgets('TextField prefix and suffix appear correctly with hint text', (WidgetTester tester) async {
    final TextStyle hintStyle = TextStyle(
      inherit: false,
      color: Colors.pink[500],
      fontSize: 10.0,
    );
    final Key secondKey = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: Column(
          children: <Widget>[
            const TextField(
              decoration: InputDecoration(
                labelText: 'First',
              ),
            ),
            TextField(
              key: secondKey,
              decoration: InputDecoration(
                hintText: 'Hint',
                hintStyle: hintStyle,
                prefixText: 'Prefix',
                suffixText: 'Suffix',
              ),
            ),
          ],
        ),
      ),
    );

    // Neither the prefix or the suffix should initially be visible, only the hint.
    expect(getOpacity(tester, find.text('Prefix')), 0.0);
    expect(getOpacity(tester, find.text('Suffix')), 0.0);
    expect(getOpacity(tester, find.text('Hint')), 1.0);

    await tester.tap(find.byKey(secondKey));
    await tester.pumpAndSettle();

    // Focus the Input. The hint, prefix, and suffix should appear
    expect(getOpacity(tester, find.text('Prefix')), 1.0);
    expect(getOpacity(tester, find.text('Suffix')), 1.0);
    expect(getOpacity(tester, find.text('Hint')), 1.0);

    // Enter some text, and the hint should disappear and the prefix and suffix
    // should continue to be visible
    await tester.enterText(find.byKey(secondKey), 'Hi');
    await tester.pumpAndSettle();

    expect(getOpacity(tester, find.text('Prefix')), 1.0);
    expect(getOpacity(tester, find.text('Suffix')), 1.0);
    expect(getOpacity(tester, find.text('Hint')), 0.0);

    // Check and make sure that the right styles were applied.
    final Text prefixText = tester.widget(find.text('Prefix'));
    expect(prefixText.style, hintStyle);
    final Text suffixText = tester.widget(find.text('Suffix'));
    expect(suffixText.style, hintStyle);
  });

  testWidgets('TextField prefix and suffix appear correctly with label text', (WidgetTester tester) async {
    final TextStyle prefixStyle = TextStyle(
      color: Colors.pink[500],
      fontSize: 10.0,
    );
    final TextStyle suffixStyle = TextStyle(
      color: Colors.green[500],
      fontSize: 12.0,
    );
    final Key secondKey = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: Column(
          children: <Widget>[
            const TextField(
              decoration: InputDecoration(
                labelText: 'First',
              ),
            ),
            TextField(
              key: secondKey,
              decoration: InputDecoration(
                labelText: 'Label',
                prefixText: 'Prefix',
                prefixStyle: prefixStyle,
                suffixText: 'Suffix',
                suffixStyle: suffixStyle,
              ),
            ),
          ],
        ),
      ),
    );

    // Not focused. The prefix and suffix should not appear, but the label should.
    expect(getOpacity(tester, find.text('Prefix')), 0.0);
    expect(getOpacity(tester, find.text('Suffix')), 0.0);
    expect(find.text('Label'), findsOneWidget);

    // Focus the input. The label, prefix, and suffix should appear.
    await tester.tap(find.byKey(secondKey));
    await tester.pumpAndSettle();

    expect(getOpacity(tester, find.text('Prefix')), 1.0);
    expect(getOpacity(tester, find.text('Suffix')), 1.0);
    expect(find.text('Label'), findsOneWidget);

    // Enter some text. The label, prefix, and suffix should remain visible.
    await tester.enterText(find.byKey(secondKey), 'Hi');
    await tester.pumpAndSettle();

    expect(getOpacity(tester, find.text('Prefix')), 1.0);
    expect(getOpacity(tester, find.text('Suffix')), 1.0);
    expect(find.text('Label'), findsOneWidget);

    // Check and make sure that the right styles were applied.
    final Text prefixText = tester.widget(find.text('Prefix'));
    expect(prefixText.style, prefixStyle);
    final Text suffixText = tester.widget(find.text('Suffix'));
    expect(suffixText.style, suffixStyle);
  });

  testWidgets('TextField label text animates', (WidgetTester tester) async {
    final Key secondKey = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: Column(
          children: <Widget>[
            const TextField(
              decoration: InputDecoration(
                labelText: 'First',
              ),
            ),
            TextField(
              key: secondKey,
              decoration: const InputDecoration(
                labelText: 'Second',
              ),
            ),
          ],
        ),
      ),
    );

    Offset pos = tester.getTopLeft(find.text('Second'));

    // Focus the Input. The label should start animating upwards.
    await tester.tap(find.byKey(secondKey));
    await tester.idle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    Offset newPos = tester.getTopLeft(find.text('Second'));
    expect(newPos.dy, lessThan(pos.dy));

    // Label should still be sliding upward.
    await tester.pump(const Duration(milliseconds: 50));
    pos = newPos;
    newPos = tester.getTopLeft(find.text('Second'));
    expect(newPos.dy, lessThan(pos.dy));
  });

  testWidgets('Icon is separated from input/label by 16+12', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const TextField(
          decoration: InputDecoration(
            icon: Icon(Icons.phone),
            labelText: 'label',
            filled: true,
          ),
        ),
      ),
    );
    final double iconRight = tester.getTopRight(find.byType(Icon)).dx;
    // Per https://material.io/go/design-text-fields#text-fields-layout
    // There's a 16 dps gap between the right edge of the icon and the text field's
    // container, and the 12dps more padding between the left edge of the container
    // and the left edge of the input and label.
    expect(iconRight + 28.0, equals(tester.getTopLeft(find.text('label')).dx));
    expect(iconRight + 28.0, equals(tester.getTopLeft(find.byType(EditableText)).dx));
  });

  testWidgets('Collapsed hint text placement', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const TextField(
          decoration: InputDecoration.collapsed(
            hintText: 'hint',
          ),
          strutStyle: StrutStyle.disabled,
        ),
      ),
    );

    expect(tester.getTopLeft(find.text('hint')), equals(tester.getTopLeft(find.byType(EditableText))));
  });

  testWidgets('Can align to center', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const SizedBox(
          width: 300.0,
          child: TextField(
            textAlign: TextAlign.center,
            decoration: null,
          ),
        ),
      ),
    );

    final RenderEditable editable = findRenderEditable(tester);
    Offset topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 0)).topLeft,
    );

    // The overlay() function centers its child within a 800x600 window.
    // Default cursorWidth is 2.0, test windowWidth is 800
    // Centered cursor topLeft.dx: 399 == windowWidth/2 - cursorWidth/2
    expect(topLeft.dx, equals(399.0));

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 2)).topLeft,
    );

    // TextPosition(offset: 2) - center of 'abcd'
    expect(topLeft.dx, equals(399.0));
  });

  testWidgets('Can align to center within center', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const SizedBox(
          width: 300.0,
          child: Center(
            child: TextField(
              textAlign: TextAlign.center,
              decoration: null,
            ),
          ),
        ),
      ),
    );

    final RenderEditable editable = findRenderEditable(tester);
    Offset topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 0)).topLeft,
    );

    // The overlay() function centers its child within a 800x600 window.
    // Default cursorWidth is 2.0, test windowWidth is 800
    // Centered cursor topLeft.dx: 399 == windowWidth/2 - cursorWidth/2
    expect(topLeft.dx, equals(399.0));

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 2)).topLeft,
    );

    // TextPosition(offset: 2) - center of 'abcd'
    expect(topLeft.dx, equals(399.0));
  });

  testWidgets('Controller can update server', (WidgetTester tester) async {
    final TextEditingController controller1 = TextEditingController(
      text: 'Initial Text',
    );
    final TextEditingController controller2 = TextEditingController(
      text: 'More Text',
    );

    TextEditingController? currentController;
    late StateSetter setState;

    await tester.pumpWidget(
      overlay(
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setter) {
            setState = setter;
            return TextField(controller: currentController);
          }
        ),
      ),
    );
    expect(tester.testTextInput.editingState, isNull);

    // Initial state with null controller.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.editingState!['text'], isEmpty);

    // Update the controller from null to controller1.
    setState(() {
      currentController = controller1;
    });
    await tester.pump();
    expect(tester.testTextInput.editingState!['text'], equals('Initial Text'));

    // Verify that updates to controller1 are handled.
    controller1.text = 'Updated Text';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('Updated Text'));

    // Verify that switching from controller1 to controller2 is handled.
    setState(() {
      currentController = controller2;
    });
    await tester.pump();
    expect(tester.testTextInput.editingState!['text'], equals('More Text'));

    // Verify that updates to controller1 are ignored.
    controller1.text = 'Ignored Text';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('More Text'));

    // Verify that updates to controller text are handled.
    controller2.text = 'Additional Text';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('Additional Text'));

    // Verify that updates to controller selection are handled.
    controller2.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.idle();
    expect(tester.testTextInput.editingState!['selectionBase'], equals(0));
    expect(tester.testTextInput.editingState!['selectionExtent'], equals(5));

    // Verify that calling clear() clears the text.
    controller2.clear();
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals(''));

    // Verify that switching from controller2 to null preserves current text.
    controller2.text = 'The Final Cut';
    await tester.idle();
    expect(tester.testTextInput.editingState!['text'], equals('The Final Cut'));
    setState(() {
      currentController = null;
    });
    await tester.pump();
    expect(tester.testTextInput.editingState!['text'], equals('The Final Cut'));

    // Verify that changes to controller2 are ignored.
    controller2.text = 'Goodbye Cruel World';
    expect(tester.testTextInput.editingState!['text'], equals('The Final Cut'));
  });

  testWidgets('Cannot enter new lines onto single line TextField', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(controller: textController, decoration: null),
    ));

    await tester.enterText(find.byType(TextField), 'abc\ndef');

    expect(textController.text, 'abcdef');
  });

  testWidgets('Injected formatters are chained', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        decoration: null,
        inputFormatters: <TextInputFormatter> [
          FilteringTextInputFormatter.deny(
            RegExp(r'[a-z]'),
            replacementString: '#',
          ),
        ],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'a一b二c三\nd四e五f六');
    // The default single line formatter replaces \n with empty string.
    expect(textController.text, '#一#二#三#四#五#六');
  });

  testWidgets('Injected formatters are chained (deprecated names)', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        decoration: null,
        inputFormatters: <TextInputFormatter> [
          FilteringTextInputFormatter.deny(
            RegExp(r'[a-z]'),
            replacementString: '#',
          ),
        ],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'a一b二c三\nd四e五f六');
    // The default single line formatter replaces \n with empty string.
    expect(textController.text, '#一#二#三#四#五#六');
  });

  testWidgets('Chained formatters are in sequence', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        decoration: null,
        maxLines: 2,
        inputFormatters: <TextInputFormatter> [
          FilteringTextInputFormatter.deny(
            RegExp(r'[a-z]'),
            replacementString: '12\n',
          ),
          FilteringTextInputFormatter.allow(RegExp(r'\n[0-9]')),
        ],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'a1b2c3');
    // The first formatter turns it into
    // 12\n112\n212\n3
    // The second formatter turns it into
    // \n1\n2\n3
    // Multiline is allowed since maxLine != 1.
    expect(textController.text, '\n1\n2\n3');
  });

  testWidgets('Chained formatters are in sequence (deprecated names)', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        decoration: null,
        maxLines: 2,
        inputFormatters: <TextInputFormatter> [
          FilteringTextInputFormatter.deny(
            RegExp(r'[a-z]'),
            replacementString: '12\n',
          ),
          FilteringTextInputFormatter.allow(RegExp(r'\n[0-9]')),
        ],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'a1b2c3');
    // The first formatter turns it into
    // 12\n112\n212\n3
    // The second formatter turns it into
    // \n1\n2\n3
    // Multiline is allowed since maxLine != 1.
    expect(textController.text, '\n1\n2\n3');
  });

  testWidgets('Pasted values are formatted', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: textController,
          decoration: null,
          inputFormatters: <TextInputFormatter> [
            FilteringTextInputFormatter.digitsOnly,
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'a1b\n2c3');
    expect(textController.text, '123');
    await skipPastScrollingAnimation(tester);

    await tester.tapAt(textOffsetToPosition(tester, '123'.indexOf('2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero
    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(textController.selection),
      renderEditable,
    );
    await tester.tapAt(endpoints[0].point + const Offset(1.0, 1.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero

    Clipboard.setData(const ClipboardData(text: '一4二\n5三6'));
    await tester.tap(find.text('Paste'));
    await tester.pump();
    // Puts 456 before the 2 in 123.
    expect(textController.text, '145623');
  }, skip: isContextMenuProvidedByPlatform);

  testWidgets('Pasted values are formatted (deprecated names)', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: textController,
          decoration: null,
          inputFormatters: <TextInputFormatter> [
            FilteringTextInputFormatter.digitsOnly,
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'a1b\n2c3');
    expect(textController.text, '123');
    await skipPastScrollingAnimation(tester);

    await tester.tapAt(textOffsetToPosition(tester, '123'.indexOf('2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero
    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(textController.selection),
      renderEditable,
    );
    await tester.tapAt(endpoints[0].point + const Offset(1.0, 1.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is zero

    Clipboard.setData(const ClipboardData(text: '一4二\n5三6'));
    await tester.tap(find.text('Paste'));
    await tester.pump();
    // Puts 456 before the 2 in 123.
    expect(textController.text, '145623');
  }, skip: isContextMenuProvidedByPlatform);

  testWidgets('Do not add LengthLimiting formatter to the user supplied list', (WidgetTester tester) async {
    final List<TextInputFormatter> formatters = <TextInputFormatter>[];

    await tester.pumpWidget(
      overlay(
        child: TextField(
          decoration: null,
          maxLength: 5,
          inputFormatters: formatters,
        ),
      ),
    );

    expect(formatters.isEmpty, isTrue);
  });

  testWidgets('Text field scrolls the caret into view', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: SizedBox(
          width: 100.0,
          child: TextField(
            controller: controller,
          ),
        ),
      ),
    );

    final String longText = 'a' * 20;
    await tester.enterText(find.byType(TextField), longText);
    await skipPastScrollingAnimation(tester);

    ScrollableState scrollableState = tester.firstState(find.byType(Scrollable));
    expect(scrollableState.position.pixels, equals(0.0));

    // Move the caret to the end of the text and check that the text field
    // scrolls to make the caret visible.
    scrollableState = tester.firstState(find.byType(Scrollable));
    final EditableTextState editableTextState = tester.firstState(find.byType(EditableText));
    editableTextState.userUpdateTextEditingValue(
      editableTextState.textEditingValue.copyWith(
        selection: TextSelection.collapsed(offset: longText.length),
      ),
      null,
    );

    await tester.pump(); // TODO(ianh): Figure out why this extra pump is needed.
    await skipPastScrollingAnimation(tester);

    scrollableState = tester.firstState(find.byType(Scrollable));
    // For a horizontal input, scrolls to the exact position of the caret.
    expect(scrollableState.position.pixels, equals(222.0));
  });

  testWidgets('Multiline text field scrolls the caret into view', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
          maxLines: 6,
        ),
      ),
    );

    const String tallText = 'a\nb\nc\nd\ne\nf\ng'; // One line over max
    await tester.enterText(find.byType(TextField), tallText);
    await skipPastScrollingAnimation(tester);

    ScrollableState scrollableState = tester.firstState(find.byType(Scrollable));
    expect(scrollableState.position.pixels, equals(0.0));

    // Move the caret to the end of the text and check that the text field
    // scrolls to make the caret visible.
    final EditableTextState editableTextState = tester.firstState(find.byType(EditableText));
    editableTextState.userUpdateTextEditingValue(
      editableTextState.textEditingValue.copyWith(
        selection: const TextSelection.collapsed(offset: tallText.length),
      ),
      null,
    );
    await tester.pump();
    await skipPastScrollingAnimation(tester);

    // Should have scrolled down exactly one line height (7 lines of text in 6
    // line text field).
    final double lineHeight = findRenderEditable(tester).preferredLineHeight;
    scrollableState = tester.firstState(find.byType(Scrollable));
    expect(scrollableState.position.pixels, moreOrLessEquals(lineHeight, epsilon: 0.1));
  });

  testWidgets('haptic feedback', (WidgetTester tester) async {
    final FeedbackTester feedback = FeedbackTester();
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: SizedBox(
          width: 100.0,
          child: TextField(
            controller: controller,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(feedback.clickSoundCount, 0);
    expect(feedback.hapticCount, 0);

    await tester.longPress(find.byType(TextField));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(feedback.clickSoundCount, 0);
    expect(feedback.hapticCount, 1);

    feedback.dispose();
  });

  testWidgets('Text field drops selection when losing focus', (WidgetTester tester) async {
    final Key key1 = UniqueKey();
    final TextEditingController controller1 = TextEditingController();
    final Key key2 = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: Column(
          children: <Widget>[
            TextField(
              key: key1,
              controller: controller1,
            ),
            TextField(key: key2),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(key1));
    await tester.enterText(find.byKey(key1), 'abcd');
    await tester.pump();
    controller1.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();
    expect(controller1.selection, isNot(equals(TextRange.empty)));

    await tester.tap(find.byKey(key2));
    await tester.pump();
    expect(controller1.selection, equals(TextRange.empty));
  });

  testWidgets('Selection is consistent with text length', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    controller.text = 'abcde';
    controller.selection = const TextSelection.collapsed(offset: 5);

    controller.text = '';
    expect(controller.selection.start, lessThanOrEqualTo(0));
    expect(controller.selection.end, lessThanOrEqualTo(0));

    late FlutterError error;
    try {
      controller.selection = const TextSelection.collapsed(offset: 10);
    } on FlutterError catch (e) {
      error = e;
    } finally {
      expect(error.diagnostics.length, 1);
      expect(
        error.toStringDeep(),
        equalsIgnoringHashCodes(
          'FlutterError\n'
          '   invalid text selection: TextSelection(baseOffset: 10,\n'
          '   extentOffset: 10, affinity: TextAffinity.downstream,\n'
          '   isDirectional: false)\n',
        ),
      );
    }
  });

  // Regression test for https://github.com/flutter/flutter/issues/35848
  testWidgets('Clearing text field with suffixIcon does not cause text selection exception', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Prefilled text.',
    );

    await tester.pumpWidget(
      boilerplate(
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              icon: const Icon(Icons.close),
              onPressed: controller.clear,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    expect(controller.text, '');
  });

  testWidgets('maxLength limits input.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
      ),
    ));

    await tester.enterText(find.byType(TextField), '0123456789101112');
    expect(textController.text, '0123456789');
  });

  testWidgets('maxLength limits input with surrogate pairs.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
      ),
    ));

    const String surrogatePair = '😆';
    await tester.enterText(find.byType(TextField), surrogatePair + '0123456789101112');
    expect(textController.text, surrogatePair + '012345678');
  });

  testWidgets('maxLength limits input with grapheme clusters.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
      ),
    ));

    const String graphemeCluster = '👨‍👩‍👦';
    await tester.enterText(find.byType(TextField), graphemeCluster + '0123456789101112');
    expect(textController.text, graphemeCluster + '012345678');
  });

  testWidgets('maxLength limits input in the center of a maxed-out field.', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/37420.
    final TextEditingController textController = TextEditingController();
    const String testValue = '0123456789';

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
      ),
    ));

    // Max out the character limit in the field.
    await tester.enterText(find.byType(TextField), testValue);
    expect(textController.text, testValue);

    // Entering more characters at the end does nothing.
    await tester.enterText(find.byType(TextField), testValue + '9999999');
    expect(textController.text, testValue);

    // Entering text in the middle of the field also does nothing.
    await tester.enterText(find.byType(TextField), '0123455555555556789');
    expect(textController.text, testValue);
  });

  testWidgets(
    'maxLength limits input in the center of a maxed-out field, with collapsed selection',
    (WidgetTester tester) async {
      final TextEditingController textController = TextEditingController();
      const String testValue = '0123456789';

      await tester.pumpWidget(boilerplate(
        child: TextField(
          controller: textController,
          maxLength: 10,
        ),
      ));

      // Max out the character limit in the field.
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: testValue,
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange.empty,
      ));
      await tester.pump();
      expect(textController.text, testValue);

      // Entering more characters at the end does nothing.
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: testValue + '9999999',
        selection: TextSelection.collapsed(offset: 10 + 7),
        composing: TextRange.empty,
      ));
      await tester.pump();

      expect(textController.text, testValue);

      // Entering text in the middle of the field also does nothing.
      // Entering more characters at the end does nothing.
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '0123455555555556789',
        selection: TextSelection.collapsed(offset: 19),
        composing: TextRange.empty,
      ));
      await tester.pump();

      expect(textController.text, testValue);
    },
  );

  testWidgets(
    'maxLength limits input in the center of a maxed-out field, with non-collapsed selection',
    (WidgetTester tester) async {
      final TextEditingController textController = TextEditingController();
      const String testValue = '0123456789';

      await tester.pumpWidget(boilerplate(
        child: TextField(
          controller: textController,
          maxLength: 10,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
        ),
      ));

      // Max out the character limit in the field.
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: testValue,
        selection: TextSelection(baseOffset: 8, extentOffset: 10),
        composing: TextRange.empty,
      ));
      await tester.pump();
      expect(textController.text, testValue);

      // Entering more characters at the end does nothing.
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '01234569999999',
        selection: TextSelection.collapsed(offset: 14),
        composing: TextRange.empty,
      ));
      await tester.pump();

      expect(textController.text,  '0123456999');
    },
  );

  testWidgets('maxLength limits input length even if decoration is null.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        decoration: null,
        maxLength: 10,
      ),
    ));

    await tester.enterText(find.byType(TextField), '0123456789101112');
    expect(textController.text, '0123456789');
  });

  testWidgets('maxLength still works with other formatters', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
        inputFormatters: <TextInputFormatter> [
          FilteringTextInputFormatter.deny(
            RegExp(r'[a-z]'),
            replacementString: '#',
          ),
        ],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'a一b二c三\nd四e五f六');
    // The default single line formatter replaces \n with empty string.
    expect(textController.text, '#一#二#三#四#五');
  });

  testWidgets('maxLength still works with other formatters (deprecated names)', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
        inputFormatters: <TextInputFormatter> [
          FilteringTextInputFormatter.deny(
            RegExp(r'[a-z]'),
            replacementString: '#',
          ),
        ],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'a一b二c三\nd四e五f六');
    // The default single line formatter replaces \n with empty string.
    expect(textController.text, '#一#二#三#四#五');
  });

  testWidgets("maxLength isn't enforced when maxLengthEnforced is false.", (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
        maxLengthEnforcement: MaxLengthEnforcement.none,
      ),
    ));

    await tester.enterText(find.byType(TextField), '0123456789101112');
    expect(textController.text, '0123456789101112');
  });

  testWidgets('maxLength shows warning when maxLengthEnforced is false.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();
    const TextStyle testStyle = TextStyle(color: Colors.deepPurpleAccent);

    await tester.pumpWidget(boilerplate(
      child: TextField(
        decoration: const InputDecoration(errorStyle: testStyle),
        controller: textController,
        maxLength: 10,
        maxLengthEnforcement: MaxLengthEnforcement.none,
      ),
    ));

    await tester.enterText(find.byType(TextField), '0123456789101112');
    await tester.pump();

    expect(textController.text, '0123456789101112');
    expect(find.text('16/10'), findsOneWidget);
    Text counterTextWidget = tester.widget(find.text('16/10'));
    expect(counterTextWidget.style!.color, equals(Colors.deepPurpleAccent));

    await tester.enterText(find.byType(TextField), '0123456789');
    await tester.pump();

    expect(textController.text, '0123456789');
    expect(find.text('10/10'), findsOneWidget);
    counterTextWidget = tester.widget(find.text('10/10'));
    expect(counterTextWidget.style!.color, isNot(equals(Colors.deepPurpleAccent)));
  });

  testWidgets('maxLength shows warning when maxLengthEnforced is false with surrogate pairs.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();
    const TextStyle testStyle = TextStyle(color: Colors.deepPurpleAccent);

    await tester.pumpWidget(boilerplate(
      child: TextField(
        decoration: const InputDecoration(errorStyle: testStyle),
        controller: textController,
        maxLength: 10,
        maxLengthEnforcement: MaxLengthEnforcement.none,
      ),
    ));

    await tester.enterText(find.byType(TextField), '😆012345678910111');
    await tester.pump();

    expect(textController.text, '😆012345678910111');
    expect(find.text('16/10'), findsOneWidget);
    Text counterTextWidget = tester.widget(find.text('16/10'));
    expect(counterTextWidget.style!.color, equals(Colors.deepPurpleAccent));

    await tester.enterText(find.byType(TextField), '😆012345678');
    await tester.pump();

    expect(textController.text, '😆012345678');
    expect(find.text('10/10'), findsOneWidget);
    counterTextWidget = tester.widget(find.text('10/10'));
    expect(counterTextWidget.style!.color, isNot(equals(Colors.deepPurpleAccent)));
  });

  testWidgets('maxLength shows warning when maxLengthEnforced is false with grapheme clusters.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();
    const TextStyle testStyle = TextStyle(color: Colors.deepPurpleAccent);

    await tester.pumpWidget(boilerplate(
      child: TextField(
        decoration: const InputDecoration(errorStyle: testStyle),
        controller: textController,
        maxLength: 10,
        maxLengthEnforcement: MaxLengthEnforcement.none,
      ),
    ));

    await tester.enterText(find.byType(TextField), '👨‍👩‍👦012345678910111');
    await tester.pump();

    expect(textController.text, '👨‍👩‍👦012345678910111');
    expect(find.text('16/10'), findsOneWidget);
    Text counterTextWidget = tester.widget(find.text('16/10'));
    expect(counterTextWidget.style!.color, equals(Colors.deepPurpleAccent));

    await tester.enterText(find.byType(TextField), '👨‍👩‍👦012345678');
    await tester.pump();

    expect(textController.text, '👨‍👩‍👦012345678');
    expect(find.text('10/10'), findsOneWidget);
    counterTextWidget = tester.widget(find.text('10/10'));
    expect(counterTextWidget.style!.color, isNot(equals(Colors.deepPurpleAccent)));
  });

  testWidgets('maxLength limits input with surrogate pairs.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
      ),
    ));

    const String surrogatePair = '😆';
    await tester.enterText(find.byType(TextField), surrogatePair + '0123456789101112');
    expect(textController.text, surrogatePair + '012345678');
  });

  testWidgets('maxLength limits input with grapheme clusters.', (WidgetTester tester) async {
    final TextEditingController textController = TextEditingController();

    await tester.pumpWidget(boilerplate(
      child: TextField(
        controller: textController,
        maxLength: 10,
      ),
    ));

    const String graphemeCluster = '👨‍👩‍👦';
    await tester.enterText(find.byType(TextField), graphemeCluster + '0123456789101112');
    expect(textController.text, graphemeCluster + '012345678');
  });

  testWidgets('setting maxLength shows counter', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Material(
        child: Center(
            child: TextField(
              maxLength: 10,
            ),
          ),
        ),
      ),
    );

    expect(find.text('0/10'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '01234');
    await tester.pump();

    expect(find.text('5/10'), findsOneWidget);
  });

  testWidgets('maxLength counter measures surrogate pairs as one character', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Material(
        child: Center(
            child: TextField(
              maxLength: 10,
            ),
          ),
        ),
      ),
    );

    expect(find.text('0/10'), findsOneWidget);

    const String surrogatePair = '😆';
    await tester.enterText(find.byType(TextField), surrogatePair);
    await tester.pump();

    expect(find.text('1/10'), findsOneWidget);
  });

  testWidgets('maxLength counter measures grapheme clusters as one character', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Material(
        child: Center(
            child: TextField(
              maxLength: 10,
            ),
          ),
        ),
      ),
    );

    expect(find.text('0/10'), findsOneWidget);

    const String familyEmoji = '👨‍👩‍👦';
    await tester.enterText(find.byType(TextField), familyEmoji);
    await tester.pump();

    expect(find.text('1/10'), findsOneWidget);
  });

  testWidgets('setting maxLength to TextField.noMaxLength shows only entered length', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Material(
        child: Center(
            child: TextField(
              maxLength: TextField.noMaxLength,
            ),
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '01234');
    await tester.pump();

    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('passing a buildCounter shows returned widget', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
            child: TextField(
              buildCounter: (BuildContext context, { required int currentLength, int? maxLength, required bool isFocused }) {
                return Text('${currentLength.toString()} of ${maxLength.toString()}');
              },
              maxLength: 10,
            ),
          ),
        ),
      ),
    );

    expect(find.text('0 of 10'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '01234');
    await tester.pump();

    expect(find.text('5 of 10'), findsOneWidget);
  });

  testWidgets('TextField identifies as text field in semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Center(
              child: TextField(
                maxLength: 10,
              ),
            ),
          ),
        ),
    );

    expect(semantics, includesNodeWith(flags: <SemanticsFlag>[SemanticsFlag.isTextField]));

    semantics.dispose();
  });

  testWidgets('Disabled text field does not have tap action', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              maxLength: 10,
              enabled: false,
            ),
          ),
        ),
      ),
    );

    expect(semantics, isNot(includesNodeWith(actions: <SemanticsAction>[SemanticsAction.tap])));

    semantics.dispose();
  });

  testWidgets('Readonly text field does not have tap action', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              maxLength: 10,
              readOnly: true,
            ),
          ),
        ),
      ),
    );

    expect(semantics, isNot(includesNodeWith(actions: <SemanticsAction>[SemanticsAction.tap])));

    semantics.dispose();
  });

  testWidgets('Disabled text field hides helper and counter', (WidgetTester tester) async {
    const String helperText = 'helper text';
    const String counterText = 'counter text';
    const String errorText = 'error text';
    Widget buildFrame(bool enabled, bool hasError) {
      return MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              decoration: InputDecoration(
                labelText: 'label text',
                helperText: helperText,
                counterText: counterText,
                errorText: hasError ? errorText : null,
                enabled: enabled,
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildFrame(true, false));
    Text helperWidget = tester.widget(find.text(helperText));
    Text counterWidget = tester.widget(find.text(counterText));
    expect(helperWidget.style!.color, isNot(equals(Colors.transparent)));
    expect(counterWidget.style!.color, isNot(equals(Colors.transparent)));
    await tester.pumpWidget(buildFrame(true, true));
    counterWidget = tester.widget(find.text(counterText));
    Text errorWidget = tester.widget(find.text(errorText));
    expect(helperWidget.style!.color, isNot(equals(Colors.transparent)));
    expect(errorWidget.style!.color, isNot(equals(Colors.transparent)));

    // When enabled is false, the helper/error and counter are not visible.
    await tester.pumpWidget(buildFrame(false, false));
    helperWidget = tester.widget(find.text(helperText));
    counterWidget = tester.widget(find.text(counterText));
    expect(helperWidget.style!.color, equals(Colors.transparent));
    expect(counterWidget.style!.color, equals(Colors.transparent));
    await tester.pumpWidget(buildFrame(false, true));
    errorWidget = tester.widget(find.text(errorText));
    counterWidget = tester.widget(find.text(counterText));
    expect(counterWidget.style!.color, equals(Colors.transparent));
    expect(errorWidget.style!.color, equals(Colors.transparent));
  });

  testWidgets('currentValueLength/maxValueLength are in the tree', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              controller: controller,
              maxLength: 10,
            ),
          ),
        ),
      ),
    );

    expect(semantics, includesNodeWith(
      flags: <SemanticsFlag>[SemanticsFlag.isTextField],
      maxValueLength: 10,
      currentValueLength: 0,
    ));

    await tester.showKeyboard(find.byType(TextField));
    const String testValue = '123';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: testValue,
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: testValue.length),
    ));
    await tester.pump();

    expect(semantics, includesNodeWith(
      flags: <SemanticsFlag>[SemanticsFlag.isTextField, SemanticsFlag.isFocused],
      maxValueLength: 10,
      currentValueLength: 3,
    ));

    semantics.dispose();
  });

  testWidgets('Read only TextField identifies as read only text field in semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              maxLength: 10,
              readOnly: true,
            ),
          ),
        ),
      ),
    );

    expect(
      semantics,
      includesNodeWith(flags: <SemanticsFlag>[SemanticsFlag.isTextField, SemanticsFlag.isReadOnly]),
    );

    semantics.dispose();
  });

  testWidgets("Disabled TextField can't be traversed to when disabled.", (WidgetTester tester) async {
    final FocusNode focusNode1 = FocusNode(debugLabel: 'TextField 1');
    final FocusNode focusNode2 = FocusNode(debugLabel: 'TextField 2');
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: Column(
              children: <Widget>[
                TextField(
                  focusNode: focusNode1,
                  autofocus: true,
                  maxLength: 10,
                  enabled: true,
                ),
                TextField(
                  focusNode: focusNode2,
                  maxLength: 10,
                  enabled: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(focusNode1.hasPrimaryFocus, isTrue);
    expect(focusNode2.hasPrimaryFocus, isFalse);

    expect(focusNode1.nextFocus(), isTrue);
    await tester.pump();

    expect(focusNode1.hasPrimaryFocus, isTrue);
    expect(focusNode2.hasPrimaryFocus, isFalse);
  });

  group('Keyboard Tests', () {
    late TextEditingController controller;

    setUp( () {
      controller = TextEditingController();
    });

    Future<void> setupWidget(WidgetTester tester) async {
      final FocusNode focusNode = FocusNode();
      controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: RawKeyboardListener(
              focusNode: focusNode,
              onKey: null,
              child: TextField(
                controller: controller,
                maxLines: 3,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Shift test 1', (WidgetTester tester) async {
      await setupWidget(tester);
      const String testValue = 'a big house';
      await tester.enterText(find.byType(TextField), testValue);

      await tester.idle();
      // Need to wait for selection to catch up.
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      expect(controller.selection.extentOffset - controller.selection.baseOffset, -1);
    });

    testWidgets('Shift test 2', (WidgetTester tester) async {
      await setupWidget(tester);

      const String testValue = 'abcdefghi';
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: testValue,
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: testValue.length),
      ));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.selection.extentOffset - controller.selection.baseOffset, 1);
    });

    testWidgets('Control Shift test', (WidgetTester tester) async {
      await setupWidget(tester);
      const String testValue = 'their big house';
      await tester.enterText(find.byType(TextField), testValue);

      await tester.idle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(controller.selection.extentOffset - controller.selection.baseOffset, 5);
    });

    testWidgets('Down and up test', (WidgetTester tester) async {
      await setupWidget(tester);
      const String testValue = 'a big house';
      await tester.enterText(find.byType(TextField), testValue);

      await tester.idle();
      // Need to wait for selection to catch up.
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(controller.selection.extentOffset - controller.selection.baseOffset, -11);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(controller.selection.extentOffset - controller.selection.baseOffset, 0);
    });

    testWidgets('Down and up test 2', (WidgetTester tester) async {
      await setupWidget(tester);
      const String testValue = 'a big house\njumped over a mouse\nOne more line yay'; // 11 \n 19
      await tester.enterText(find.byType(TextField), testValue);

      await tester.idle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i += 1) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      expect(controller.selection.extentOffset - controller.selection.baseOffset, 12);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      expect(controller.selection.extentOffset - controller.selection.baseOffset, 32);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      expect(controller.selection.extentOffset - controller.selection.baseOffset, 12);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      expect(controller.selection.extentOffset - controller.selection.baseOffset, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      expect(controller.selection.extentOffset - controller.selection.baseOffset, -5);
    });

    testWidgets('Read only keyboard selection test', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(text: 'readonly');
      await tester.pumpWidget(
          overlay(
            child: TextField(
              controller: controller,
              readOnly: true,
            ),
          ),
      );

      await tester.idle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      expect(controller.selection.extentOffset - controller.selection.baseOffset, -1);
    });
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('Copy paste test', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    final TextEditingController controller = TextEditingController();
    final TextField textField =
      TextField(
        controller: controller,
        maxLines: 3,
      );

    String clipboardContent = '';
    SystemChannels.platform
      .setMockMethodCallHandler((MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData')
          clipboardContent = methodCall.arguments['text'] as String;
        else if (methodCall.method == 'Clipboard.getData')
          return <String, dynamic>{'text': clipboardContent};
        return null;
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: null,
            child: textField,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    const String testValue = 'a big house\njumped over a mouse'; // 11 \n 19
    await tester.enterText(find.byType(TextField), testValue);

    await tester.idle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Select the first 5 characters
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    // Copy them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pumpAndSettle();

    expect(clipboardContent, 'a big');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // Paste them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pumpAndSettle();

    const String expected = 'a biga big house\njumped over a mouse';
    expect(find.text(expected), findsOneWidget, reason: 'Because text contains ${controller.text}');
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('Copy paste obscured text test', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    final TextEditingController controller = TextEditingController();
    final TextField textField =
      TextField(
        controller: controller,
        obscureText: true,
      );

    String clipboardContent = '';
    SystemChannels.platform
      .setMockMethodCallHandler((MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData')
          clipboardContent = methodCall.arguments['text'] as String;
        else if (methodCall.method == 'Clipboard.getData')
          return <String, dynamic>{'text': clipboardContent};
        return null;
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: null,
            child: textField,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    const String testValue = 'a big house jumped over a mouse';
    await tester.enterText(find.byType(TextField), testValue);

    await tester.idle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Select the first 5 characters
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    // Copy them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pumpAndSettle();

    expect(clipboardContent, 'a big');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // Paste them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pumpAndSettle();

    const String expected = 'a biga big house jumped over a mouse';
    expect(find.text(expected), findsOneWidget, reason: 'Because text contains ${controller.text}');
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('Cut test', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    final TextEditingController controller = TextEditingController();
    final TextField textField =
      TextField(
        controller: controller,
        maxLines: 3,
      );
    String clipboardContent = '';
    SystemChannels.platform
      .setMockMethodCallHandler((MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData')
          clipboardContent = methodCall.arguments['text'] as String;
        else if (methodCall.method == 'Clipboard.getData')
          return <String, dynamic>{'text': clipboardContent};
        return null;
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: null,
            child: textField,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    const String testValue = 'a big house\njumped over a mouse'; // 11 \n 19
    await tester.enterText(find.byType(TextField), testValue);

    await tester.idle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Select the first 5 characters
    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
    }

    // Cut them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pumpAndSettle();

    expect(clipboardContent, 'a big');

    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }

    // Paste them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pumpAndSettle();

    const String expected = ' housa bige\njumped over a mouse';
    expect(find.text(expected), findsOneWidget);
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('Cut obscured text test', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    final TextEditingController controller = TextEditingController();
    final TextField textField = TextField(
      controller: controller,
      obscureText: true,
    );
    String clipboardContent = '';
    SystemChannels.platform
      .setMockMethodCallHandler((MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData')
          clipboardContent = methodCall.arguments['text'] as String;
        else if (methodCall.method == 'Clipboard.getData')
          return <String, dynamic>{'text': clipboardContent};
        return null;
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: null,
            child: textField,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    const String testValue = 'a big house jumped over a mouse';
    await tester.enterText(find.byType(TextField), testValue);

    await tester.idle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Select the first 5 characters
    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
    }

    // Cut them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pumpAndSettle();

    expect(clipboardContent, 'a big');

    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }

    // Paste them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    await tester.pumpAndSettle();

    const String expected = ' housa bige jumped over a mouse';
    expect(find.text(expected), findsOneWidget);
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('Select all test', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    final TextEditingController controller = TextEditingController();
    final TextField textField =
      TextField(
        controller: controller,
        maxLines: 3,
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: null,
            child: textField,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    const String testValue = 'a big house\njumped over a mouse'; // 11 \n 19
    await tester.enterText(find.byType(TextField), testValue);

    await tester.idle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Select All
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    // Delete them
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    const String expected = '';
    expect(find.text(expected), findsOneWidget);
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('Delete test', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    final TextEditingController controller = TextEditingController();
    final TextField textField =
      TextField(
        controller: controller,
        maxLines: 3,
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: null,
            child: textField,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    const String testValue = 'a big house\njumped over a mouse'; // 11 \n 19
    await tester.enterText(find.byType(TextField), testValue);

    await tester.idle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Delete
    for (int i = 0; i < 6; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
    }

    const String expected = 'house\njumped over a mouse';
    expect(find.text(expected), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    const String expected2 = '';
    expect(find.text(expected2), findsOneWidget);
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('Changing positions of text fields', (WidgetTester tester) async {

    final FocusNode focusNode = FocusNode();
    final List<RawKeyEvent> events = <RawKeyEvent>[];

    final TextEditingController c1 = TextEditingController();
    final TextEditingController c2 = TextEditingController();
    final Key key1 = UniqueKey();
    final Key key2 = UniqueKey();

    await tester.pumpWidget(
      MaterialApp(
        home:
        Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: events.add,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  key: key1,
                  controller: c1,
                  maxLines: 3,
                ),
                TextField(
                  key: key2,
                  controller: c2,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    const String testValue = 'a big house';
    await tester.enterText(find.byType(TextField).first, testValue);

    await tester.idle();
    // Need to wait for selection to catch up.
    await tester.pump();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    expect(c1.selection.extentOffset - c1.selection.baseOffset, -5);

    await tester.pumpWidget(
      MaterialApp(
        home:
        Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: events.add,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  key: key2,
                  controller: c2,
                  maxLines: 3,
                ),
                TextField(
                  key: key1,
                  controller: c1,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    expect(c1.selection.extentOffset - c1.selection.baseOffset, -10);
  }, skip: areKeyEventsHandledByPlatform);


  testWidgets('Changing focus test', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    final List<RawKeyEvent> events = <RawKeyEvent>[];

    final TextEditingController c1 = TextEditingController();
    final TextEditingController c2 = TextEditingController();
    final Key key1 = UniqueKey();
    final Key key2 = UniqueKey();

    await tester.pumpWidget(
      MaterialApp(
        home:
        Material(
          child: RawKeyboardListener(
            focusNode: focusNode,
            onKey: events.add,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  key: key1,
                  controller: c1,
                  maxLines: 3,
                ),
                TextField(
                  key: key2,
                  controller: c2,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    const String testValue = 'a big house';
    await tester.enterText(find.byType(TextField).first, testValue);
    await tester.idle();
    await tester.pump();

    await tester.idle();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    expect(c1.selection.extentOffset - c1.selection.baseOffset, -5);
    expect(c2.selection.extentOffset - c2.selection.baseOffset, 0);

    await tester.enterText(find.byType(TextField).last, testValue);
    await tester.idle();
    await tester.pump();

    await tester.idle();
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    for (int i = 0; i < 5; i += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);

    expect(c1.selection.extentOffset - c1.selection.baseOffset, 0);
    expect(c2.selection.extentOffset - c2.selection.baseOffset, -5);
  }, skip: areKeyEventsHandledByPlatform);

  testWidgets('Caret works when maxLines is null', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          controller: controller,
          maxLines: null,
        ),
      ),
    );

    const String testValue = 'x';
    await tester.enterText(find.byType(TextField), testValue);
    await skipPastScrollingAnimation(tester);
    expect(controller.selection.isCollapsed, true);
    expect(controller.selection.baseOffset, testValue.length);

    // Tap the selection handle to bring up the "paste / select all" menu.
    await tester.tapAt(textOffsetToPosition(tester, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // skip past the frame where the opacity is

    // Confirm that the selection was updated.
    expect(controller.selection.baseOffset, 0);
  });

  testWidgets('TextField baseline alignment no-strut', (WidgetTester tester) async {
    final TextEditingController controllerA = TextEditingController(text: 'A');
    final TextEditingController controllerB = TextEditingController(text: 'B');
    final Key keyA = UniqueKey();
    final Key keyB = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: keyA,
                decoration: null,
                controller: controllerA,
                style: const TextStyle(fontSize: 10.0),
                strutStyle: StrutStyle.disabled,
              ),
            ),
            const Text(
              'abc',
              style: TextStyle(fontSize: 20.0),
            ),
            Expanded(
              child: TextField(
                key: keyB,
                decoration: null,
                controller: controllerB,
                style: const TextStyle(fontSize: 30.0),
                strutStyle: StrutStyle.disabled,
              ),
            ),
          ],
        ),
      ),
    );

    // The Ahem font extends 0.2 * fontSize below the baseline.
    // So the three row elements line up like this:
    //
    //  A  abc  B
    //  ---------   baseline
    //  2  4    6   space below the baseline = 0.2 * fontSize
    //  ---------   rowBottomY

    final double rowBottomY = tester.getBottomLeft(find.byType(Row)).dy;
    expect(tester.getBottomLeft(find.byKey(keyA)).dy, moreOrLessEquals(rowBottomY - 4.0, epsilon: 0.001));
    expect(tester.getBottomLeft(find.text('abc')).dy, moreOrLessEquals(rowBottomY - 2.0, epsilon: 0.001));
    expect(tester.getBottomLeft(find.byKey(keyB)).dy, rowBottomY);
  });

  testWidgets('TextField baseline alignment', (WidgetTester tester) async {
    final TextEditingController controllerA = TextEditingController(text: 'A');
    final TextEditingController controllerB = TextEditingController(text: 'B');
    final Key keyA = UniqueKey();
    final Key keyB = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: keyA,
                decoration: null,
                controller: controllerA,
                style: const TextStyle(fontSize: 10.0),
              ),
            ),
            const Text(
              'abc',
              style: TextStyle(fontSize: 20.0),
            ),
            Expanded(
              child: TextField(
                key: keyB,
                decoration: null,
                controller: controllerB,
                style: const TextStyle(fontSize: 30.0),
              ),
            ),
          ],
        ),
      ),
    );

    // The Ahem font extends 0.2 * fontSize below the baseline.
    // So the three row elements line up like this:
    //
    //  A  abc  B
    //  ---------   baseline
    //  2  4    6   space below the baseline = 0.2 * fontSize
    //  ---------   rowBottomY

    final double rowBottomY = tester.getBottomLeft(find.byType(Row)).dy;
    // The values here should match the version with strut disabled ('TextField baseline alignment no-strut')
    expect(tester.getBottomLeft(find.byKey(keyA)).dy, moreOrLessEquals(rowBottomY - 4.0, epsilon: 0.001));
    expect(tester.getBottomLeft(find.text('abc')).dy, moreOrLessEquals(rowBottomY - 2.0, epsilon: 0.001));
    expect(tester.getBottomLeft(find.byKey(keyB)).dy, rowBottomY);
  });

  testWidgets('TextField semantics include label when unfocused and label/hint when focused', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController(text: 'value');
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'hint',
            labelText: 'label',
          ),
        ),
      ),
    );

    final SemanticsNode node = tester.getSemantics(find.byKey(key));

    expect(node.label, 'label');
    expect(node.value, 'value');

    // Focus text field.
    await tester.tap(find.byKey(key));
    await tester.pump();

    expect(node.label, 'label\nhint');
    expect(node.value, 'value');
    semantics.dispose();
  });

  testWidgets('TextField semantics always include label when no hint is given', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController(text: 'value');
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'label',
          ),
        ),
      ),
    );

    final SemanticsNode node = tester.getSemantics(find.byKey(key));

    expect(node.label, 'label');
    expect(node.value, 'value');

    // Focus text field.
    await tester.tap(find.byKey(key));
    await tester.pump();

    expect(node.label, 'label');
    expect(node.value, 'value');
    semantics.dispose();
  });

  testWidgets('TextField semantics always include hint when no label is given', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController(text: 'value');
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'hint',
          ),
        ),
      ),
    );

    final SemanticsNode node = tester.getSemantics(find.byKey(key));

    expect(node.label, 'hint');
    expect(node.value, 'value');

    // Focus text field.
    await tester.tap(find.byKey(key));
    await tester.pump();

    expect(node.label, 'hint');
    expect(node.value, 'value');
    semantics.dispose();
  });

  testWidgets('TextField semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController();
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
        ),
      ),
    );

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    controller.text = 'Guten Tag';
    await tester.pump();

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          textDirection: TextDirection.ltr,
          value: 'Guten Tag',
          actions: <SemanticsAction>[
            SemanticsAction.tap,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    await tester.tap(find.byKey(key));
    await tester.pump();

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          textDirection: TextDirection.ltr,
          value: 'Guten Tag',
          textSelection: const TextSelection.collapsed(offset: 9),
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          textDirection: TextDirection.ltr,
          textSelection: const TextSelection.collapsed(offset: 4),
          value: 'Guten Tag',
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorForwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.moveCursorForwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    controller.text = 'Schönen Feierabend';
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          textDirection: TextDirection.ltr,
          textSelection: const TextSelection.collapsed(offset: 0),
          value: 'Schönen Feierabend',
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.moveCursorForwardByCharacter,
            SemanticsAction.moveCursorForwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    semantics.dispose();
  });

  testWidgets('TextField semantics, enableInteractiveSelection = false', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController();
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
          enableInteractiveSelection: false,
        ),
      ),
    );

    await tester.tap(find.byKey(key));
    await tester.pump();

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.setText,
            // Absent the following because enableInteractiveSelection: false
            // SemanticsAction.moveCursorBackwardByCharacter,
            // SemanticsAction.moveCursorBackwardByWord,
            // SemanticsAction.setSelection,
            // SemanticsAction.paste,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    semantics.dispose();
  });

  testWidgets('TextField semantics for selections', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController()
      ..text = 'Hello';
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
        ),
      ),
    );

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          value: 'Hello',
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    // Focus the text field
    await tester.tap(find.byKey(key));
    await tester.pump();

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          value: 'Hello',
          textSelection: const TextSelection.collapsed(offset: 5),
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    controller.selection = const TextSelection(baseOffset: 5, extentOffset: 3);
    await tester.pump();

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: 1,
          value: 'Hello',
          textSelection: const TextSelection(baseOffset: 5, extentOffset: 3),
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorForwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.moveCursorForwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
            SemanticsAction.cut,
            SemanticsAction.copy,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    semantics.dispose();
  });

  testWidgets('TextField change selection with semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final SemanticsOwner semanticsOwner = tester.binding.pipelineOwner.semanticsOwner!;
    final TextEditingController controller = TextEditingController()
      ..text = 'Hello';
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
        ),
      ),
    );

    // Focus the text field
    await tester.tap(find.byKey(key));
    await tester.pump();

    const int inputFieldId = 1;

    expect(controller.selection, const TextSelection.collapsed(offset: 5, affinity: TextAffinity.upstream));
    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: inputFieldId,
          value: 'Hello',
          textSelection: const TextSelection.collapsed(offset: 5),
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    // move cursor back once
    semanticsOwner.performAction(inputFieldId, SemanticsAction.setSelection, <dynamic, dynamic>{
      'base': 4,
      'extent': 4,
    });
    await tester.pump();
    expect(controller.selection, const TextSelection.collapsed(offset: 4));

    // move cursor to front
    semanticsOwner.performAction(inputFieldId, SemanticsAction.setSelection, <dynamic, dynamic>{
      'base': 0,
      'extent': 0,
    });
    await tester.pump();
    expect(controller.selection, const TextSelection.collapsed(offset: 0));

    // select all
    semanticsOwner.performAction(inputFieldId, SemanticsAction.setSelection, <dynamic, dynamic>{
      'base': 0,
      'extent': 5,
    });
    await tester.pump();
    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          id: inputFieldId,
          value: 'Hello',
          textSelection: const TextSelection(baseOffset: 0, extentOffset: 5),
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.moveCursorBackwardByCharacter,
            SemanticsAction.moveCursorBackwardByWord,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
            SemanticsAction.cut,
            SemanticsAction.copy,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    semantics.dispose();
  });

  testWidgets('Can activate TextField with explicit controller via semantics ', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/17801

    const String textInTextField = 'Hello';

    final SemanticsTester semantics = SemanticsTester(tester);
    final SemanticsOwner semanticsOwner = tester.binding.pipelineOwner.semanticsOwner!;
    final TextEditingController controller = TextEditingController()
      ..text = textInTextField;
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
        ),
      ),
    );

    const int inputFieldId = 1;

    expect(semantics, hasSemantics(
      TestSemantics.root(
        children: <TestSemantics>[
          TestSemantics(
            id: inputFieldId,
            flags: <SemanticsFlag>[SemanticsFlag.isTextField],
            actions: <SemanticsAction>[SemanticsAction.tap],
            value: textInTextField,
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
      ignoreRect: true, ignoreTransform: true,
    ));

    semanticsOwner.performAction(inputFieldId, SemanticsAction.tap);
    await tester.pump();

    expect(semantics, hasSemantics(
      TestSemantics.root(
        children: <TestSemantics>[
          TestSemantics(
            id: inputFieldId,
            flags: <SemanticsFlag>[
              SemanticsFlag.isTextField,
              SemanticsFlag.isFocused,
            ],
            actions: <SemanticsAction>[
              SemanticsAction.tap,
              SemanticsAction.moveCursorBackwardByCharacter,
              SemanticsAction.moveCursorBackwardByWord,
              SemanticsAction.setSelection,
              SemanticsAction.setText,
              SemanticsAction.paste,
            ],
            value: textInTextField,
            textDirection: TextDirection.ltr,
            textSelection: const TextSelection(
              baseOffset: textInTextField.length,
              extentOffset: textInTextField.length,
            ),
          ),
        ],
      ),
      ignoreRect: true, ignoreTransform: true,
    ));

    semantics.dispose();
  });

  testWidgets('When clipboard empty, no semantics paste option', (WidgetTester tester) async {
    const String textInTextField = 'Hello';

    final SemanticsTester semantics = SemanticsTester(tester);
    final SemanticsOwner semanticsOwner = tester.binding.pipelineOwner.semanticsOwner!;
    final TextEditingController controller = TextEditingController()
      ..text = textInTextField;
    final Key key = UniqueKey();

    // Clear the clipboard.
    await Clipboard.setData(const ClipboardData(text: ''));

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
        ),
      ),
    );

    const int inputFieldId = 1;

    expect(semantics, hasSemantics(
      TestSemantics.root(
        children: <TestSemantics>[
          TestSemantics(
            id: inputFieldId,
            flags: <SemanticsFlag>[SemanticsFlag.isTextField],
            actions: <SemanticsAction>[SemanticsAction.tap],
            value: textInTextField,
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
      ignoreRect: true, ignoreTransform: true,
    ));

    semanticsOwner.performAction(inputFieldId, SemanticsAction.tap);
    await tester.pump();

    expect(semantics, hasSemantics(
      TestSemantics.root(
        children: <TestSemantics>[
          TestSemantics(
            id: inputFieldId,
            flags: <SemanticsFlag>[
              SemanticsFlag.isTextField,
              SemanticsFlag.isFocused,
            ],
            actions: <SemanticsAction>[
              SemanticsAction.tap,
              SemanticsAction.moveCursorBackwardByCharacter,
              SemanticsAction.moveCursorBackwardByWord,
              SemanticsAction.setSelection,
              SemanticsAction.setText,
              // No paste option.
            ],
            value: textInTextField,
            textDirection: TextDirection.ltr,
            textSelection: const TextSelection(
              baseOffset: textInTextField.length,
              extentOffset: textInTextField.length,
            ),
          ),
        ],
      ),
      ignoreRect: true, ignoreTransform: true,
    ));

    semantics.dispose();

    // On web (just like iOS), we don't check for pasteability because that
    // triggers a permission dialog in the browser.
    // https://github.com/flutter/flutter/pull/57139#issuecomment-629048058
  }, skip: isBrowser);

  testWidgets('TextField throws when not descended from a Material widget', (WidgetTester tester) async {
    const Widget textField = TextField();
    await tester.pumpWidget(textField);
    final dynamic exception = tester.takeException();
    expect(exception, isFlutterError);
    expect(exception.toString(), startsWith('No Material widget found.'));
    expect(exception.toString(), endsWith(':\n  $textField\nThe ancestors of this widget were:\n  [root]'));
  });

  testWidgets('TextField loses focus when disabled', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode(debugLabel: 'TextField Focus Node');

    await tester.pumpWidget(
      boilerplate(
        child: TextField(
          focusNode: focusNode,
          autofocus: true,
          enabled: true,
        ),
      ),
    );
    expect(focusNode.hasFocus, isTrue);

    await tester.pumpWidget(
      boilerplate(
        child: TextField(
          focusNode: focusNode,
          autofocus: true,
          enabled: false,
        ),
      ),
    );
    expect(focusNode.hasFocus, isFalse);

    await tester.pumpWidget(
      boilerplate(
        child: Builder(builder: (BuildContext context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              navigationMode: NavigationMode.directional,
            ),
            child: TextField(
              focusNode: focusNode,
              autofocus: true,
              enabled: true,
            ),
          );
        }),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);

    await tester.pumpWidget(
      boilerplate(
        child: Builder(builder: (BuildContext context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              navigationMode: NavigationMode.directional,
            ),
            child:  TextField(
              focusNode: focusNode,
              autofocus: true,
              enabled: false,
            ),
          );
        }),
      ),
    );
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('TextField displays text with text direction', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TextField(
            textDirection: TextDirection.rtl,
          ),
        ),
      ),
    );

    RenderEditable editable = findRenderEditable(tester);

    await tester.enterText(find.byType(TextField), '0123456789101112');
    await tester.pumpAndSettle();
    Offset topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 10)).topLeft,
    );

    expect(topLeft.dx, equals(701));

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TextField(
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    editable = findRenderEditable(tester);

    await tester.enterText(find.byType(TextField), '0123456789101112');
    await tester.pumpAndSettle();
    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 10)).topLeft,
    );

    expect(topLeft.dx, equals(160.0));

    // TODO(mdebbar): RTL support still has issues on the web.
    // https://github.com/flutter/flutter/projects/159
  }, skip: isBrowser);

  testWidgets('TextField semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController();
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
          maxLength: 10,
          decoration: const InputDecoration(
            labelText: 'label',
            hintText: 'hint',
            helperText: 'helper',
          ),
        ),
      ),
    );

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          label: 'label',
          id: 1,
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
          ],
          children: <TestSemantics>[
            TestSemantics(
              id: 2,
              label: 'helper',
              textDirection: TextDirection.ltr,
            ),
            TestSemantics(
              id: 3,
              label: '10 characters remaining',
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          label: 'label\nhint',
          id: 1,
          textDirection: TextDirection.ltr,
          textSelection: const TextSelection(baseOffset: 0, extentOffset: 0),
          actions: <SemanticsAction>[
            SemanticsAction.tap,
            SemanticsAction.setSelection,
            SemanticsAction.setText,
            SemanticsAction.paste,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
            SemanticsFlag.isFocused,
          ],
          children: <TestSemantics>[
            TestSemantics(
              id: 2,
              label: 'helper',
              textDirection: TextDirection.ltr,
            ),
            TestSemantics(
              id: 3,
              label: '10 characters remaining',
              flags: <SemanticsFlag>[
                SemanticsFlag.isLiveRegion,
              ],
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true));

    controller.text = 'hello';
    await tester.pump();
    semantics.dispose();
  });

  testWidgets('InputDecoration counterText can have a semanticCounterText', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController();
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'label',
            hintText: 'hint',
            helperText: 'helper',
            counterText: '0/10',
            semanticCounterText: '0 out of 10',
          ),
        ),
      ),
    );

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          label: 'label',
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
          ],
          children: <TestSemantics>[
            TestSemantics(
              label: 'helper',
              textDirection: TextDirection.ltr,
            ),
            TestSemantics(
              label: '0 out of 10',
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true, ignoreId: true));

    semantics.dispose();
  });

  testWidgets('InputDecoration errorText semantics', (WidgetTester tester) async {
    final SemanticsTester semantics = SemanticsTester(tester);
    final TextEditingController controller = TextEditingController();
    final Key key = UniqueKey();

    await tester.pumpWidget(
      overlay(
        child: TextField(
          key: key,
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'label',
            hintText: 'hint',
            errorText: 'oh no!',
          ),
        ),
      ),
    );

    expect(semantics, hasSemantics(TestSemantics.root(
      children: <TestSemantics>[
        TestSemantics.rootChild(
          label: 'label',
          textDirection: TextDirection.ltr,
          actions: <SemanticsAction>[
            SemanticsAction.tap,
          ],
          flags: <SemanticsFlag>[
            SemanticsFlag.isTextField,
          ],
          children: <TestSemantics>[
            TestSemantics(
              label: 'oh no!',
              flags: <SemanticsFlag>[
                SemanticsFlag.isLiveRegion,
              ],
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ],
    ), ignoreTransform: true, ignoreRect: true, ignoreId: true));

    semantics.dispose();
  });

  testWidgets('floating label does not overlap with value at large textScaleFactors', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(text: 'Just some text');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
              data: MediaQueryData.fromWindow(ui.window).copyWith(textScaleFactor: 4.0),
              child: Center(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Label', border: UnderlineInputBorder()),
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
    );

    await tester.tap(find.byType(TextField));
    final Rect labelRect = tester.getRect(find.text('Label'));
    final Rect fieldRect = tester.getRect(find.text('Just some text'));
    expect(labelRect.bottom, lessThanOrEqualTo(fieldRect.top));
  });

  testWidgets('TextField scrolls into view but does not bounce (SingleChildScrollView)', (WidgetTester tester) async {
    // This is a regression test for https://github.com/flutter/flutter/issues/20485

    final Key textField1 = UniqueKey();
    final Key textField2 = UniqueKey();
    final ScrollController scrollController = ScrollController();

    double? minOffset;
    double? maxOffset;

    scrollController.addListener(() {
      final double offset = scrollController.offset;
      minOffset = math.min(minOffset ?? offset, offset);
      maxOffset = math.max(maxOffset ?? offset, offset);
    });

    Widget buildFrame(Axis scrollDirection) {
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              controller: scrollController,
              child: Column(
                children: <Widget>[
                  SizedBox( // visible when scrollOffset is 0.0
                    height: 100.0,
                    width: 100.0,
                    child: TextField(key: textField1, scrollPadding: const EdgeInsets.all(200.0)),
                  ),
                  const SizedBox(
                    height: 600.0, // Same size as the frame. Initially
                    width: 800.0,  // textField2 is not visible
                  ),
                  SizedBox( // visible when scrollOffset is 200.0
                    height: 100.0,
                    width: 100.0,
                    child: TextField(key: textField2, scrollPadding: const EdgeInsets.all(200.0)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildFrame(Axis.vertical));
    await tester.enterText(find.byKey(textField1), '1');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(textField2), '2'); //scroll textField2 into view
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(textField1), '3'); //scroll textField1 back into view
    await tester.pumpAndSettle();

    expect(minOffset, 0.0);
    expect(maxOffset, 200.0);

    minOffset = null;
    maxOffset = null;

    await tester.pumpWidget(buildFrame(Axis.horizontal));
    await tester.enterText(find.byKey(textField1), '1');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(textField2), '2'); //scroll textField2 into view
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(textField1), '3'); //scroll textField1 back into view
    await tester.pumpAndSettle();

    expect(minOffset, 0.0);
    expect(maxOffset, 200.0);
  });

  testWidgets('TextField scrolls into view but does not bounce (ListView)', (WidgetTester tester) async {
    // This is a regression test for https://github.com/flutter/flutter/issues/20485

    final Key textField1 = UniqueKey();
    final Key textField2 = UniqueKey();
    final ScrollController scrollController = ScrollController();

    double? minOffset;
    double? maxOffset;

    scrollController.addListener(() {
      final double offset = scrollController.offset;
      minOffset = math.min(minOffset ?? offset, offset);
      maxOffset = math.max(maxOffset ?? offset, offset);
    });

    Widget buildFrame(Axis scrollDirection) {
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              controller: scrollController,
              children: <Widget>[
                SizedBox( // visible when scrollOffset is 0.0
                  height: 100.0,
                  width: 100.0,
                  child: TextField(key: textField1, scrollPadding: const EdgeInsets.all(200.0)),
                ),
                const SizedBox(
                  height: 450.0, // 50.0 smaller than the overall frame so that both
                  width: 650.0,  // textfields are always partially visible.
                ),
                SizedBox( // visible when scrollOffset = 50.0
                  height: 100.0,
                  width: 100.0,
                  child: TextField(key: textField2, scrollPadding: const EdgeInsets.all(200.0)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildFrame(Axis.vertical));
    await tester.enterText(find.byKey(textField1), '1'); // textfield1 is visible
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(textField2), '2'); //scroll textField2 into view
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(textField1), '3'); //scroll textField1 back into view
    await tester.pumpAndSettle();

    expect(minOffset, 0.0);
    expect(maxOffset, 50.0);

    minOffset = null;
    maxOffset = null;

    await tester.pumpWidget(buildFrame(Axis.horizontal));
    await tester.enterText(find.byKey(textField1), '1'); // textfield1 is visible
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(textField2), '2'); //scroll textField2 into view
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(textField1), '3'); //scroll textField1 back into view
    await tester.pumpAndSettle();

    expect(minOffset, 0.0);
    expect(maxOffset, 50.0);
  });

  testWidgets('onTap is called upon tap', (WidgetTester tester) async {
    int tapCount = 0;
    await tester.pumpWidget(
      overlay(
        child: TextField(
          onTap: () {
            tapCount += 1;
          },
        ),
      ),
    );

    expect(tapCount, 0);
    await tester.tap(find.byType(TextField));
    // Wait a bit so they're all single taps and not double taps.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tapCount, 3);
  });

  testWidgets('onTap is not called, field is disabled', (WidgetTester tester) async {
    int tapCount = 0;
    await tester.pumpWidget(
      overlay(
        child: TextField(
          enabled: false,
          onTap: () {
            tapCount += 1;
          },
        ),
      ),
    );

    expect(tapCount, 0);
    await tester.tap(find.byType(TextField));
    await tester.tap(find.byType(TextField));
    await tester.tap(find.byType(TextField));
    expect(tapCount, 0);
  });

  testWidgets('Includes cursor for TextField', (WidgetTester tester) async {
    // This is a regression test for https://github.com/flutter/flutter/issues/24612

    Widget buildFrame({
      double? stepWidth,
      required double cursorWidth,
      required TextAlign textAlign,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IntrinsicWidth(
                  stepWidth: stepWidth,
                  child: TextField(
                    textAlign: textAlign,
                    cursorWidth: cursorWidth,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // A cursor of default size doesn't cause the TextField to increase its
    // width.
    const String text = '1234';
    double? stepWidth = 80.0;
    await tester.pumpWidget(buildFrame(
      stepWidth: 80.0,
      cursorWidth: 2.0,
      textAlign: TextAlign.left,
    ));
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextField)).width, stepWidth);

    // A wide cursor is counted in the width of the text and causes the
    // TextField to increase to twice the stepWidth.
    await tester.pumpWidget(buildFrame(
      stepWidth: stepWidth,
      cursorWidth: 18.0,
      textAlign: TextAlign.left,
    ));
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextField)).width, 2 * stepWidth);

    // A null stepWidth causes the TextField to perfectly wrap the text plus
    // the cursor regardless of alignment.
    stepWidth = null;
    const double WIDTH_OF_CHAR = 16.0;
    await tester.pumpWidget(buildFrame(
      stepWidth: stepWidth,
      cursorWidth: 18.0,
      textAlign: TextAlign.left,
    ));
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextField)).width, WIDTH_OF_CHAR * text.length + 18.0);
    await tester.pumpWidget(buildFrame(
      stepWidth: stepWidth,
      cursorWidth: 18.0,
      textAlign: TextAlign.right,
    ));
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextField)).width, WIDTH_OF_CHAR * text.length + 18.0);
  });

  testWidgets('TextField style is merged with theme', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/23994

    final ThemeData themeData = ThemeData(
      textTheme: TextTheme(
        subtitle1: TextStyle(
          color: Colors.blue[500],
        ),
      ),
    );

    Widget buildFrame(TextStyle style) {
      return MaterialApp(
        theme: themeData,
        home: Material(
          child: Center(
            child: TextField(
              style: style,
            ),
          ),
        ),
      );
    }

    // Empty TextStyle is overridden by theme
    await tester.pumpWidget(buildFrame(const TextStyle()));
    EditableText editableText = tester.widget(find.byType(EditableText));
    expect(editableText.style.color, themeData.textTheme.subtitle1!.color);
    expect(editableText.style.background, themeData.textTheme.subtitle1!.background);
    expect(editableText.style.shadows, themeData.textTheme.subtitle1!.shadows);
    expect(editableText.style.decoration, themeData.textTheme.subtitle1!.decoration);
    expect(editableText.style.locale, themeData.textTheme.subtitle1!.locale);
    expect(editableText.style.wordSpacing, themeData.textTheme.subtitle1!.wordSpacing);

    // Properties set on TextStyle override theme
    const Color setColor = Colors.red;
    await tester.pumpWidget(buildFrame(const TextStyle(color: setColor)));
    editableText = tester.widget(find.byType(EditableText));
    expect(editableText.style.color, setColor);

    // inherit: false causes nothing to be merged in from theme
    await tester.pumpWidget(buildFrame(const TextStyle(
      fontSize: 24.0,
      textBaseline: TextBaseline.alphabetic,
      inherit: false,
    )));
    editableText = tester.widget(find.byType(EditableText));
    expect(editableText.style.color, isNull);
  });

  testWidgets('style enforces required fields', (WidgetTester tester) async {
    Widget buildFrame(TextStyle style) {
      return MaterialApp(
        home: Material(
          child: TextField(
            style: style,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildFrame(const TextStyle(
      inherit: false,
      fontSize: 12.0,
      textBaseline: TextBaseline.alphabetic,
    )));
    expect(tester.takeException(), isNull);

    // With inherit not set to false, will pickup required fields from theme
    await tester.pumpWidget(buildFrame(const TextStyle(
      fontSize: 12.0,
    )));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(buildFrame(const TextStyle(
      inherit: false,
      fontSize: 12.0,
    )));
    expect(tester.takeException(), isNotNull);
  });

  testWidgets(
    'tap moves cursor to the edge of the word it tapped',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump();

      // We moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 7, affinity: TextAffinity.upstream),
      );

      // But don't trigger the toolbar.
      expect(find.byType(CupertinoButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'tap with a mouse does not move cursor to the edge of the word',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      final TestGesture gesture = await tester.startGesture(
        textfieldStart + const Offset(50.0, 9.0),
        pointer: 1,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.up();

      // Cursor at tap position, not at word edge.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 3, affinity: TextAffinity.downstream),
      );
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets('tap moves cursor to the position tapped', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump();

      // We moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 3),
      );

      // But don't trigger the toolbar.
      expect(find.byType(TextButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.fuchsia, TargetPlatform.linux, TargetPlatform.windows }));

  testWidgets(
    'two slow taps do not trigger a word selection',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump();

      // Plain collapsed selection.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 7, affinity: TextAffinity.upstream),
      );

      // No toolbar.
      expect(find.byType(CupertinoButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'double tap selects word and first tap of double tap moves cursor',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      // This tap just puts the cursor somewhere different than where the double
      // tap will occur to test that the double tap moves the existing cursor first.
      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 8, affinity: TextAffinity.downstream),
      );
      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pumpAndSettle();

      // Second tap selects the word around the cursor.
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );

      // Selected text shows 3 toolbar buttons.
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(3));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'double tap selects word and first tap of double tap moves cursor and shows toolbar',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      // This tap just puts the cursor somewhere different than where the double
      // tap will occur to test that the double tap moves the existing cursor first.
      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 9),
      );
      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pumpAndSettle();

      // Second tap selects the word around the cursor.
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );

      // Selected text shows 4 toolbar buttons: cut, copy, paste, select all
      expect(find.byType(TextButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(4));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.fuchsia, TargetPlatform.linux, TargetPlatform.windows }));

  testWidgets('Custom toolbar test - Android text selection controls', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
                selectionControls: materialTextSelectionControls
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pumpAndSettle();

      // Selected text shows 4 toolbar buttons: cut, copy, paste, select all
      expect(find.byType(TextButton), findsNWidgets(4));
  }, variant: TargetPlatformVariant.all(), skip: isContextMenuProvidedByPlatform);

  testWidgets(
    'Custom toolbar test - Cupertino text selection controls',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
                selectionControls: cupertinoTextSelectionControls,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pumpAndSettle();

      // Selected text shows 3 toolbar buttons: cut, copy, paste
      expect(find.byType(CupertinoButton), findsNWidgets(3));
  }, variant: TargetPlatformVariant.all(), skip: isContextMenuProvidedByPlatform);

  testWidgets('selectionControls is passed to EditableText',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Scaffold(
            body: TextField(
              selectionControls: materialTextSelectionControls,
            ),
          ),
        ),
      ),
    );

    final EditableText widget = tester.widget(find.byType(EditableText));
    expect(widget.selectionControls, equals(materialTextSelectionControls));
  });

  testWidgets(
    'double tap on top of cursor also selects word',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      // Tap to put the cursor after the "w".
      const int index = 3;
      await tester.tapAt(textOffsetToPosition(tester, index));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: index),
      );

      // Double tap on the same location.
      await tester.tapAt(textOffsetToPosition(tester, index));
      await tester.pump(const Duration(milliseconds: 50));

      // First tap doesn't change the selection
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: index),
      );

      // Second tap selects the word around the cursor.
      await tester.tapAt(textOffsetToPosition(tester, index));
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );

      // Selected text shows 4 toolbar buttons: cut, copy, paste, select all
      expect(find.byType(TextButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(4));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.fuchsia, TargetPlatform.linux, TargetPlatform.windows }));

  testWidgets(
    'double double tap just shows the selection menu',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      // Double tap on the same location shows the selection menu.
      await tester.tapAt(textOffsetToPosition(tester, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(textOffsetToPosition(tester, 0));
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);

      // Double tap again keeps the selection menu visible.
      await tester.tapAt(textOffsetToPosition(tester, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(textOffsetToPosition(tester, 0));
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);
    },
    skip: isContextMenuProvidedByPlatform,
  );

  testWidgets(
    'double long press just shows the selection menu',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      // Long press shows the selection menu.
      await tester.longPressAt(textOffsetToPosition(tester, 0));
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);

      // Long press again keeps the selection menu visible.
      await tester.longPressAt(textOffsetToPosition(tester, 0));
      await tester.pump();
      expect(find.text('Paste'), findsOneWidget);
    },
    skip: isContextMenuProvidedByPlatform,
  );

  testWidgets(
    'A single tap hides the selection menu',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      // Long press shows the selection menu.
      await tester.longPress(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);

      // Tap hides the selection menu.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Paste'), findsNothing);
    },
    skip: isContextMenuProvidedByPlatform,
  );

  testWidgets(
    'Long press on an autofocused field shows the selection menu',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                autofocus: true,
                controller: controller,
              ),
            ),
          ),
        ),
      );
      // This extra pump allows the selection set by autofocus to propagate to
      // the RenderEditable.
      await tester.pump();

      // Long press shows the selection menu.
      expect(find.text('Paste'), findsNothing);
      await tester.longPress(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);
    },
    skip: isContextMenuProvidedByPlatform,
  );

  testWidgets(
    'double tap hold selects word',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      final TestGesture gesture =
         await tester.startGesture(textfieldStart + const Offset(150.0, 9.0));
      // Hold the press.
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );

      // Selected text shows 3 toolbar buttons.
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(3));

      await gesture.up();
      await tester.pump();

      // Still selected.
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );
      // The toolbar is still showing.
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(3));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'tap after a double tap select is not affected',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 8, affinity: TextAffinity.downstream),
      );
      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tapAt(textfieldStart + const Offset(100.0, 9.0));
      await tester.pump();

      // Plain collapsed selection at the edge of first word. In iOS 12, the
      // first tap after a double tap ends up putting the cursor at where
      // you tapped instead of the edge like every other single tap. This is
      // likely a bug in iOS 12 and not present in other versions.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 7, affinity: TextAffinity.upstream),
      );

      // No toolbar.
      expect(find.byType(CupertinoButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'long press moves cursor to the exact long press position and shows toolbar',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.longPressAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pumpAndSettle();

      // Collapsed cursor for iOS long press.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 3),
      );

      // Collapsed toolbar shows 2 buttons.
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(2));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'long press selects word and shows toolbar',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.longPressAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );

      // Collapsed toolbar shows 4 buttons: cut, copy, paste, select all
      expect(find.byType(TextButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(4));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.fuchsia, TargetPlatform.linux, TargetPlatform.windows }));

  testWidgets(
    'long press tap cannot initiate a double tap',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.longPressAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump();

      // We ended up moving the cursor to the edge of the same word and dismissed
      // the toolbar.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 7, affinity: TextAffinity.upstream),
      );

      // Collapsed toolbar shows 2 buttons.
      expect(find.byType(CupertinoButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'long press drag moves the cursor under the drag and shows toolbar on lift',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      final TestGesture gesture =
          await tester.startGesture(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump(const Duration(milliseconds: 500));

      // Long press on iOS shows collapsed selection cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 3, affinity: TextAffinity.downstream),
      );
      // Cursor move doesn't trigger a toolbar initially.
      expect(find.byType(CupertinoButton), findsNothing);

      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();

      // The selection position is now moved with the drag.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 6, affinity: TextAffinity.downstream),
      );
      // Still no toolbar.
      expect(find.byType(CupertinoButton), findsNothing);

      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();

      // The selection position is now moved with the drag.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 9, affinity: TextAffinity.downstream),
      );
      // Still no toolbar.
      expect(find.byType(CupertinoButton), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();

      // The selection isn't affected by the gesture lift.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 9, affinity: TextAffinity.downstream),
      );
      // The toolbar now shows up.
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(2));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets('long press drag can edge scroll', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure Angrignon Peel Côte-des-Neiges',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              controller: controller,
              maxLines: 1,
            ),
          ),
        ),
      ),
    );

    final RenderEditable renderEditable = findRenderEditable(tester);

    List<TextSelectionPoint> lastCharEndpoint = renderEditable.getEndpointsForSelection(
      const TextSelection.collapsed(offset: 66), // Last character's position.
    );

    expect(lastCharEndpoint.length, 1);
    // Just testing the test and making sure that the last character is off
    // the right side of the screen.
    expect(lastCharEndpoint[0].point.dx, 1056);

    final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

    final TestGesture gesture =
        await tester.startGesture(textfieldStart + const Offset(300, 5));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 19, affinity: TextAffinity.upstream),
    );
    expect(find.byType(CupertinoButton), findsNothing);

    await gesture.moveBy(const Offset(600, 0));
    // To the edge of the screen basically.
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 56, affinity: TextAffinity.downstream),
    );
    // Keep moving out.
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 62, affinity: TextAffinity.downstream),
    );
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 66, affinity: TextAffinity.upstream),
    ); // We're at the edge now.
    expect(find.byType(CupertinoButton), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();

    // The selection isn't affected by the gesture lift.
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 66, affinity: TextAffinity.upstream),
    );
    // The toolbar now shows up.
    expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(2));

    lastCharEndpoint = renderEditable.getEndpointsForSelection(
      const TextSelection.collapsed(offset: 66), // Last character's position.
    );

    expect(lastCharEndpoint.length, 1);
    // The last character is now on screen near the right edge.
    expect(lastCharEndpoint[0].point.dx, moreOrLessEquals(798, epsilon: 1));

    final List<TextSelectionPoint> firstCharEndpoint = renderEditable.getEndpointsForSelection(
      const TextSelection.collapsed(offset: 0), // First character's position.
    );
    expect(firstCharEndpoint.length, 1);
    // The first character is now offscreen to the left.
    expect(firstCharEndpoint[0].point.dx, moreOrLessEquals(-257, epsilon: 1));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'long tap after a double tap select is not affected',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor to the beginning of the second word.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 8, affinity: TextAffinity.downstream),
      );
      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.longPressAt(textfieldStart + const Offset(100.0, 9.0));
      await tester.pumpAndSettle();

      // Plain collapsed selection at the exact tap position.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 6),
      );

      // Long press toolbar.
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(2));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets(
    'double tap after a long tap is not affected',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.longPressAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 3, affinity: TextAffinity.downstream),
      );

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 8, affinity: TextAffinity.downstream),
      );
      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pumpAndSettle();

      // Double tap selection.
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(3));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.macOS }));

  testWidgets(
    'double click after a click on Mac',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textFieldStart = tester.getTopLeft(find.byType(TextField));

      final TestGesture gesture = await tester.startGesture(
        textFieldStart + const Offset(50.0, 9.0),
        pointer: 7,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 3, affinity: TextAffinity.downstream),
      );

      await gesture.down(textFieldStart + const Offset(150.0, 9.0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      // First click moved the cursor to the precise location, not the start of
      // the word.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 9, affinity: TextAffinity.downstream),
      );

      // Double click selection.
      await gesture.down(textFieldStart + const Offset(150.0, 9.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );
      // The text selection toolbar isn't shown on Mac without a right click.
      expect(find.byType(CupertinoButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux }));

  testWidgets('double tap chains work', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 7, affinity: TextAffinity.upstream),
      );
      await tester.tapAt(textfieldStart + const Offset(50.0, 9.0));
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(3));

      // Double tap selecting the same word somewhere else is fine.
      await tester.tapAt(textfieldStart + const Offset(100.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 7, affinity: TextAffinity.upstream),
      );
      await tester.tapAt(textfieldStart + const Offset(100.0, 9.0));
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(3));

      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 8, affinity: TextAffinity.downstream),
      );
      await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );
      expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(3));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.macOS }));

  testWidgets('double click chains work', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Atwater Peel Sherbrooke Bonaventure',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: TextField(
                controller: controller,
              ),
            ),
          ),
        ),
      );

      final Offset textFieldStart = tester.getTopLeft(find.byType(TextField));

      // First click moves the cursor to the point of the click, not the edge of
      // the clicked word.
      final TestGesture gesture = await tester.startGesture(
        textFieldStart + const Offset(50.0, 9.0),
        pointer: 7,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 3, affinity: TextAffinity.downstream),
      );

      // Second click selects.
      await gesture.down(textFieldStart + const Offset(50.0, 9.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
      expect(find.byType(CupertinoButton), findsNothing);

      // Double tap selecting the same word somewhere else is fine.
      await gesture.down(textFieldStart + const Offset(100.0, 9.0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 6, affinity: TextAffinity.downstream),
      );
      await gesture.down(textFieldStart + const Offset(100.0, 9.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
      expect(find.byType(CupertinoButton), findsNothing);

      await gesture.down(textFieldStart + const Offset(150.0, 9.0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      // First tap moved the cursor.
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 9, affinity: TextAffinity.downstream),
      );
      await gesture.down(textFieldStart + const Offset(150.0, 9.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );
      expect(find.byType(CupertinoButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux }));

  testWidgets('double tapping a space selects the previous word on iOS', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: ' blah blah  \n  blah',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              controller: controller,
            ),
          ),
        ),
      ),
    );

    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, -1);
    expect(controller.value.selection.extentOffset, -1);

    // Put the cursor at the end of the field.
    await tester.tapAt(textOffsetToPosition(tester, 19));
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 19);
    expect(controller.value.selection.extentOffset, 19);

    // Double tapping does the same thing.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(textOffsetToPosition(tester, 5));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(textOffsetToPosition(tester, 5));
    await tester.pumpAndSettle();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.extentOffset, 5);
    expect(controller.value.selection.baseOffset, 1);

    // Put the cursor at the end of the field.
    await tester.tapAt(textOffsetToPosition(tester, 19));
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 19);
    expect(controller.value.selection.extentOffset, 19);

    // Double tapping does the same thing for the first space.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(textOffsetToPosition(tester, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(textOffsetToPosition(tester, 0));
    await tester.pumpAndSettle();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 0);
    expect(controller.value.selection.extentOffset, 1);

    // Put the cursor at the end of the field.
    await tester.tapAt(textOffsetToPosition(tester, 19));
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 19);
    expect(controller.value.selection.extentOffset, 19);

    // Double tapping the last space selects all previous contiguous spaces on
    // both lines and the previous word.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(textOffsetToPosition(tester, 14));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(textOffsetToPosition(tester, 14));
    await tester.pumpAndSettle();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 6);
    expect(controller.value.selection.extentOffset, 14);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS }));

  testWidgets('selecting a space selects the space on non-iOS platforms', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: ' blah blah',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              controller: controller,
            ),
          ),
        ),
      ),
    );

    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, -1);
    expect(controller.value.selection.extentOffset, -1);

    // Put the cursor at the end of the field.
    await tester.tapAt(textOffsetToPosition(tester, 10));
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 10);
    expect(controller.value.selection.extentOffset, 10);

    // Double tapping the second space selects it.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(textOffsetToPosition(tester, 5));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(textOffsetToPosition(tester, 5));
    await tester.pumpAndSettle();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 5);
    expect(controller.value.selection.extentOffset, 6);

    // Put the cursor at the end of the field.
    await tester.tapAt(textOffsetToPosition(tester, 10));
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 10);
    expect(controller.value.selection.extentOffset, 10);

    // Double tapping the second space selects it.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(textOffsetToPosition(tester, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(textOffsetToPosition(tester, 0));
    await tester.pumpAndSettle();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 0);
    expect(controller.value.selection.extentOffset, 1);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia, TargetPlatform.android }));

  testWidgets('selecting a space selects the space on Mac', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: ' blah blah',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              controller: controller,
            ),
          ),
        ),
      ),
    );

    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, -1);
    expect(controller.value.selection.extentOffset, -1);

    // Put the cursor at the end of the field.
    final TestGesture gesture = await tester.startGesture(
      textOffsetToPosition(tester, 10),
      pointer: 7,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.up();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 10);
    expect(controller.value.selection.extentOffset, 10);

    // Double clicking the second space selects it.
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.down(textOffsetToPosition(tester, 5));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.down(textOffsetToPosition(tester, 5));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 5);
    expect(controller.value.selection.extentOffset, 6);

    // Put the cursor at the end of the field.
    await gesture.down(textOffsetToPosition(tester, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 10);
    expect(controller.value.selection.extentOffset, 10);

    // Double tapping the second space selects it.
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.down(textOffsetToPosition(tester, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.down(textOffsetToPosition(tester, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.value.selection, isNotNull);
    expect(controller.value.selection.baseOffset, 0);
    expect(controller.value.selection.extentOffset, 1);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux }));

  testWidgets('force press does not select a word', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
          ),
        ),
      ),
    );

    final Offset offset = tester.getTopLeft(find.byType(TextField)) + const Offset(150.0, 9.0);

    final int pointerValue = tester.nextPointer;
    final TestGesture gesture = await tester.createGesture();
    await gesture.downWithCustomEvent(
      offset,
      PointerDownEvent(
          pointer: pointerValue,
          position: offset,
          pressure: 0.0,
          pressureMax: 6.0,
          pressureMin: 0.0,
      ),
    );
    await gesture.updateWithCustomEvent(PointerMoveEvent(
      pointer: pointerValue,
      position: offset + const Offset(150.0, 9.0),
      pressure: 0.5,
      pressureMin: 0,
      pressureMax: 1,
    ));

    // We don't want this gesture to select any word on Android.
    expect(controller.selection, const TextSelection.collapsed(offset: -1));

    await gesture.up();
    await tester.pump();
    expect(find.byType(TextButton), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.android, TargetPlatform.fuchsia, TargetPlatform.linux, TargetPlatform.windows }));

  testWidgets('force press selects word', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
          ),
        ),
      ),
    );

    final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

    final int pointerValue = tester.nextPointer;
    final Offset offset = textfieldStart + const Offset(150.0, 9.0);
    final TestGesture gesture = await tester.createGesture();
    await gesture.downWithCustomEvent(
      offset,
      PointerDownEvent(
        pointer: pointerValue,
        position: offset,
        pressure: 0.0,
        pressureMax: 6.0,
        pressureMin: 0.0,
      ),
    );

    await gesture.updateWithCustomEvent(
      PointerMoveEvent(
        pointer: pointerValue,
        position: textfieldStart + const Offset(150.0, 9.0),
        pressure: 0.5,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    // We expect the force press to select a word at the given location.
    expect(
      controller.selection,
      const TextSelection(baseOffset: 8, extentOffset: 12),
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoButton), isContextMenuProvidedByPlatform ? findsNothing : findsNWidgets(3));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS }));

  testWidgets('tap on non-force-press-supported devices work', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure',
    );
    await tester.pumpWidget(Container(key: GlobalKey()));
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
          ),
        ),
      ),
    );

    final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

    final int pointerValue = tester.nextPointer;
    final Offset offset = textfieldStart + const Offset(150.0, 9.0);
    final TestGesture gesture = await tester.createGesture();
    await gesture.downWithCustomEvent(
      offset,
      PointerDownEvent(
        pointer: pointerValue,
        position: offset,
        // iPhone 6 and below report 0 across the board.
        pressure: 0,
        pressureMax: 0,
        pressureMin: 0,
      ),
    );

    await gesture.updateWithCustomEvent(
      PointerMoveEvent(
        pointer: pointerValue,
        position: textfieldStart + const Offset(150.0, 9.0),
        pressure: 0.5,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await gesture.up();
    // The event should fallback to a normal tap and move the cursor.
    // Single taps selects the edge of the word.
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 8),
    );

    await tester.pump();
    // Single taps shouldn't trigger the toolbar.
    expect(find.byType(CupertinoButton), findsNothing);

    // TODO(gspencergoog): Add in TargetPlatform.macOS in the line below when we figure out what global state is leaking.
    // https://github.com/flutter/flutter/issues/43445
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('default TextField debugFillProperties', (WidgetTester tester) async {
    final DiagnosticPropertiesBuilder builder = DiagnosticPropertiesBuilder();

    const TextField().debugFillProperties(builder);

    final List<String> description = builder.properties
      .where((DiagnosticsNode node) => !node.isFiltered(DiagnosticLevel.info))
      .map((DiagnosticsNode node) => node.toString()).toList();

    expect(description, <String>[]);
  });

  testWidgets('TextField implements debugFillProperties', (WidgetTester tester) async {
    final DiagnosticPropertiesBuilder builder = DiagnosticPropertiesBuilder();

    // Not checking controller, inputFormatters, focusNode
    const TextField(
      decoration: InputDecoration(labelText: 'foo'),
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.none,
      style: TextStyle(color: Color(0xff00ff00)),
      textAlign: TextAlign.end,
      textDirection: TextDirection.ltr,
      autofocus: true,
      obscureText: false,
      autocorrect: false,
      maxLines: 10,
      maxLength: 100,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      enabled: false,
      cursorWidth: 1.0,
      cursorHeight: 1.0,
      cursorRadius: Radius.zero,
      cursorColor: Color(0xff00ff00),
      keyboardAppearance: Brightness.dark,
      scrollPadding: EdgeInsets.zero,
      scrollPhysics: ClampingScrollPhysics(),
      enableInteractiveSelection: false,
    ).debugFillProperties(builder);

    final List<String> description = builder.properties
      .where((DiagnosticsNode node) => !node.isFiltered(DiagnosticLevel.info))
      .map((DiagnosticsNode node) => node.toString()).toList();

    expect(description, <String>[
      'enabled: false',
      'decoration: InputDecoration(labelText: "foo")',
      'style: TextStyle(inherit: true, color: Color(0xff00ff00))',
      'autofocus: true',
      'autocorrect: false',
      'smartDashesType: disabled',
      'smartQuotesType: disabled',
      'maxLines: 10',
      'maxLength: 100',
      'maxLengthEnforcement: none',
      'textInputAction: done',
      'textAlign: end',
      'textDirection: ltr',
      'cursorWidth: 1.0',
      'cursorHeight: 1.0',
      'cursorRadius: Radius.circular(0.0)',
      'cursorColor: Color(0xff00ff00)',
      'keyboardAppearance: Brightness.dark',
      'scrollPadding: EdgeInsets.zero',
      'selection disabled',
      'scrollPhysics: ClampingScrollPhysics',
    ]);
  });

  testWidgets(
    'strut basic single line',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Material(
            child: Center(
              child: TextField(),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TextField)),
        // The TextField will be as tall as the decoration (24) plus the metrics
        // from the default TextStyle of the theme (16), or 40 altogether.
        // Because this is less than the kMinInteractiveDimension, it will be
        // increased to that value (48).
        const Size(800, kMinInteractiveDimension),
      );
    },
  );

  testWidgets(
    'strut TextStyle increases height',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Material(
            child: Center(
              child: TextField(
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TextField)),
        // Strut should inherit the TextStyle.fontSize by default and produce the
        // same height as if it were disabled.
        const Size(800, kMinInteractiveDimension), // Because 44 < 48.
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Material(
            child: Center(
              child: TextField(
                style: TextStyle(fontSize: 20),
                strutStyle: StrutStyle.disabled,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TextField)),
        // The height here should match the previous version with strut enabled.
        const Size(800, kMinInteractiveDimension), // Because 44 < 48.
      );
    },
  );

  testWidgets(
    'strut basic multi line',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Material(
            child: Center(
              child: TextField(
                maxLines: 6,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TextField)),
        // The height should be the input decoration (24) plus 6x the strut height (16).
        const Size(800, 120),
      );
    },
  );

  testWidgets(
    'strut no force small strut',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Material(
            child: Center(
              child: TextField(
                maxLines: 6,
                strutStyle: StrutStyle(
                  // The small strut is overtaken by the larger
                  // TextStyle fontSize.
                  fontSize: 5,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TextField)),
        // When the strut's height is smaller than TextStyle's and forceStrutHeight
        // is disabled, then the TextStyle takes precedence. Should be the same height
        // as 'strut basic multi line'.
        const Size(800, 120),
      );
    },
  );

  testWidgets(
    'strut no force large strut',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Material(
            child: Center(
              child: TextField(
                maxLines: 6,
                strutStyle: StrutStyle(
                  fontSize: 25,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TextField)),
        // When the strut's height is larger than TextStyle's and forceStrutHeight
        // is disabled, then the StrutStyle takes precedence.
        const Size(800, 174),
      );
    },

    // TODO(mdebbar): https://github.com/flutter/flutter/issues/32243
    skip: isBrowser,
  );

  testWidgets(
    'strut height override',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Material(
            child: Center(
              child: TextField(
                maxLines: 3,
                strutStyle: StrutStyle(
                  fontSize: 8,
                  forceStrutHeight: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TextField)),
        // The smaller font size of strut make the field shorter than normal.
        const Size(800, 48),
      );
    },

    // TODO(mdebbar): https://github.com/flutter/flutter/issues/32243
    skip: isBrowser,
  );

  testWidgets(
    'strut forces field taller',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Material(
            child: Center(
              child: TextField(
                maxLines: 3,
                style: TextStyle(fontSize: 10),
                strutStyle: StrutStyle(
                  fontSize: 18,
                  forceStrutHeight: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TextField)),
        // When the strut fontSize is larger than a provided TextStyle, the
        // the strut's height takes precedence.
        const Size(800, 78),
      );
    },

    // TODO(mdebbar): https://github.com/flutter/flutter/issues/32243
    skip: isBrowser,
  );

  testWidgets('Caret center position', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const SizedBox(
          width: 300.0,
          child: TextField(
            textAlign: TextAlign.center,
            decoration: null,
          ),
        ),
      ),
    );

    final RenderEditable editable = findRenderEditable(tester);

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();


    Offset topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 4)).topLeft,
    );
    expect(topLeft.dx, equals(431));

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 3)).topLeft,
    );
    expect(topLeft.dx, equals(415));

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 2)).topLeft,
    );
    expect(topLeft.dx, equals(399));

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 1)).topLeft,
    );
    expect(topLeft.dx, equals(383));
  });

  testWidgets('Caret indexes into trailing whitespace center align', (WidgetTester tester) async {
    await tester.pumpWidget(
      overlay(
        child: const SizedBox(
          width: 300.0,
          child: TextField(
            textAlign: TextAlign.center,
            decoration: null,
          ),
        ),
      ),
    );

    final RenderEditable editable = findRenderEditable(tester);

    await tester.enterText(find.byType(TextField), 'abcd    ');
    await tester.pump();

    Offset topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 7)).topLeft,
    );
    expect(topLeft.dx, equals(479));

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 8)).topLeft,
    );
    expect(topLeft.dx, equals(495));

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 4)).topLeft,
    );
    expect(topLeft.dx, equals(431));

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 3)).topLeft,
    );
    expect(topLeft.dx, equals(415)); // Should be same as equivalent in 'Caret center position'

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 2)).topLeft,
    );
    expect(topLeft.dx, equals(399)); // Should be same as equivalent in 'Caret center position'

    topLeft = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 1)).topLeft,
    );
    expect(topLeft.dx, equals(383)); // Should be same as equivalent in 'Caret center position'
  });

  testWidgets('selection handles are rendered and not faded away', (WidgetTester tester) async {
    const String testText = 'lorem ipsum';
    final TextEditingController controller = TextEditingController(text: testText);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
          ),
        ),
      ),
    );

    final EditableTextState state =
      tester.state<EditableTextState>(find.byType(EditableText));
    final RenderEditable renderEditable = state.renderEditable;

    await tester.tapAt(const Offset(20, 10));
    renderEditable.selectWord(cause: SelectionChangedCause.longPress);
    await tester.pumpAndSettle();

    final List<FadeTransition> transitions = find.descendant(
      of: find.byWidgetPredicate((Widget w) => '${w.runtimeType}' == '_TextSelectionHandleOverlay'),
      matching: find.byType(FadeTransition),
    ).evaluate().map((Element e) => e.widget).cast<FadeTransition>().toList();
    expect(transitions.length, 2);
    final FadeTransition left = transitions[0];
    final FadeTransition right = transitions[1];
    expect(left.opacity.value, equals(1.0));
    expect(right.opacity.value, equals(1.0));
  });

  testWidgets('iOS selection handles are rendered and not faded away', (WidgetTester tester) async {
    const String testText = 'lorem ipsum';
    final TextEditingController controller = TextEditingController(text: testText);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
          ),
        ),
      ),
    );

    final RenderEditable renderEditable =
      tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

    await tester.tapAt(const Offset(20, 10));
    renderEditable.selectWord(cause: SelectionChangedCause.longPress);
    await tester.pumpAndSettle();

    final List<FadeTransition> transitions =
      find.byType(FadeTransition).evaluate().map((Element e) => e.widget).cast<FadeTransition>().toList();
    expect(transitions.length, 2);
    final FadeTransition left = transitions[0];
    final FadeTransition right = transitions[1];

    expect(left.opacity.value, equals(1.0));
    expect(right.opacity.value, equals(1.0));
  }, variant: const TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.iOS,  TargetPlatform.macOS }));

  testWidgets('Tap shows handles but not toolbar', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'abc def ghi',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(controller: controller),
        ),
      ),
    );

    // Tap to trigger the text field.
    await tester.tap(find.byType(TextField));
    await tester.pump();

    final EditableTextState editableText = tester.state(find.byType(EditableText));
    expect(editableText.selectionOverlay!.handlesAreVisible, isTrue);
    expect(editableText.selectionOverlay!.toolbarIsVisible, isFalse);
  });

  testWidgets(
    'Tap in empty text field does not show handles nor toolbar',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: controller),
          ),
        ),
      );

      // Tap to trigger the text field.
      await tester.tap(find.byType(TextField));
      await tester.pump();

      final EditableTextState editableText = tester.state(find.byType(EditableText));
      expect(editableText.selectionOverlay!.handlesAreVisible, isFalse);
      expect(editableText.selectionOverlay!.toolbarIsVisible, isFalse);
    },
  );

  testWidgets('Long press shows handles and toolbar', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'abc def ghi',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(controller: controller),
        ),
      ),
    );

    // Long press to trigger the text field.
    await tester.longPress(find.byType(TextField));
    await tester.pump();

    final EditableTextState editableText = tester.state(find.byType(EditableText));
    expect(editableText.selectionOverlay!.handlesAreVisible, isTrue);
    expect(editableText.selectionOverlay!.toolbarIsVisible, isContextMenuProvidedByPlatform ? isFalse : isTrue);
  });

  testWidgets(
    'Long press in empty text field shows handles and toolbar',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: controller),
          ),
        ),
      );

      // Tap to trigger the text field.
      await tester.longPress(find.byType(TextField));
      await tester.pump();

      final EditableTextState editableText = tester.state(find.byType(EditableText));
      expect(editableText.selectionOverlay!.handlesAreVisible, isTrue);
      expect(editableText.selectionOverlay!.toolbarIsVisible, isContextMenuProvidedByPlatform ? isFalse : isTrue);
    },
  );

  testWidgets('Double tap shows handles and toolbar', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'abc def ghi',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(controller: controller),
        ),
      ),
    );

    // Double tap to trigger the text field.
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    final EditableTextState editableText = tester.state(find.byType(EditableText));
    expect(editableText.selectionOverlay!.handlesAreVisible, isTrue);
    expect(editableText.selectionOverlay!.toolbarIsVisible, isContextMenuProvidedByPlatform ? isFalse : isTrue);
  });

  testWidgets(
    'Double tap in empty text field shows toolbar but not handles',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: controller),
          ),
        ),
      );

      // Double tap to trigger the text field.
      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(TextField));
      await tester.pump();

      final EditableTextState editableText = tester.state(find.byType(EditableText));
      expect(editableText.selectionOverlay!.handlesAreVisible, isFalse);
      expect(editableText.selectionOverlay!.toolbarIsVisible, isContextMenuProvidedByPlatform ? isFalse : isTrue);
    },
  );

  testWidgets(
    'Mouse tap does not show handles nor toolbar',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'abc def ghi',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: controller),
          ),
        ),
      );

      // Long press to trigger the text field.
      final Offset textFieldPos = tester.getCenter(find.byType(TextField));
      final TestGesture gesture = await tester.startGesture(
        textFieldPos,
        pointer: 7,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final EditableTextState editableText = tester.state(find.byType(EditableText));
      expect(editableText.selectionOverlay!.toolbarIsVisible, isFalse);
      expect(editableText.selectionOverlay!.handlesAreVisible, isFalse);
    },
  );

  testWidgets(
    'Mouse long press does not show handles nor toolbar',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'abc def ghi',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: controller),
          ),
        ),
      );

      // Long press to trigger the text field.
      final Offset textFieldPos = tester.getCenter(find.byType(TextField));
      final TestGesture gesture = await tester.startGesture(
        textFieldPos,
        pointer: 7,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pump();

      final EditableTextState editableText = tester.state(find.byType(EditableText));
      expect(editableText.selectionOverlay!.toolbarIsVisible, isFalse);
      expect(editableText.selectionOverlay!.handlesAreVisible, isFalse);
    },
  );

  testWidgets(
    'Mouse double tap does not show handles nor toolbar',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'abc def ghi',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(controller: controller),
          ),
        ),
      );

      // Double tap to trigger the text field.
      final Offset textFieldPos = tester.getCenter(find.byType(TextField));
      final TestGesture gesture = await tester.startGesture(
        textFieldPos,
        pointer: 7,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();
      await gesture.down(textFieldPos);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final EditableTextState editableText = tester.state(find.byType(EditableText));
      expect(editableText.selectionOverlay!.toolbarIsVisible, isFalse);
      expect(editableText.selectionOverlay!.handlesAreVisible, isFalse);
    },
  );

  testWidgets('Does not show handles when updated from the web engine', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'abc def ghi',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(controller: controller),
        ),
      ),
    );

    // Interact with the text field to establish the input connection.
    final Offset topLeft = tester.getTopLeft(find.byType(EditableText));
    final TestGesture gesture = await tester.startGesture(
      topLeft + const Offset(0.0, 5.0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    final EditableTextState state = tester.state(find.byType(EditableText));
    expect(state.selectionOverlay!.handlesAreVisible, isFalse);
    expect(controller.selection, const TextSelection.collapsed(offset: 0));

    if (kIsWeb) {
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'abc def ghi',
        selection: TextSelection(baseOffset: 2, extentOffset: 7),
      ));
      // Wait for all the `setState` calls to be flushed.
      await tester.pumpAndSettle();
      expect(
        state.currentTextEditingValue.selection,
        const TextSelection(baseOffset: 2, extentOffset: 7),
      );
      expect(state.selectionOverlay!.handlesAreVisible, isFalse);
    }
  });

  testWidgets('Tapping selection handles toggles the toolbar', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'abc def ghi',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(controller: controller),
        ),
      ),
    );

    // Tap to position the cursor and show the selection handles.
    final Offset ePos = textOffsetToPosition(tester, 5); // Index of 'e'.
    await tester.tapAt(ePos, pointer: 7);
    await tester.pumpAndSettle();

    final EditableTextState editableText = tester.state(find.byType(EditableText));
    expect(editableText.selectionOverlay!.toolbarIsVisible, isFalse);
    expect(editableText.selectionOverlay!.handlesAreVisible, isTrue);

    final RenderEditable renderEditable = findRenderEditable(tester);
    final List<TextSelectionPoint> endpoints = globalize(
      renderEditable.getEndpointsForSelection(controller.selection),
      renderEditable,
    );
    expect(endpoints.length, 1);

    // Tap the handle to show the toolbar.
    final Offset handlePos = endpoints[0].point + const Offset(0.0, 1.0);
    await tester.tapAt(handlePos, pointer: 7);
    expect(editableText.selectionOverlay!.toolbarIsVisible, isContextMenuProvidedByPlatform ? isFalse : isTrue);

    // Tap the handle again to hide the toolbar.
    await tester.tapAt(handlePos, pointer: 7);
    expect(editableText.selectionOverlay!.toolbarIsVisible, isFalse);
  });

  testWidgets('when TextField would be blocked by keyboard, it is shown with enough space for the selection handle', (WidgetTester tester) async {
    final ScrollController scrollController = ScrollController();

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(),
      home: Scaffold(
        body: Center(
          child: ListView(
            controller: scrollController,
            children: <Widget>[
              Container(height: 579), // Push field almost off screen.
              const TextField(),
              Container(height: 1000),
            ],
          ),
        ),
      ),
    ));

    // Tap the TextField to put the cursor into it and bring it into view.
    expect(scrollController.offset, 0.0);
    await tester.tapAt(tester.getTopLeft(find.byType(TextField)));
    await tester.pumpAndSettle();

    // The ListView has scrolled to keep the TextField and cursor handle
    // visible.
    expect(scrollController.offset, 48.0);
  });

  // Regression test for https://github.com/flutter/flutter/issues/74566
  testWidgets('TextField and last input character are visible on the screen when the cursor is not shown', (WidgetTester tester) async {
    final ScrollController scrollController = ScrollController();
    final ScrollController textFieldScrollController = ScrollController();

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(),
      home: Scaffold(
        body: Center(
          child: ListView(
            controller: scrollController,
            children: <Widget>[
              Container(height: 579), // Push field almost off screen.
              TextField(
                scrollController: textFieldScrollController,
                showCursor: false,
              ),
              Container(height: 1000),
            ],
          ),
        ),
      ),
    ));

    // Tap the TextField to bring it into view.
    expect(scrollController.offset, 0.0);
    await tester.tapAt(tester.getTopLeft(find.byType(TextField)));
    await tester.pumpAndSettle();

    // The ListView has scrolled to keep the TextField visible.
    expect(scrollController.offset, 48.0);
    expect(textFieldScrollController.offset, 0.0);

    // After entering some long text, the last input character remains on the screen.
    final String testValue = 'I love Flutter!' * 10;
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: testValue,
      selection: TextSelection.collapsed(offset: testValue.length),
    ));
    await tester.pump();
    await tester.pumpAndSettle(); // Text scroll animation.

    expect(textFieldScrollController.offset, 1602.0);
  });

  group('height', () {
    testWidgets('By default, TextField is at least kMinInteractiveDimension high', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(),
        home: const Scaffold(
          body: Center(
            child: TextField(),
          ),
        ),
      ));

      final RenderBox renderBox = tester.renderObject(find.byType(TextField));
      expect(renderBox.size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    });

    testWidgets("When text is very small, TextField still doesn't go below kMinInteractiveDimension height", (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(),
        home: const Scaffold(
          body: Center(
            child: TextField(
              style: TextStyle(fontSize: 2.0),
            ),
          ),
        ),
      ));

      final RenderBox renderBox = tester.renderObject(find.byType(TextField));
      expect(renderBox.size.height, kMinInteractiveDimension);
    });

    testWidgets('When isDense, TextField can go below kMinInteractiveDimension height', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(),
        home: const Scaffold(
          body: Center(
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
              ),
            ),
          ),
        ),
      ));

      final RenderBox renderBox = tester.renderObject(find.byType(TextField));
      expect(renderBox.size.height, lessThan(kMinInteractiveDimension));
    });

    group('intrinsics', () {
      Widget _buildTest({ required bool isDense }) {
        return MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    children: <Widget>[
                      TextField(
                        decoration: InputDecoration(
                          isDense: isDense,
                        )
                      ),
                      Container(
                        height: 1000,
                      ),
                    ],
                  )
                )
              ],
            )
          )
        );
      }

      testWidgets('By default, intrinsic height is at least kMinInteractiveDimension high', (WidgetTester tester) async {
        // Regression test for https://github.com/flutter/flutter/issues/54729
        // If the intrinsic height does not match that of the height after
        // performLayout, this will fail.
        await tester.pumpWidget(_buildTest(isDense: false));
      });

      testWidgets('When isDense, intrinsic height can go below kMinInteractiveDimension height', (WidgetTester tester) async {
        // Regression test for https://github.com/flutter/flutter/issues/54729
        // If the intrinsic height does not match that of the height after
        // performLayout, this will fail.
        await tester.pumpWidget(_buildTest(isDense: true));
      });
    });
  });
  testWidgets("Arrow keys don't move input focus", (WidgetTester tester) async {
    final TextEditingController controller1 = TextEditingController();
    final TextEditingController controller2 = TextEditingController();
    final TextEditingController controller3 = TextEditingController();
    final TextEditingController controller4 = TextEditingController();
    final TextEditingController controller5 = TextEditingController();
    final FocusNode focusNode1 = FocusNode(debugLabel: 'Field 1');
    final FocusNode focusNode2 = FocusNode(debugLabel: 'Field 2');
    final FocusNode focusNode3 = FocusNode(debugLabel: 'Field 3');
    final FocusNode focusNode4 = FocusNode(debugLabel: 'Field 4');
    final FocusNode focusNode5 = FocusNode(debugLabel: 'Field 5');

    // Lay out text fields in a "+" formation, and focus the center one.
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 100.0,
                child: TextField(
                  controller: controller1,
                  focusNode: focusNode1,
                ),
              ),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 100.0,
                      child: TextField(
                        controller: controller2,
                        focusNode: focusNode2,
                      ),
                    ),
                    SizedBox(
                      width: 100.0,
                      child: TextField(
                        controller: controller3,
                        focusNode: focusNode3,
                      ),
                    ),
                    SizedBox(
                      width: 100.0,
                      child: TextField(
                        controller: controller4,
                        focusNode: focusNode4,
                      ),
                    ),
                  ],
                ),
              SizedBox(
                width: 100.0,
                child: TextField(
                  controller: controller5,
                  focusNode: focusNode5,
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    focusNode3.requestFocus();
    await tester.pump();
    expect(focusNode3.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusNode3.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusNode3.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focusNode3.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusNode3.hasPrimaryFocus, isTrue);
  });

  testWidgets('Scrolling shortcuts are disabled in text fields', (WidgetTester tester) async {
    bool scrollInvoked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Actions(
          actions: <Type, Action<Intent>>{
            ScrollIntent: CallbackAction<ScrollIntent>(onInvoke: (Intent intent) {
              scrollInvoked = true;
            }),
          },
          child: Material(
            child: ListView(
              children: const <Widget>[
                Padding(padding: EdgeInsets.symmetric(vertical: 200)),
                TextField(),
                Padding(padding: EdgeInsets.symmetric(vertical: 800)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(scrollInvoked, isFalse);

    // Set focus on the text field.
    await tester.tapAt(tester.getTopLeft(find.byType(TextField)));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(scrollInvoked, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(scrollInvoked, isFalse);
  });

  testWidgets("A buildCounter that returns null doesn't affect the size of the TextField", (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/44909

    final GlobalKey textField1Key = GlobalKey();
    final GlobalKey textField2Key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              TextField(key: textField1Key),
              TextField(
                key: textField2Key,
                maxLength: 1,
                buildCounter: (BuildContext context, {required int currentLength, required bool isFocused, int? maxLength}) => null,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final Size textFieldSize1 = tester.getSize(find.byKey(textField1Key));
    final Size textFieldSize2 = tester.getSize(find.byKey(textField2Key));

    expect(textFieldSize1, equals(textFieldSize2));
  });

  testWidgets(
    'The selection menu displays in an Overlay without error',
    (WidgetTester tester) async {
      // This is a regression test for
      // https://github.com/flutter/flutter/issues/43787
      final TextEditingController controller = TextEditingController(
        text: 'This is a test that shows some odd behavior with Text Selection!',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Container(
            color: Colors.grey,
            child: Center(
              child: Container(
                color: Colors.red,
                width: 300,
                height: 600,
                child: Overlay(
                  initialEntries: <OverlayEntry>[
                    OverlayEntry(
                      builder: (BuildContext context) => Center(
                        child: TextField(
                          controller: controller,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ));

      await _showSelectionMenuAt(tester, controller, controller.text.indexOf('test'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Web does not check the clipboard status', (WidgetTester tester) async {
    final TextEditingController controller = TextEditingController(
      text: 'Atwater Peel Sherbrooke Bonaventure',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: TextField(
              controller: controller,
            ),
          ),
        ),
      ),
    );

    bool triedToReadClipboard = false;
    SystemChannels.platform
      .setMockMethodCallHandler((MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          triedToReadClipboard = true;
        }
        return null;
      });

    final Offset textfieldStart = tester.getTopLeft(find.byType(TextField));

    // Double tap like when showing the text selection menu on Android/iOS.
    await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(textfieldStart + const Offset(150.0, 9.0));
    await tester.pump();

    if (kIsWeb) {
      // The clipboard is not checked because it requires user permissions and
      // web doesn't show a custom text selection menu.
      expect(triedToReadClipboard, false);
    } else {
      // The clipboard is checked in order to decide if the content can be
      // pasted.
      expect(triedToReadClipboard, true);
    }
  });

  testWidgets('TextField changes mouse cursor when hovered', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: MouseRegion(
            cursor: SystemMouseCursors.forbidden,
            child: TextField(
              mouseCursor: SystemMouseCursors.grab,
              decoration: InputDecoration(
                // Add an icon so that the left edge is not the text area
                icon: Icon(Icons.person),
              ),
            ),
          ),
        ),
      ),
    );

    // Center, which is within the text area
    final Offset center = tester.getCenter(find.byType(TextField));
    // Top left, which is not the text area
    final Offset edge = tester.getTopLeft(find.byType(TextField)) + const Offset(1, 1);

    final TestGesture gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);

    await tester.pump();

    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.grab);

    // Test default cursor
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: MouseRegion(
            cursor: SystemMouseCursors.forbidden,
            child: TextField(
              decoration: InputDecoration(
                icon: Icon(Icons.person),
              ),
            ),
          ),
        ),
      ),
    );

    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);
    await gesture.moveTo(edge);
    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);
    await gesture.moveTo(center);

    // Test default cursor when disabled
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: MouseRegion(
            cursor: SystemMouseCursors.forbidden,
            child: TextField(
              enabled: false,
              decoration: InputDecoration(
                icon: Icon(Icons.person),
              ),
            ),
          ),
        ),
      ),
    );

    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
    await gesture.moveTo(edge);
    expect(RendererBinding.instance!.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
    await gesture.moveTo(center);
  });

  testWidgets('Caret rtl with changing width', (WidgetTester tester) async {
    late StateSetter setState;
    bool isWide = false;
    const double wideWidth = 300.0;
    const double narrowWidth = 200.0;
    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(
      boilerplate(
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setter) {
            setState = setter;
            return SizedBox(
              width: isWide ? wideWidth : narrowWidth,
              child: TextField(
                key: textFieldKey,
                controller: controller,
                textDirection: TextDirection.rtl,
              ),
            );
          }
        ),
      ),
    );

    // The cursor is on the right of the input because it's RTL.
    RenderEditable editable = findRenderEditable(tester);
    double cursorRight = editable.getLocalRectForCaret(
      TextPosition(offset: controller.value.text.length),
    ).topRight.dx;
    double inputWidth = editable.size.width;
    expect(inputWidth, narrowWidth);
    expect(cursorRight, inputWidth - kCaretGap);

    // After entering some text, the cursor remains on the right of the input.
    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    editable = findRenderEditable(tester);
    cursorRight = editable.getLocalRectForCaret(
      TextPosition(offset: controller.value.text.length),
    ).topRight.dx;
    inputWidth = editable.size.width;
    expect(cursorRight, inputWidth - kCaretGap);

    // Since increasing the width of the input moves its right edge further to
    // the right, the cursor has followed this change and still appears on the
    // right of the input.
    setState(() {
      isWide = true;
    });
    await tester.pump();
    editable = findRenderEditable(tester);
    cursorRight = editable.getLocalRectForCaret(
      TextPosition(offset: controller.value.text.length),
    ).topRight.dx;
    inputWidth = editable.size.width;
    expect(inputWidth, wideWidth);
    expect(cursorRight, inputWidth - kCaretGap);

    // TODO(mdebbar): RTL support still has issues on the web.
    // https://github.com/flutter/flutter/projects/159
  }, skip: isBrowser);

  // Regressing test for https://github.com/flutter/flutter/issues/70625
  testWidgets('TextFields can inherit [FloatingLabelBehaviour] from InputDecorationTheme.', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    Widget textFieldBuilder({ FloatingLabelBehavior behavior = FloatingLabelBehavior.auto }) {
      return MaterialApp(
        theme: ThemeData(
          inputDecorationTheme: InputDecorationTheme(
            floatingLabelBehavior: behavior,
          ),
        ),
        home: Scaffold(
          body: TextField(
            focusNode: focusNode,
            decoration: const InputDecoration(
              labelText: 'Label',
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(textFieldBuilder(behavior: FloatingLabelBehavior.auto));
    // The label will be positioned within the content when unfocused.
    expect(tester.getTopLeft(find.text('Label')).dy, 20.0);

    focusNode.requestFocus();
    await tester.pumpAndSettle(); // label animation.
    // The label will float above the content when focused.
    expect(tester.getTopLeft(find.text('Label')).dy, 12.0);

    focusNode.unfocus();
    await tester.pumpAndSettle(); // label animation.

    await tester.pumpWidget(textFieldBuilder(behavior: FloatingLabelBehavior.never));
    await tester.pumpAndSettle(); // theme animation.
    // The label will be positioned within the content.
    expect(tester.getTopLeft(find.text('Label')).dy, 20.0);

    focusNode.requestFocus();
    await tester.pumpAndSettle(); // label animation.
    // The label will always be positioned within the content.
    expect(tester.getTopLeft(find.text('Label')).dy, 20.0);

    await tester.pumpWidget(textFieldBuilder(behavior: FloatingLabelBehavior.always));
    await tester.pumpAndSettle(); // theme animation.
    // The label will always float above the content.
    expect(tester.getTopLeft(find.text('Label')).dy, 12.0);

    focusNode.unfocus();
    await tester.pumpAndSettle(); // label animation.
    // The label will always float above the content.
    expect(tester.getTopLeft(find.text('Label')).dy, 12.0);
  });

  group('MaxLengthEnforcement', () {
    const int maxLength = 5;

    Future<void> setupWidget(
      WidgetTester tester,
      MaxLengthEnforcement? enforcement,
    ) async {
      final Widget widget = MaterialApp(
        home: Material(
          child: TextField(
            maxLength: maxLength,
            maxLengthEnforcement: enforcement,
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
    }

    testWidgets('using none enforcement.', (WidgetTester tester) async {
      const MaxLengthEnforcement enforcement = MaxLengthEnforcement.none;

      await setupWidget(tester, enforcement);

      final EditableTextState state = tester.state(find.byType(EditableText));

      state.updateEditingValue(const TextEditingValue(text: 'abc'));
      expect(state.currentTextEditingValue.text, 'abc');
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      state.updateEditingValue(const TextEditingValue(text: 'abcdef', composing: TextRange(start: 3, end: 6)));
      expect(state.currentTextEditingValue.text, 'abcdef');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 6));

      state.updateEditingValue(const TextEditingValue(text: 'abcdef'));
      expect(state.currentTextEditingValue.text, 'abcdef');
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });

    testWidgets('using enforced.', (WidgetTester tester) async {
      const MaxLengthEnforcement enforcement = MaxLengthEnforcement.enforced;

      await setupWidget(tester, enforcement);

      final EditableTextState state = tester.state(find.byType(EditableText));

      state.updateEditingValue(const TextEditingValue(text: 'abc'));
      expect(state.currentTextEditingValue.text, 'abc');
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      state.updateEditingValue(const TextEditingValue(text: 'abcde', composing: TextRange(start: 3, end: 5)));
      expect(state.currentTextEditingValue.text, 'abcde');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      state.updateEditingValue(const TextEditingValue(text: 'abcdef', composing: TextRange(start: 3, end: 6)));
      expect(state.currentTextEditingValue.text, 'abcde');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      state.updateEditingValue(const TextEditingValue(text: 'abcdef'));
      expect(state.currentTextEditingValue.text, 'abcde');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));
    });

    testWidgets('using truncateAfterCompositionEnds.', (WidgetTester tester) async {
      const MaxLengthEnforcement enforcement = MaxLengthEnforcement.truncateAfterCompositionEnds;

      await setupWidget(tester, enforcement);

      final EditableTextState state = tester.state(find.byType(EditableText));

      state.updateEditingValue(const TextEditingValue(text: 'abc'));
      expect(state.currentTextEditingValue.text, 'abc');
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      state.updateEditingValue(const TextEditingValue(text: 'abcde', composing: TextRange(start: 3, end: 5)));
      expect(state.currentTextEditingValue.text, 'abcde');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      state.updateEditingValue(const TextEditingValue(text: 'abcdef', composing: TextRange(start: 3, end: 6)));
      expect(state.currentTextEditingValue.text, 'abcdef');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 6));

      state.updateEditingValue(const TextEditingValue(text: 'abcdef'));
      expect(state.currentTextEditingValue.text, 'abcde');
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });

    testWidgets('using default behavior for different platforms.', (WidgetTester tester) async {
      await setupWidget(tester, null);

      final EditableTextState state = tester.state(find.byType(EditableText));

      state.updateEditingValue(const TextEditingValue(text: '侬好啊'));
      expect(state.currentTextEditingValue.text, '侬好啊');
      expect(state.currentTextEditingValue.composing, TextRange.empty);

      state.updateEditingValue(const TextEditingValue(text: '侬好啊旁友', composing: TextRange(start: 3, end: 5)));
      expect(state.currentTextEditingValue.text, '侬好啊旁友');
      expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));

      state.updateEditingValue(const TextEditingValue(text: '侬好啊旁友们', composing: TextRange(start: 3, end: 6)));
      if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.fuchsia
      ) {
        expect(state.currentTextEditingValue.text, '侬好啊旁友们');
        expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 6));
      } else {
        expect(state.currentTextEditingValue.text, '侬好啊旁友');
        expect(state.currentTextEditingValue.composing, const TextRange(start: 3, end: 5));
      }

      state.updateEditingValue(const TextEditingValue(text: '侬好啊旁友'));
      expect(state.currentTextEditingValue.text, '侬好啊旁友');
      expect(state.currentTextEditingValue.composing, TextRange.empty);
    });
  });
}
