import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shaire/providers/expense_provider.dart';
import '../providers/currency_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';
import '../widgets/loading_spinner.dart';
import '../services/expense_draft_service.dart';
import '../database/expense.dart';
import '../theme/theme.dart';
import 'add_expense_screen.dart';
import 'expense_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  late AnimationController _animationController;
  bool _hasLoadedOnce = false;
  double _youGet = 0;
  double _youOwe = 0;
  final Set<String> _hiddenActivityIds = {};
  ExpenseDraft? _activeDraft;

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
    if (!mounted) return;
    setState(() {
      _hiddenActivityIds.addAll(prefs.getStringList('hiddenActivityIds') ?? []);
    });
  }

  Future<void> _saveHiddenActivityIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hiddenActivityIds', _hiddenActivityIds.toList());
  }

  Future<void> _checkDraft() async {
    final draft = await ExpenseDraftService.getDraft();
    if (mounted) {
      setState(() {
        _activeDraft = draft;
      });
    }
  }

  /// `force: false` (tab returns) is served from the provider's TTL cache —
  /// instant, no spinner, no network if the data is young. Pull-to-refresh
  /// passes `force: true` to bypass it.
  Future<void> _fetchData({bool force = false}) async {
    if (!_hasLoadedOnce && mounted) {
      setState(() {});
    }

    try {
      final expenseProvider =
          Provider.of<ExpenseProvider>(context, listen: false);
      final balancesFuture =
          expenseProvider.fetchUserOverallBalances(force: force);
      final expensesFuture = expenseProvider.fetchExpenses(force: force);
      final draftFuture = _checkDraft();

      final results =
          await Future.wait([balancesFuture, expensesFuture, draftFuture]);
      final balances = results[0] as Map<String, double>;

      if (!mounted) return;
      setState(() {
        _youGet = balances['youGet'] ?? 0.0;
        _youOwe = balances['youOwe'] ?? 0.0;
        _hasLoadedOnce = true;
      });
    } catch (e) {
      LoggerService.error('Error fetching data in home_screen: $e');
      if (mounted) {
        setState(() {
          _hasLoadedOnce = true;
        });
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
      return DateFormat('MMM d, yyyy').format(date);
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
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

  // ── Activity rows ───────────────────────────────────────────────────────

  void _hideActivity(String id, {String? title}) {
    setState(() {
      _hiddenActivityIds.add(id);
    });
    _saveHiddenActivityIds();

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          title == null
              ? 'Removed from recent activity'
              : 'Removed “$title” from recent activity',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              _hiddenActivityIds.remove(id);
            });
            _saveHiddenActivityIds();
          },
        ),
      ),
    );
  }

  Widget _buildDraftBanner(BuildContext context) {
    final currencyProvider =
        Provider.of<CurrencyProvider>(context, listen: false);
    final draft = _activeDraft!;
    final desc = draft.description.trim().isNotEmpty
        ? draft.description.trim()
        : 'Untitled Expense';
    final amountText = (draft.totalAmount != null && draft.totalAmount! > 0)
        ? currencyProvider.format(draft.totalAmount!)
        : 'Draft in progress';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Colors.amber.shade600.withValues(alpha: 0.7), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'DRAFT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  amountText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Resume'),
            style: TextButton.styleFrom(
              foregroundColor:
                  isDark ? Colors.amber.shade200 : Colors.amber.shade900,
              backgroundColor: Colors.amber.withValues(alpha: 0.18),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const AddExpenseScreen(resumeDraft: true),
                ),
              );
              _checkDraft();
              if (!mounted) return;
              _fetchData(force: true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Discard Draft',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await ExpenseDraftService.clearDraft();
              if (!mounted) return;
              setState(() => _activeDraft = null);
              messenger.showSnackBar(
                const SnackBar(content: Text('Draft discarded')),
              );
            },
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
    final theme = Theme.of(context);
    return Expanded(
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.surface,
            child: Icon(
              icon,
              size: 16,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // FittedBox keeps large amounts (₹1,23,456.00) on one line
                // on narrow phones instead of overflowing.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    currencyProvider.format(amount),
                    style: theme.textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(
    BuildContext context,
    Expense expense,
    String id,
    String title,
    String action,
    double amount,
    IconData icon,
  ) {
    final currencyProvider = Provider.of<CurrencyProvider>(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExpenseDetailsScreen(expense: expense),
            ),
          ).then((_) {
            if (mounted) _fetchData();
          });
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(icon,
                    color: Theme.of(context).colorScheme.onPrimaryContainer),
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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  currencyProvider.format(amount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              // Swipe or tap the ✕; both remove instantly with an Undo snack —
              // no modal confirm dialog interrupting the flow.
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove from Recent Activity',
                onPressed: () => _hideActivity(id, title: title),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the flattened list of (date header + cards) rows for the sliver.
  List<Widget> _buildActivityRows(BuildContext context) {
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final expenses = expenseProvider.expenses;

    // Group expenses by date, skipping hidden ones
    final groupedActivities = <String, List<Map<String, dynamic>>>{};

    for (var expense in expenses.take(10)) {
      final String expenseId = expense.id.toString();
      if (_hiddenActivityIds.contains(expenseId)) continue;

      final dateKey = _formatDateKey(expense.date);
      final isMyExpense = expense.createdBy == expenseProvider.currentUserId;

      (groupedActivities[dateKey] ??= []).add({
        'id': expenseId,
        'expense': expense,
        'title': expense.description,
        'action': isMyExpense ? 'You paid' : 'Someone paid',
        'amount': expense.totalAmount,
        'icon': _getCategoryIcon(expense.categoryName),
      });
    }

    final sortedDates = groupedActivities.keys.toList()
      ..sort((a, b) {
        if (a == 'Today') return -1;
        if (b == 'Today') return 1;
        if (a == 'Yesterday') return -1;
        if (b == 'Yesterday') return 1;
        // Newest first; parse back from 'MMM d, yyyy' for real ordering.
        final da = DateFormat('MMM d, yyyy').tryParse(a);
        final db = DateFormat('MMM d, yyyy').tryParse(b);
        if (da != null && db != null) return db.compareTo(da);
        return b.compareTo(a);
      });

    final rows = <Widget>[];
    for (final date in sortedDates) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(
          date,
          style: Theme.of(context).textTheme.titleSmall!.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ));
      for (final item in groupedActivities[date]!) {
        rows.add(
          Dismissible(
            key: Key(item['id']),
            direction: DismissDirection.endToStart,
            background: Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              decoration: BoxDecoration(
                color:
                    AppSemanticColors.negative(context).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Icon(Icons.delete_outline,
                  color: AppSemanticColors.negative(context)),
            ),
            // Swipe removes directly — with Undo in the snack — instead of
            // interrupting with a confirmation dialog.
            onDismissed: (_) => _hideActivity(item['id'], title: item['title']),
            child: _buildActivityItem(
              context,
              item['expense'] as Expense,
              item['id'],
              item['title'],
              item['action'],
              item['amount'],
              item['icon'],
            ),
          ),
        );
      }
    }
    return rows;
  }

  Widget _buildEmptyActivity(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 64),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No recent activity',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Expenses you add will show up here. Tap the + button to log your first one.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceSection(BuildContext context) {
    final theme = Theme.of(context);
    final netBalance = _youGet - _youOwe;
    final currencyProvider = Provider.of<CurrencyProvider>(context);
    final positive = netBalance >= 0;
    final netColor = positive
        ? AppSemanticColors.positive(context)
        : AppSemanticColors.negative(context);

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
              // Flat, not a gradient: tints read noisy next to the lists and
              // cost needless shader work on low-end devices.
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Total Balance',
                      style: theme.textTheme.titleMedium!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      positive ? Icons.trending_up : Icons.trending_down,
                      size: 20,
                      color: netColor,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    currencyProvider.format(netBalance),
                    style: theme.textTheme.headlineMedium!.copyWith(
                      fontWeight: FontWeight.bold,
                      color: netColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildBalanceIndicator(
                        context,
                        'You Get',
                        _youGet,
                        AppSemanticColors.positive(context),
                        Icons.arrow_upward,
                      ),
                      const SizedBox(width: 24),
                      _buildBalanceIndicator(
                        context,
                        'You Owe',
                        _youOwe,
                        AppSemanticColors.negative(context),
                        Icons.arrow_downward,
                      ),
                    ],
                  ),
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
    // First load only: show the spinner. Everything after that refreshes in
    // place (no blank-screen flash when navigating back).
    if (!_hasLoadedOnce) {
      return const Scaffold(
        body: SafeArea(
          child: LoadingSpinner(
            initialMessage: 'Loading dashboard...',
            wakeUpMessage: 'Please wait as the backend wakes up...',
          ),
        ),
      );
    }

    final activityRows = _buildActivityRows(context);

    return Scaffold(
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _fetchData(force: true),
          child: CustomScrollView(
            // Makes pull-to-refresh work even when content is short, and
            // across the whole screen (the old non-scrollable Column broke it).
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(child: _buildBalanceSection(context)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    'Recent Activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              if (_activeDraft != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _buildDraftBanner(context),
                  ),
                ),
              if (activityRows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyActivity(context),
                )
              else
                SliverList(
                  delegate: SliverChildListDelegate(activityRows),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }
}
