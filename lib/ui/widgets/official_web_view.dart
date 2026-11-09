import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show JavaScriptMode, NavigationDecision, NavigationDelegate, WebViewController, WebViewWidget;
import 'package:webview_win_floating/webview_win_floating.dart' as win;

import '../../core/browser_navigation.dart';
import '../../core/log.dart';
import '../../core/webview_crash_guard.dart';
import '../../design/theme.dart';

class EmbeddedBrowserBridge {
  const EmbeddedBrowserBridge({required this.run, required this.setVisible});
  final Future<Object> Function(String script) run;
  final Future<void> Function(bool visible) setVisible;
}

/// Affiche un site si navigation explicite, ou charge sa page en mode
/// invisible pour le seul parcours de lecture natif de Pazulu Reader.
/// Windows: WebView2 est un controle HWND enfant de la fenetre Flutter.
/// Pas de capture GPU / texture Flutter (cause plausible des crashs 0.4.1).
/// Android: WebView systeme conservee.
/// Aucune extraction CBZ ne se fait depuis cette WebView.
class OfficialWebView extends StatelessWidget {
  const OfficialWebView({super.key, required this.url, required this.fallback,
      this.onScriptRunner, this.initiallyVisible = true});

  final String url;
  final Widget fallback;
  final ValueChanged<EmbeddedBrowserBridge?>? onScriptRunner;
  // False: charge le DOM du chapitre en arriere-plan, sans afficher le site.
  final bool initiallyVisible;

  @override
  Widget build(BuildContext context) {
    if (safeReadingUri(url) == null) return fallback;
    if (Platform.isWindows) return _WindowsEmbeddedBrowser(
        url: url, onScriptRunner: onScriptRunner,
        initiallyVisible: initiallyVisible);
    if (Platform.isAndroid || Platform.isIOS) return _MobileWebView(url: url, onScriptRunner: onScriptRunner);
    return fallback;
  }
}

/// Utilise une vue native enfant (et non une texture / une fenetre Edge --app).
///
/// Un plantage natif Win32 ne peut pas etre intercepte par Dart. Pour eviter
/// une boucle de plantages, un marqueur persistant reste present tant que la
/// WebView est ouverte. Si le processus s'arrete brutalement, la prochaine
/// tentative affiche un mode de securite avec un bouton de nouvel essai.
class _WindowsEmbeddedBrowser extends StatefulWidget {
  const _WindowsEmbeddedBrowser({required this.url, this.onScriptRunner,
      required this.initiallyVisible});

  final String url;
  final ValueChanged<EmbeddedBrowserBridge?>? onScriptRunner;
  final bool initiallyVisible;

  @override
  State<_WindowsEmbeddedBrowser> createState() => _WindowsEmbeddedBrowserState();
}

class _WindowsEmbeddedBrowserState extends State<_WindowsEmbeddedBrowser> {
  win.WinWebViewController? _controller;
  WebviewCrashGuard? _crashGuard;
  Future<void>? _startup;
  bool _ready = false;
  bool _busy = true;
  bool _safeMode = false;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startup = _start();
  }

  Future<void> _start({bool retry = false}) async {
    try {
      final support = await getApplicationSupportDirectory();
      final marker = File('${support.path}${Platform.pathSeparator}webview-v042-active.flag');
      final guard = WebviewCrashGuard(marker);
      _crashGuard = guard;
      if (!await guard.enter(retry: retry)) {
        if (mounted) {
          setState(() {
            _safeMode = true;
            _busy = false;
          });
        }
        return;
      }

      if (!mounted || _closing) {
        await _deleteMarker();
        return;
      }

      final profile = Directory('${support.path}${Platform.pathSeparator}webview2-profile');
      await profile.create(recursive: true);
      if (!mounted || _closing) {
        await _deleteMarker();
        return;
      }

      final controller = win.WinWebViewController(
        params: win.WindowsWebViewControllerCreationParams(
          userDataFolder: profile.path,
          profileName: 'PazuluReader',
        ),
      );
      _controller = controller;
      // CRITIQUE : masquer le HWND AVANT de charger la page. Sur Windows,
      // une WebView2 native recouvre les widgets Flutter si elle reste visible.
      if (!widget.initiallyVisible) await controller.setVisibility(false);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(win.WinNavigationDelegate(
        onPageStarted: (_) {
          if (!widget.initiallyVisible) {
            unawaited(controller.setVisibility(false).catchError((Object _) {}));
          }
        },
        onPageFinished: (_) {
          if (!widget.initiallyVisible) {
            unawaited(controller.setVisibility(false).catchError((Object _) {}));
          }
        },
        onNavigationRequest: (request) {
          // Le plugin signale aussi les demandes de nouvelle fenetre via
          // la navigation. N'autoriser que la navigation du cadre principal.
          if (!request.isMainFrame) {
            AppLog.info('Popup / navigation secondaire refusee : ${request.url}');
            return NavigationDecision.prevent;
          }
          if (safeReadingUri(request.url) == null) {
            AppLog.error('Navigation WebView bloquee', request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (error) {
          AppLog.error('Page WebView2 Windows', error.description);
        },
      ));
      if (!mounted || _closing) return;
      await controller.loadRequest(safeReadingUri(widget.url)!);
      if (!mounted || _closing) return;
      // The native child HWND can be reattached or displayed by the plugin
      // during navigation. Enforce hidden mode again before exposing the JS
      // bridge to the Pazulu-only reader.
      if (!widget.initiallyVisible) await controller.setVisibility(false);
      widget.onScriptRunner?.call(EmbeddedBrowserBridge(
        run: (script) => controller.runJavaScriptReturningResult(script),
        setVisible: (visible) => controller.setVisibility(visible),
      ));
      setState(() {
        _ready = true;
        _busy = false;
      });
    } catch (error, stack) {
      AppLog.error('Lecture integree Windows (HWND)', error, stack);
      widget.onScriptRunner?.call(null);
      final controller = _controller;
      _controller = null;
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (disposeError) {
          AppLog.error('Fermeture WebView2 apres echec', disposeError);
        }
      }
      await _deleteMarker();
      if (mounted && !_closing) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _deleteMarker() async {
    final guard = _crashGuard;
    if (guard == null) return;
    try {
      await guard.leave();
    } catch (error) {
      AppLog.error('Nettoyage du marqueur WebView2', error);
    }
  }

  Future<void> _navigate(String nextUrl) async {
    final uri = safeReadingUri(nextUrl);
    if (uri == null) return;
    try {
      await _controller?.loadRequest(uri);
    } catch (error, stack) {
      AppLog.error('Navigation WebView2 integree', error, stack);
      // Le HWND natif est au-dessus de Flutter. Il faut le fermer AVANT
      // d'afficher une erreur, sinon il masquerait le bouton Reessayer.
      final controller = _controller;
      _controller = null;
      if (controller != null) {
        try {
          await controller.setVisibility(false);
          await controller.dispose();
        } catch (closeError) {
          AppLog.error('Fermeture WebView apres erreur', closeError);
        }
      }
      await _deleteMarker();
      if (mounted && !_closing) {
        setState(() {
          _ready = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant _WindowsEmbeddedBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && _ready) {
      unawaited(_navigate(widget.url));
    }
  }

  Future<void> _retry() async {
    if (_busy || _closing) return;
    setState(() => _busy = true);
    widget.onScriptRunner?.call(null);
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      try {
        await previous.setVisibility(false);
        await previous.dispose();
      } catch (error, stack) {
        AppLog.error('Fermeture WebView avant reprise', error, stack);
      }
    }
    // Sur demande explicite, autoriser un nouvel essai apres un crash natif.
    await _deleteMarker();
    if (!mounted || _closing) return;
    setState(() {
      _safeMode = false;
      _error = null;
      _ready = false;
    });
    _startup = _start(retry: true);
    await _startup;
  }

  Future<void> _close() async {
    widget.onScriptRunner?.call(null);
    try {
      await _startup;
    } catch (error) {
      AppLog.error('Initialisation WebView2 interrompue', error);
    }
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.setVisibility(false);
        await controller.dispose();
      } catch (error, stack) {
        AppLog.error('Fermeture WebView2 Windows', error, stack);
      }
    }
    // Un crash natif pendant dispose() laisse le marqueur en place.
    await _deleteMarker();
  }

  @override
  void dispose() {
    _closing = true;
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (_safeMode || _error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(PazuluSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: p.bright, size: 40),
                const SizedBox(height: PazuluSpace.md),
                Text('Lecture integree en mode securite',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: PazuluSpace.sm),
                Text(
                  _safeMode
                      ? 'La derniere tentative de lecture integree a pu arreter Windows brutalement. '
                          'Pour proteger votre bibliotheque, la page ne se recharge pas automatiquement.'
                      : 'Le moteur de lecture Windows ne peut pas demarrer. Votre bibliotheque reste accessible.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted),
                ),
                if (_error != null) ...[
                  const SizedBox(height: PazuluSpace.sm),
                  SelectableText(_error!, textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
                const SizedBox(height: PazuluSpace.md),
                Text('Le site ne sera jamais ouvert dans une autre fenetre.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(height: PazuluSpace.lg),
                FilledButton.icon(
                  onPressed: _busy ? null : () => unawaited(_retry()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reessayer dans Pazulu'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_busy || !_ready || _controller == null) {
      return Center(child: CircularProgressIndicator(color: p.bright));
    }
    // Cette vue native est integree au HWND Flutter, sans seconde fenetre.
    // Elle n'utilise pas de texture : ne pas ajouter de widgets Flutter dessus.
    return win.WinWebViewWidget(controller: _controller!);
  }
}

class _MobileWebView extends StatefulWidget {
  const _MobileWebView({required this.url, this.onScriptRunner});

  final String url;
  final ValueChanged<EmbeddedBrowserBridge?>? onScriptRunner;

  @override
  State<_MobileWebView> createState() => _MobileWebViewState();
}

class _MobileWebViewState extends State<_MobileWebView> {
  late final WebViewController _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onWebResourceError: (e) => AppLog.error('Page officielle', e.description),
        ),
      )
      ..loadRequest(safeReadingUri(widget.url)!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onScriptRunner?.call(EmbeddedBrowserBridge(
        run: (script) => _controller.runJavaScriptReturningResult(script),
        setVisible: (visible) async {},
      ));
    });
  }

  @override
  void didUpdateWidget(covariant _MobileWebView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      final uri = safeReadingUri(widget.url);
      if (uri != null) unawaited(_controller.loadRequest(uri));
    }
  }

  @override
  void dispose() {
    widget.onScriptRunner?.call(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        if (_progress < 1)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress,
              minHeight: 3,
              color: context.pal.bright,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }
}
