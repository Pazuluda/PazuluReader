import 'models.dart';

/// Contrat que chaque source (connecteur) respecte.
///
/// En v0.1 les connecteurs sont écrits en Dart et compilés avec l'app.
/// La phase 2 ajoutera un hôte QuickJS : les connecteurs JS implémenteront
/// exactement ce même contrat, sans changer le reste de l'application.
abstract class ContentSource {
  /// Identifiant stable (ex. "mangadex").
  String get id;

  /// Nom affiché.
  String get name;

  /// Langues que cette source peut fournir.
  List<String> get languages;

  /// En-têtes HTTP à envoyer pour charger les images.
  Map<String, String> get imageHeaders;

  Future<List<WorkInfo>> search(String query, {int limit = 30});

  Future<WorkInfo> getWork(String workId);

  /// Tous les chapitres disponibles dans [langs].
  Future<List<SourceChapter>> listChapters(
    String workId, {
    required List<String> langs,
  });

  /// Les chapitres les plus récents (surveillance des sorties).
  Future<List<SourceChapter>> latestChapters(
    String workId, {
    required List<String> langs,
    int limit = 30,
  });

  /// Adresses des pages d'un chapitre lisible dans l'app.
  Future<List<PageRef>> getPages(SourceChapter chapter);

  /// Crédit à afficher (obligatoire pour certaines sources).
  String get credit;
}

class SourceException implements Exception {
  const SourceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Registre des sources activées.
class SourceRegistry {
  SourceRegistry(List<ContentSource> sources)
      : _sources = {for (final s in sources) s.id: s};

  final Map<String, ContentSource> _sources;

  ContentSource? byId(String id) => _sources[id];

  /// Register a configured metadata adapter on demand. Does not install code.
  void register(ContentSource source) => _sources[source.id] = source;

  void unregister(String id) { _sources.remove(id); }

  Iterable<ContentSource> get all => _sources.values;
}
