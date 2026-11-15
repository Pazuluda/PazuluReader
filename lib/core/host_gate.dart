import 'dart:async';
import 'dart:collection';

/// Traffic control shared by every background engine.
///
/// Two teams of engines, one per language (« fr » and « en » sites): each
/// team has [perLane] engines (8 by default). When a team has nothing left
/// to do, its engines help the other team. On top of that, never more than
/// [perSite] requests at the same time on one site, so a site never gets a
/// burst of requests (no « too many requests » block).
class HostGate {
  HostGate({this.perSite = 2, this.perLane = 8});

  int perSite;
  int perLane;

  static const lanes = ['fr', 'en'];

  int get total => perLane * lanes.length;

  final Map<String, int> _bySite = {};
  final Map<String, int> _byLane = {};
  int _running = 0;
  final Queue<(String, String, Completer<void>)> _waiting = Queue();

  int get running => _running;
  int runningOn(String site) => _bySite[site] ?? 0;
  int runningIn(String lane) => _byLane[lane] ?? 0;

  /// Runs [task] for [site] in the team of [lane] (« fr » or « en »).
  Future<T> run<T>(String site, Future<T> Function() task, {String lane = 'en'}) async {
    final l = lanes.contains(lane) ? lane : 'en';
    await _enter(site, l);
    try {
      return await task();
    } finally {
      _leave(site, l);
    }
  }

  bool _othersWaiting(String lane) => _waiting.any((w) => w.$2 != lane);

  bool _free(String site, String lane) {
    if (_running >= total || (_bySite[site] ?? 0) >= perSite) return false;
    // Its own team has room, or the other team has nothing waiting (help).
    return (_byLane[lane] ?? 0) < perLane || !_othersWaiting(lane);
  }

  Future<void> _enter(String site, String lane) {
    if (_free(site, lane)) {
      _take(site, lane);
      return Future.value();
    }
    final c = Completer<void>();
    _waiting.add((site, lane, c));
    return c.future;
  }

  void _take(String site, String lane) {
    _running++;
    _bySite[site] = (_bySite[site] ?? 0) + 1;
    _byLane[lane] = (_byLane[lane] ?? 0) + 1;
  }

  void _drop(Map<String, int> m, String k) {
    final n = (m[k] ?? 1) - 1;
    if (n <= 0) {
      m.remove(k);
    } else {
      m[k] = n;
    }
  }

  void _leave(String site, String lane) {
    _running--;
    _drop(_bySite, site);
    _drop(_byLane, lane);
    // Start every waiting request that now has room, in arrival order.
    var started = true;
    while (started) {
      started = false;
      for (final w in _waiting) {
        if (_free(w.$1, w.$2)) {
          _waiting.remove(w);
          _take(w.$1, w.$2);
          w.$3.complete();
          started = true;
          break;
        }
      }
    }
  }
}

/// At most [size] jobs at the same time, the others wait their turn in
/// order (used for the « search every site » lookups: one or two works at
/// a time, never hundreds at once after a big import).
class Slots {
  Slots(this.size);

  int size;
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  int get waiting => _waiting.length;

  Future<T> run<T>(Future<T> Function() job) async {
    if (_running >= size) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    } else {
      _running++;
    }
    try {
      return await job();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete(); // the place passes to the next
      } else {
        _running--;
      }
    }
  }
}
