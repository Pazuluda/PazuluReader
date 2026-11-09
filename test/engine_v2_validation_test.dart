import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/engine/availability.dart';
import 'package:pazulu_reader/engine/validation/access_detector.dart';
import 'package:pazulu_reader/engine/validation/image_sniffer.dart';
import 'package:pazulu_reader/engine/validation/page_validation.dart';

import 'engine_v2_support.dart';

List<PageRef> refs(int n, {String base = 'https://cdn.example.org/ch/'}) =>
    [for (var i = 1; i <= n; i++) PageRef('$base${i.toString().padLeft(2, '0')}.png')];

List<PageProbe> probesFor(List<PageRef> pages, {Set<int> htmlAt = const {},
    String html = '<html><body>Subscription required</body></html>'}) => [
      for (final i in PageValidationEngine.probeSample(pages.length))
        htmlAt.contains(i)
            ? PageProbe.fromBytes(i, pages[i].url, 200,
                Uint8List.fromList(utf8.encode(html)), contentType: 'image/jpeg')
            : PageProbe.fromBytes(i, pages[i].url, 200, png(900, 1300, seed: i),
                contentType: 'image/png', complete: true),
    ];

void main() {
  const engine = PageValidationEngine();

  group('ImageSniff', () {
    test('lit les dimensions sans décoder l\'image', () {
      final p = ImageSniff.inspect(png(900, 1300));
      expect(p.isImage, isTrue);
      expect(p.format, 'png');
      expect((p.width, p.height), (900, 1300));
      final j = ImageSniff.inspect(jpeg(1080, 1600));
      expect((j.format, j.width, j.height), ('jpeg', 1080, 1600));
      final g = ImageSniff.inspect(gif(64, 64));
      expect((g.format, g.width, g.height), ('gif', 64, 64));
      final w = ImageSniff.inspect(webpVp8x(1200, 1800));
      expect((w.format, w.width, w.height), ('webp', 1200, 1800));
    });

    test('du HTML servi avec une URL d\'image est reconnu', () {
      final s = ImageSniff.inspect(Uint8List.fromList(utf8.encode(
          '<!DOCTYPE html><html><title>404</title></html>')), contentType: 'image/jpeg');
      expect(s.kind, PayloadKind.html);
      expect(ImageSniff.inspect(Uint8List(0)).kind, PayloadKind.empty);
      expect(ImageSniff.inspect(Uint8List.fromList(utf8.encode('<svg></svg>'))).isImage,
          isFalse);
    });
  });

  group('AccessDetector', () {
    test('Manga UP! « n\'est plus gratuit » = abonnement', () {
      expect(AccessDetector.classifyText('This chapter is no longer free. '
          'Use points to read.'), AccessKind.subscriptionRequired);
      expect(AccessDetector.classifyText('Ce chapitre n\'est plus gratuit'),
          AccessKind.subscriptionRequired);
    });

    test('K MANGA : vérification d\'âge et cookies ne sont pas un chapitre', () {
      expect(AccessDetector.classifyText('Age verification. Are you 18 or older?'),
          AccessKind.ageVerification);
      expect(AccessDetector.classifyText('We use cookies. Accept all cookies'),
          AccessKind.cookieConsent);
      // A real chapter with a cookie banner remains a chapter.
      expect(AccessDetector.classifyText('Accept cookies', imageCount: 12),
          AccessKind.open);
    });

    test('défi anti-robot, connexion, retrait, région', () {
      expect(AccessDetector.classifyText('Just a moment... Checking your browser'),
          AccessKind.botChallenge);
      expect(AccessDetector.classifyText('Please log in to continue reading'),
          AccessKind.loginRequired);
      expect(AccessDetector.classifyText('Chapter not found'), AccessKind.removed);
      expect(AccessDetector.classifyText('Not available in your region'),
          AccessKind.regionLocked);
      expect(AccessDetector.classifyStatus(429), AccessKind.rateLimited);
      expect(AccessDetector.classifyStatus(200), AccessKind.open);
    });
  });

  group('PageValidationEngine', () {
    test('14 pages annoncées, 14 valides => COMPLETE', () {
      final pages = refs(14);
      final r = engine.evaluate(pages, announcedTotal: 14, probes: probesFor(pages));
      expect(r.completeness, PageCompleteness.complete);
      expect(r.readable, isTrue);
      expect(r.validCount, 14);
    });

    test('14 pages annoncées, 8 obtenues => PARTIAL (autre version à chercher)', () {
      final pages = refs(8);
      final r = engine.evaluate(pages, announcedTotal: 14, probes: probesFor(pages));
      expect(r.completeness, PageCompleteness.partial);
      expect(r.readable, isFalse);
      expect(r.summary, contains('8/14'));
    });

    test('page HTML « subscription required » => ACCESS_RESTRICTED, pas une planche', () {
      final pages = refs(1);
      final r = engine.evaluate(pages, probes: probesFor(pages, htmlAt: {0}));
      expect(r.completeness, PageCompleteness.restricted);
      expect(r.access, AccessKind.subscriptionRequired);
      expect(r.readable, isFalse);
    });

    test('jamais de faux 1/1 à partir d\'une seule image non vérifiée', () {
      final r = engine.evaluate(refs(1));
      expect(r.completeness, PageCompleteness.invalid);
    });

    test('total inconnu => complétude non confirmée (mais lisible)', () {
      final pages = refs(30);
      final r = engine.evaluate(pages, probes: probesFor(pages));
      expect(r.completeness, PageCompleteness.unconfirmed);
      expect(r.readable, isTrue);
    });

    test('logos, GIF de chargement et pixels espions sont rejetés', () {
      final pages = [
        const PageRef('https://cdn.example.org/assets/logo.png'),
        const PageRef('https://cdn.example.org/assets/loading.png'),
      ];
      expect(engine.evaluate(pages).completeness, PageCompleteness.invalid);
      final spinner = engine.evaluate(refs(3), probes: [
        PageProbe.fromBytes(0, refs(3)[0].url, 200, gif(120, 120), complete: true),
        PageProbe.fromBytes(2, refs(3)[2].url, 200, png(1, 1), complete: true),
      ]);
      expect(spinner.completeness, PageCompleteness.partial);
      expect(spinner.issues.map((i) => i.code), containsAll(['loading_gif', 'tracker']));
    });

    test('images identiques (fichier complet) => page invalide', () {
      final pages = refs(8);
      final same = png(900, 1300, seed: 7);
      final r = engine.evaluate(pages, announcedTotal: 8, probes: [
        for (final i in PageValidationEngine.probeSample(8))
          PageProbe.fromBytes(i, pages[i].url, 200, same, complete: true),
      ]);
      expect(r.completeness, PageCompleteness.partial);
      expect(r.issues.any((i) => i.code == 'same_image' && i.fatal), isTrue);
    });

    test('URL non HTTPS, hôte local ou doublon : refus', () {
      expect(engine.structural([const PageRef('http://cdn.example.org/1.jpg')])
          .any((i) => i.fatal), isTrue);
      expect(engine.structural([const PageRef('https://127.0.0.1/1.jpg')])
          .any((i) => i.fatal), isTrue);
      expect(engine.structural([
        const PageRef('https://cdn.example.org/1.jpg'),
        const PageRef('https://cdn.example.org/1.jpg'),
      ]).any((i) => i.code == 'duplicate_url'), isTrue);
    });

    test('tranches de webtoon étroites tolérées par la politique webtoon', () {
      final pages = refs(10);
      final r = engine.evaluate(pages, policy: ValidationPolicy.webtoon, probes: [
        for (final i in PageValidationEngine.probeSample(10))
          PageProbe.fromBytes(i, pages[i].url, 200, png(720, 90, seed: i), complete: true),
      ]);
      expect(r.readable, isTrue);
      final strict = engine.evaluate(pages, probes: [
        for (final i in PageValidationEngine.probeSample(10))
          PageProbe.fromBytes(i, pages[i].url, 200, png(720, 90, seed: i), complete: true),
      ]);
      expect(strict.readable, isFalse);
    });

    test('HTTP 403 sur les images => restreint', () {
      final pages = refs(2);
      final r = engine.evaluate(pages, probes: [
        PageProbe.fromBytes(0, pages[0].url, 403, Uint8List(0)),
        PageProbe.fromBytes(1, pages[1].url, 403, Uint8List(0)),
      ]);
      expect(r.readable, isFalse);
      expect(r.completeness, PageCompleteness.restricted);
    });
  });
}
