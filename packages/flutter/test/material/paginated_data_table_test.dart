// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;

import 'data_table_test_utils.dart';

class TestDataSource extends DataTableSource {
  TestDataSource({
    this.allowSelection = false,
  });

  final bool allowSelection;

  int get generation => _generation;
  int _generation = 0;
  set generation(int value) {
    if (_generation == value)
      return;
    _generation = value;
    notifyListeners();
  }

  final Set<int> _selectedRows = <int>{};

  void _handleSelected(int index, bool? selected) {
    if (selected == true) {
      _selectedRows.add(index);
    } else {
      _selectedRows.remove(index);
    }
    notifyListeners();
  }

  @override
  DataRow getRow(int index) {
    final Dessert dessert = kDesserts[index % kDesserts.length];
    final int page = index ~/ kDesserts.length;
    return DataRow.byIndex(
      index: index,
      selected: _selectedRows.contains(index),
      cells: <DataCell>[
        DataCell(Text('${dessert.name} ($page)')),
        DataCell(Text('${dessert.calories}')),
        DataCell(Text('$generation')),
      ],
      onSelectChanged: allowSelection ? (bool? selected) => _handleSelected(index, selected) : null,
    );
  }

  @override
  int get rowCount => 50 * kDesserts.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => _selectedRows.length;
}

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized() as TestWidgetsFlutterBinding;

  testWidgets('PaginatedDataTable paging', (WidgetTester tester) async {
    final TestDataSource source = TestDataSource();

    final List<String> log = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: PaginatedDataTable(
        header: const Text('Test table'),
        source: source,
        rowsPerPage: 2,
        showFirstLastButtons: true,
        availableRowsPerPage: const <int>[
          2, 4, 8, 16,
        ],
        onRowsPerPageChanged: (int? rowsPerPage) {
          log.add('rows-per-page-changed: $rowsPerPage');
        },
        onPageChanged: (int rowIndex) {
          log.add('page-changed: $rowIndex');
        },
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Calories'), numeric: true),
          DataColumn(label: Text('Generation')),
        ],
      ),
    ));

    await tester.tap(find.byTooltip('Next page'));

    expect(log, <String>['page-changed: 2']);
    log.clear();

    await tester.pump();

    expect(find.text('Frozen yogurt (0)'), findsNothing);
    expect(find.text('Eclair (0)'), findsOneWidget);
    expect(find.text('Gingerbread (0)'), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_left));

    expect(log, <String>['page-changed: 0']);
    log.clear();

    await tester.pump();

    expect(find.text('Frozen yogurt (0)'), findsOneWidget);
    expect(find.text('Eclair (0)'), findsNothing);
    expect(find.text('Gingerbread (0)'), findsNothing);

    final Finder lastPageButton = find.ancestor(of: find.byTooltip('Last page'),
        matching: find.byWidgetPredicate((Widget widget) => widget is IconButton));

    expect(tester.widget<IconButton>(lastPageButton).onPressed, isNotNull);

    await tester.tap(lastPageButton);

    expect(log, <String>['page-changed: 498']);
    log.clear();

    await tester.pump();

    expect(tester.widget<IconButton>(lastPageButton).onPressed, isNull);

    expect(find.text('Frozen yogurt (0)'), findsNothing);
    expect(find.text('Donut (49)'), findsOneWidget);
    expect(find.text('KitKat (49)'), findsOneWidget);

    final Finder firstPageButton = find.ancestor(of: find.byTooltip('First page'),
        matching: find.byWidgetPredicate((Widget widget) => widget is IconButton));

    expect(tester.widget<IconButton>(firstPageButton).onPressed, isNotNull);

    await tester.tap(firstPageButton);

    expect(log, <String>['page-changed: 0']);
    log.clear();

    await tester.pump();

    expect(tester.widget<IconButton>(firstPageButton).onPressed, isNull);

    expect(find.text('Frozen yogurt (0)'), findsOneWidget);
    expect(find.text('Eclair (0)'), findsNothing);
    expect(find.text('Gingerbread (0)'), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_left));

    expect(log, isEmpty);

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    await tester.tap(find.text('8').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(log, <String>['rows-per-page-changed: 8']);
    log.clear();
  });

  testWidgets('PaginatedDataTable control test', (WidgetTester tester) async {
    TestDataSource source = TestDataSource()
      ..generation = 42;

    final List<String> log = <String>[];

    Widget buildTable(TestDataSource source) {
      return PaginatedDataTable(
        header: const Text('Test table'),
        source: source,
        onPageChanged: (int rowIndex) {
          log.add('page-changed: $rowIndex');
        },
        columns: <DataColumn>[
          const DataColumn(
            label: Text('Name'),
            tooltip: 'Name',
          ),
          DataColumn(
            label: const Text('Calories'),
            tooltip: 'Calories',
            numeric: true,
            onSort: (int columnIndex, bool ascending) {
              log.add('column-sort: $columnIndex $ascending');
            },
          ),
          const DataColumn(
            label: Text('Generation'),
            tooltip: 'Generation',
          ),
        ],
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.adjust),
            onPressed: () {
              log.add('action: adjust');
            },
          ),
        ],
      );
    }

    await tester.pumpWidget(MaterialApp(
      home: buildTable(source),
    ));

    // the column overflows because we're forcing it to 600 pixels high
    final dynamic exception = tester.takeException();
    expect(exception, isFlutterError);
    expect(exception.diagnostics.first.level, DiagnosticLevel.summary);
    expect(exception.diagnostics.first.toString(), startsWith('A RenderFlex overflowed by '));

    expect(find.text('Gingerbread (0)'), findsOneWidget);
    expect(find.text('Gingerbread (1)'), findsNothing);
    expect(find.text('42'), findsNWidgets(10));

    source.generation = 43;
    await tester.pump();

    expect(find.text('42'), findsNothing);
    expect(find.text('43'), findsNWidgets(10));

    source = TestDataSource()
      ..generation = 15;

    await tester.pumpWidget(MaterialApp(
      home: buildTable(source),
    ));

    expect(find.text('42'), findsNothing);
    expect(find.text('43'), findsNothing);
    expect(find.text('15'), findsNWidgets(10));

    final PaginatedDataTableState state = tester.state(find.byType(PaginatedDataTable));

    expect(log, isEmpty);
    state.pageTo(23);
    expect(log, <String>['page-changed: 20']);
    log.clear();

    await tester.pump();

    expect(find.text('Gingerbread (0)'), findsNothing);
    expect(find.text('Gingerbread (1)'), findsNothing);
    expect(find.text('Gingerbread (2)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.adjust));
    expect(log, <String>['action: adjust']);
    log.clear();
  });

  testWidgets('PaginatedDataTable text alignment', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PaginatedDataTable(
        header: const Text('HEADER'),
        source: TestDataSource(),
        rowsPerPage: 8,
        availableRowsPerPage: const <int>[
          8, 9,
        ],
        onRowsPerPageChanged: (int? rowsPerPage) { },
        columns: const <DataColumn>[
          DataColumn(label: Text('COL1')),
          DataColumn(label: Text('COL2')),
          DataColumn(label: Text('COL3')),
        ],
      ),
    ));
    expect(find.text('Rows per page:'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(tester.getTopRight(find.text('8')).dx, tester.getTopRight(find.text('Rows per page:')).dx + 40.0); // per spec
  });

  testWidgets('PaginatedDataTable with and without header and actions', (WidgetTester tester) async {
    await binding.setSurfaceSize(const Size(800, 800));
    const String headerText = 'HEADER';
    final List<Widget> actions = <Widget>[
      IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
    ];
    Widget buildTable({String? header, List<Widget>? actions}) => MaterialApp(
      home: PaginatedDataTable(
        header: header != null ? Text(header) : null,
        actions: actions,
        source: TestDataSource(allowSelection: true),
        showCheckboxColumn: true,
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Calories'), numeric: true),
          DataColumn(label: Text('Generation')),
        ],
      ),
    );

    await tester.pumpWidget(buildTable(header: headerText));
    expect(find.text(headerText), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);

    await tester.pumpWidget(buildTable(header: headerText, actions: actions));
    expect(find.text(headerText), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    await tester.pumpWidget(buildTable());
    expect(find.text(headerText), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);

    expect(() => buildTable(actions: actions), throwsAssertionError);

    await binding.setSurfaceSize(null);
  });

  testWidgets('PaginatedDataTable with large text', (WidgetTester tester) async {
    final TestDataSource source = TestDataSource();
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          textScaleFactor: 20.0,
        ),
        child: PaginatedDataTable(
          header: const Text('HEADER'),
          source: source,
          rowsPerPage: 501,
          availableRowsPerPage: const <int>[ 501 ],
          onRowsPerPageChanged: (int? rowsPerPage) { },
          columns: const <DataColumn>[
            DataColumn(label: Text('COL1')),
            DataColumn(label: Text('COL2')),
            DataColumn(label: Text('COL3')),
          ],
        ),
      ),
    ));
    // the column overflows because we're forcing it to 600 pixels high
    final dynamic exception = tester.takeException();
    expect(exception, isFlutterError);
    expect(exception.diagnostics.first.level, DiagnosticLevel.summary);
    expect(exception.diagnostics.first.toString(), contains('A RenderFlex overflowed by'));

    expect(find.text('Rows per page:'), findsOneWidget);
    // Test that we will show some options in the drop down even if the lowest option is bigger than the source:
    assert(501 > source.rowCount);
    expect(find.text('501'), findsOneWidget);
    // Test that it fits:
    expect(tester.getTopRight(find.text('501')).dx, greaterThanOrEqualTo(tester.getTopRight(find.text('Rows per page:')).dx + 40.0));
  }, skip: isBrowser);  // https://github.com/flutter/flutter/issues/43433

  testWidgets('PaginatedDataTable footer scrolls', (WidgetTester tester) async {
    final TestDataSource source = TestDataSource();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100.0,
            child: PaginatedDataTable(
              header: const Text('HEADER'),
              source: source,
              rowsPerPage: 5,
              dragStartBehavior: DragStartBehavior.down,
              availableRowsPerPage: const <int>[ 5 ],
              onRowsPerPageChanged: (int? rowsPerPage) { },
              columns: const <DataColumn>[
                DataColumn(label: Text('COL1')),
                DataColumn(label: Text('COL2')),
                DataColumn(label: Text('COL3')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Rows per page:'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Rows per page:')).dx, lessThan(0.0)); // off screen
    await tester.dragFrom(
      Offset(50.0, tester.getTopLeft(find.text('Rows per page:')).dy),
      const Offset(1000.0, 0.0),
    );
    await tester.pump();
    expect(find.text('Rows per page:'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Rows per page:')).dx, 18.0); // 14 padding in the footer row, 4 padding from the card
  });
  testWidgets('PaginatedDataTable custom row height', (WidgetTester tester) async {
    final TestDataSource source = TestDataSource();

    Widget buildCustomHeightPaginatedTable({
      double dataRowHeight = 48.0,
      double headingRowHeight = 56.0,
    }) {
      return PaginatedDataTable(
        header: const Text('Test table'),
        source: source,
        rowsPerPage: 2,
        availableRowsPerPage: const <int>[
          2, 4, 8, 16,
        ],
        onRowsPerPageChanged: (int? rowsPerPage) {},
        onPageChanged: (int rowIndex) {},
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Calories'), numeric: true),
          DataColumn(label: Text('Generation')),
        ],
        dataRowHeight: dataRowHeight,
        headingRowHeight: headingRowHeight,
      );
    }

    // DEFAULT VALUES
    await tester.pumpWidget(MaterialApp(
      home: PaginatedDataTable(
        header: const Text('Test table'),
        source: source,
        rowsPerPage: 2,
        availableRowsPerPage: const <int>[
          2, 4, 8, 16,
        ],
        onRowsPerPageChanged: (int? rowsPerPage) {},
        onPageChanged: (int rowIndex) {},
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Calories'), numeric: true),
          DataColumn(label: Text('Generation')),
        ],
      ),
    ));
    expect(tester.renderObject<RenderBox>(
      find.widgetWithText(Container, 'Name').first
    ).size.height, 56.0); // This is the header row height
    expect(tester.renderObject<RenderBox>(
      find.widgetWithText(Container, 'Frozen yogurt (0)').first
    ).size.height, 48.0); // This is the data row height

    // CUSTOM VALUES
    await tester.pumpWidget(MaterialApp(
      home: Material(child: buildCustomHeightPaginatedTable(headingRowHeight: 48.0)),
    ));
    expect(tester.renderObject<RenderBox>(
      find.widgetWithText(Container, 'Name').first
    ).size.height, 48.0);

    await tester.pumpWidget(MaterialApp(
      home: Material(child: buildCustomHeightPaginatedTable(headingRowHeight: 64.0)),
    ));
    expect(tester.renderObject<RenderBox>(
      find.widgetWithText(Container, 'Name').first
    ).size.height, 64.0);

    await tester.pumpWidget(MaterialApp(
      home: Material(child: buildCustomHeightPaginatedTable(dataRowHeight: 30.0)),
    ));
    expect(tester.renderObject<RenderBox>(
      find.widgetWithText(Container, 'Frozen yogurt (0)').first
    ).size.height, 30.0);

    await tester.pumpWidget(MaterialApp(
      home: Material(child: buildCustomHeightPaginatedTable(dataRowHeight: 56.0)),
    ));
    expect(tester.renderObject<RenderBox>(
      find.widgetWithText(Container, 'Frozen yogurt (0)').first
    ).size.height, 56.0);
  });

  testWidgets('PaginatedDataTable custom horizontal padding - checkbox', (WidgetTester tester) async {
    const double _defaultHorizontalMargin = 24.0;
    const double _defaultColumnSpacing = 56.0;
    const double _customHorizontalMargin = 10.0;
    const double _customColumnSpacing = 15.0;

    const double _width = 400;
    const double _height = 400;

    final Size originalSize = binding.renderView.size;

    // Ensure the containing Card is small enough that we don't expand too
    // much, resulting in our custom margin being ignored.
    await binding.setSurfaceSize(const Size(_width, _height));

    final TestDataSource source = TestDataSource(allowSelection: true);
    Finder cellContent;
    Finder checkbox;
    Finder padding;

    await tester.pumpWidget(MaterialApp(
      home: PaginatedDataTable(
        header: const Text('Test table'),
        source: source,
        rowsPerPage: 2,
        availableRowsPerPage: const <int>[
          2, 4,
        ],
        onRowsPerPageChanged: (int? rowsPerPage) {},
        onPageChanged: (int rowIndex) {},
        onSelectAll: (bool? value) {},
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Calories'), numeric: true),
          DataColumn(label: Text('Generation')),
        ],
      ),
    ));

    // default checkbox padding
    checkbox = find.byType(Checkbox).first;
    padding = find.ancestor(of: checkbox, matching: find.byType(Padding)).first;
    expect(
      tester.getRect(checkbox).left - tester.getRect(padding).left,
      _defaultHorizontalMargin,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(checkbox).right,
      _defaultHorizontalMargin / 2,
    );

    // default first column padding
    padding = find.widgetWithText(Padding, 'Frozen yogurt (0)').first;
    cellContent = find.widgetWithText(Align, 'Frozen yogurt (0)'); // DataTable wraps its DataCells in an Align widget
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _defaultHorizontalMargin / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _defaultColumnSpacing / 2,
    );

    // default middle column padding
    padding = find.widgetWithText(Padding, '159').first;
    cellContent = find.widgetWithText(Align, '159');
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _defaultColumnSpacing / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _defaultColumnSpacing / 2,
    );

    // default last column padding
    padding = find.widgetWithText(Padding, '0').first;
    cellContent = find.widgetWithText(Align, '0').first;
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _defaultColumnSpacing / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _defaultHorizontalMargin,
    );

    // CUSTOM VALUES
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: PaginatedDataTable(
          header: const Text('Test table'),
          source: source,
          rowsPerPage: 2,
          availableRowsPerPage: const <int>[
            2, 4,
          ],
          onRowsPerPageChanged: (int? rowsPerPage) {},
          onPageChanged: (int rowIndex) {},
          onSelectAll: (bool? value) {},
          columns: const <DataColumn>[
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Calories'), numeric: true),
            DataColumn(label: Text('Generation')),
          ],
          horizontalMargin: _customHorizontalMargin,
          columnSpacing: _customColumnSpacing,
        ),
      ),
    ));

    // custom checkbox padding
    checkbox = find.byType(Checkbox).first;
    padding = find.ancestor(of: checkbox, matching: find.byType(Padding)).first;
    expect(
      tester.getRect(checkbox).left - tester.getRect(padding).left,
      _customHorizontalMargin,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(checkbox).right,
      _customHorizontalMargin / 2,
    );

    // custom first column padding
    padding = find.widgetWithText(Padding, 'Frozen yogurt (0)').first;
    cellContent = find.widgetWithText(Align, 'Frozen yogurt (0)'); // DataTable wraps its DataCells in an Align widget
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _customHorizontalMargin / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _customColumnSpacing / 2,
    );

    // custom middle column padding
    padding = find.widgetWithText(Padding, '159').first;
    cellContent = find.widgetWithText(Align, '159');
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _customColumnSpacing / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _customColumnSpacing / 2,
    );

    // custom last column padding
    padding = find.widgetWithText(Padding, '0').first;
    cellContent = find.widgetWithText(Align, '0').first;
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _customColumnSpacing / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _customHorizontalMargin,
    );

    // Reset the surface size.
    await binding.setSurfaceSize(originalSize);
  });

  testWidgets('PaginatedDataTable custom horizontal padding - no checkbox', (WidgetTester tester) async {
    const double _defaultHorizontalMargin = 24.0;
    const double _defaultColumnSpacing = 56.0;
    const double _customHorizontalMargin = 10.0;
    const double _customColumnSpacing = 15.0;
    final TestDataSource source = TestDataSource();
    Finder cellContent;
    Finder padding;

    await tester.pumpWidget(MaterialApp(
      home: PaginatedDataTable(
        header: const Text('Test table'),
        source: source,
        rowsPerPage: 2,
        availableRowsPerPage: const <int>[
          2, 4, 8, 16,
        ],
        onRowsPerPageChanged: (int? rowsPerPage) {},
        onPageChanged: (int rowIndex) {},
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Calories'), numeric: true),
          DataColumn(label: Text('Generation')),
        ],
      ),
    ));

    // default first column padding
    padding = find.widgetWithText(Padding, 'Frozen yogurt (0)').first;
    cellContent = find.widgetWithText(Align, 'Frozen yogurt (0)'); // DataTable wraps its DataCells in an Align widget
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _defaultHorizontalMargin,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _defaultColumnSpacing / 2,
    );

    // default middle column padding
    padding = find.widgetWithText(Padding, '159').first;
    cellContent = find.widgetWithText(Align, '159');
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _defaultColumnSpacing / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _defaultColumnSpacing / 2,
    );

    // default last column padding
    padding = find.widgetWithText(Padding, '0').first;
    cellContent = find.widgetWithText(Align, '0').first;
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _defaultColumnSpacing / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _defaultHorizontalMargin,
    );

    // CUSTOM VALUES
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: PaginatedDataTable(
          header: const Text('Test table'),
          source: source,
          rowsPerPage: 2,
          availableRowsPerPage: const <int>[
            2, 4, 8, 16,
          ],
          onRowsPerPageChanged: (int? rowsPerPage) {},
          onPageChanged: (int rowIndex) {},
          columns: const <DataColumn>[
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Calories'), numeric: true),
            DataColumn(label: Text('Generation')),
          ],
          horizontalMargin: _customHorizontalMargin,
          columnSpacing: _customColumnSpacing,
        ),
      ),
    ));

    // custom first column padding
    padding = find.widgetWithText(Padding, 'Frozen yogurt (0)').first;
    cellContent = find.widgetWithText(Align, 'Frozen yogurt (0)');
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _customHorizontalMargin,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _customColumnSpacing / 2,
    );

    // custom middle column padding
    padding = find.widgetWithText(Padding, '159').first;
    cellContent = find.widgetWithText(Align, '159');
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _customColumnSpacing / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _customColumnSpacing / 2,
    );

    // custom last column padding
    padding = find.widgetWithText(Padding, '0').first;
    cellContent = find.widgetWithText(Align, '0').first;
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _customColumnSpacing / 2,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(cellContent).right,
      _customHorizontalMargin,
    );
  });

  testWidgets('PaginatedDataTable table fills Card width', (WidgetTester tester) async {
    final TestDataSource source = TestDataSource();

    // Note: 800 is wide enough to ensure that all of the columns fit in the
    // Card. The DataTable can be larger than its containing Card, but this test
    // is only concerned with ensuring the DataTable is at least as wide as the
    // Card.
    const double _originalWidth = 800;
    const double _expandedWidth = 1600;
    const double _height = 400;

    final Size originalSize = binding.renderView.size;

    Widget buildWidget() => MaterialApp(
      home: PaginatedDataTable(
        header: const Text('Test table'),
        source: source,
        rowsPerPage: 2,
        availableRowsPerPage: const <int>[
          2, 4, 8, 16,
        ],
        onRowsPerPageChanged: (int? rowsPerPage) {},
        onPageChanged: (int rowIndex) {},
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Calories'), numeric: true),
          DataColumn(label: Text('Generation')),
        ],
      ),
    );

    await binding.setSurfaceSize(const Size(_originalWidth, _height));
    await tester.pumpWidget(buildWidget());

    // Widths should be equal before we resize...
    expect(
      tester.renderObject<RenderBox>(find.byType(DataTable).first).size.width,
      moreOrLessEquals(
        tester.renderObject<RenderBox>(find.byType(Card).first).size.width)
    );

    await binding.setSurfaceSize(const Size(_expandedWidth, _height));
    await tester.pumpWidget(buildWidget());

    final double cardWidth = tester.renderObject<RenderBox>(find.byType(Card).first).size.width;

    // ... and should still be equal after the resize.
    expect(
      tester.renderObject<RenderBox>(find.byType(DataTable).first).size.width,
      moreOrLessEquals(cardWidth)
    );

    // Double check to ensure we actually resized the surface properly.
    expect(cardWidth, moreOrLessEquals(_expandedWidth));

    // Reset the surface size.
    await binding.setSurfaceSize(originalSize);
  });

  testWidgets('PaginatedDataTable with optional column checkbox', (WidgetTester tester) async {
    await binding.setSurfaceSize(const Size(800, 800));

    Widget buildTable(bool checkbox) => MaterialApp(
      home: PaginatedDataTable(
        header: const Text('Test table'),
        source: TestDataSource(allowSelection: true),
        showCheckboxColumn: checkbox,
        columns: const <DataColumn>[
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Calories'), numeric: true),
          DataColumn(label: Text('Generation')),
        ],
      ),
    );

    await tester.pumpWidget(buildTable(true));
    expect(find.byType(Checkbox), findsNWidgets(11));

    await tester.pumpWidget(buildTable(false));
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('Table should not use decoration from DataTableTheme', (WidgetTester tester) async {
    final Size originalSize = binding.renderView.size;
    await binding.setSurfaceSize(const Size(800, 800));

    Widget buildTable() {
      return MaterialApp(
        theme: ThemeData.light().copyWith(
            dataTableTheme: const DataTableThemeData(
              decoration: BoxDecoration(color: Colors.white),
            ),
        ),
        home: PaginatedDataTable(
          header: const Text('Test table'),
          source: TestDataSource(allowSelection: true),
          showCheckboxColumn: true,
          columns: const <DataColumn>[
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Calories'), numeric: true),
            DataColumn(label: Text('Generation')),
          ],
        ),
      );
    }

    await tester.pumpWidget(buildTable());
    final Finder tableContainerFinder = find.ancestor(of: find.byType(Table), matching: find.byType(Container)).first;
    expect(tester.widget<Container>(tableContainerFinder).decoration, const BoxDecoration());

    // Reset the surface size.
    await binding.setSurfaceSize(originalSize);
  });

  testWidgets('PaginatedDataTable custom checkboxHorizontalMargin properly applied', (WidgetTester tester) async {
    const double _customCheckboxHorizontalMargin = 15.0;
    const double _customHorizontalMargin = 10.0;

    const double _width = 400;
    const double _height = 400;

    final Size originalSize = binding.renderView.size;

    // Ensure the containing Card is small enough that we don't expand too
    // much, resulting in our custom margin being ignored.
    await binding.setSurfaceSize(const Size(_width, _height));

    final TestDataSource source = TestDataSource(allowSelection: true);
    Finder cellContent;
    Finder checkbox;
    Finder padding;

    // CUSTOM VALUES
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: PaginatedDataTable(
          header: const Text('Test table'),
          source: source,
          rowsPerPage: 2,
          availableRowsPerPage: const <int>[
            2, 4,
          ],
          onRowsPerPageChanged: (int? rowsPerPage) {},
          onPageChanged: (int rowIndex) {},
          onSelectAll: (bool? value) {},
          columns: const <DataColumn>[
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Calories'), numeric: true),
            DataColumn(label: Text('Generation')),
          ],
          horizontalMargin: _customHorizontalMargin,
          checkboxHorizontalMargin: _customCheckboxHorizontalMargin,
        ),
      ),
    ));

    // Custom checkbox padding.
    checkbox = find.byType(Checkbox).first;
    padding = find.ancestor(of: checkbox, matching: find.byType(Padding)).first;
    expect(
      tester.getRect(checkbox).left - tester.getRect(padding).left,
      _customCheckboxHorizontalMargin,
    );
    expect(
      tester.getRect(padding).right - tester.getRect(checkbox).right,
      _customCheckboxHorizontalMargin,
    );

    // Custom first column padding.
    padding = find.widgetWithText(Padding, 'Frozen yogurt (0)').first;
    cellContent = find.widgetWithText(Align, 'Frozen yogurt (0)'); // DataTable wraps its DataCells in an Align widget.
    expect(
      tester.getRect(cellContent).left - tester.getRect(padding).left,
      _customHorizontalMargin,
    );

    // Reset the surface size.
    await binding.setSurfaceSize(originalSize);
  });

  testWidgets('Items selected text uses secondary color', (WidgetTester tester) async {
    const Color selectedTextColor = Color(0xff00ddff);
    final ColorScheme colors = const ColorScheme.light().copyWith(secondary: selectedTextColor);
    final ThemeData theme = ThemeData.from(colorScheme: colors);

    Widget buildTable() {
      return MaterialApp(
        theme: theme,
        home: PaginatedDataTable(
          header: const Text('Test table'),
          source: TestDataSource(allowSelection: true),
          columns: const <DataColumn>[
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Calories'), numeric: true),
            DataColumn(label: Text('Generation')),
          ],
        ),
      );
    }

    await binding.setSurfaceSize(const Size(800, 800));
    await tester.pumpWidget(buildTable());
    expect(find.text('Test table'), findsOneWidget);

    // Select a row with yogurt
    await tester.tap(find.text('Frozen yogurt (0)'));
    await tester.pumpAndSettle();

    // The header should be replace with a selected text item
    expect(find.text('Test table'), findsNothing);
    expect(find.text('1 item selected'), findsOneWidget);

    // The color of the selected text item should be the colorScheme.secondary
    final TextStyle selectedTextStyle = tester.renderObject<RenderParagraph>(find.text('1 item selected')).text.style!;
    expect(selectedTextStyle.color, equals(selectedTextColor));

    await binding.setSurfaceSize(null);
  });
}
