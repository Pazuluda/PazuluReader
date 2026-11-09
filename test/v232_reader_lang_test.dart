import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/models.dart';
import 'package:pazulu_reader/core/source_catalog.dart';
import 'package:pazulu_reader/core/sources/public_catalog.dart';

void main() {
  const site = CatalogSite('directory_200', 'ScanFR', 'https://scanfr.example/', ['fr'],
      SiteIntegration.website);
  final source = PublicCatalogSource(site, fetchHtml: (_) async => '');
  final base = Uri.parse('https://scanfr.example/manga/frozen-player/');

  test('chapitres premium, VIP ou « bientôt » : pas encore sortis en FR', () {
    final list = source.parseChapterList('''
<ul>
<li class="wp-manga-chapter premium"><a href="https://scanfr.example/manga/frozen-player/chapitre-229/">Chapitre 229</a><i class="fas fa-lock"></i></li>
<li class="wp-manga-chapter"><a href="https://scanfr.example/manga/frozen-player/chapitre-228/">Chapitre 228</a><span>Accès anticipé</span></li>
<li class="wp-manga-chapter"><a href="https://scanfr.example/manga/frozen-player/chapitre-227/">Chapitre 227</a><span class="coin">30</span></li>
<li class="wp-manga-chapter"><a href="https://scanfr.example/manga/frozen-player/chapitre-226/">Chapitre 226</a><span>Bientôt disponible</span></li>
<li class="wp-manga-chapter"><a href="https://scanfr.example/manga/frozen-player/chapitre-225/">Chapitre 225</a>
  <span class="chapter-release-date"><i>02/11/2026</i></span><i class="fa fa-clock"></i></li>
</ul>''', base, lang: 'fr');
    expect(list.map((c) => c.key.id), ['225']);
  });

  test('date de sortie dans le futur : annoncé, pas sorti', () {
    final list = source.parseChapterList('''
<ul>
<li class="wp-manga-chapter"><a href="https://scanfr.example/manga/frozen-player/chapitre-230/">Chapitre 230</a>
  <span class="chapter-release-date">01/01/2099</span></li>
<li class="wp-manga-chapter"><a href="https://scanfr.example/manga/frozen-player/chapitre-224/">Chapitre 224</a></li>
</ul>''', base, lang: 'fr');
    expect(list.map((c) => c.key.id), ['224']);
  });

  test('navigateur caché désactivé par défaut, réglage sauvegardé', () {
    expect(Settings().browserReader, isFalse);
    final s = Settings()..browserReader = true;
    expect(Settings.fromJson(s.toJson()).browserReader, isTrue);
    expect(Settings.fromJson(const {}).browserReader, isFalse);
  });

  test('sources bloquées sauvegardées', () {
    final s = Settings()..blockedSources = ['public_directory_123'];
    expect(Settings.fromJson(s.toJson()).blockedSources, ['public_directory_123']);
    expect(Settings.fromJson(const {}).blockedSources, isEmpty);
  });
}
