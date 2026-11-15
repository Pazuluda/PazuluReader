import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/achievements.dart';
import 'package:pazulu_reader/core/app_state.dart';
import 'package:pazulu_reader/core/host_gate.dart';
import 'package:pazulu_reader/core/models.dart';

void main() {
  test('recherches de sites : 2 œuvres à la fois, les autres attendent leur tour', () async {
    final slots = Slots(2);
    var running = 0, max = 0;
    final order = <int>[];
    await Future.wait([
      for (var i = 0; i < 30; i++)
        slots.run(() async {
          running++;
          if (running > max) max = running;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          order.add(i);
          running--;
        }),
    ]);
    expect(max, 2);
    expect(order.length, 30);
    expect(slots.waiting, 0);
  });

  test('une erreur libère la place', () async {
    final slots = Slots(1);
    await expectLater(slots.run(() async => throw StateError('x')), throwsStateError);
    expect(await slots.run(() async => 3), 3);
  });

  group('fiche AniList de la même œuvre', () {
    final hits = [
      const WorkInfo(id: 'a:1', title: 'The Reincarnated Assassin is a Genius Swordsman'),
      const WorkInfo(id: 'a:2', title: 'Reincarnator', altTitles: ["Reincarnator's Stream"]),
      const WorkInfo(id: 'a:3', title: 'Solo Leveling: Ragnarok'),
    ];

    test('même titre, écrit un peu autrement', () {
      expect(AppState.sameMetadataWork("Reincarnator's Stream", const [], hits)?.id, 'a:2');
      expect(AppState.sameMetadataWork('Solo Leveling Ragnarok', const [], hits)?.id, 'a:3');
    });

    test('titre coupé par le navigateur : retrouvé par son début', () {
      expect(AppState.sameMetadataWork('The Reincarnated Assassin Is a Geni', const [], hits,
          truncated: true)?.id, 'a:1');
      // Sans coupure, un début seul ne suffit pas.
      expect(AppState.sameMetadataWork('The Reincarnated Assassin Is a Geni', const [], hits), isNull);
    });

    test('autre œuvre : rien', () {
      expect(AppState.sameMetadataWork('Omniscient Reader', const [], hits), isNull);
    });
  });

  test('succès : identifiants uniques, nouveaux paliers présents', () {
    final ids = [for (final a in Achievements.all) a.id];
    expect(ids.toSet().length, ids.length);
    expect(ids, containsAll(['ch_25000', 'library_150', 'one_500', 'level_100']));
  });
}
