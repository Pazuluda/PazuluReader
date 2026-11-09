String relativeTime(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.isNegative) {
    // A date to come (planning): « dans 3 h », « dans 2 j ».
    final ahead = -diff.inMinutes;
    if (ahead < 1) return 'à l\'instant';
    if (ahead < 60) return 'dans $ahead min';
    if (ahead < 24 * 60) return 'dans ${ahead ~/ 60} h';
    if (ahead < 7 * 24 * 60) return 'dans ${ahead ~/ (24 * 60)} j';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
  if (diff.inDays < 60) return 'il y a ${(diff.inDays / 7).floor()} sem.';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String langName(String code) => switch (code) {
      'en' => 'Anglais',
      'fr' => 'Français',
      _ => code.toUpperCase(),
    };

const _weekdays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août',
  'sept.', 'oct.', 'nov.', 'déc.'];

String two(int n) => n.toString().padLeft(2, '0');

/// « ven. 7 nov. » (local time).
String shortDate(DateTime d) {
  final l = d.toLocal();
  return '${_weekdays[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}';
}

/// « 17:30 » (local time).
String clockTime(DateTime d) {
  final l = d.toLocal();
  return '${two(l.hour)}:${two(l.minute)}';
}

/// « dans 2 j 4 h », « dans 35 min », « il y a 3 h ».
String countdown(DateTime target, {DateTime? now}) {
  final diff = target.difference(now ?? DateTime.now());
  final past = diff.isNegative;
  final d = diff.abs();
  final String body;
  if (d.inMinutes < 1) {
    return past ? 'à l\'instant' : 'maintenant';
  } else if (d.inHours < 1) {
    body = '${d.inMinutes} min';
  } else if (d.inDays < 1) {
    final m = d.inMinutes % 60;
    body = m == 0 ? '${d.inHours} h' : '${d.inHours} h ${two(m)}';
  } else {
    final h = d.inHours % 24;
    body = h == 0 ? '${d.inDays} j' : '${d.inDays} j $h h';
  }
  return past ? 'il y a $body' : 'dans $body';
}

const _longMonths = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
  'septembre', 'octobre', 'novembre', 'décembre'];

/// « 6 mai 2026 ».
String longDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_longMonths[l.month - 1]} ${l.year}';
}

/// Age of a release, never as a raw date: « il y a 3 h », « il y a 6 mois ».
String releaseAge(DateTime d, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.isNegative || diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
  if (diff.inDays < 31) return 'il y a ${(diff.inDays / 7).floor()} sem.';
  if (diff.inDays < 365) return 'il y a ${(diff.inDays / 30.4).floor()} mois';
  final years = (diff.inDays / 365.25).floor();
  return 'il y a $years an${years > 1 ? 's' : ''}';
}

/// « Sorti il y a 3 h » (recent) or « Sorti le 6 mai 2026 · il y a 6 mois ».
String releaseLine(DateTime d, {DateTime? now, String verb = 'Sorti'}) {
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inDays < 7) return '$verb ${releaseAge(d, now: now)}';
  return '$verb le ${longDate(d)} · ${releaseAge(d, now: now)}';
}
