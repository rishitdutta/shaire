import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shaire/providers/prediction_provider.dart';
import '../providers/currency_provider.dart';
import '../widgets/weekly_spending_chart.dart';
import '../widgets/category_breakdown_list.dart';
import '../widgets/loading_spinner.dart';
import '../database/expense.dart';
import '../providers/expense_provider.dart';
import 'package:intl/intl.dart';
import 'package:shaire/services/logger_service.dart';
import '../services/expense_draft_service.dart';
import 'add_expense_screen.dart';
import 'expense_details_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool _isLoading = true;
  double _expenseChangePercent = 0;
  List<List<double>> _weeklyExpensesData = [];
  List<String> _weekLabels = [];
  int _currentWeekIndex = 0;
  double _maxChartExpense = 50.0;
  List<Map<String, dynamic>> _cachedCategories = [];
  String _highestCategory = 'Unknown';
  String _lowestCategory = 'Unknown';
  List<Expense> _cachedRecentExpenses = [];
  List<Expense>? _lastProcessedExpenses;
  ExpenseDraft? _activeDraft;

  @override
  void initState() {
    super.initState();

    // Load cached data and drafts first, then fetch if needed
    _loadDataAndFetch();
  }

  Future<void> _checkDraft() async {
    final draft = await ExpenseDraftService.getDraft();
    if (mounted) {
      setState(() {
        _activeDraft = draft;
      });
    }
  }

  Future<void> _loadDataAndFetch() async {
    final predictionProvider =
        Provider.of<PredictionProvider>(context, listen: false);

    // First load cached predictions & draft
    await Future.wait([
      predictionProvider.loadCachedPredictions(),
      _checkDraft(),
    ]);

    // Then fetch fresh expenses & predictions if needed
    await _fetchExpenses();
  }

  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);

    try {
      final expenseProvider =
          Provider.of<ExpenseProvider>(context, listen: false);
      final predictionProvider =
          Provider.of<PredictionProvider>(context, listen: false);
      await expenseProvider.fetchExpenses();

      if (!mounted) return;
      _processExpensesData(expenseProvider.expenses);
      setState(() => _isLoading = false);

      // Fetch predictions in the background without blocking the expenses UI
      if (predictionProvider.needsRefresh) {
        predictionProvider.fetchPredictions(expenseProvider.expenses);
      }
    } catch (e) {
      LoggerService.error(
          'Error fetching expenses or processing predictions', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Pull-to-refresh handler that forces prediction refresh
  Future<void> _refreshWithForcedUpdate() async {
    try {
      final expenseProvider =
          Provider.of<ExpenseProvider>(context, listen: false);
      final predictionProvider =
          Provider.of<PredictionProvider>(context, listen: false);
      await expenseProvider.fetchExpenses();

      await predictionProvider.fetchPredictions(expenseProvider.expenses,
          forceRefresh: true);

      if (!mounted) return;
      _processExpensesData(expenseProvider.expenses);
      setState(() {});
    } catch (e) {
      LoggerService.error('Error refreshing data', e);
    }
  }

  void _processExpensesData(List<Expense> expenses) {
    _lastProcessedExpenses = expenses;
    final now = DateTime.now();

    // Generate week labels for the last 2 weeks and 2 future weeks
    _weekLabels = [];
    final weeklyData = List<double>.filled(5, 0); // 5 weeks total
    _currentWeekIndex = 2; // "This week" index is in the middle

    for (int i = -2; i <= 2; i++) {
      final weekLabel = i == 0
          ? 'This week'
          : i == -1
              ? 'Last week'
              : i < 0
                  ? '${i.abs()}w ago'
                  : 'In ${i}w';
      _weekLabels.add(weekLabel);
    }

    // Group expenses by week
    for (var expense in expenses) {
      final weekDiff = _getWeekDifference(expense.date, now);
      if (weekDiff >= -2 && weekDiff <= 0) {
        final index = weekDiff + 2; // Convert to array index (0-2)
        weeklyData[index] += expense.totalAmount;
      }
    }

    // Calculate week-over-week change percentage
    if (weeklyData[1] > 0) {
      _expenseChangePercent =
          ((weeklyData[2] - weeklyData[1]) / weeklyData[1]) * 100;
    } else {
      _expenseChangePercent = 0;
    }

    _weeklyExpensesData = [weeklyData];

    // Update future predictions in weekly data
    final predictionProvider =
        Provider.of<PredictionProvider>(context, listen: false);
    if (!predictionProvider.hasError &&
        predictionProvider.futurePredictions.isNotEmpty) {
      final daysUntilNextMonday = 8 - now.weekday;
      final startOfNextWeek =
          DateTime(now.year, now.month, now.day + daysUntilNextMonday);
      final startOfWeekAfterNext = startOfNextWeek.add(const Duration(days: 7));
      final startOfTwoWeeksAfterNext =
          startOfWeekAfterNext.add(const Duration(days: 7));

      double nextWeekPredictedTotal = 0;
      double weekAfterNextPredictedTotal = 0;

      for (final prediction in predictionProvider.futurePredictions) {
        final predictionDate = prediction.date;
        if (!predictionDate.isBefore(startOfNextWeek) &&
            predictionDate.isBefore(startOfWeekAfterNext)) {
          nextWeekPredictedTotal += prediction.predictedAmount;
        } else if (!predictionDate.isBefore(startOfWeekAfterNext) &&
            predictionDate.isBefore(startOfTwoWeeksAfterNext)) {
          weekAfterNextPredictedTotal += prediction.predictedAmount;
        }
      }

      _weeklyExpensesData[0][3] = nextWeekPredictedTotal; // In 1w
      _weeklyExpensesData[0][4] = weekAfterNextPredictedTotal; // In 2w
    }

    // Precompute chart max expense
    if (_weeklyExpensesData.isNotEmpty && _weeklyExpensesData[0].isNotEmpty) {
      final maxVal =
          _weeklyExpensesData[0].reduce((max, v) => v > max ? v : max);
      _maxChartExpense = maxVal > 0 ? maxVal * 1.2 : 50.0;
    } else {
      _maxChartExpense = 50.0;
    }

    // Precompute category breakdown and spending insights
    final Map<String, double> categoryTotals = {};
    double totalAmount = 0;
    for (var expense in expenses) {
      String category = _getCategoryName(expense.categoryId);
      categoryTotals.update(category, (val) => val + expense.totalAmount,
          ifAbsent: () => expense.totalAmount);
      totalAmount += expense.totalAmount;
    }

    _cachedCategories = categoryTotals.entries.map((entry) {
      int percent =
          totalAmount > 0 ? ((entry.value / totalAmount) * 100).round() : 0;
      return {
        'name': entry.key,
        'amount': entry.value,
        'percent': percent,
        'icon': _getCategoryIcon(entry.key),
      };
    }).toList()
      ..sort((a, b) => (b['amount'] as num).compareTo(a['amount'] as num));

    String highCat = 'Unknown';
    String lowCat = 'Unknown';
    double highestAmount = 0;
    double lowestAmount = double.infinity;

    categoryTotals.forEach((category, amount) {
      if (amount > highestAmount) {
        highestAmount = amount;
        highCat = category;
      }
      if (amount < lowestAmount && amount > 0) {
        lowestAmount = amount;
        lowCat = category;
      }
    });
    _highestCategory = highCat;
    _lowestCategory = lowCat;

    // Precompute recent expenses (top 5 sorted by date)
    _cachedRecentExpenses = (List<Expense>.from(expenses)
          ..sort((a, b) => b.date.compareTo(a.date)))
        .take(5)
        .toList();
  }

  // Helper to get week number from date
  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final dayOfYear = date.difference(firstDayOfYear).inDays;
    return (dayOfYear / 7).floor() + 1;
  }

  // Helper to get week difference between two dates
  int _getWeekDifference(DateTime date1, DateTime date2) {
    final week1 = _getWeekNumber(date1);
    final week2 = _getWeekNumber(date2);
    return date1.year == date2.year
        ? week1 - week2
        : ((date1.year - date2.year) * 52) + (week1 - week2);
  }

  // Add a new method to build the prediction section
  Widget _buildPredictions(
      BuildContext context, CurrencyProvider currencyProvider) {
    final predictionProvider = Provider.of<PredictionProvider>(context);

    if (predictionProvider.isLoading) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: LoadingSpinner(
            compact: true,
            initialMessage: 'Generating AI spending forecast...',
            wakeUpMessage: 'Please wait as the AI backend wakes up...',
          ),
        ),
      );
    }

    if (predictionProvider.hasError) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
              'Failed to load predictions: ${predictionProvider.errorMessage}'),
        ),
      );
    }

    final futurePredictions = predictionProvider.futurePredictions;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Predicted Spending',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'AI Powered',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Monthly prediction summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly prediction',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyProvider
                            .format(predictionProvider.totalPredictedSpending),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Daily average',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyProvider
                            .format(predictionProvider.averageDailySpending),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Next 14 Days Forecast',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            futurePredictions.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No prediction data available'),
                    ),
                  )
                : Column(
                    children: futurePredictions.take(7).map((prediction) {
                      final date = prediction.date;
                      final formattedDate = _formatPredictionDate(date);

                      return _buildPredictionItem(
                        context,
                        currencyProvider,
                        formattedDate,
                        prediction.predictedAmount,
                      );
                    }).toList(),
                  ),
            // Show the "See More" button if there are more than 7 days of predictions
            if (futurePredictions.length > 7)
              Center(
                child: TextButton(
                  onPressed: () {
                    // TODO: Navigate to detailed predictions page
                  },
                  child: const Text('See More'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to format prediction dates
  String _formatPredictionDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == tomorrow) {
      return 'Tomorrow';
    } else {
      return DateFormat('EEE, MMM d').format(date); // "Mon, Apr 8"
    }
  }

  // Helper method to build a single prediction item
  Widget _buildPredictionItem(BuildContext context,
      CurrencyProvider currencyProvider, String date, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  'Predicted expense',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            currencyProvider.format(amount),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyProvider = Provider.of<CurrencyProvider>(context);
    final expenseProvider = Provider.of<ExpenseProvider>(context);
    final expenses = expenseProvider.expenses;

    if (!identical(expenses, _lastProcessedExpenses)) {
      _processExpensesData(expenses);
    }

    return Scaffold(
      body: _isLoading
          ? const LoadingSpinner(
              initialMessage: 'Loading expenses & analytics...',
              wakeUpMessage: 'Please wait as the backend wakes up...',
            )
          : RefreshIndicator(
              onRefresh: _refreshWithForcedUpdate, // Use new refresh method
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildExpenseChangeSummary(context, currencyProvider),
                      const SizedBox(height: 16),
                      WeeklySpendingChart(
                        weeklyExpensesData: _weeklyExpensesData,
                        weekLabels: _weekLabels,
                        currentWeekIndex: _currentWeekIndex,
                        maxExpense: _maxChartExpense,
                        currencyProvider: currencyProvider,
                      ),
                      const SizedBox(height: 24),
                      _buildPredictions(
                          context, currencyProvider),
                      const SizedBox(height: 24),
                      CategoryBreakdownList(
                        categories: _cachedCategories,
                        currencyProvider: currencyProvider,
                      ),
                      const SizedBox(height: 24),
                      _buildAIInsights(context),
                      const SizedBox(height: 24),
                      _buildRecentExpenses(context, currencyProvider),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildRecentExpenses(
      BuildContext context, CurrencyProvider currencyProvider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Expenses',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to detailed expense history
                  },
                  child: const Text('See All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_activeDraft != null) ...[
              _buildDraftItem(context, currencyProvider),
              const SizedBox(height: 12),
            ],
            _cachedRecentExpenses.isEmpty && _activeDraft == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No recent expenses'),
                    ),
                  )
                : Column(
                    children: _cachedRecentExpenses.map((expense) {
                      return _buildExpenseItem(
                        context,
                        currencyProvider,
                        expense,
                        expense.description,
                        _formatExpenseDate(expense.date),
                        expense.totalAmount,
                        expense.categoryName,
                        _getCategoryIcon(expense.categoryName),
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftItem(
      BuildContext context, CurrencyProvider currencyProvider) {
    final draft = _activeDraft!;
    final desc = draft.description.trim().isNotEmpty
        ? draft.description.trim()
        : 'Untitled Expense';
    final amountText = (draft.totalAmount != null && draft.totalAmount! > 0)
        ? currencyProvider.format(draft.totalAmount!)
        : 'Draft in progress';

    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade600, width: 1.5),
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
              foregroundColor: Colors.amber.shade900,
              backgroundColor: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const AddExpenseScreen(resumeDraft: true),
                ),
              ).then((_) => _checkDraft());
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            tooltip: 'Discard Draft',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Discard Draft?'),
                  content: const Text(
                    'Are you sure you want to discard this unfinished expense?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ExpenseDraftService.clearDraft();
                _checkDraft();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAIInsights(BuildContext context) {
    final hasNoExpenses =
        _lastProcessedExpenses == null || _lastProcessedExpenses!.isEmpty;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: Theme.of(context).primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Spending Insights',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInsightTile(
              context,
              _getCategoryIcon(_highestCategory),
              '$_highestCategory is your highest expense category this month.',
              'Consider setting a budget for this category.',
            ),
            Divider(color: Theme.of(context).dividerColor),
            _buildInsightTile(
              context,
              Icons.trending_down,
              'You\'ve spent least on $_lowestCategory recently.',
              'Great work on controlling these expenses!',
            ),
            if (hasNoExpenses) Divider(color: Theme.of(context).dividerColor),
            if (hasNoExpenses)
              _buildInsightTile(
                context,
                Icons.add_circle_outline,
                'No expenses recorded yet.',
                'Start adding your expenses to see personalized insights.',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightTile(BuildContext context, IconData icon, String insight,
      String recommendation) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).iconTheme.color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  recommendation,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getCategoryName(int? categoryId) {
    switch (categoryId) {
      case 1:
        return 'Food & Drinks';
      case 2:
        return 'Transportation';
      case 3:
        return 'Entertainment';
      case 4:
        return 'Shopping';
      case 5:
        return 'Utilities';
      case 6:
        return 'Rent';
      case 7:
        return 'Other';
      default:
        return 'Other';
    }
  }

  Widget _buildExpenseChangeSummary(
      BuildContext context, CurrencyProvider currencyProvider) {
    final bool isPositive = _expenseChangePercent >= 0;
    final String changeText = isPositive
        ? '+${_expenseChangePercent.toStringAsFixed(1)}%'
        : '${_expenseChangePercent.toStringAsFixed(1)}%';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This Week vs Last Week',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isPositive ? Colors.red : Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      changeText,
                      style: TextStyle(
                        color: isPositive ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Icon(
              isPositive ? Icons.trending_up : Icons.trending_down,
              color: isPositive ? Colors.red : Colors.green,
              size: 36,
            ),
          ],
        ),
      ),
    );
  }

  String _formatExpenseDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('EEEE').format(date); // Day name
    } else {
      return DateFormat('MMM d').format(date); // "Apr 8"
    }
  }

  Widget _buildExpenseItem(
      BuildContext context,
      CurrencyProvider currencyProvider,
      Expense expense,
      String description,
      String date,
      double amount,
      String category,
      IconData icon) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExpenseDetailsScreen(expense: expense),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: Icon(
                icon,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '$date · $category',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              currencyProvider.format(amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
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
}
