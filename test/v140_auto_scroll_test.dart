import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/ui/widgets/auto_scroll.dart';

void main() {
  test('vitesse : rien près du point, plus vite en s\'éloignant, plafonnée', () {
    expect(AutoScrollAreaState.speedFor(5), 0);
    expect(AutoScrollAreaState.speedFor(-10), 0);
    expect(AutoScrollAreaState.speedFor(60), greaterThan(0));
    expect(AutoScrollAreaState.speedFor(-60), lessThan(0));
    expect(AutoScrollAreaState.speedFor(200), greaterThan(AutoScrollAreaState.speedFor(60)));
    expect(AutoScrollAreaState.speedFor(5000), 6000);
  });

  testWidgets('clic molette puis souris vers le bas : la page défile toute seule, un clic l\'arrête',
      (tester) async {
    final controller = ScrollController();
    final key = GlobalKey<AutoScrollAreaState>();
    await tester.pumpWidget(MaterialApp(
      home: AutoScrollArea(
        key: key,
        controller: controller,
        child: ListView.builder(
          controller: controller,
          itemCount: 200,
          itemBuilder: (_, i) => SizedBox(height: 100, child: Text('$i')),
        ),
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await mouse.addPointer(location: const Offset(200, 200));
    await mouse.down(const Offset(200, 200));
    await mouse.up();
    expect(key.currentState!.active, isTrue);
    await mouse.moveTo(const Offset(200, 320)); // 120 px sous le point
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.offset, greaterThan(100));

    final click = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await click.addPointer(location: const Offset(200, 320));
    await click.down(const Offset(200, 320));
    await click.up();
    await tester.pump();
    expect(key.currentState!.active, isFalse);
    final stoppedAt = controller.offset;
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, stoppedAt);
    await mouse.removePointer();
    await click.removePointer();
  });
}
