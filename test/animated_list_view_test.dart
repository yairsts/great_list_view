import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
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
