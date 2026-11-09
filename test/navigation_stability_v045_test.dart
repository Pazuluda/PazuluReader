import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/ui/shell.dart';

/// Navigation regression: a tab must be created only when visited, and must
/// keep its State while the user navigates quickly between tabs.
class _TrackedPage extends StatefulWidget {
  const _TrackedPage(this.id, this.created, this.disposed);
  final int id;
  final List<int> created;
  final List<int> disposed;

  @override
  State<_TrackedPage> createState() => _TrackedPageState();
}

class _TrackedPageState extends State<_TrackedPage> {
  @override
  void initState() {
    super.initState();
    widget.created.add(widget.id);
  }

  @override
  void dispose() {
    widget.disposed.add(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Text('Tab ${widget.id}', key: ValueKey('tab-${widget.id}')),
  );
}

void main() {
  testWidgets('Tabs are lazy and retain state across rapid switching', (tester) async {
    final created = <int>[];
    final disposed = <int>[];
    final pages = <Widget>[
      for (var i = 0; i < 5; i++) _TrackedPage(i, created, disposed),
    ];

    Future<void> show(int index) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LazyTabBody(
          activeIndex: index,
          pages: pages,
        )),
      ));
      await tester.pump(const Duration(milliseconds: 18));
      expect(tester.takeException(), isNull);
    }

    await show(0);
    expect(created, [0]);
    for (var i = 0; i < 40; i++) {
      await show(i.isEven ? 2 : 0);
    }
    expect(created, [0, 2]);
    expect(disposed, isEmpty);
    await show(4);
    expect(created, [0, 2, 4]);
    await show(1);
    await show(3);
    expect(created.toSet(), {0, 1, 2, 3, 4});
    expect(disposed, isEmpty);
  });

  testWidgets('Only the active tab has tickers enabled', (tester) async {
    const pages = <Widget>[
      Text('Accueil'), Text('Biblio'), Text('Decouvrir'),
    ];
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: LazyTabBody(activeIndex: 0, pages: pages),
    )));
    expect(tester.takeException(), isNull);
    final tickerModes = tester.widgetList<TickerMode>(find.byType(TickerMode));
    expect(tickerModes.any((mode) => mode.enabled), isTrue);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: LazyTabBody(activeIndex: 1, pages: pages),
    )));
    expect(tester.takeException(), isNull);
    expect(find.text('Biblio'), findsOneWidget);
  });
}
