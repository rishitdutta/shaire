import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'logger_service.dart';

/// Broadcasts which Postgres tables changed so cached lists can be
/// invalidated the moment anything moves — including writes from *other*
/// devices (a friend settles up, someone adds an expense to your group…).
///
/// Degrades gracefully: if the Supabase project has not added these tables
/// to the `supabase_realtime` publication, no events arrive and nothing
/// breaks — [DataCache]'s TTL still bounds staleness, and every mutation in
/// this app already forces a refresh.
class RealtimeService {
  RealtimeService._();

  static final RealtimeService instance = RealtimeService._();

  /// Tables whose changes should invalidate app data.
  static const Set<String> watchedTables = {
    'expenses',
    'expense_participants',
    'payments',
    'balances',
    'groups',
    'group_members',
    'friendships',
    'custom_friends',
    'notifications',
    'profiles',
  };

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// Stream of table names that just changed (already debounced).
  Stream<String> get changes => _controller.stream;

  RealtimeChannel? _channel;
  Timer? _debounce;
  final Set<String> _pending = <String>{};
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    try {
      final client = Supabase.instance.client;
      final channel = client.channel('shaire-db-changes');
      for (final table in watchedTables) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (payload) => _note(table),
        );
      }
      channel.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.channelError) {
          LoggerService.warning(
              'Realtime subscribe failed ($error) — falling back to TTL refreshes.');
        }
      });
      _channel = channel;
      LoggerService.info(
          'RealtimeService started for ${watchedTables.length} tables');
    } catch (e) {
      LoggerService.warning('Realtime unavailable ($e) — relying on TTL.');
      _started = false;
    }
  }

  /// Coalesces bursts (one expense insert touches expenses, participants and
  /// balances rows) into a single invalidation pass per 600 ms.
  void _note(String table) {
    _pending.add(table);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      for (final t in _pending) {
        if (!_controller.isClosed) _controller.add(t);
      }
      _pending.clear();
    });
  }

  Future<void> stop() async {
    _debounce?.cancel();
    _pending.clear();
    final ch = _channel;
    _channel = null;
    _started = false;
    if (ch != null) {
      try {
        await Supabase.instance.client.removeChannel(ch);
      } catch (_) {
        // Channel already gone (e.g. client disposed during app shutdown).
      }
    }
  }
}
