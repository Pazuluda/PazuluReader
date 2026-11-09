import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/theme.dart';
import '../core/log.dart';
import 'app_scope.dart';
import 'discover_page.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'planning_page.dart';
import 'profile_page.dart';
import 'read_actions.dart';
import 'settings_page.dart';
import 'widgets/command_palette.dart';
import 'widgets/common.dart';
import 'widgets/update_dialog.dart';

class _Dest {
  const _Dest(this.label, this.short, this.icon, this.selectedIcon);

  final String label;
  final String short;
  final IconData icon;
  final IconData selectedIcon;
}

const _dests = [
  _Dest('Accueil', 'Accueil', Icons.home_outlined, Icons.home_rounded),
  _Dest('Bibliothèque', 'Biblio', Icons.collections_bookmark_outlined, Icons.collections_bookmark_rounded),
  _Dest('Découvrir', 'Découvrir', Icons.explore_outlined, Icons.explore_rounded),
  _Dest('Planning', 'Planning', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  _Dest('Profil', 'Profil', Icons.emoji_events_outlined, Icons.emoji_events_rounded),
  _Dest('Réglages', 'Réglages', Icons.tune_outlined, Icons.tune_rounded),
];

/// Structure principale : rail latéral sur grand écran, barre du bas sur
/// téléphone. Le fond d'ambiance animé est commun à tous les onglets.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  int _switchCount = 0;

  // Switching tabs must not create a second window or relaunch a route.
  void _go(int i) {
    if (i < 0 || i >= _dests.length || i == _index || !mounted) return;
    setState(() => _index = i);
    // Rare, low-overhead breadcrumbs for a native Windows crash diagnosis.
    _switchCount++;
    if (_switchCount % 10 == 0) {
      AppLog.info('Navigation : $_switchCount changements, onglet ${_dests[i].label}');
    }
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _paletteOpen = false;

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    try {
      await showCommandPalette(context,
          tabs: [for (final d in _dests) d.label],
          goTab: _go,
          searchEverywhere: (q) {
            _go(2);
            discoverSearchRequest.value = q;
          });
    } finally {
      _paletteOpen = false;
    }
  }

  /// Keyboard shortcuts, on the main screen only (never in the reader, a
  /// work page or a dialog), and never while typing in a text field:
  /// Ctrl+K or / = search everything, 1–6 = tabs, R = resume reading.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    if ((keys.isControlPressed || keys.isMetaPressed) && key == LogicalKeyboardKey.keyK) {
      _openPalette();
      return true;
    }
    if (keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText || focus.findAncestorStateOfType<EditableTextState>() != null)) {
      return false;
    }
    const digits = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6,
    ];
    final tab = digits.indexOf(key) >= 0 ? digits.indexOf(key) : numpad.indexOf(key);
    if (tab >= 0) {
      _go(tab);
      return true;
    }
    if (key == LogicalKeyboardKey.slash) {
      _openPalette();
      return true;
    }
    if (key == LogicalKeyboardKey.keyR) {
      final app = AppScope.read(context);
      final resume = app.continueReading();
      if (resume.isEmpty) return false;
      resumeInPazulu(context, resume.first.work);
      return true;
    }
    return false;
  }

  bool _langAsked = false;

  /// First launch: English or French first? (asked once, changeable in
  /// Réglages).
  void _maybeAskLanguage(BuildContext context) {
    final app = AppScope.read(context);
    if (_langAsked || !app.ready || app.settings.langChosen) return;
    _langAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const _LanguageDialog(),
      );
      if (!mounted) return;
      app.chooseLanguagePriority(choice ?? app.settings.comicLangs.first);
    });
  }

  bool _toastScheduled = false;

  /// New achievements: a short celebration, then a link to the profile.
  void _maybeToast(BuildContext context) {
    final app = AppScope.read(context);
    if (_toastScheduled || app.pendingAchievements.isEmpty) return;
    _toastScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toastScheduled = false;
      if (!mounted) return;
      final fresh = app.takePendingAchievements();
      if (fresh.isEmpty) return;
      final p = context.pal;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Row(children: [
          Icon(achievementIcon(fresh.first.icon), color: p.warning),
          const SizedBox(width: 12),
          Expanded(child: Text(fresh.length == 1
              ? 'Succès débloqué : ${fresh.first.title} — ${fresh.first.description}'
              : '${fresh.length} succès débloqués : ${fresh.map((a) => a.title).take(3).join(', ')}'
                  '${fresh.length > 3 ? '…' : ''}')),
        ]),
        action: SnackBarAction(label: 'Voir', onPressed: () => _go(4)),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    _maybeToast(context);
    _maybeAskLanguage(context);
    final unseen = app.unseenUpdates;
    final pages = <Widget>[
      HomePage(onNavigate: _go),
      const LibraryPage(),
      const DiscoverPage(),
      const PlanningPage(),
      const ProfilePage(),
      const SettingsPage(),
    ];

    // Fond « papier imprimé » (trame de points) commun à tous les onglets.
    // Inactive pages keep their state, scroll position and search, but must
    // not animate while hidden.
    final p = context.pal;
    final body = Stack(
      children: [
        Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: HalftonePainter(p.halftone)))),
        Positioned.fill(child: LazyTabBody(activeIndex: _index, pages: pages)),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 840) {
          return Scaffold(
            body: Column(
              children: [
                _KiosqueHeader(
                  index: _index,
                  unseen: unseen,
                  onSelect: _go,
                  onSearch: _openPalette,
                  onToggleTheme: app.toggleDarkMode,
                  dark: app.settings.darkMode,
                  compact: c.maxWidth < 1180,
                  update: app.availableUpdate?.version,
                  updating: app.updateProgress != null,
                ),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _go,
            destinations: [
              for (var i = 0; i < _dests.length; i++)
                NavigationDestination(
                  icon: _badge(i == 3 ? unseen : 0, Icon(_dests[i].icon)),
                  selectedIcon: _badge(i == 3 ? unseen : 0, Icon(_dests[i].selectedIcon)),
                  label: _dests[i].short,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Mount pages only after the first visit. IndexedStack preserves their state,
/// while TickerMode stops repeating skeleton/card animations in other tabs.
/// This avoids eagerly starting every tab and its asynchronous requests when
/// the app opens, and bounds work during rapid navigation.
class LazyTabBody extends StatefulWidget {
  const LazyTabBody({
    super.key,
    required this.activeIndex,
    required this.pages,
  });

  final int activeIndex;
  final List<Widget> pages;

  @override
  State<LazyTabBody> createState() => _LazyTabBodyState();
}

class _LazyTabBodyState extends State<LazyTabBody> {
  final Set<int> _visited = <int>{};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.activeIndex);
  }

  @override
  void didUpdateWidget(covariant LazyTabBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.activeIndex);
    // No setState: Flutter is already rebuilding because widget changed.
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.activeIndex >= 0 && widget.activeIndex < widget.pages.length);
    return IndexedStack(
      index: widget.activeIndex,
      children: [
        for (var i = 0; i < widget.pages.length; i++)
          if (!_visited.contains(i))
            const SizedBox.shrink()
          else
            TickerMode(
              enabled: i == widget.activeIndex,
              child: _TabEntrance(
                active: i == widget.activeIndex,
                child: widget.pages[i],
              ),
            ),
      ],
    );
  }
}

/// Petite entrée animée quand un onglet devient visible, sans recréer la
/// page (son état, sa recherche et son défilement sont conservés).
class _TabEntrance extends StatefulWidget {
  const _TabEntrance({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<_TabEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);

  @override
  void didUpdateWidget(covariant _TabEntrance old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !PazuluMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
        );
      },
    );
  }
}

Widget _badge(int count, Widget child) => Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: child,
    );

/// En-tête « Kiosque » : bloc logo à l'accent, onglets numérotés en
/// majuscules (l'actif en négatif), recherche et bascule clair / sombre.
class _KiosqueHeader extends StatelessWidget {
  const _KiosqueHeader({
    required this.index,
    required this.unseen,
    required this.onSelect,
    required this.onSearch,
    required this.onToggleTheme,
    required this.dark,
    required this.compact,
    this.update,
    this.updating = false,
  });

  /// Version available on GitHub (null = up to date).
  final String? update;
  final bool updating;
  final int index;
  final int unseen;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onToggleTheme;
  final bool dark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final line = BorderSide(color: p.ink, width: 2.5);
    return Container(
      height: 62,
      decoration: BoxDecoration(color: p.surface, border: Border(bottom: line)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: p.accent, border: Border(right: line)),
            alignment: Alignment.center,
            child: Row(children: [
              Icon(Icons.auto_stories_rounded, color: p.onAccent, size: 22),
              const SizedBox(width: 8),
              Text('PAZULU', style: kiosqueDisplay(20, color: p.onAccent)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _dests.length; i++)
                    _HeaderTab(
                      number: (i + 1).toString().padLeft(2, '0'),
                      label: compact ? _dests[i].short : _dests[i].label,
                      selected: i == index,
                      badge: i == 3 ? unseen : 0,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
          ),
          _HeaderButton(
            tooltip: update != null
                ? 'Mise à jour disponible : v$update'
                : (updating ? 'Mise à jour en cours…' : 'Mises à jour'),
            icon: Icons.system_update_alt_rounded,
            highlight: update != null || updating,
            badge: updating ? '…' : (update != null ? 'MAJ' : null),
            onTap: () => showUpdateDialog(context),
          ),
          _HeaderButton(
            tooltip: 'Recherche rapide (Ctrl+K)',
            icon: Icons.search_rounded,
            onTap: onSearch,
          ),
          _HeaderButton(
            tooltip: dark ? 'Passer en mode clair' : 'Passer en mode sombre',
            icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            onTap: onToggleTheme,
          ),
        ],
      ),
    );
  }
}

class _HeaderTab extends StatefulWidget {
  const _HeaderTab({
    required this.number,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final String number;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  State<_HeaderTab> createState() => _HeaderTabState();
}

class _HeaderTabState extends State<_HeaderTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sel = widget.selected;
    final fg = sel ? p.background : p.text;
    return Semantics(
      button: true,
      selected: sel,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: PazuluMotion.of(context, PazuluMotion.hover),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: sel ? p.ink : (_hover ? p.surfaceHigh : Colors.transparent),
              border: Border(right: BorderSide(color: p.ink, width: 2.5)),
            ),
            alignment: Alignment.center,
            child: Row(children: [
              Text(widget.number,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg.withValues(alpha: 0.6))),
              const SizedBox(width: 8),
              Text(widget.label.toUpperCase(), style: kiosqueDisplay(13, color: fg).copyWith(letterSpacing: 0.3)),
              if (widget.badge > 0) ...[
                const SizedBox(width: 8),
                Transform.rotate(
                  angle: -0.1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: p.accent,
                      border: Border.all(color: const Color(0xFF111111), width: 2),
                    ),
                    child: Text(widget.badge > 99 ? '99+' : '${widget.badge}',
                        style: kiosqueDisplay(11, color: p.onAccent)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatefulWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.highlight = false,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  /// Accent background (an update is waiting).
  final bool highlight;
  final String? badge;

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final hi = widget.highlight;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Semantics(
            button: true,
            label: widget.tooltip,
            child: AnimatedContainer(
              duration: PazuluMotion.of(context, PazuluMotion.hover),
              width: 62,
              decoration: BoxDecoration(
                color: hi ? p.accent : (_hover ? p.surfaceHigh : Colors.transparent),
                border: Border(left: BorderSide(color: p.ink, width: 2.5)),
              ),
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                Icon(widget.icon, color: hi ? p.onAccent : p.text, size: 22),
                if (widget.badge != null)
                  Positioned(
                    top: 6,
                    right: 4,
                    child: Transform.rotate(
                      angle: -0.12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: p.ink,
                          border: Border.all(color: p.ink, width: 1.5),
                        ),
                        child: Text(widget.badge!, style: kiosqueDisplay(9, color: p.background)),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageDialog extends StatelessWidget {
  const _LanguageDialog();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget choice(String code, String flag, String title, String detail) => Expanded(
          child: PressableBox(
            onTap: () => Navigator.pop(context, code),
            child: Container(
                padding: const EdgeInsets.all(PazuluSpace.lg),
                child: Column(children: [
                  Text(flag, style: kiosqueDisplay(40)),
                  const SizedBox(height: 10),
                  Text(title, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(detail, textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
                ]),
              ),
          ),
        );
    return AlertDialog(
      title: const Text('Dans quelle langue lire en priorité ?'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Pazulu ouvrira les chapitres dans cette langue quand ils existent, '
              'puis dans l\'autre. Modifiable à tout moment dans Réglages, '
              'et œuvre par œuvre avec « Lire en ».',
              style: TextStyle(color: p.muted, height: 1.45)),
          const SizedBox(height: PazuluSpace.lg),
          Row(children: [
            choice('fr', 'FR', 'Français d\'abord', 'Les scans VF en premier ; l\'anglais quand le chapitre n\'est pas encore traduit.'),
            const SizedBox(width: PazuluSpace.md),
            choice('en', 'EN', 'Anglais d\'abord', 'Les sorties anglaises, souvent plus rapides ; le français ensuite.'),
          ]),
        ]),
      ),
    );
  }
}
