import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/anime/crunchyroll.dart';
import '../core/anime/rwyf/rwyf_extension.dart';
import '../core/anime/rwyf/rwyf_room.dart';
import '../core/log.dart';
import '../design/theme.dart';
import 'app_scope.dart';
import 'firefox.dart';
import 'widgets/common.dart';
import 'widgets/official_web_view.dart';

/// Crunchyroll inside Pazulu: the official site and player in the built-in
/// WebView2 (own profile: sign in once on crunchyroll.com, the session is
/// kept). Pazulu never reads the login form nor the video.
///
/// With [episode] and a series page as [url], Pazulu looks for that
/// episode's link in the page Crunchyroll displays (its own list) and goes
/// to it, like a chapter in the manga reader.
///
/// « Ensemble » : the « Roll With Your Friends » extension (downloaded
/// from Mozilla, kept up to date) runs in the page, its room is handled by
/// Pazulu ([RwyfRoom]); links are the same as the Firefox extension's.
class CrunchyrollPlayerPage extends StatefulWidget {
  const CrunchyrollPlayerPage({super.key, required this.url, required this.title,
      this.episode, this.onEpisodeUrl, this.together = false, this.hints = const {},
      this.onCrunchyrollNumber});

  /// Crunchyroll.seasonHints of the AniList entry (season number, titles,
  /// episode count): to pick the right Crunchyroll season.
  final Map<String, Object?> hints;

  final String url;
  final String title;
  final int? episode;

  /// Called with the episode page found in the series page (remembered for
  /// the next time).
  final ValueChanged<String>? onEpisodeUrl;

  /// Crunchyroll's own number of the episode found (« E176 » for episode 6
  /// of Black Clover Season 2).
  final ValueChanged<int>? onCrunchyrollNumber;

  /// Opened with « Regarder ensemble »: the room is created as soon as the
  /// episode's player is ready.
  final bool together;

  @override
  State<CrunchyrollPlayerPage> createState() => _CrunchyrollPlayerPageState();
}

enum _Seek { none, searching, found, notFound }

class _CrunchyrollPlayerPageState extends State<CrunchyrollPlayerPage> {
  _Seek _seek = _Seek.none;
  String _current = '';
  Timer? _timer;
  Timer? _pump;
  int _tries = 0;

  EmbeddedBrowserBridge? _bridge;
  RwyfExtension? _ext;
  String? _extError;
  late final RwyfRoom _room = RwyfRoom(send: _deliver);
  bool _panel = false;
  bool _autoCreate = false;
  bool _injecting = false;
  final _joinField = TextEditingController();

  @override
  void initState() {
    super.initState();
    _current = widget.url;
    _panel = widget.together || RwyfRoom.roomOf(widget.url) != null;
    _autoCreate = widget.together && RwyfRoom.roomOf(widget.url) == null;
    if (widget.episode != null && !Crunchyroll.isEpisodeUrl(widget.url)) _seek = _Seek.searching;
    _room.addListener(_onRoom);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExtension());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pump?.cancel();
    _room.removeListener(_onRoom);
    _room.dispose();
    _joinField.dispose();
    super.dispose();
  }

  String? _copiedRoom;

  void _onRoom() {
    if (!mounted) return;
    final id = _room.roomId;
    if (id != null && _copiedRoom != id) {
      // Room just created / joined: show the card; created here: the link is
      // copied right away, ready to paste to friends.
      _copiedRoom = id;
      _panel = true;
      if (_room.createdHere) unawaited(_copy());
    }
    // « Regarder ensemble »: create the room once the episode page is ready.
    if (_autoCreate && _room.pageReady && Crunchyroll.isEpisodeUrl(_room.pageUrl) && !_room.inRoom) {
      _autoCreate = false;
      _room.createRoom();
    }
    setState(() {});
  }

  bool _updatingExt = false;

  /// « Mettre à jour » : checks Mozilla and GitHub now; with a new version,
  /// the page is reloaded so the new script runs (not inside a room).
  Future<void> _forceUpdate() async {
    if (_updatingExt) return;
    setState(() => _updatingExt = true);
    final before = _ext?.version;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await _loadExtension(force: true);
    if (!mounted) return;
    setState(() => _updatingExt = false);
    final now = _ext?.version;
    final changed = now != null && now != before;
    messenger?.showSnackBar(SnackBar(content: Text(now == null
        ? 'Extension introuvable (hors ligne ?)'
        : changed
            ? 'Roll With Your Friends mis à jour : v$before → v$now'
            : 'Roll With Your Friends est à jour (v$now)')));
    if (changed && !_room.inRoom) {
      try {
        await _bridge?.run('location.reload(); 0');
      } catch (_) {}
    }
  }

  Future<void> _loadExtension({bool force = false}) async {
    try {
      final app = AppScope.read(context);
      final dir = await getApplicationSupportDirectory();
      final ext = await RwyfExtension.load(app.engine.http, dir, force: force);
      if (!mounted) return;
      if (ext != null) _room.server = ext.syncServer;
      setState(() {
        _ext = ext;
        _extError = ext == null ? 'Extension Roll With Your Friends indisponible (hors ligne ?)' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _extError = 'Extension indisponible ($e)');
    }
  }

  // ---------------------------------------------------------------- page

  void _onBridge(EmbeddedBrowserBridge? bridge) {
    _bridge = bridge;
    _timer?.cancel();
    _pump?.cancel();
    if (bridge == null) return;
    // Messages of the extension script, ~3 times a second.
    _pump = Timer.periodic(const Duration(milliseconds: 350), (_) => _pumpPage());
    if (_seek != _Seek.searching) return;
    final n = widget.episode!;
    _tries = 0;
    var started = false;
    // The search runs in the page (season menu, « Voir plus »…): started
    // once, then its result is read every second, 60 s max.
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (++_tries > 60) {
        t.cancel();
        setState(() => _seek = _Seek.notFound);
        return;
      }
      try {
        final raw = _string(await bridge.run(Crunchyroll.findEpisodeState));
        final st = raw.isEmpty ? null : jsonDecode(raw);
        if (st is! Map) {
          // not started yet, or the page was reloaded: (re)start
          if (!started || _tries % 5 == 0) {
            started = true;
            await bridge.run(Crunchyroll.findEpisodeScript(n, hints: widget.hints));
          }
          return;
        }
        if (st['state'] == 'done') {
          final found = '${st['href'] ?? ''}';
          t.cancel();
          if (Crunchyroll.isEpisodeUrl(found)) {
            AppLog.info('Crunchyroll : ép. $n de « ${widget.title} » → $found (${st['note']})');
            widget.onEpisodeUrl?.call(found);
            final label = st['label'];
            if (label is num) widget.onCrunchyrollNumber?.call(label.toInt());
            if (mounted) setState(() { _seek = _Seek.found; _current = found; });
          } else if (mounted) {
            setState(() => _seek = _Seek.notFound);
          }
        } else if (st['state'] == 'fail') {
          t.cancel();
          AppLog.info('Crunchyroll : ép. $n de « ${widget.title} » introuvable (${st['note']})');
          if (mounted) setState(() => _seek = _Seek.notFound);
        }
      } catch (_) {
        // page still loading: next try
      }
    });
  }

  static String _string(Object? raw) {
    var s = raw is String ? raw : '$raw';
    if (s.startsWith('"')) {
      try {
        s = jsonDecode(s) as String;
      } catch (_) {}
    }
    return s == 'null' ? '' : s;
  }

  bool _pumping = false;

  Future<void> _pumpPage() async {
    final bridge = _bridge;
    if (bridge == null || _pumping) return;
    _pumping = true;
    try {
      final raw = _string(await bridge.run(
          "window.__pazuluRwyf ? window.__pazuluRwyf.take() : '__none__'"));
      if (raw == '__none__' || raw.isEmpty) {
        // New page (or reload): run the extension in it.
        final ext = _ext;
        if (ext != null && !_injecting) {
          _injecting = true;
          try {
            final r = _string(await bridge.run(ext.injection()));
            if (r.startsWith('error:')) AppLog.info('Roll With Your Friends : $r');
          } finally {
            _injecting = false;
          }
        }
        return;
      }
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final url = '${data['u'] ?? ''}';
      if (url.isNotEmpty && url != _room.pageUrl) {
        _room.pageUrl = url;
        if (mounted) setState(() {});
      }
      final list = data['m'];
      if (list is List) {
        for (final m in list) {
          if (m is! Map) continue;
          final type = '${m['type']}';
          if (type == 'pz_error') {
            AppLog.info('Roll With Your Friends (page) : erreur ${m['message']}');
            continue;
          }
          if (type != 'cs2w2_heart_beat') {
            AppLog.info('Roll With Your Friends (page → Pazulu) : $type'
                '${m['state'] == null ? '' : ' ${m['state']} @${m['currentProgress']}'}');
          }
          _room.fromPage(m.cast<String, Object?>(), url);
        }
      }
      await _probeVideo(bridge);
    } catch (_) {
      // page navigating: next tick
    } finally {
      _pumping = false;
    }
  }

  String _lastVideo = '';
  DateTime _lastProbe = DateTime.fromMillisecondsSinceEpoch(0);

  /// Diagnostic: state of the Crunchyroll video (written to pazulu.log when
  /// it changes): present?, readyState, paused, position, size, error.
  Future<void> _probeVideo(EmbeddedBrowserBridge bridge) async {
    if (DateTime.now().difference(_lastProbe) < const Duration(seconds: 2)) return;
    _lastProbe = DateTime.now();
    final v = _string(await bridge.run('''(function(){
      var v = document.querySelector('video[id^="bitmovinplayer-video"]') || document.querySelector('video');
      if (!v) return 'aucune vidéo';
      var r = v.getBoundingClientRect();
      return 'prête ' + v.readyState + ' · ' + (v.paused ? 'pause' : 'lecture') + ' · ' +
        Math.round(r.width) + 'x' + Math.round(r.height) + (v.error ? ' · erreur ' + v.error.code : '') +
        (document.fullscreenElement ? ' · plein écran' : '');
    })()'''));
    // Position left out: only real changes are written.
    if (v != _lastVideo) {
      _lastVideo = v;
      AppLog.info('Lecteur Crunchyroll : $v${_room.inRoom ? ' (salon ${_room.roomId})' : ''}');
    }
  }

  Future<void> _deliver(Map<String, Object?> message) async {
    final bridge = _bridge;
    if (bridge == null) return;
    AppLog.info('Roll With Your Friends (Pazulu → page) : ${message['type']}'
        '${message['kind'] == null ? '' : ' ${message['kind']} ${message['roomState']} @${message['roomProgress']}'}');
    try {
      await bridge.run('window.__pazuluRwyf && window.__pazuluRwyf.deliver(${jsonEncode(message)}); 0');
    } catch (_) {}
  }

  // ---------------------------------------------------------------- actions

  void _join() {
    final text = _joinField.text.trim();
    final room = RwyfRoom.roomOf(text);
    if (!Crunchyroll.isCrunchyrollUrl(text) || room == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Colle un lien Crunchyroll de soirée (avec « rollTogetherRoom= »).')));
      return;
    }
    if (_room.inRoom) _room.leave();
    setState(() => _current = text);
  }

  Future<void> _copy() async {
    final link = _room.shareUrl;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Lien copié : envoie-le à tes potes (Pazulu ou Firefox avec l’extension).')));
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final n = widget.episode;
    final heading = n == null ? widget.title : '${widget.title} · ép. $n';
    final status = switch (_seek) {
      _Seek.searching => 'Recherche de l’épisode $n dans la liste Crunchyroll…',
      _Seek.notFound => 'Épisode $n introuvable automatiquement : choisis-le dans la liste ci-dessous '
          '(vérifie la saison). Si Crunchyroll demande de te connecter, fais-le une fois.',
      _ => null,
    };
    final inRoom = _room.inRoom;
    return Scaffold(
      backgroundColor: p.background,
      body: Column(children: [
        // Everything stays ABOVE the native view: nothing Flutter may be
        // drawn over it (no dialog, no menu on top of the video).
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(bottom: BorderSide(color: p.ink, width: 2)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SafeArea(
            bottom: false,
            child: Row(children: [
              IconButton(
                tooltip: 'Retour',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(heading.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: kiosqueDisplay(16, color: p.text)),
              ),
              _TogetherButton(
                label: inRoom ? 'SALON · ${_room.userCount}' : (_room.connecting ? 'CONNEXION…' : 'ENSEMBLE'),
                active: inRoom || _panel,
                onTap: () => setState(() => _panel = !_panel),
              ),
            ]),
          ),
        ),
        if (_panel) _togetherPanel(context),
        if (status != null)
          Container(
            width: double.infinity,
            color: _seek == _Seek.notFound ? p.accent : p.surfaceHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(status, style: TextStyle(
                color: _seek == _Seek.notFound ? p.onAccent : p.text,
                fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        Expanded(
          child: OfficialWebView(
            url: _current,
            onScriptRunner: _onBridge,
            fallback: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Le lecteur intégré n’est pas disponible ici.',
                      style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => openInFirefox(context, _current),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Regarder dans Firefox'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _togetherPanel(BuildContext context) {
    final p = context.pal;
    final ext = _ext;
    final r = _room;
    final small = TextStyle(color: p.muted, fontSize: 12.5);
    Widget body;
    if (r.inRoom) {
      // Same card as the extension's popup: the link to share, « Copier »,
      // « Se déconnecter ». (Above the video: nothing may cover it.)
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.groups_rounded, color: p.accent),
              const SizedBox(width: 10),
              Expanded(child: Text('ROLL WITH YOUR FRIENDS', style: kiosqueDisplay(16, color: p.text))),
              Tag('${r.userCount} PERSONNE${r.userCount > 1 ? 'S' : ''}'),
            ]),
            const SizedBox(height: 6),
            Text('Partage ce lien pour inviter tes potes à regarder en synchro avec toi '
                '(Pazulu ou Firefox avec l’extension).', style: small),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(color: p.background, border: Border.all(color: p.ink, width: 2)),
                  child: SelectableText(r.shareUrl ?? '', maxLines: 1,
                      style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _copy, icon: const Icon(Icons.content_copy_rounded, size: 18),
                  label: const Text('Copier le lien')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: r.leave, child: const Text('Se déconnecter')),
            ]),
          ]),
        ),
      );
    } else {
      final canCreate = ext != null && r.pageReady && Crunchyroll.isEpisodeUrl(r.pageUrl) && !r.connecting;
      body = Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          onPressed: canCreate ? r.createRoom : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(r.connecting ? 'Création…' : 'Créer un salon'),
        ),
        SizedBox(
          width: 340,
          child: TextField(
            controller: _joinField,
            onSubmitted: (_) => _join(),
            decoration: const InputDecoration(isDense: true, hintText: 'Coller le lien d’un pote pour rejoindre'),
          ),
        ),
        OutlinedButton(onPressed: _join, child: const Text('Rejoindre')),
        TextButton.icon(
          onPressed: () => openInFirefox(context, _current),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Firefox'),
        ),
        TextButton.icon(
          onPressed: _updatingExt ? null : _forceUpdate,
          icon: const Icon(Icons.system_update_alt_rounded, size: 16),
          label: Text(_updatingExt ? 'Vérification…' : 'Mettre à jour l’extension'),
        ),
        Text(
          _extError ?? r.error ?? r.status ??
              (ext == null
                  ? 'Chargement de Roll With Your Friends…'
                  : !Crunchyroll.isEpisodeUrl(r.pageUrl)
                      ? 'Ouvre un épisode pour créer un salon · extension v${ext.version}'
                      : !r.pageReady
                          ? 'En attente du lecteur Crunchyroll… · extension v${ext.version}'
                          : 'Prêt · extension v${ext.version} · serveur ${ext.syncServer.host} '
                              '(vérifiée à chaque ouverture)'),
          style: small,
        ),
      ]);
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.card,
        border: Border(bottom: BorderSide(color: p.ink, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: body,
    );
  }
}

class _TogetherButton extends StatelessWidget {
  const _TogetherButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: active ? p.accent : p.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.ink, width: 2)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.groups_rounded, size: 18, color: active ? p.onAccent : p.text),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                color: active ? p.onAccent : p.text)),
          ]),
        ),
      ),
    );
  }
}
