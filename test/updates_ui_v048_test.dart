import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/app_state.dart';
import 'package:pazulu_reader/core/release_scan.dart';
import 'package:pazulu_reader/design/theme.dart';
import 'package:pazulu_reader/ui/app_scope.dart';
import 'package:pazulu_reader/ui/updates_page.dart';

void main() {
  test('Every verification state has an explicit label', () {
    for (final status in FeedCheckState.values) {
      expect(feedCheckStatusLabel(status).isNotEmpty, isTrue);
    }
    expect(feedCheckStatusLabel(FeedCheckState.rateLimited), 'Accès limité');
    expect(feedCheckStatusLabel(FeedCheckState.checked), 'Contrôlé');
  });

  for (final width in [1240.0, 390.0]) {
    testWidgets('Sorties dashboard renders at width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      final state = AppState();
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        state.dispose();
      });
      await tester.pumpWidget(MaterialApp(
        theme: buildPazuluTheme(paletteById('indigo')),
        home: AppScope(state: state, child: const UpdatesPage()),
      ));
      await tester.pump();
      expect(find.text('Nouveautés'), findsOneWidget);
      expect(find.text('Œuvres suivies'), findsOneWidget);
      // Kiosque 2.4 : libellés de boutons en majuscules.
      expect(find.text('VÉRIFIER LES SORTIES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
