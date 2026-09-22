import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/currency_provider.dart';
import '../providers/expense_provider.dart';
import '../database/balance.dart';
import '../database/payment.dart';
import 'add_expense_screen.dart';

class FriendDetailsScreen extends StatefulWidget {
  final dynamic friendId;
  const FriendDetailsScreen({super.key, required this.friendId});

  @override
  State<FriendDetailsScreen> createState() => _FriendDetailsScreenState();
}

class _FriendDetailsScreenState extends State<FriendDetailsScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  bool _loading = true, _error = false;
  String? _errorMsg;

  Map<String, dynamic>? _friendProfile;
  final List<Map<String, dynamic>> _expenses = [];
  final List<Map<String, dynamic>> _payments = [];
  double _youOwe = 0.0;
  double _youAreOwed = 0.0;
  double _netBalance = 0.0;

  late TabController _tabController;
  String? _currentUserId;
  late ExpenseProvider _expenseProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentUserId = _supabase.auth.currentUser?.id;
    _expenseProvider = Provider.of<ExpenseProvider>(context, listen: false);
    _expenseProvider.addListener(_onExpensesChanged);
    _loadFriendDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _expenseProvider.removeListener(_onExpensesChanged);
    super.dispose();
  }

  void _onExpensesChanged() {
    if (mounted) {
      _loadFriendDetails();
    }
  }

  Future<void> _loadFriendDetails() async {
    setState(() => _loading = true);
    try {
      // 1. Load friend's profile
      final profileRes = await _supabase
          .from('profiles')
          .select('full_name, username, avatar_url')
          .eq('id', widget.friendId)
          .maybeSingle();

      if (profileRes != null) {
        _friendProfile = profileRes;
      } else {
        try {
          final customRes = await _supabase
              .from('custom_friends')
              .select('name')
              .eq('id', widget.friendId)
              .maybeSingle();
          if (customRes != null) {
            _friendProfile = {
              'full_name': customRes['name'],
              'username': null,
              'avatar_url': null,
            };
          }
        } catch (_) {}
      }

      // 2. Load shared expenses
      final expensesRes = await _supabase.rpc(
        'get_shared_expenses',
        params: {
          'p_current_user_id': _currentUserId,
          'p_friend_id': widget.friendId,
        },
      );

      // 3. Load payments between the two users
      final paymentsRes = await PaymentService().fetchPaymentsBetweenUsers(
        _currentUserId!,
        widget.friendId.toString(),
      );

      _expenses.clear();
      double expensesYouOwe = 0;
      double expensesYouAreOwed = 0;

      for (final e in expensesRes) {
        final amount = (e['total_amount'] as num).toDouble();
        final yourShare = (e['your_share'] as num? ?? 0).toDouble();
        final friendShare = (e['friend_share'] as num?)?.toDouble() ??
            (amount > yourShare ? amount - yourShare : 0.0);
        final youPaid = (e['you_paid'] as num? ?? 0).toDouble();
        final friendPaid = (e['friend_paid'] as num? ?? 0).toDouble();

        // Exact pairwise logic:
        if (youPaid > 0 && friendShare > 0) {
          final coverage = amount > 0 ? (youPaid / amount).clamp(0.0, 1.0) : 1.0;
          expensesYouAreOwed += friendShare * coverage;
        }
        if (friendPaid > 0 && yourShare > 0) {
          final coverage = amount > 0 ? (friendPaid / amount).clamp(0.0, 1.0) : 1.0;
          expensesYouOwe += yourShare * coverage;
        }

        _expenses.add({
          'id': e['id'] as int,
          'description': e['description'],
          'amount': amount,
          'date': DateTime.parse(e['date'] as String),
          'creator_name': e['creator_name'],
          'your_share': yourShare,
          'you_paid': youPaid,
          'friend_paid': friendPaid,
        });
      }

      _payments.clear();
      double paidToFriend = 0.0;
      double receivedFromFriend = 0.0;
      for (final p in paymentsRes) {
        final pAmt = (p['amount'] as num).toDouble();
        if (p['from_user_id'] == _currentUserId) {
          paidToFriend += pAmt;
        } else {
          receivedFromFriend += pAmt;
        }
        _payments.add(Map<String, dynamic>.from(p));
      }

      final net = (expensesYouAreOwed - expensesYouOwe) + (paidToFriend - receivedFromFriend);
      _netBalance = net;
      if (net > 0) {
        _youAreOwed = net;
        _youOwe = 0.0;
      } else {
        _youOwe = net.abs();
        _youAreOwed = 0.0;
      }
    } catch (e) {
      _error = true;
      _errorMsg = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _navigateToAddExpense() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          friendId: widget.friendId,
          friendName:
              _friendProfile?['full_name'] ?? _friendProfile?['username'],
        ),
      ),
    ).then((_) => _loadFriendDetails());
  }

  Future<void> _settleUp() async {
    final selectedAmount = await showDialog<double>(
      context: context,
      builder: (ctx) => SettleUpDialog(
        youOwe: _youOwe,
        youAreOwed: _youAreOwed,
      ),
    );

    if (selectedAmount != null && selectedAmount > 0 && mounted) {
      setState(() => _loading = true);
      try {
        final currencyProvider = Provider.of<CurrencyProvider>(context, listen: false);
        final currencyCode = currencyProvider.currencyCode;
        final fromId = _netBalance < 0 ? _currentUserId! : widget.friendId.toString();
        final toId = _netBalance < 0 ? widget.friendId.toString() : _currentUserId!;

        // 1. Create a payment record via PaymentService
        await PaymentService().createPaymentRecord(
          fromUserId: fromId,
          toUserId: toId,
          amount: selectedAmount,
          currency: currencyCode,
          paymentMethod: 'manual',
          notes: 'Settlement payment',
        );

        // 2. Adjust balances in database
        final balanceService = BalanceService();
        await balanceService.adjustBalance(
          fromUserId: toId, // creditor
          toUserId: fromId, // debtor
          deltaAmount: -selectedAmount, // reduces the debt
          currency: currencyCode,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settlement of ${currencyProvider.format(selectedAmount)} recorded'),
          ),
        );

        // Refresh data
        await _loadFriendDetails();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = true;
          _errorMsg = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recording payment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;
    final onPrimaryColor = colorScheme.onPrimary;
    final currencyProvider = Provider.of<CurrencyProvider>(context);

    if (_loading && _friendProfile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Friend Details')),
        body: Center(child: Text('Error: $_errorMsg')),
      );
    }

    final friendName =
        _friendProfile?['full_name'] ?? _friendProfile?['username'] ?? 'Friend';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: onPrimaryColor,
        iconTheme: IconThemeData(color: onPrimaryColor),
        titleTextStyle:
            theme.textTheme.titleLarge?.copyWith(color: onPrimaryColor),
        title: Text(friendName),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: onPrimaryColor,
          dividerColor: onPrimaryColor,
          labelColor: onPrimaryColor,
          unselectedLabelColor: onPrimaryColor.withAlpha((0.7 * 255).round()),
          tabs: const [
            Tab(text: 'EXPENSES'),
            Tab(text: 'SUMMARY'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Balance summary card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _netBalance >= 0 ? 'You are owed' : 'You owe',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Text(
                        currencyProvider.format(_netBalance.abs()),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: _netBalance >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  if (_netBalance != 0) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _settleUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: onPrimaryColor,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.handshake),
                          SizedBox(width: 8),
                          Text('Settle Up'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Expenses Tab
                _expenses.isEmpty
                    ? const Center(child: Text('No shared expenses found'))
                    : RefreshIndicator(
                        onRefresh: _loadFriendDetails,
                        child: ListView.builder(
                          itemCount: _expenses.length,
                          itemBuilder: (ctx, i) {
                            final exp = _expenses[i];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      primaryColor.withValues(alpha: 0.1),
                                  child: Icon(Icons.receipt, color: primaryColor),
                                ),
                                title: Text(
                                  exp['description'],
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(DateFormat.yMMMd()
                                        .format(exp['date'] as DateTime)),
                                    Text('Paid by ${exp['creator_name']}'),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      currencyProvider.format(exp['amount']),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Your share: ${currencyProvider.format(exp['your_share'])}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                      ),

                // Summary Tab - Payment history and other details
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Expense Statistics',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ListTile(
                                title: const Text('Total Shared Expenses'),
                                trailing: Text(
                                  '${_expenses.length}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              ListTile(
                                title: const Text('Total Amount'),
                                trailing: Text(
                                  currencyProvider.format(
                                      _expenses.fold<double>(
                                          0,
                                          (sum, exp) =>
                                              sum + (exp['amount'] as num))),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Recent Settlements',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_payments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No settlements recorded yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        Card(
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _payments.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final p = _payments[idx];
                              final isPayer = p['from_user_id'] == _currentUserId;
                              final pAmt = (p['amount'] as num).toDouble();
                              final pDate = p['payment_date'] != null
                                  ? DateTime.parse(p['payment_date'] as String)
                                  : null;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isPayer ? Colors.orange.shade100 : Colors.green.shade100,
                                  child: Icon(
                                    isPayer ? Icons.arrow_upward : Icons.arrow_downward,
                                    color: isPayer ? Colors.orange.shade800 : Colors.green.shade800,
                                  ),
                                ),
                                title: Text(isPayer ? 'You paid friend' : 'Friend paid you'),
                                subtitle: pDate != null ? Text(DateFormat.yMMMd().format(pDate)) : null,
                                trailing: Text(
                                  currencyProvider.format(pAmt),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isPayer ? Colors.orange.shade800 : Colors.green.shade800,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _navigateToAddExpense,
              backgroundColor: primaryColor,
              foregroundColor: onPrimaryColor,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// Dialog for settling up
class SettleUpDialog extends StatefulWidget {
  final double youOwe;
  final double youAreOwed;

  const SettleUpDialog({
    super.key,
    required this.youOwe,
    required this.youAreOwed,
  });

  @override
  State<SettleUpDialog> createState() => _SettleUpDialogState();
}

class _SettleUpDialogState extends State<SettleUpDialog> {
  late TextEditingController _amountController;
  final _formatter = NumberFormat.currency(symbol: '₹');
  bool _useFullAmount = true;

  @override
  void initState() {
    super.initState();
    final netAmount = (widget.youOwe - widget.youAreOwed).abs();
    _amountController =
        TextEditingController(text: netAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final netAmount = (widget.youOwe - widget.youAreOwed).abs();
    final youPay = widget.youOwe > widget.youAreOwed;

    return AlertDialog(
      title: Text(youPay ? 'You Pay' : 'They Pay'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Settle up with ${_formatter.format(netAmount)}?',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Use full amount'),
            value: _useFullAmount,
            onChanged: (value) {
              setState(() {
                _useFullAmount = value ?? true;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (!_useFullAmount)
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () {
            try {
              final amount = _useFullAmount
                  ? netAmount
                  : double.parse(_amountController.text);
              Navigator.pop(context, amount);
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a valid amount')),
              );
            }
          },
          child: const Text('RECORD'),
        ),
      ],
    );
  }
}
