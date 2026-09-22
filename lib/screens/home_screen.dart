import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shaire/providers/expense_provider.dart';
import '../providers/currency_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';
import '../widgets/loading_spinner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  late AnimationController _animationController;
  bool _isLoading = true;
  double _youGet = 0;
  double _youOwe = 0;
  final Set<String> _hiddenActivityIds = {};

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _loadHiddenActivityIds().then((_) => _fetchData());
  }

  Future<void> _loadHiddenActivityIds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hiddenActivityIds.addAll(prefs.getStringList('hiddenActivityIds') ?? []);
    });
  }

  Future<void> _saveHiddenActivityIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hiddenActivityIds', _hiddenActivityIds.toList());
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    try {
      final expenseProvider =
          Provider.of<ExpenseProvider>(context, listen: false);
      final balances = await expenseProvider.fetchUserOverallBalances();
      await expenseProvider.fetchExpenses();

      if (!mounted) return;
      setState(() {
        _youGet = balances['youGet'] ?? 0.0;
        _youOwe = balances['youOwe'] ?? 0.0;
        _isLoading = false;
      });
    } catch (e) {
      LoggerService.error('Error fetching data in home_screen: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('yyyy-MM-dd').format(date);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Food & Drinks':
        return Icons.restaurant;
      case 'Transportation':
        return Icons.directions_car;
      case 'Entertainment':
        return Icons.movie;
      case 'Shopping':
        return Icons.shopping_cart;
      case 'Utilities':
        return Icons.power;
      case 'Rent':
        return Icons.home;
      case 'Other':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }

  Future<bool> _onWillPop() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit App'),
        content: const Text('Do you want to exit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => exit(0),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    // Unsubscribe from the RouteObserver
    routeObserver.unsubscribe(this);
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    super.didPopNext();
    LoggerService.info(
        "HomeScreen became visible again (didPopNext), fetching data...");
    _fetchData();
  }

  Widget _buildRecentActivities(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Recent Activity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildActivityList(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceIndicator(
    BuildContext context,
    String label,
    double amount,
    Color iconColor,
    IconData icon,
  ) {
    final currencyProvider = Provider.of<CurrencyProvider>(context);
    return Expanded(
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: iconColor.withValues(alpha: 0.2),
            child: Icon(
              icon,
              size: 16,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimary
                          .withValues(alpha: 0.8),
                    ),
              ),
              Text(
                currencyProvider.format(amount),
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(
    BuildContext context,
    String id,
    String title,
    String action,
    double amount,
    IconData icon,
    VoidCallback onRemove,
  ) {
    final currencyProvider = Provider.of<CurrencyProvider>(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    action,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              currencyProvider.format(amount),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.redAccent),
              tooltip: 'Remove from Recent Activity',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final expenses = expenseProvider.expenses;

    // Group expenses by date, skipping hidden ones
    final groupedActivities = <String, List<Map<String, dynamic>>>{};

    for (var expense in expenses.take(10)) {
      final String expenseId = expense.id.toString();
      if (_hiddenActivityIds.contains(expenseId)) continue;

      final dateKey = _formatDateKey(expense.date);
      final isMyExpense = expense.createdBy == expenseProvider.currentUserId;

      if (!groupedActivities.containsKey(dateKey)) {
        groupedActivities[dateKey] = [];
      }
      groupedActivities[dateKey]!.add({
        'id': expenseId,
        'title': expense.description,
        'action': isMyExpense ? 'You paid' : 'Someone paid',
        'amount': expense.totalAmount,
        'icon': _getCategoryIcon(expense.categoryName),
      });
    }

    if (groupedActivities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No recent activities',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final sortedDates = groupedActivities.keys.toList()
      ..sort((a, b) {
        if (a == 'Today') return -1;
        if (b == 'Today') return 1;
        if (a == 'Yesterday') return -1;
        if (b == 'Yesterday') return 1;
        return b.compareTo(a);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final items = groupedActivities[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Text(
                date,
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            ...items.map((item) {
              return Dismissible(
                key: Key(item['id']),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.redAccent,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Remove Activity'),
                      content: const Text(
                          'Are you sure you want to remove this activity from recent activity?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Remove',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (direction) async {
                  setState(() {
                    _hiddenActivityIds.add(item['id']);
                  });
                  await _saveHiddenActivityIds();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Removed from recent activity')),
                  );
                },
                child: _buildActivityItem(
                  context,
                  item['id'],
                  item['title'],
                  item['action'],
                  item['amount'],
                  item['icon'],
                  () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Remove Activity'),
                        content: const Text(
                            'Are you sure you want to remove this activity from recent activity?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Remove',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      setState(() {
                        _hiddenActivityIds.add(item['id']);
                      });
                      await _saveHiddenActivityIds();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Removed from recent activity')),
                      );
                    }
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildBalanceSection(BuildContext context) {
    final theme = Theme.of(context);
    final netBalance = _youGet - _youOwe;
    final currencyProvider = Provider.of<CurrencyProvider>(context);
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      )),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.0, 0.8),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.primary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Balance',
                  style: theme.textTheme.titleMedium!.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currencyProvider.format(netBalance),
                  style: theme.textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildBalanceIndicator(
                      context,
                      'You Get',
                      _youGet,
                      Colors.greenAccent,
                      Icons.arrow_upward,
                    ),
                    const SizedBox(width: 24),
                    _buildBalanceIndicator(
                      context,
                      'You Owe',
                      _youOwe,
                      Colors.redAccent,
                      Icons.arrow_downward,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) {
          exit(0);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: _isLoading
              ? const LoadingSpinner(
                  initialMessage: 'Loading dashboard...',
                  wakeUpMessage: 'Please wait as the backend wakes up...',
                )
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildBalanceSection(context),
                      const SizedBox(height: 24),
                      _buildRecentActivities(context),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
