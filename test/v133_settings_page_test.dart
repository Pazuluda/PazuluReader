import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/app_state.dart';
import 'package:pazulu_reader/design/theme.dart';
import 'package:pazulu_reader/ui/app_scope.dart';
import 'package:pazulu_reader/ui/settings_page.dart';

void main() {
  for (final width in [1240.0, 900.0]) {
    testWidgets('la page Réglages s\'affiche sans erreur ($width px)', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 2400));
      final state = AppState();
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        state.dispose();
      });
      await tester.pumpWidget(MaterialApp(
        theme: buildPazuluTheme(paletteById('indigo')),
        home: AppScope(state: state, child: const SettingsPage()),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('Performances'), findsOneWidget);
    });
  }
}
