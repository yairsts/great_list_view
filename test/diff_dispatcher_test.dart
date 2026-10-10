import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:great_list_view/great_list_view.dart';

class _RecordingController extends AnimatedListController {
  final List<String> updates = [];

  @override
  void batch(VoidCallback callback) => callback();

  @override
  void notifyInsertedRange(int from, int count) =>
      updates.add('insert:$from:$count');

  @override
  void notifyRemovedRange(int from, int count, AnimatedWidgetBuilder builder) =>
      updates.add('remove:$from:$count');

  @override
  void notifyChangedRange(int from, int count, AnimatedWidgetBuilder builder) =>
      updates.add('change:$from:$count');

  @override
  void notifyReplacedRange(int from, int removeCount, int insertCount,
          AnimatedWidgetBuilder builder) =>
      updates.add('replace:$from:$removeCount:$insertCount');

  @override
  void notifyMovedRange(int from, int count, int newIndex) =>
      updates.add('move:$from:$count:$newIndex');
}

Widget _buildItem(
        BuildContext context, int item, AnimatedWidgetBuilderData data) =>
    const SizedBox.shrink();

bool _sameItem(int a, int b) => a == b;

bool _brokenComparator(int a, int b) => throw StateError('comparison failed');

class _NotifyingComparator extends AnimatedListDiffListBaseComparator<int> {
  const _NotifyingComparator(this.started);
  final SendPort started;

  @override
  bool sameItem(int a, int b) {
    if (b == 4) {
      started.send('failed');
      throw StateError('cancelled comparison failed');
    }
    return a == b;
  }

  @override
  bool sameContent(int a, int b) => a == b;
}

AnimatedListDiffListDispatcher<int> _dispatcher(
  _RecordingController controller, {
  int threshold = 0,
  bool Function(int, int) sameItem = _sameItem,
}) =>
    AnimatedListDiffListDispatcher<int>(
      controller: controller,
      currentList: [1, 2, 3],
      itemBuilder: _buildItem,
      comparator: AnimatedListDiffListComparator<int>(
        sameItem: sameItem,
        sameContent: _sameItem,
      ),
      spawnNewInsolateCount: threshold,
    );

void main() {
  test('background diff applies insertions and keeps the latest list',
      () async {
    final controller = _RecordingController();
    final dispatcher = _dispatcher(controller);
    await dispatcher.dispatchNewList([1, 2, 3, 4]);
    expect(dispatcher.currentList, [1, 2, 3, 4]);
    expect(dispatcher.hasPendingTask, isFalse);
    expect(controller.updates, ['insert:3:1']);
  });

  test('cancelled diffs settle and only the latest update is applied',
      () async {
    final controller = _RecordingController();
    final dispatcher = _dispatcher(controller);
    final first = dispatcher.dispatchNewList([1, 2, 3, 4]);
    final second = dispatcher.dispatchNewList([1, 2, 3, 5]);
    final latest = dispatcher.dispatchNewList([1, 2, 3, 6]);

    await Future.wait([first, second, latest])
        .timeout(const Duration(seconds: 5));
    expect(dispatcher.currentList, [1, 2, 3, 6]);
    expect(dispatcher.hasPendingTask, isFalse);
    expect(controller.updates, ['insert:3:1']);

    // A later update must still work after the cancelled tasks have settled.
    await dispatcher.dispatchNewList([1, 2, 3]);
    expect(dispatcher.currentList, [1, 2, 3]);
    expect(controller.updates, ['insert:3:1', 'remove:3:1']);
  });

  test('discard cancels pending work without applying its result', () async {
    final controller = _RecordingController();
    final dispatcher = _dispatcher(controller);
    final discarded = [1, 2, 3, 4];
    final pending = dispatcher.dispatchNewList(discarded);
    expect(dispatcher.discard(), same(discarded));
    await pending.timeout(const Duration(seconds: 5));
    expect(dispatcher.currentList, [1, 2, 3]);
    expect(dispatcher.hasPendingTask, isFalse);
    expect(controller.updates, isEmpty);
  });

  test('late errors from a cancelled isolate do not break the next update',
      () async {
    final started = ReceivePort();
    addTearDown(started.close);
    final controller = _RecordingController();
    final dispatcher = AnimatedListDiffListDispatcher<int>(
      controller: controller,
      currentList: [1, 2, 3],
      itemBuilder: _buildItem,
      comparator: _NotifyingComparator(started.sendPort),
      spawnNewInsolateCount: 0,
    );
    final cancelled = dispatcher.dispatchNewList([4]);
    final latest = dispatcher.dispatchNewList([1, 2, 3, 5]);
    await started.first.timeout(const Duration(seconds: 5));
    await Future.wait([cancelled, latest]).timeout(const Duration(seconds: 5));
    expect(dispatcher.currentList, [1, 2, 3, 5]);
    expect(dispatcher.hasPendingTask, isFalse);
    expect(controller.updates, ['insert:3:1']);
  });

  test('background failures reach the caller and a later update recovers',
      () async {
    final controller = _RecordingController();
    final dispatcher = _dispatcher(controller, sameItem: _brokenComparator);
    await expectLater(dispatcher.dispatchNewList([4]), throwsStateError);
    expect(dispatcher.currentList, [1, 2, 3]);
    expect(dispatcher.hasPendingTask, isFalse);
    expect(controller.updates, isEmpty);
    dispatcher.discard();
    final recovered = _dispatcher(controller);
    await recovered.dispatchNewList([1, 2, 3, 4]);
    expect(recovered.currentList, [1, 2, 3, 4]);
  });

  test('small diffs still notify synchronously', () async {
    final controller = _RecordingController();
    final dispatcher = _dispatcher(controller, threshold: 500);
    final pending = dispatcher.dispatchNewList([1, 2, 3, 4]);
    expect(controller.updates, ['insert:3:1']);
    expect(dispatcher.currentList, [1, 2, 3, 4]);
    await pending;
  });
}
