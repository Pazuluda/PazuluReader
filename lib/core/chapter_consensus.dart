import 'models.dart';

/// What the consensus removed, for the journal.
class ConsensusNote {
  const ConsensusNote(this.sourceId, this.message);

  final String sourceId;
  final String message;
}

/// Chapter numbering checked by agreement between ALL the sources of a work
/// (none is a reference). Same rules for every work.
///
/// 1. A site whose whole numbering is shifted (its « chapter 195 » has the
///    date of everybody else's 194) is set aside for this work.
/// 2. A number far ahead of what most sites have (« 203 » when the others
///    stop at 195), with no chapter in between on that site and no recent
///    date, is not shown: it is another numbering or another series. A site
///    really ahead (196, 197 … 203 all listed), early releases of 1–3
///    chapters and chapters dated in the last 14 days are kept.
class ChapterConsensus {
  static const int aheadTolerance = 3;
  static const Duration freshRelease = Duration(days: 14);

  /// A chapter ahead of every other site, dated this recently, is a real
  /// new release on the fastest site (not another numbering).
  static const Duration freshAheadWindow = Duration(days: 21);

  static (List<SourceChapter>, List<ConsensusNote>) apply(List<SourceChapter> all,
      {DateTime? now}) {
    final at = now ?? DateTime.now();
    final notes = <ConsensusNote>[];
    all = _withoutSplitParts(all, notes);
    final bySource = <String, List<SourceChapter>>{};
    for (final c in all) {
      if (c.isExternal || c.key.number == null) continue;
      bySource.putIfAbsent('${c.sourceId}|${c.lang}', () => []).add(c);
    }
    // Lists that can vote: at least 10 numbered chapters.
    final voters = {
      for (final e in bySource.entries) if (e.value.length >= 10) e.key: e.value,
    };
    if (voters.length < 3) return (all, notes);

    // 1. Shifted numbering, from the dates.
    final shifted = <String>{};
    for (final e in voters.entries) {
      final others = <double, List<DateTime>>{};
      for (final o in voters.entries) {
        if (o.key == e.key) continue;
        for (final c in o.value) {
          if (c.publishedAt != null) others.putIfAbsent(c.key.number!, () => []).add(c.publishedAt!);
        }
      }
      DateTime? ref(double n) {
        final list = others[n];
        if (list == null || list.length < 2) return null;
        final sorted = [...list]..sort();
        return sorted[sorted.length ~/ 2];
      }
      bool near(DateTime a, DateTime b) => a.difference(b).abs() <= const Duration(days: 2);
      var same = 0;
      var minusOne = 0;
      var plusOne = 0;
      for (final c in e.value) {
        final d = c.publishedAt;
        if (d == null) continue;
        final n = c.key.number!;
        final r0 = ref(n);
        final rm = ref(n - 1);
        final rp = ref(n + 1);
        // Weekly series: the neighbours are 7 days apart, so one date only
        // matches one number.
        if (r0 != null && near(d, r0)) same++;
        if (rm != null && near(d, rm) && (r0 == null || !near(d, r0))) minusOne++;
        if (rp != null && near(d, rp) && (r0 == null || !near(d, r0))) plusOne++;
      }
      // A site whose « 194 » is dated weeks BEFORE everybody else's 194
      // (manganato / mangabats: 12 June vs 25 August) numbers differently:
      // a chapter cannot be out on a copy site before its release.
      // Only the chapters released elsewhere AFTER this site's first date
      // count (a site that copied a whole series in one day has old
      // chapters dated late, which is normal; « early » is impossible).
      final own = [for (final c in e.value) if (c.publishedAt != null) c.publishedAt!]..sort();
      var tooEarly = 0;
      var compared = 0;
      for (final c in e.value) {
        final d = c.publishedAt;
        final r0 = d == null ? null : ref(c.key.number!);
        if (d == null || r0 == null || own.isEmpty) continue;
        if (!r0.isAfter(own.first.add(const Duration(days: 14)))) continue;
        compared++;
        if (r0.difference(d) > const Duration(days: 14)) tooEarly++;
      }
      // Early dates alone prove nothing: when the other sites copied a
      // whole series late (bulk uploads dated the same day), the FAST and
      // accurate sites look « early » (Catastrophic Necromancer: MangaDex,
      // mangaread… set aside, 319 lost). Early dates only mean another
      // numbering when this site also claims chapters NOBODY else has,
      // and those chapters are not a fresh release.
      final ownMax = e.value.map((c) => c.key.number!).reduce((a, b) => a > b ? a : b);
      var othersMax = double.negativeInfinity;
      for (final o in voters.entries) {
        if (o.key == e.key) continue;
        for (final c in o.value) {
          if (c.key.number! > othersMax) othersMax = c.key.number!;
        }
      }
      final aheadChapters = [for (final c in e.value) if (c.key.number! > othersMax) c];
      final freshAhead = aheadChapters.any((c) =>
          c.publishedAt != null && at.difference(c.publishedAt!) <= freshAheadWindow);
      final claimsOthersLack = ownMax > othersMax && aheadChapters.isNotEmpty;
      if (compared >= 5 && tooEarly * 2 > compared && claimsOthersLack && !freshAhead) {
        shifted.add(e.key);
        notes.add(ConsensusNote(e.value.first.sourceId,
            'numérotation différente des autres sites : $tooEarly chapitres sur $compared datés '
            'plus de 2 semaines AVANT leur sortie ailleurs, mis de côté'));
        continue;
      }
      final off = minusOne > plusOne ? minusOne : plusOne;
      if (off >= 5 && off > same * 2) {
        shifted.add(e.key);
        notes.add(ConsensusNote(e.value.first.sourceId,
            'numérotation décalée de ${minusOne > plusOne ? '+1' : '-1'} par rapport aux autres '
            'sites ($off dates sur ${off + same}), mis de côté'));
      }
    }

    // 2. Numbers far ahead of the majority, per language (French follows
    // English with a delay: never compared with each other).
    final majorityMax = <String, double>{};
    for (final lang in {for (final k in voters.keys) k.split('|').last}) {
      final maxima = [
        for (final e in voters.entries)
          if (!shifted.contains(e.key) && e.key.endsWith('|$lang'))
            e.value.map((c) => c.key.number!).reduce((a, b) => a > b ? a : b),
      ]..sort((a, b) => b.compareTo(a));
      if (maxima.length < 3) continue;
      // The highest chapter reached by at least half of the sites.
      final need = (maxima.length / 2).ceil().clamp(2, maxima.length);
      majorityMax[lang] = maxima[need - 1];
    }
    final numbersOf = <String, Set<double>>{
      for (final e in bySource.entries) e.key: {for (final c in e.value) c.key.number!},
    };
    final dropped = <String, List<String>>{};
    final out = <SourceChapter>[];
    for (final c in all) {
      final key = '${c.sourceId}|${c.lang}';
      if (shifted.contains(key)) continue;
      final n = c.key.number;
      final top = majorityMax[c.lang];
      final fresh = c.publishedAt != null && at.difference(c.publishedAt!) <= freshRelease;
      if (n != null && top != null && n > top + aheadTolerance && !fresh) {
        // A really faster site lists every chapter in between (196…203);
        // a « 203 » after 195 with nothing between is another numbering.
        final own = numbersOf[key] ?? const <double>{};
        var present = 0;
        var expected = 0;
        for (var k = top.floor() + 1; k < n; k++) {
          expected++;
          if (own.contains(k.toDouble())) present++;
        }
        if (expected == 0 || present < expected * 0.8) {
          dropped.putIfAbsent(c.sourceId, () => []).add(c.key.id);
          continue;
        }
      }
      out.add(c);
    }
    for (final e in dropped.entries) {
      notes.add(ConsensusNote(e.key,
          'ch. ${e.value.take(5).join(', ')}${e.value.length > 5 ? '…' : ''} non montré(s) : '
          'les autres sites s\'arrêtent avant, sans les chapitres intermédiaires ni date récente'));
    }
    return (out, notes);
  }

  /// « lang|chapter » claimed by ONE site only, ahead of at least 3 other
  /// sites of that language (Mythic Item Obtained « 195 » when the series
  /// ended at 194): shown « non confirmé », never « NOUVEAU » nor notified.
  static Set<String> unconfirmedAhead(List<SourceChapter> all, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final byLang = <String, Map<String, Set<double>>>{};
    final dates = <String, DateTime>{};
    for (final c in all) {
      final n = c.key.number;
      if (c.isExternal || n == null) continue;
      byLang.putIfAbsent(c.lang, () => {}).putIfAbsent(c.sourceId, () => {}).add(n);
      if (c.publishedAt != null) dates['${c.lang}|${c.sourceId}|$n'] = c.publishedAt!;
    }
    final out = <String>{};
    for (final lang in byLang.entries) {
      final sources = lang.value;
      if (sources.length < 4) continue;
      final holders = <double, List<String>>{};
      for (final s in sources.entries) {
        for (final n in s.value) {
          holders.putIfAbsent(n, () => []).add(s.key);
        }
      }
      for (final h in holders.entries) {
        if (h.value.length != 1) continue;
        final owner = h.value.single;
        // The fastest site's brand-new chapter (dated in the last weeks,
        // following its previous chapter) is a release, not an error.
        final d = dates['${lang.key}|$owner|${h.key}'];
        final follows = sources[owner]!.contains(h.key - 1) ||
            sources[owner]!.any((n) => n < h.key && n >= h.key - 1);
        if (d != null && at.difference(d) <= freshAheadWindow && follows) continue;
        var lower = 0;
        for (final s in sources.entries) {
          if (s.key == owner) continue;
          final top = s.value.reduce((a, b) => a > b ? a : b);
          if (top < h.key && s.value.length >= 10) lower++;
        }
        if (lower >= 3) {
          final n = h.key;
          out.add('${lang.key}|${n == n.roundToDouble() ? n.toInt() : n}');
        }
      }
    }
    return out;
  }

  /// 0. A chapter uploaded in pieces by some sites (« 90.1, 90.2, 90.3,
  /// 90.4 » while other sites have the whole « 90 ») is the same chapter:
  /// the pieces are not extra chapters. They are hidden when at least 2
  /// sources of that language have the whole chapter, so the whole one is
  /// read. A lone « 107.5 » (a real extra) is never touched; pieces nobody
  /// has whole stay visible.
  static List<SourceChapter> _withoutSplitParts(List<SourceChapter> all, List<ConsensusNote> notes) {
    // lang → whole number → sources having it whole.
    final whole = <String, Map<int, Set<String>>>{};
    // lang|source|N → piece numbers.
    final pieces = <String, Set<double>>{};
    for (final c in all) {
      final n = c.key.number;
      if (c.isExternal || n == null || n < 1) continue;
      if (n == n.roundToDouble()) {
        whole.putIfAbsent(c.lang, () => {}).putIfAbsent(n.toInt(), () => {}).add(c.sourceId);
      } else {
        final frac = ((n - n.floor()) * 10).round();
        if (frac >= 1 && frac <= 9) {
          pieces.putIfAbsent('${c.lang}|${c.sourceId}|${n.floor()}', () => {}).add(n);
        }
      }
    }
    final drop = <String>{}; // lang|number
    final droppedBy = <String, Set<String>>{};
    for (final e in pieces.entries) {
      if (e.value.length < 2) continue; // one « .5 »: a real extra
      final parts = e.key.split('|');
      final lang = parts[0];
      final n = int.parse(parts[2]);
      final holders = whole[lang]?[n] ?? const <String>{};
      if (holders.length < 2) continue;
      for (final p in e.value) {
        drop.add('$lang|$p');
      }
      droppedBy.putIfAbsent(parts[1], () => {}).add('$n');
    }
    if (drop.isEmpty) return all;
    for (final e in droppedBy.entries) {
      notes.add(ConsensusNote(e.key,
          'chapitre(s) ${e.value.join(', ')} découpé(s) en morceaux : morceaux masqués, '
          'le chapitre entier existe sur d\'autres sites'));
    }
    return [
      for (final c in all)
        if (c.key.number == null || !drop.contains('${c.lang}|${c.key.number}')) c,
    ];
  }
}
