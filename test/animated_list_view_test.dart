import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  for (final updates in <List<List<int>>>[
    [
      [1, 2, 3]
    ],
    [
      [1, 2, 3],
      [3, 2, 4],
      [4, 3]
    ],
    [
      [],
      [4, 5]
    ],
  ]) {
    testWidgets('applies $updates received before the first layout',
        (tester) async {
      final controller = AnimatedListController();
      await tester.pumpWidget(_GatedList(
          items: const [1, 2], controller: controller, layout: false));
      for (final items in updates) {
        await tester.pumpWidget(
            _GatedList(items: items, controller: controller, layout: false));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(_GatedList(
          items: updates.last, controller: controller, layout: true));
      // Measurement yields through timers before it can schedule animation frames.
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (updates.last.every((item) => find.text('$item').evaluate().isNotEmpty)) {
          break;
        }
      }
      await tester.pumpAndSettle();
      for (final item in updates.last) {
        expect(find.text('$item'), findsOneWidget);
      }
      for (var i = 0; i + 1 < updates.last.length; i++) {
        expect(
            tester.getTopLeft(find.text('${updates.last[i]}')).dy,
            lessThan(
                tester.getTopLeft(find.text('${updates.last[i + 1]}')).dy));
      }
      expect(find.byType(Text), findsNWidgets(updates.last.length));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('can dispose a list waiting for its first layout',
      (tester) async {
    final controller = AnimatedListController();
    await tester.pumpWidget(
        _GatedList(items: const [1, 2], controller: controller, layout: false));
    await tester.pumpWidget(_GatedList(
        items: const [1, 2, 3], controller: controller, layout: false));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('estimates an offset after rendered children are removed', (
    tester,
  ) async {
    final controller = AnimatedListController();

    Widget buildList(List<int> items) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 0,
              child: AutomaticAnimatedListView<int>(
                list: items,
                listController: controller,
                comparator: AnimatedListDiffListComparator<int>(
                  sameItem: (a, b) => a == b,
                  sameContent: (a, b) => a == b,
                ),
                itemBuilder: (context, item, data) => SizedBox(
                  height: 50,
                  child: Text('$item'),
                ),
                detectMoves: true,
                addLongPressReorderable: false,
              ),
            ),
          ),
        );

    await tester.pumpWidget(buildList([0, 1, 2]));
    final sliver = tester.renderObject<AnimatedRenderSliverList>(
      find.byType(AnimatedSliverList, skipOffstage: false),
    );
    final scrollExtent = sliver.geometry!.scrollExtent;
    sliver.removeAll(null);
    final estimate = sliver.estimateLayoutOffset(1, 3, null, null);
    expect(estimate.value, closeTo(scrollExtent / 3, 0.001));
    expect(estimate.estimated, isTrue);
  });

  testWidgets('keeps moved items in the new order', (tester) async {
    final controller = AnimatedListController();

    Widget buildList(List<int> items) => MaterialApp(
          home: Scaffold(
            body: AutomaticAnimatedListView<int>(
              list: items,
              listController: controller,
              comparator: AnimatedListDiffListComparator<int>(
                sameItem: (a, b) => a == b,
                sameContent: (a, b) => a == b,
              ),
              itemBuilder: (context, item, data) => SizedBox(
                height: 50,
                child: Text('$item'),
              ),
              detectMoves: true,
              addLongPressReorderable: false,
            ),
          ),
        );

    await tester.pumpWidget(buildList([1, 2, 3]));
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildList([3, 1, 2]));
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('3')).dy;
    final second = tester.getTopLeft(find.text('1')).dy;
    final third = tester.getTopLeft(find.text('2')).dy;
    expect(first, lessThan(second));
    expect(second, lessThan(third));
  });
}

bool _sameItem(int a, int b) => a == b;

class _GatedList extends StatelessWidget {
  const _GatedList(
      {required this.items, required this.controller, required this.layout});
  final List<int> items;
  final AnimatedListController controller;
  final bool layout;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: _LayoutGate(
          layout: layout,
          child: AutomaticAnimatedListView<int>(
            list: items,
            listController: controller,
            comparator: const AnimatedListDiffListComparator<int>(
                sameItem: _sameItem, sameContent: _sameItem),
            itemBuilder: (context, item, data) =>
                SizedBox(height: 50, child: Text('$item')),
            addLongPressReorderable: false,
          ),
        ),
      );
}

// Keeps the real list mounted while its parent has not laid it out yet.
class _LayoutGate extends SingleChildRenderObjectWidget {
  const _LayoutGate({required this.layout, required super.child});
  final bool layout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutGate(layout);

  @override
  void updateRenderObject(
      BuildContext context, _RenderLayoutGate renderObject) {
    renderObject.layoutChild = layout;
    renderObject.markNeedsLayout();
  }
}

class _RenderLayoutGate extends RenderProxyBox {
  _RenderLayoutGate(this.layoutChild);
  bool layoutChild;

  @override
  void performLayout() {
    if (layoutChild) {
      super.performLayout();
    } else {
      size = constraints.biggest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (layoutChild) super.paint(context, offset);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (layoutChild) super.visitChildrenForSemantics(visitor);
  }
}
