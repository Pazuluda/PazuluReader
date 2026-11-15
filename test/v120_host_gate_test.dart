import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/host_gate.dart';

void main() {
  test('jamais plus de 2 requêtes en même temps sur un site', () async {
    final gate = HostGate(perSite: 2, perLane: 8);
    var max = 0;
    await Future.wait([
      for (var i = 0; i < 10; i++)
        gate.run('site_a', () async {
          if (gate.runningOn('site_a') > max) max = gate.runningOn('site_a');
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }),
    ]);
    expect(max, 2);
    expect(gate.running, 0);
  });

  test('équipe FR et équipe EN : 8 chacune quand les deux ont du travail', () async {
    final gate = HostGate(perSite: 2, perLane: 8);
    final release = Completer<void>();
    final runs = <Future<void>>[
      for (var i = 0; i < 20; i++) ...[
        gate.run('fr_$i', () => release.future, lane: 'fr'),
        gate.run('en_$i', () => release.future, lane: 'en'),
      ],
    ];
    await Future<void>.delayed(Duration.zero);
    expect(gate.runningIn('fr'), 8);
    expect(gate.runningIn('en'), 8);
    release.complete();
    await Future.wait(runs);
    expect(gate.running, 0);
  });

  test('une équipe qui a fini aide l\'autre', () async {
    final gate = HostGate(perSite: 2, perLane: 8);
    final release = Completer<void>();
    final runs = [
      for (var i = 0; i < 20; i++) gate.run('fr_$i', () => release.future, lane: 'fr'),
    ];
    await Future<void>.delayed(Duration.zero);
    // Aucun site anglais à lire : les 16 moteurs travaillent sur le français.
    expect(gate.runningIn('fr'), 16);
    release.complete();
    await Future.wait(runs);
  });

  test('l\'aide est rendue dès que l\'autre équipe a du travail', () async {
    final gate = HostGate(perSite: 2, perLane: 2);
    final fr = [for (var i = 0; i < 4; i++) Completer<void>()];
    final runs = [
      for (var i = 0; i < 4; i++) gate.run('fr_$i', () => fr[i].future, lane: 'fr'),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(gate.runningIn('fr'), 4); // l'équipe EN aide
    final en = gate.run('en_0', () async {}, lane: 'en');
    await Future<void>.delayed(Duration.zero);
    expect(gate.runningIn('en'), 0); // tout est pris, elle attend
    fr[0].complete();
    await en; // la première place libérée va à l'équipe EN
    for (final c in fr.skip(1)) {
      c.complete();
    }
    await Future.wait(runs);
    expect(gate.running, 0);
  });

  test('une erreur libère sa place', () async {
    final gate = HostGate(perSite: 1, perLane: 1);
    await expectLater(gate.run('s', () async => throw StateError('x')), throwsStateError);
    expect(await gate.run('s', () async => 7), 7);
    expect(gate.running, 0);
  });
}
