/// Session-scoped, in-memory "cache with TTL" layer for the list fetches
/// that screens re-run on every tab visit / pop-back.
///
/// Rules:
///  - `fetch(key, ...)` skips the network when the key was synced within its
///    TTL — screens switch instantly from data already in memory.
///  - Concurrent fetches of the same key are coalesced into one request.
///  - Anything that *writes* (create/update/delete expense, settle-up,
///    friend request response…) or an explicit pull-to-refresh passes
///    `force: true` to bypass the cache.
///  - `RealtimeService` invalidates keys when the underlying Postgres tables
///    change, so another device's update lands without waiting for the TTL.
///
/// Memory-only by design: the cached values are parsed model objects, and
/// persisting/round-tripping them through SharedPreferences would add a
/// serialization failure mode for a win that only affects cold starts.
class DataCache {
  DataCache._();

  static final DataCache instance = DataCache._();

  /// Default window during which a repeated fetch is served from memory.
  static const Duration defaultTtl = Duration(seconds: 30);

  final Map<String, DateTime> _lastSync = {};
  final Map<String, Future<void>> _inFlight = {};

  bool isFresh(String key, {Duration ttl = defaultTtl}) {
    final at = _lastSync[key];
    return at != null && DateTime.now().difference(at) < ttl;
  }

  /// Marks [key] as needing a network round trip on its next `fetch`.
  void invalidate([String? key]) {
    if (key == null) {
      _lastSync.clear();
    } else {
      _lastSync.remove(key);
    }
  }

  /// Runs [fetch] unless [key] is fresh (and `force` is not set).
  /// Returns `true` when the network was actually hit.
  Future<bool> fetch(
    String key, {
    required Future<void> Function() fetch,
    Duration ttl = defaultTtl,
    bool force = false,
  }) async {
    if (!force && isFresh(key, ttl: ttl)) return false;

    // Coalesce: Home and Expenses opening together must not double-fetch.
    final pending = _inFlight[key];
    if (pending != null) {
      await pending;
      return false;
    }

    late final Future<void> completer;
    completer = (() async {
      await fetch();
      _lastSync[key] = DateTime.now();
    })();
    _inFlight[key] = completer;
    try {
      await completer;
      return true;
    } finally {
      if (identical(_inFlight[key], completer)) _inFlight.remove(key);
    }
  }

  /// Forget everything (call on sign-out so a different account never sees
  /// the previous one's data).
  void reset() {
    _lastSync.clear();
    _inFlight.clear();
  }
}
