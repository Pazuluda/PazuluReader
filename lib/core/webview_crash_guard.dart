import 'dart:io';

/// Marque un essai de WebView Windows en cours.
/// Un arret natif brutal laisse le fichier : le prochain lancement ne cree
/// pas automatiquement le controle natif qui pourrait replanter.
///
/// 2.5.5 : le marqueur contient le PID et l'heure. Il n'est pris pour un
/// plantage que s'il vient d'un AUTRE lancement de Pazulu et date de moins
/// de [crashWindow] (boucle de plantages). Deux WebView du meme lancement
/// (lecteur manga cache + lecteur Crunchyroll) ou une fermeture de Pazulu
/// avec une page ouverte ne declenchent plus le mode securite.
class WebviewCrashGuard {
  WebviewCrashGuard(this.marker);

  final File marker;
  bool _entered = false;

  static const crashWindow = Duration(minutes: 3);

  /// WebView ouvertes dans ce lancement (toutes partagent le marqueur).
  static int _active = 0;

  static String encode(int processId, DateTime at) => '$processId|${at.toUtc().toIso8601String()}';

  /// True si le contenu du marqueur signale un plantage recent d'un autre
  /// lancement. Ancien format (date seule) : traite comme un autre lancement.
  static bool looksLikeCrash(String content, {required int processId, required DateTime now}) {
    final parts = content.trim().split('|');
    final owner = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final at = DateTime.tryParse(parts.last);
    if (owner == processId) return false; // autre WebView de ce lancement
    if (at == null) return false;
    return now.toUtc().difference(at.toUtc()) < crashWindow;
  }

  Future<bool> enter({bool retry = false}) async {
    await marker.parent.create(recursive: true);
    if (!retry && _active == 0 && await marker.exists()) {
      try {
        if (looksLikeCrash(await marker.readAsString(), processId: pid, now: DateTime.now())) return false;
      } catch (_) {
        // marqueur illisible : on repart proprement
      }
    }
    if (!_entered) _active++;
    _entered = true;
    await marker.writeAsString(encode(pid, DateTime.now()), flush: true);
    return true;
  }

  Future<void> leave() async {
    if (!_entered) return; // cette WebView n'a jamais demarre
    _entered = false;
    if (_active > 0) _active--;
    if (_active == 0 && await marker.exists()) await marker.delete();
  }
}
