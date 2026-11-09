enum BreakerState { closed, open, halfOpen }

class _Circuit {
  BreakerState state = BreakerState.closed;
  int consecutiveFailures = 0;
  int trips = 0;
  DateTime? openUntil;
  String? reason;
  bool trialInFlight = false;
}

/// Snapshot for diagnostics.
class BreakerStatus {
  const BreakerStatus(this.key, this.state, {this.openUntil, this.reason,
    this.consecutiveFailures = 0});

  final String key;
  final BreakerState state;
  final DateTime? openUntil;
  final String? reason;
  final int consecutiveFailures;
}

/// Per-domain circuit breaker with expiry. After [threshold] consecutive
/// failures a domain is left alone for a cooldown that doubles on repeated
/// trips (capped by [maxCooldown]). A 429 opens the circuit for exactly the
/// server's Retry-After delay. After expiry one trial request is allowed
/// (half-open); its result closes or re-opens the circuit.
class CircuitBreaker {
  CircuitBreaker({
    this.threshold = 4,
    this.baseCooldown = const Duration(seconds: 20),
    this.maxCooldown = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int threshold;
  final Duration baseCooldown;
  final Duration maxCooldown;
  final DateTime Function() _clock;
  final Map<String, _Circuit> _circuits = {};

  _Circuit _get(String key) => _circuits.putIfAbsent(key.toLowerCase(), _Circuit.new);

  /// Whether a request may be sent now. In half-open state only one trial.
  bool allow(String key) {
    final c = _get(key);
    if (c.state == BreakerState.closed) return true;
    if (c.state == BreakerState.open) {
      final until = c.openUntil;
      if (until != null && !_clock().isBefore(until)) {
        c.state = BreakerState.halfOpen;
        c.trialInFlight = true;
        return true;
      }
      return false;
    }
    // Half-open: a single trial request at a time.
    if (c.trialInFlight) return false;
    c.trialInFlight = true;
    return true;
  }

  /// Remaining wait before the next attempt, or null when allowed.
  Duration? retryIn(String key) {
    final c = _circuits[key.toLowerCase()];
    if (c == null || c.state == BreakerState.closed) return null;
    final until = c.openUntil;
    if (until == null) return null;
    final left = until.difference(_clock());
    return left.isNegative ? null : left;
  }

  void recordSuccess(String key) {
    final c = _get(key);
    c
      ..state = BreakerState.closed
      ..consecutiveFailures = 0
      ..trips = 0
      ..openUntil = null
      ..reason = null
      ..trialInFlight = false;
  }

  void recordFailure(String key, {String? reason}) {
    final c = _get(key);
    c.trialInFlight = false;
    c.consecutiveFailures++;
    c.reason = reason;
    if (c.state == BreakerState.halfOpen || c.consecutiveFailures >= threshold) {
      c.trips++;
      var cooldown = baseCooldown * (1 << (c.trips - 1).clamp(0, 8).toInt());
      if (cooldown > maxCooldown) cooldown = maxCooldown;
      c.state = BreakerState.open;
      c.openUntil = _clock().add(cooldown);
    }
  }

  /// Open immediately for [delay] (HTTP 429 Retry-After, maintenance…).
  void openFor(String key, Duration delay, {String? reason}) {
    final c = _get(key);
    c.trialInFlight = false;
    c.state = BreakerState.open;
    c.reason = reason;
    final until = _clock().add(delay);
    if (c.openUntil == null || until.isAfter(c.openUntil!)) c.openUntil = until;
  }

  void reset(String key) => _circuits.remove(key.toLowerCase());

  /// The user explicitly asked to retry: every paused source gets a new
  /// chance immediately (a 429 Retry-After pause is kept, it is the site's rule).
  void resetAll() => _circuits.removeWhere((_, c) => c.reason != 'HTTP 429');

  BreakerStatus status(String key) {
    final c = _circuits[key.toLowerCase()];
    if (c == null) return BreakerStatus(key, BreakerState.closed);
    return BreakerStatus(key, c.state, openUntil: c.openUntil, reason: c.reason,
        consecutiveFailures: c.consecutiveFailures);
  }

  Iterable<BreakerStatus> get all => _circuits.keys.map(status);
}

/// Parses `Retry-After` (delta-seconds or HTTP-date). Bounded to 1 hour so a
/// hostile header cannot disable a source forever.
Duration? parseRetryAfter(String? header, {DateTime? now}) {
  if (header == null) return null;
  final value = header.trim();
  if (value.isEmpty) return null;
  final seconds = int.tryParse(value);
  Duration? result;
  if (seconds != null) {
    if (seconds < 0) return null;
    result = Duration(seconds: seconds);
  } else {
    final date = _parseHttpDate(value);
    if (date == null) return null;
    final diff = date.difference((now ?? DateTime.now()).toUtc());
    result = diff.isNegative ? Duration.zero : diff;
  }
  const cap = Duration(hours: 1);
  return result > cap ? cap : result;
}

DateTime? _parseHttpDate(String value) {
  // IMF-fixdate: Sun, 06 Nov 1994 08:49:37 GMT
  final m = RegExp(r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$')
      .firstMatch(value);
  if (m == null) return null;
  const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug',
    'sep', 'oct', 'nov', 'dec'];
  final month = months.indexOf(m.group(2)!.toLowerCase());
  if (month < 0) return null;
  return DateTime.utc(int.parse(m.group(3)!), month + 1, int.parse(m.group(1)!),
      int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
}
