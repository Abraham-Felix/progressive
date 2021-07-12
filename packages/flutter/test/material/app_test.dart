// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../rendering/mock_canvas.dart';

class StateMarker extends StatefulWidget {
  const StateMarker({ Key? key, this.child }) : super(key: key);

  final Widget? child;

  @override
  StateMarkerState createState() => StateMarkerState();
}

class StateMarkerState extends State<StateMarker> {
  late String marker;

  @override
  Widget build(BuildContext context) {
    if (widget.child != null)
      return widget.child!;
    return Container();
  }
}

void main() {
  testWidgets('Can nest apps', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MaterialApp(
          home: Text('Home sweet home'),
        ),
      ),
    );

    expect(find.text('Home sweet home'), findsOneWidget);
  });

  testWidgets('Focus handling', (WidgetTester tester) async {
    final FocusNode focusNode = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Center(
          child: TextField(focusNode: focusNode, autofocus: true),
        ),
      ),
    ));

    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('Can place app inside FocusScope', (WidgetTester tester) async {
    final FocusScopeNode focusScopeNode = FocusScopeNode();

    await tester.pumpWidget(FocusScope(
      autofocus: true,
      node: focusScopeNode,
      child: const MaterialApp(
        home: Text('Home'),
      ),
    ));

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Can show grid without losing sync', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StateMarker(),
      ),
    );

    final StateMarkerState state1 = tester.state(find.byType(StateMarker));
    state1.marker = 'original';

    await tester.pumpWidget(
      const MaterialApp(
        debugShowMaterialGrid: true,
        home: StateMarker(),
      ),
    );

    final StateMarkerState state2 = tester.state(find.byType(StateMarker));
    expect(state1, equals(state2));
    expect(state2.marker, equals('original'));
  });

  testWidgets('Do not rebuild page during a route transition', (WidgetTester tester) async {
    int buildCounter = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Material(
              child: ElevatedButton(
                child: const Text('X'),
                onPressed: () { Navigator.of(context).pushNamed('/next'); },
              ),
            );
          }
        ),
        routes: <String, WidgetBuilder>{
          '/next': (BuildContext context) {
            return Builder(
              builder: (BuildContext context) {
                ++buildCounter;
                return const Text('Y');
              },
            );
          },
        },
      ),
    );

    expect(buildCounter, 0);
    await tester.tap(find.text('X'));
    expect(buildCounter, 0);
    await tester.pump();
    expect(buildCounter, 1);
    await tester.pump(const Duration(milliseconds: 10));
    expect(buildCounter, 1);
    await tester.pump(const Duration(milliseconds: 10));
    expect(buildCounter, 1);
    await tester.pump(const Duration(milliseconds: 10));
    expect(buildCounter, 1);
    await tester.pump(const Duration(milliseconds: 10));
    expect(buildCounter, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(buildCounter, 1);
    expect(find.text('Y'), findsOneWidget);
  });

  testWidgets('Do rebuild the home page if it changes', (WidgetTester tester) async {
    int buildCounter = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            ++buildCounter;
            return const Text('A');
          }
        ),
      ),
    );
    expect(buildCounter, 1);
    expect(find.text('A'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            ++buildCounter;
            return const Text('B');
          }
        ),
      ),
    );
    expect(buildCounter, 2);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('Do not rebuild the home page if it does not actually change', (WidgetTester tester) async {
    int buildCounter = 0;
    final Widget home = Builder(
      builder: (BuildContext context) {
        ++buildCounter;
        return const Placeholder();
      }
    );
    await tester.pumpWidget(
      MaterialApp(
        home: home,
      ),
    );
    expect(buildCounter, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: home,
      ),
    );
    expect(buildCounter, 1);
  });

  testWidgets('Do rebuild pages that come from the routes table if the MaterialApp changes', (WidgetTester tester) async {
    int buildCounter = 0;
    final Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{
      '/': (BuildContext context) {
        ++buildCounter;
        return const Placeholder();
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        routes: routes,
      ),
    );
    expect(buildCounter, 1);
    await tester.pumpWidget(
      MaterialApp(
        routes: routes,
      ),
    );
    expect(buildCounter, 2);
  });

  testWidgets('Cannot pop the initial route', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Home')));

    expect(find.text('Home'), findsOneWidget);

    final NavigatorState navigator = tester.state(find.byType(Navigator));
    final bool result = await navigator.maybePop();

    expect(result, isFalse);

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Default initialRoute', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(routes: <String, WidgetBuilder>{
      '/': (BuildContext context) => const Text('route "/"'),
    }));

    expect(find.text('route "/"'), findsOneWidget);
  });

  testWidgets('One-step initial route', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/a',
        routes: <String, WidgetBuilder>{
          '/': (BuildContext context) => const Text('route "/"'),
          '/a': (BuildContext context) => const Text('route "/a"'),
          '/a/b': (BuildContext context) => const Text('route "/a/b"'),
          '/b': (BuildContext context) => const Text('route "/b"'),
        },
      ),
    );

    expect(find.text('route "/"', skipOffstage: false), findsOneWidget);
    expect(find.text('route "/a"'), findsOneWidget);
    expect(find.text('route "/a/b"', skipOffstage: false), findsNothing);
    expect(find.text('route "/b"', skipOffstage: false), findsNothing);
  });

  testWidgets('Return value from pop is correct', (WidgetTester tester) async {
    late Future<Object?> result;
    await tester.pumpWidget(
        MaterialApp(
          home: Builder(
              builder: (BuildContext context) {
                return Material(
                  child: ElevatedButton(
                      child: const Text('X'),
                      onPressed: () async {
                        result = Navigator.of(context).pushNamed<Object?>('/a');
                      },
                  ),
                );
              }
          ),
          routes: <String, WidgetBuilder>{
            '/a': (BuildContext context) {
              return Material(
                child: ElevatedButton(
                  child: const Text('Y'),
                  onPressed: () {
                    Navigator.of(context).pop('all done');
                  },
                ),
              );
            },
          },
        ),
    );
    await tester.tap(find.text('X'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Y'), findsOneWidget);
    await tester.tap(find.text('Y'));
    await tester.pump();

    expect(await result, equals('all done'));
  });

  testWidgets('Two-step initial route', (WidgetTester tester) async {
    final Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{
      '/': (BuildContext context) => const Text('route "/"'),
      '/a': (BuildContext context) => const Text('route "/a"'),
      '/a/b': (BuildContext context) => const Text('route "/a/b"'),
      '/b': (BuildContext context) => const Text('route "/b"'),
    };

    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/a/b',
        routes: routes,
      ),
    );
    expect(find.text('route "/"', skipOffstage: false), findsOneWidget);
    expect(find.text('route "/a"', skipOffstage: false), findsOneWidget);
    expect(find.text('route "/a/b"'), findsOneWidget);
    expect(find.text('route "/b"', skipOffstage: false), findsNothing);
  });

  testWidgets('Initial route with missing step', (WidgetTester tester) async {
    final Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{
      '/': (BuildContext context) => const Text('route "/"'),
      '/a': (BuildContext context) => const Text('route "/a"'),
      '/a/b': (BuildContext context) => const Text('route "/a/b"'),
      '/b': (BuildContext context) => const Text('route "/b"'),
    };

    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/a/b/c',
        routes: routes,
      ),
    );
    final dynamic exception = tester.takeException();
    expect(exception, isA<String>());
    expect(exception.startsWith('Could not navigate to initial route.'), isTrue);
    expect(find.text('route "/"'), findsOneWidget);
    expect(find.text('route "/a"'), findsNothing);
    expect(find.text('route "/a/b"'), findsNothing);
    expect(find.text('route "/b"'), findsNothing);
  });

  testWidgets('Make sure initialRoute is only used the first time', (WidgetTester tester) async {
    final Map<String, WidgetBuilder> routes = <String, WidgetBuilder>{
      '/': (BuildContext context) => const Text('route "/"'),
      '/a': (BuildContext context) => const Text('route "/a"'),
      '/b': (BuildContext context) => const Text('route "/b"'),
    };

    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/a',
        routes: routes,
      ),
    );
    expect(find.text('route "/"', skipOffstage: false), findsOneWidget);
    expect(find.text('route "/a"'), findsOneWidget);
    expect(find.text('route "/b"', skipOffstage: false), findsNothing);

    // changing initialRoute has no effect
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/b',
        routes: routes,
      ),
    );
    expect(find.text('route "/"', skipOffstage: false), findsOneWidget);
    expect(find.text('route "/a"'), findsOneWidget);
    expect(find.text('route "/b"', skipOffstage: false), findsNothing);

    // removing it has no effect
    await tester.pumpWidget(MaterialApp(routes: routes));
    expect(find.text('route "/"', skipOffstage: false), findsOneWidget);
    expect(find.text('route "/a"'), findsOneWidget);
    expect(find.text('route "/b"', skipOffstage: false), findsNothing);
  });

  testWidgets('onGenerateRoute / onUnknownRoute', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (RouteSettings settings) {
          log.add('onGenerateRoute ${settings.name}');
          return null;
        },
        onUnknownRoute: (RouteSettings settings) {
          log.add('onUnknownRoute ${settings.name}');
          return null;
        },
      ),
    );
    expect(tester.takeException(), isFlutterError);
    expect(log, <String>['onGenerateRoute /', 'onUnknownRoute /']);

    // Work-around for https://github.com/flutter/flutter/issues/65655.
    await tester.pumpWidget(Container());
    expect(tester.takeException(), isAssertionError);
  });

  testWidgets('MaterialApp with builder and no route information works.', (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/18904
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          return const SizedBox();
        },
      ),
    );
  });

  testWidgets("WidgetsApp don't rebuild routes when MediaQuery updates", (WidgetTester tester) async {
    // Regression test for https://github.com/flutter/flutter/issues/37878
    int routeBuildCount = 0;
    int dependentBuildCount = 0;

    await tester.pumpWidget(WidgetsApp(
      color: const Color.fromARGB(255, 255, 255, 255),
      onGenerateRoute: (_) {
        return PageRouteBuilder<void>(pageBuilder: (_, __, ___) {
          routeBuildCount++;
          return Builder(
            builder: (BuildContext context) {
              dependentBuildCount++;
              MediaQuery.of(context);
              return Container();
            },
          );
        });
      },
    ));

    expect(routeBuildCount, equals(1));
    expect(dependentBuildCount, equals(1));

    // didChangeMetrics
    tester.binding.window.physicalSizeTestValue = const Size(42, 42);
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

    await tester.pump();

    expect(routeBuildCount, equals(1));
    expect(dependentBuildCount, equals(2));

    // didChangeTextScaleFactor
    tester.binding.window.textScaleFactorTestValue = 42;
    addTearDown(tester.binding.window.clearTextScaleFactorTestValue);

    await tester.pump();

    expect(routeBuildCount, equals(1));
    expect(dependentBuildCount, equals(3));

    // didChangePlatformBrightness
    tester.binding.window.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.binding.window.clearPlatformBrightnessTestValue);

    await tester.pump();

    expect(routeBuildCount, equals(1));
    expect(dependentBuildCount, equals(4));

    // didChangeAccessibilityFeatures
    tester.binding.window.accessibilityFeaturesTestValue = MockAccessibilityFeature();
    addTearDown(tester.binding.window.clearAccessibilityFeaturesTestValue);

    await tester.pump();

    expect(routeBuildCount, equals(1));
    expect(dependentBuildCount, equals(5));
  });

  testWidgets('Can get text scale from media query', (WidgetTester tester) async {
    double? textScaleFactor;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder:(BuildContext context) {
        textScaleFactor = MediaQuery.of(context).textScaleFactor;
        return Container();
      }),
    ));
    expect(textScaleFactor, isNotNull);
    expect(textScaleFactor, equals(1.0));
  });

  testWidgets('MaterialApp.navigatorKey', (WidgetTester tester) async {
    final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      color: const Color(0xFF112233),
      home: const Placeholder(),
    ));
    expect(key.currentState, isA<NavigatorState>());
    await tester.pumpWidget(const MaterialApp(
      color: Color(0xFF112233),
      home: Placeholder(),
    ));
    expect(key.currentState, isNull);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      color: const Color(0xFF112233),
      home: const Placeholder(),
    ));
    expect(key.currentState, isA<NavigatorState>());
  });

  testWidgets('Has default material and cupertino localizations', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Column(
              children: <Widget>[
                Text(MaterialLocalizations.of(context).selectAllButtonLabel),
                Text(CupertinoLocalizations.of(context).selectAllButtonLabel),
              ],
            );
          },
        ),
      ),
    );

    // Default US "select all" text.
    expect(find.text('Select all'), findsOneWidget);
    // Default Cupertino US "select all" text.
    expect(find.text('Select All'), findsOneWidget);
  });

  testWidgets('MaterialApp uses regular theme when themeMode is light', (WidgetTester tester) async {
    // Mock the Window to explicitly report a light platformBrightness.
    tester.binding.window.platformBrightnessTestValue = Brightness.light;

    late ThemeData appliedTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
            brightness: Brightness.light
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(appliedTheme.brightness, Brightness.light);

    // Mock the Window to explicitly report a dark platformBrightness.
    tester.binding.window.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
            brightness: Brightness.light
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(appliedTheme.brightness, Brightness.light);
  });

  testWidgets('MaterialApp uses darkTheme when themeMode is dark', (WidgetTester tester) async {
    // Mock the Window to explicitly report a light platformBrightness.
    tester.binding.window.platformBrightnessTestValue = Brightness.light;

    late ThemeData appliedTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
            brightness: Brightness.light
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(appliedTheme.brightness, Brightness.dark);

    // Mock the Window to explicitly report a dark platformBrightness.
    tester.binding.window.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
            brightness: Brightness.light
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(appliedTheme.brightness, Brightness.dark);
  });

  testWidgets('MaterialApp uses regular theme when themeMode is system and platformBrightness is light', (WidgetTester tester) async {
    // Mock the Window to explicitly report a light platformBrightness.
    final TestWidgetsFlutterBinding binding = tester.binding;
    binding.window.platformBrightnessTestValue = Brightness.light;

    late ThemeData appliedTheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(appliedTheme.brightness, Brightness.light);
  });

  testWidgets('MaterialApp uses darkTheme when themeMode is system and platformBrightness is dark', (WidgetTester tester) async {
    // Mock the Window to explicitly report a dark platformBrightness.
    tester.binding.window.platformBrightnessTestValue = Brightness.dark;

    late ThemeData appliedTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
            brightness: Brightness.light
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(appliedTheme.brightness, Brightness.dark);
  });

  testWidgets('MaterialApp uses light theme when platformBrightness is dark but no dark theme is provided', (WidgetTester tester) async {
    // Mock the Window to explicitly report a dark platformBrightness.
    final TestWidgetsFlutterBinding binding = tester.binding;
    binding.window.platformBrightnessTestValue = Brightness.dark;

    late ThemeData appliedTheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light
        ),
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(appliedTheme.brightness, Brightness.light);
  });

  testWidgets('MaterialApp uses fallback light theme when platformBrightness is dark but no theme is provided at all', (WidgetTester tester) async {
    // Mock the Window to explicitly report a dark platformBrightness.
    final TestWidgetsFlutterBinding binding = tester.binding;
    binding.window.platformBrightnessTestValue = Brightness.dark;

    late ThemeData appliedTheme;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(appliedTheme.brightness, Brightness.light);
  });

  testWidgets('MaterialApp uses fallback light theme when platformBrightness is light and a dark theme is provided', (WidgetTester tester) async {
    // Mock the Window to explicitly report a dark platformBrightness.
    final TestWidgetsFlutterBinding binding = tester.binding;
    binding.window.platformBrightnessTestValue = Brightness.light;

    late ThemeData appliedTheme;

    await tester.pumpWidget(
      MaterialApp(
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(appliedTheme.brightness, Brightness.light);
  });

  testWidgets('MaterialApp uses dark theme when platformBrightness is dark', (WidgetTester tester) async {
    // Mock the Window to explicitly report a dark platformBrightness.
    final TestWidgetsFlutterBinding binding = tester.binding;
    binding.window.platformBrightnessTestValue = Brightness.dark;

    late ThemeData appliedTheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(appliedTheme.brightness, Brightness.dark);
  });

  testWidgets('MaterialApp uses high contrast theme when appropriate', (WidgetTester tester) async {
    tester.binding.window.platformBrightnessTestValue = Brightness.light;
    tester.binding.window.accessibilityFeaturesTestValue = MockAccessibilityFeature();

    late ThemeData appliedTheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          primaryColor: Colors.lightBlue,
        ),
        highContrastTheme: ThemeData(
          primaryColor: Colors.blue,
        ),
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(appliedTheme.primaryColor, Colors.blue);
    tester.binding.window.clearAccessibilityFeaturesTestValue();
  });

  testWidgets('MaterialApp uses high contrast dark theme when appropriate', (WidgetTester tester) async {
    tester.binding.window.platformBrightnessTestValue = Brightness.dark;
    tester.binding.window.accessibilityFeaturesTestValue = MockAccessibilityFeature();

    late ThemeData appliedTheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          primaryColor: Colors.lightBlue,
        ),
        darkTheme: ThemeData(
          primaryColor: Colors.lightGreen,
        ),
        highContrastTheme: ThemeData(
          primaryColor: Colors.blue,
        ),
        highContrastDarkTheme: ThemeData(
          primaryColor: Colors.green,
        ),
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(appliedTheme.primaryColor, Colors.green);
    tester.binding.window.clearAccessibilityFeaturesTestValue();
  });

  testWidgets('MaterialApp uses dark theme when no high contrast dark theme is provided', (WidgetTester tester) async {
    tester.binding.window.platformBrightnessTestValue = Brightness.dark;
    tester.binding.window.accessibilityFeaturesTestValue = MockAccessibilityFeature();

    late ThemeData appliedTheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          primaryColor: Colors.lightBlue,
        ),
        darkTheme: ThemeData(
          primaryColor: Colors.lightGreen,
        ),
        home: Builder(
          builder: (BuildContext context) {
            appliedTheme = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(appliedTheme.primaryColor, Colors.lightGreen);
    tester.binding.window.clearAccessibilityFeaturesTestValue();
    tester.binding.window.clearPlatformBrightnessTestValue();
  });

  testWidgets('MaterialApp switches themes when the Window platformBrightness changes.', (WidgetTester tester) async {
    // Mock the Window to explicitly report a light platformBrightness.
    final TestWidgetsFlutterBinding binding = tester.binding;
    binding.window.platformBrightnessTestValue = Brightness.light;

    ThemeData? themeBeforeBrightnessChange;
    ThemeData? themeAfterBrightnessChange;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
        ),
        home: Builder(
          builder: (BuildContext context) {
            if (themeBeforeBrightnessChange == null) {
              themeBeforeBrightnessChange = Theme.of(context);
            } else {
              themeAfterBrightnessChange = Theme.of(context);
            }
            return const SizedBox();
          },
        ),
      ),
    );

    // Switch the platformBrightness from light to dark and pump the widget tree
    // to process changes.
    binding.window.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    expect(themeBeforeBrightnessChange!.brightness, Brightness.light);
    expect(themeAfterBrightnessChange!.brightness, Brightness.dark);
  });

  testWidgets('MaterialApp provides default overscroll color', (WidgetTester tester) async {
    Future<void> slowDrag(WidgetTester tester, Offset start, Offset offset) async {
      final TestGesture gesture = await tester.startGesture(start);
      for (int index = 0; index < 10; index += 1) {
        await gesture.moveBy(offset);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
    }

    // The overscroll color should be a transparent version of the colorScheme's
    // secondary color.
    const Color secondaryColor = Color(0xff008800);
    final Color glowSecondaryColor = secondaryColor.withOpacity(0.05);
    final ThemeData theme = ThemeData.from(
      colorScheme: const ColorScheme.light().copyWith(secondary: secondaryColor),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const SingleChildScrollView(
          child: SizedBox(height: 2000.0),
        ),
      ),
    );

    final RenderObject painter = tester.renderObject(find.byType(CustomPaint).first);
    await slowDrag(tester, const Offset(200.0, 200.0), const Offset(0.0, 5.0));
    expect(painter, paints..circle(color: glowSecondaryColor));
  });

  testWidgets('MaterialApp can customize initial routes', (WidgetTester tester) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        onGenerateInitialRoutes: (String initialRoute) {
          expect(initialRoute, '/abc');
          return <Route<void>>[
            PageRouteBuilder<void>(
              pageBuilder: (
                BuildContext context,
                Animation<double> animation,
                Animation<double> secondaryAnimation) {
                return const Text('non-regular page one');
              }
            ),
            PageRouteBuilder<void>(
              pageBuilder: (
                BuildContext context,
                Animation<double> animation,
                Animation<double> secondaryAnimation) {
                return const Text('non-regular page two');
              }
            ),
          ];
        },
        initialRoute: '/abc',
        routes: <String, WidgetBuilder>{
          '/': (BuildContext context) => const Text('regular page one'),
          '/abc': (BuildContext context) => const Text('regular page two'),
        },
      )
    );
    expect(find.text('non-regular page two'), findsOneWidget);
    expect(find.text('non-regular page one'), findsNothing);
    expect(find.text('regular page one'), findsNothing);
    expect(find.text('regular page two'), findsNothing);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('non-regular page two'), findsNothing);
    expect(find.text('non-regular page one'), findsOneWidget);
    expect(find.text('regular page one'), findsNothing);
    expect(find.text('regular page two'), findsNothing);
  });

  testWidgets('MaterialApp does create HeroController with the MaterialRectArcTween', (WidgetTester tester) async {
    final HeroController controller = MaterialApp.createMaterialHeroController();
    final Tween<Rect?> tween = controller.createRectTween!(
      const Rect.fromLTRB(0.0, 0.0, 10.0, 10.0),
      const Rect.fromLTRB(0.0, 0.0, 20.0, 20.0)
    );
    expect(tween, isA<MaterialRectArcTween>());
  });

  testWidgets('MaterialApp.navigatorKey can be updated', (WidgetTester tester) async {
    final GlobalKey<NavigatorState> key1 = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key1,
      home: const Placeholder(),
    ));
    expect(key1.currentState, isA<NavigatorState>());
    final GlobalKey<NavigatorState> key2 = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key2,
      home: const Placeholder(),
    ));
    expect(key2.currentState, isA<NavigatorState>());
    expect(key1.currentState, isNull);
  });

  testWidgets('MaterialApp.router works', (WidgetTester tester) async {
    final PlatformRouteInformationProvider provider = PlatformRouteInformationProvider(
      initialRouteInformation: const RouteInformation(
        location: 'initial',
      ),
    );
    final SimpleNavigatorRouterDelegate delegate = SimpleNavigatorRouterDelegate(
      builder: (BuildContext context, RouteInformation information) {
        return Text(information.location!);
      },
      onPopPage: (Route<void> route, void result, SimpleNavigatorRouterDelegate delegate) {
        delegate.routeInformation = const RouteInformation(
          location: 'popped',
        );
        return route.didPop(result);
      }
    );
    await tester.pumpWidget(MaterialApp.router(
      routeInformationProvider: provider,
      routeInformationParser: SimpleRouteInformationParser(),
      routerDelegate: delegate,
    ));
    expect(find.text('initial'), findsOneWidget);

    // Simulate android back button intent.
    final ByteData message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
    await ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) { });
    await tester.pumpAndSettle();
    expect(find.text('popped'), findsOneWidget);
  });

  testWidgets('MaterialApp.builder can build app without a Navigator', (WidgetTester tester) async {
    Widget? builderChild;
    await tester.pumpWidget(MaterialApp(
      builder: (BuildContext context, Widget? child) {
        builderChild = child;
        return Container();
      },
    ));
    expect(builderChild, isNull);
  });

  testWidgets('MaterialApp has correct default ScrollBehavior', (WidgetTester tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            capturedContext = context;
            return const Placeholder();
          },
        ),
      ),
    );
    expect(ScrollConfiguration.of(capturedContext).runtimeType, MaterialScrollBehavior);
  });

  testWidgets('A ScrollBehavior can be set for MaterialApp', (WidgetTester tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const MockScrollBehavior(),
        home: Builder(
          builder: (BuildContext context) {
            capturedContext = context;
            return const Placeholder();
          },
        ),
      ),
    );
    final ScrollBehavior scrollBehavior = ScrollConfiguration.of(capturedContext);
    expect(scrollBehavior.runtimeType, MockScrollBehavior);
    expect(scrollBehavior.getScrollPhysics(capturedContext).runtimeType, NeverScrollableScrollPhysics);
  });
}

class MockScrollBehavior extends ScrollBehavior {
  const MockScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const NeverScrollableScrollPhysics();
}

class MockAccessibilityFeature implements AccessibilityFeatures {
  @override
  bool get accessibleNavigation => true;

  @override
  bool get boldText => true;

  @override
  bool get disableAnimations => true;

  @override
  bool get highContrast => true;

  @override
  bool get invertColors => true;

  @override
  bool get reduceMotion => true;
}

typedef SimpleRouterDelegateBuilder = Widget Function(BuildContext, RouteInformation);
typedef SimpleNavigatorRouterDelegatePopPage<T> = bool Function(Route<T> route, T result, SimpleNavigatorRouterDelegate delegate);

class SimpleRouteInformationParser extends RouteInformationParser<RouteInformation> {
  SimpleRouteInformationParser();

  @override
  Future<RouteInformation> parseRouteInformation(RouteInformation information) {
    return SynchronousFuture<RouteInformation>(information);
  }

  @override
  RouteInformation restoreRouteInformation(RouteInformation configuration) {
    return configuration;
  }
}

class SimpleNavigatorRouterDelegate extends RouterDelegate<RouteInformation> with PopNavigatorRouterDelegateMixin<RouteInformation>, ChangeNotifier {
  SimpleNavigatorRouterDelegate({
    required this.builder,
    required this.onPopPage,
  });

  @override
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  RouteInformation get routeInformation => _routeInformation;
  late RouteInformation _routeInformation;
  set routeInformation(RouteInformation newValue) {
    _routeInformation = newValue;
    notifyListeners();
  }

  SimpleRouterDelegateBuilder builder;
  SimpleNavigatorRouterDelegatePopPage<void> onPopPage;

  @override
  Future<void> setNewRoutePath(RouteInformation configuration) {
    _routeInformation = configuration;
    return SynchronousFuture<void>(null);
  }

  bool _handlePopPage(Route<void> route, void data) {
    return onPopPage(route, data, this);
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onPopPage: _handlePopPage,
      pages: <Page<void>>[
        // We need at least two pages for the pop to propagate through.
        // Otherwise, the navigator will bubble the pop to the system navigator.
        const MaterialPage<void>(
          child: Text('base'),
        ),
        MaterialPage<void>(
          key: ValueKey<String>(routeInformation.location!),
          child: builder(context, routeInformation),
        )
      ],
    );
  }
}
