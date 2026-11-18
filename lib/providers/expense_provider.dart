import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/expense.dart';
import '../services/data_cache.dart';
import '../services/logger_service.dart';
import '../services/realtime_service.dart';

class ExpenseProvider with ChangeNotifier {
  final SupabaseClient supabase = Supabase.instance.client;

  List<Expense> _expenses = [];
  bool _isLoading = false;
  int _lastInsertedId = 0; // Changed from final to allow modification
  double _youGet = 0.0;
  double _youOwe = 0.0;

  List<Expense> get expenses => _expenses;
  bool get isLoading => _isLoading;
  int get lastInsertedId => _lastInsertedId;
  double get youGet => _youGet;
  double get youOwe => _youOwe;
  String? get currentUserId => supabase.auth.currentUser?.id;

  static const String _cacheKey = 'expenses';
  static const Duration _cacheTtl = Duration(seconds: 30);

  /// Fetch all expenses involving the current user.
  ///
  /// Served from the in-memory [DataCache] when fresh (< 30 s) so switching
  /// tabs never blocks on the network; pass `force: true` after a mutation or
  /// an explicit pull-to-refresh.
  Future<void> fetchExpenses({bool force = false}) async {
    await DataCache.instance.fetch(
      _cacheKey,
      ttl: _cacheTtl,
      force: force,
      fetch: _fetchExpensesFromNetwork,
    );
  }

  Future<void> _fetchExpensesFromNetwork() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        LoggerService.error('Cannot fetch expenses: No user is logged in');
        return;
      }

      LoggerService.info('Fetching expenses for user: ${user.id}');

      // Expenses the user created…
      final createdRes = await supabase
          .from('expenses')
          .select('*')
          .eq('created_by', user.id)
          .order('date', ascending: false);

      // …plus expenses someone else created and included them in (previously
      // missing entirely from this list!).
      final myIds =
          createdRes.map<int>((json) => (json['id'] as num).toInt()).toSet();

      List<Map<String, dynamic>> sharedRows = [];
      try {
        final participantRows = await supabase
            .from('expense_participants')
            .select('expense_id')
            .eq('user_id', user.id);
        final sharedIds = participantRows
            .map<int>((row) => (row['expense_id'] as num).toInt())
            .where((id) => !myIds.contains(id))
            .toList();
        if (sharedIds.isNotEmpty) {
          sharedRows = (await supabase
                  .from('expenses')
                  .select('*')
                  .inFilter('id', sharedIds)
                  .order('date', ascending: false))
              .cast<Map<String, dynamic>>();
        }
      } catch (e) {
        // Union failed (e.g. permissions on expense_participants) — the old
        // created-only list is still better than nothing.
        LoggerService.warning('Participant-expense union skipped: $e');
      }

      final combined = [...createdRes, ...sharedRows]
        ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

      LoggerService.debug('Fetched ${combined.length} expenses');

      _expenses =
          combined.map<Expense>((json) => Expense.fromJson(json)).toList();
    } catch (error) {
      LoggerService.error('Error fetching expenses', error);
      _expenses = []; // Reset to empty list on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch expenses by group ID (cached per group; `force` to bypass).
  Future<List<Expense>> fetchGroupExpenses(int groupId,
      {bool force = false}) async {
    final key = 'group_expenses_$groupId';
    await DataCache.instance.fetch(
      key,
      ttl: _cacheTtl,
      force: force,
      fetch: () async {
        _groupExpenseCache[key] = await _fetchGroupExpensesFromNetwork(groupId);
      },
    );
    return _groupExpenseCache[key] ?? const [];
  }

  final Map<String, List<Expense>> _groupExpenseCache = {};

  Future<List<Expense>> _fetchGroupExpensesFromNetwork(int groupId) async {
    try {
      LoggerService.info('Fetching expenses for group: $groupId');

      final response = await supabase
          .from('expenses')
          .select('*')
          .eq('group_id', groupId)
          .order('date', ascending: false);

      return response.map<Expense>((json) => Expense.fromJson(json)).toList();
    } catch (error) {
      LoggerService.error('Error fetching group expenses', error);
      return [];
    }
  }

  /// Fetch a single expense by ID
  Future<Expense?> fetchExpenseById(int id) async {
    try {
      LoggerService.info('Fetching expense by ID: $id');

      final response = await supabase
          .from('expenses')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        LoggerService.warning('Expense not found with ID: $id');
        return null;
      }

      return Expense.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching expense by ID', error);
      return null;
    }
  }

  /// Create a new expense
  Future<bool> createExpense(Expense expense) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Create a copy of expense.toJson() without the id field
      final Map<String, dynamic> expenseData = Map.from(expense.toJson())
        ..remove('id');

      LoggerService.info('Creating expense: ${expense.description}');
      LoggerService.debug('Expense data: $expenseData');

      final response =
          await supabase.from('expenses').insert(expenseData).select().single();

      _lastInsertedId = response['id'];
      LoggerService.info('Expense created with ID: $_lastInsertedId');

      await fetchExpenses(force: true); // Refresh the list after creation
      return true;
    } catch (error) {
      LoggerService.error('Error creating expense', error);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update an existing expense
  Future<bool> updateExpense(Expense expense) async {
    try {
      _isLoading = true;
      notifyListeners();

      LoggerService.info('Updating expense ID: ${expense.id}');

      await supabase
          .from('expenses')
          .update(expense.toJson())
          .eq('id', expense.id);

      LoggerService.info('Expense updated successfully');

      await fetchExpenses(force: true); // Refresh the list after update
      return true;
    } catch (error) {
      LoggerService.error('Error updating expense', error);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete an expense by ID
  Future<bool> deleteExpense(int id) async {
    try {
      _isLoading = true;
      notifyListeners();

      LoggerService.info('Deleting expense ID: $id');

      await supabase.from('expenses').delete().eq('id', id);

      _expenses.removeWhere((expense) => expense.id == id);
      LoggerService.info('Expense deleted successfully');

      // Balances change on delete too — make sure the next read is real.
      DataCache.instance.invalidate(_cacheKey);
      DataCache.instance.invalidate(_balanceCacheKey);

      return true;
    } catch (error) {
      LoggerService.error('Error deleting expense', error);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear all expenses (optional helper)
  void clearExpenses() {
    _expenses = [];
    _groupExpenseCache.clear();
    DataCache.instance.invalidate(_cacheKey);
    notifyListeners();
  }

  static const String _balanceCacheKey = 'overall_balances';

  /// Fetch total balances (you owe / you are owed) for current user.
  Future<Map<String, double>> fetchUserOverallBalances(
      {bool force = false}) async {
    await DataCache.instance.fetch(
      _balanceCacheKey,
      ttl: _cacheTtl,
      force: force,
      fetch: _fetchOverallBalancesFromNetwork,
    );
    return {'youGet': _youGet, 'youOwe': _youOwe};
  }

  Future<void> _fetchOverallBalancesFromNetwork() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final balancesResponse = await supabase
          .from('balances')
          .select('*')
          .or('from_user_id.eq.${user.id},to_user_id.eq.${user.id}');

      double getTotalAmount = 0;
      double oweTotalAmount = 0;

      if (balancesResponse.isNotEmpty) {
        for (var balance in balancesResponse) {
          final double amount = (balance['amount'] as num).toDouble();
          if (balance['from_user_id'] == user.id) {
            if (amount > 0) {
              getTotalAmount += amount;
            } else {
              oweTotalAmount += -amount;
            }
          } else {
            if (amount > 0) {
              oweTotalAmount += amount;
            } else {
              getTotalAmount += -amount;
            }
          }
        }
      } else {
        // Fallback: Compute totals dynamically from unsettled expense_participants
        final myParticipants = await supabase
            .from('expense_participants')
            .select('share_amount, paid_amount, settled')
            .eq('user_id', user.id)
            .eq('settled', false);

        for (var p in myParticipants) {
          final paid = (p['paid_amount'] as num).toDouble();
          final share = (p['share_amount'] as num).toDouble();
          if (paid > share) {
            getTotalAmount += (paid - share);
          } else if (share > paid) {
            oweTotalAmount += (share - paid);
          }
        }
      }

      _youGet = getTotalAmount;
      _youOwe = oweTotalAmount;
      notifyListeners();
    } catch (e) {
      LoggerService.error('Error calculating overall balances', e);
    }
  }

  // ── Realtime: invalidate + refetch when any relevant table changes ──────

  StreamSubscription<String>? _realtimeSub;

  ExpenseProvider() {
    _realtimeSub = RealtimeService.instance.changes.listen((table) {
      if (const {'expenses', 'expense_participants', 'payments', 'balances'}
          .contains(table)) {
        DataCache.instance.invalidate(_cacheKey);
        DataCache.instance.invalidate(_balanceCacheKey);
        _groupExpenseCache.clear();
        fetchExpenses(force: true);
        fetchUserOverallBalances(force: true);
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }
}
