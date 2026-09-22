import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shaire/providers/prediction_provider.dart';
import '../providers/currency_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;
import '../database/expense.dart';
import '../providers/expense_provider.dart';
import 'package:intl/intl.dart';
import 'package:shaire/services/logger_service.dart';

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

  @override
  void initState() {
    super.initState();

    // Load cached data first, then fetch if needed
    _loadDataAndFetch();
  }

  Future<void> _loadDataAndFetch() async {
    final predictionProvider =
        Provider.of<PredictionProvider>(context, listen: false);

    // First load cached predictions
    await predictionProvider.loadCachedPredictions();

    // Then fetch fresh expenses & predictions if needed
    await _fetchExpenses();
  }

  Future<void> _fetchExpenses() async {
    setState(() => _isLoading = true);

    try {
      final expenseProvider =
          Provider.of<ExpenseProvider>(context, listen: false);
      await expenseProvider.fetchExpenses();

      // Process expenses to generate weekly data
      _processExpensesData(expenseProvider.expenses);

      // Only fetch predictions if cache is stale
      final predictionProvider =
          Provider.of<PredictionProvider>(context, listen: false);
      if (predictionProvider.needsRefresh) {
        await predictionProvider.fetchPredictions(expenseProvider.expenses);
      }

      if (!predictionProvider.hasError &&
          predictionProvider.futurePredictions.isNotEmpty) {
        final now = DateTime.now();
        // Calculate the start date of the next week (assuming Monday is start)
        final daysUntilNextMonday = 8 - now.weekday;
        final startOfNextWeek =
            DateTime(now.year, now.month, now.day + daysUntilNextMonday);
        final startOfWeekAfterNext =
            startOfNextWeek.add(const Duration(days: 7));
        final startOfTwoWeeksAfterNext =
            startOfWeekAfterNext.add(const Duration(days: 7));

        double nextWeekPredictedTotal = 0;
        double weekAfterNextPredictedTotal = 0;

        for (final prediction in predictionProvider.futurePredictions) {
          final predictionDate = prediction.date;
          // Check if prediction falls within the next week
          if (!predictionDate.isBefore(startOfNextWeek) &&
              predictionDate.isBefore(startOfWeekAfterNext)) {
            nextWeekPredictedTotal += prediction.predictedAmount;
          }
          // Check if prediction falls within the week after next
          else if (!predictionDate.isBefore(startOfWeekAfterNext) &&
              predictionDate.isBefore(startOfTwoWeeksAfterNext)) {
            weekAfterNextPredictedTotal += prediction.predictedAmount;
          }
        }

        // Ensure _weeklyExpensesData has the list and it's long enough
        if (_weeklyExpensesData.isNotEmpty &&
            _weeklyExpensesData[0].length >= 7) {
          _weeklyExpensesData[0][5] =
              nextWeekPredictedTotal; // Index 5 is "In 1w"
          _weeklyExpensesData[0][6] =
              weekAfterNextPredictedTotal; // Index 6 is "In 2w"
          LoggerService.debug(
              'Updated weekly data with predictions: ${_weeklyExpensesData[0]}');
        } else {
          LoggerService.warning(
              'Weekly expenses data structure issue, cannot add predictions.');
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      LoggerService.error(
          'Error fetching expenses or processing predictions', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Add a pull-to-refresh handler that forces prediction refresh
  Future<void> _refreshWithForcedUpdate() async {
    try {
      final expenseProvider =
          Provider.of<ExpenseProvider>(context, listen: false);
      await expenseProvider.fetchExpenses();

      _processExpensesData(expenseProvider.expenses);

      final predictionProvider =
          Provider.of<PredictionProvider>(context, listen: false);
      // Force refresh of predictions
      await predictionProvider.fetchPredictions(expenseProvider.expenses,
          forceRefresh: true);

      if (!predictionProvider.hasError &&
          predictionProvider.futurePredictions.isNotEmpty) {
        final now = DateTime.now();
        final daysUntilNextMonday = 8 - now.weekday;
        final startOfNextWeek =
            DateTime(now.year, now.month, now.day + daysUntilNextMonday);
        final startOfWeekAfterNext =
            startOfNextWeek.add(const Duration(days: 7));
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

        if (_weeklyExpensesData.isNotEmpty &&
            _weeklyExpensesData[0].length >= 7) {
          _weeklyExpensesData[0][5] = nextWeekPredictedTotal;
          _weeklyExpensesData[0][6] = weekAfterNextPredictedTotal;
          LoggerService.debug(
              'Updated weekly data with predictions on refresh: ${_weeklyExpensesData[0]}');
        } else {
          LoggerService.warning(
              'Weekly expenses data structure issue on refresh, cannot add predictions.');
        }
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      LoggerService.error('Error refreshing data', e);
    }
  }

  void _processExpensesData(List<Expense> expenses) {
    // Create a map to group expenses by week
    final Map<String, double> weeklyTotals = {};
    final now = DateTime.now();
    final currentWeek = _getWeekNumber(now);

    // Generate week labels for the last 2 weeks and 2 future weeks
    _weekLabels = [];
    final weeklyData = List<double>.filled(5, 0); // 5 weeks total
    _currentWeekIndex = 2; // "This week" index is in the middle

    // Generate week labels
    for (int i = -2; i <= 2; i++) {
      final weekDate = DateTime(now.year, now.month, now.day + (i * 7));
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
        // Only past 2 weeks and current week
        final index = weekDiff + 2; // Convert to array index (0-2)
        weeklyData[index] += expense.totalAmount;
      }
    }

    // Calculate week-over-week change percentage
    if (weeklyData[1] > 0) {
      // If there's data for last week
      _expenseChangePercent =
          ((weeklyData[2] - weeklyData[1]) / weeklyData[1]) * 100;
    } else {
      _expenseChangePercent = 0;
    }

    // Store weekly data
    _weeklyExpensesData = [weeklyData];

    // Update future predictions
    final predictionProvider =
        Provider.of<PredictionProvider>(context, listen: false);
    if (!predictionProvider.hasError &&
        predictionProvider.futurePredictions.isNotEmpty) {
      final now = DateTime.now();
      final daysUntilNextMonday = 8 - now.weekday;
      final startOfNextWeek =
          DateTime(now.year, now.month, now.day + daysUntilNextMonday);
      final startOfWeekAfterNext =
          startOfNextWeek.add(const Duration(days: 7));
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

      // Update the predictions in the weekly data
      _weeklyExpensesData[0][3] = nextWeekPredictedTotal;     // In 1w
      _weeklyExpensesData[0][4] = weekAfterNextPredictedTotal; // In 2w
    }
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
          child: Center(child: CircularProgressIndicator()),
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
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
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

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                      _buildExpensesGraph(context, currencyProvider),
                      const SizedBox(height: 24),
                      _buildPredictions(
                          context, currencyProvider), // Add this line
                      const SizedBox(height: 24),
                      _buildCategoryBreakdown(
                          context, currencyProvider, expenses),
                      const SizedBox(height: 24),
                      _buildAIInsights(context, expenses),
                      const SizedBox(height: 24),
                      _buildRecentExpenses(context, currencyProvider, expenses),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // Update the expense graph to use real data
  Widget _buildExpensesGraph(
      BuildContext context, CurrencyProvider currencyProvider) {
    // Calculate max expense from real data
    double maxExpense = 0;
    if (_weeklyExpensesData.isNotEmpty && _weeklyExpensesData[0].isNotEmpty) {
      maxExpense = _weeklyExpensesData[0]
          .reduce((max, value) => value > max ? value : max);
      maxExpense = maxExpense > 0 ? maxExpense * 1.2 : 50;
    } else {
      maxExpense = 50;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                'Weekly Spending',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: _weeklyExpensesData.isEmpty
                  ? const Center(child: Text('No expense data available'))
                  : Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxExpense,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (spot) => Colors.blueGrey,
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                return BarTooltipItem(
                                  currencyProvider.format(rod.toY),
                                  const TextStyle(color: Colors.white),
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  if (value < 0 || value >= _weekLabels.length) {
                                    return const Text('');
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      _weekLabels[value.toInt()],
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                },
                                reservedSize: 35,
                              ),
                            ),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups:
                              _weeklyExpensesData[0].asMap().entries.map((entry) {
                            final index = entry.key;
                            final value = entry.value;
                            return BarChartGroupData(
                              x: index,
                              barRods: [
                                BarChartRodData(
                                  toY: value,
                                  color: _getBarColor(context, index),
                                  width: 18,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(4),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(
                  context,
                  Theme.of(context).colorScheme.primary,
                  'Past weeks',
                ),
                const SizedBox(width: 24),
                _buildLegendItem(
                  context,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  'This week',
                ),
                const SizedBox(width: 24),
                _buildLegendItem(
                  context,
                  Colors.grey.shade400,
                  'Projected',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Update category breakdown to use real data
  Widget _buildCategoryBreakdown(BuildContext context,
      CurrencyProvider currencyProvider, List<Expense> expenses) {
    // Calculate totals by category from real data
    final Map<String, double> categoryTotals = {};
    double totalAmount = 0;

    for (var expense in expenses) {
      String category = _getCategoryName(expense.categoryId);
      categoryTotals.update(category, (value) => value + expense.totalAmount,
          ifAbsent: () => expense.totalAmount);
      totalAmount += expense.totalAmount;
    }

    // Convert to percentage and create category items
    final categories = categoryTotals.entries.map((entry) {
      int percent =
          totalAmount > 0 ? ((entry.value / totalAmount) * 100).round() : 0;
      return {
        'name': entry.key,
        'amount': entry.value,
        'percent': percent,
        'icon': _getCategoryIcon(entry.key)
      };
    }).toList();

    // Sort by amount (highest first)
    categories.sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

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
            Text(
              'Category Breakdown',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            categories.isEmpty
                ? const Center(child: Text('No expense data available'))
                : Column(
                    children: categories
                        .map((category) => _buildCategoryItem(
                              context,
                              currencyProvider,
                              category['name'] as String,
                              category['amount'] as double,
                              category['percent'] as int,
                              category['icon'] as IconData,
                            ))
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }

  // Update the recent expenses list to use real data
  Widget _buildRecentExpenses(BuildContext context,
      CurrencyProvider currencyProvider, List<Expense> allExpenses) {
    // Sort expenses by date (most recent first) and take the top 5
    final recentExpenses = List<Expense>.from(allExpenses)
      ..sort((a, b) => b.date.compareTo(a.date));

    final expensesToShow = recentExpenses.take(5).toList();

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
            expensesToShow.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No recent expenses'),
                    ),
                  )
                : Column(
                    children: expensesToShow.map((expense) {
                      return _buildExpenseItem(
                        context,
                        currencyProvider,
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

  Color _getBarColor(BuildContext context, int index) {
    // Current week (highlighted)
    if (index == _currentWeekIndex) {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.8);
    }
    // Past weeks
    else if (index < _currentWeekIndex) {
      return Theme.of(context).colorScheme.primary;
    }
    // Future projections
    else {
      return Colors.grey.shade400;
    }
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildAIInsights(BuildContext context, List<Expense> expenses) {
    // Generate insights based on real expense data
    final Map<String, double> categoryTotals = {};

    // Calculate totals by category
    for (var expense in expenses) {
      String category = _getCategoryName(expense.categoryId);
      categoryTotals.update(category, (value) => value + expense.totalAmount,
          ifAbsent: () => expense.totalAmount);
    }

    // Find highest and lowest categories
    String highestCategory = 'Unknown';
    String lowestCategory = 'Unknown';
    double highestAmount = 0;
    double lowestAmount = double.infinity;

    categoryTotals.forEach((category, amount) {
      if (amount > highestAmount) {
        highestAmount = amount;
        highestCategory = category;
      }
      if (amount < lowestAmount && amount > 0) {
        lowestAmount = amount;
        lowestCategory = category;
      }
    });

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
              _getCategoryIcon(highestCategory),
              '$highestCategory is your highest expense category this month.',
              'Consider setting a budget for this category.',
            ),
            const Divider(),
            _buildInsightTile(
              context,
              Icons.trending_down,
              'You\'ve spent least on $lowestCategory recently.',
              'Great work on controlling these expenses!',
            ),
            if (expenses.isEmpty) const Divider(),
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
      String description,
      String date,
      double amount,
      String category,
      IconData icon) {
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

  Widget _buildCategoryItem(
      BuildContext context,
      CurrencyProvider currencyProvider,
      String name,
      double amount,
      int percent,
      IconData icon) {
    final List<Color> colors = [
      Colors.blue.shade200,
      Colors.blue.shade300,
      Colors.blue.shade400,
      Colors.blue.shade500,
      Colors.blue.shade600,
    ];

    final colorIndex = math.min(
        (categories.length * percent / 100).round(), colors.length - 1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
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
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name),
                    Text(currencyProvider.format(amount)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.7 + (0.3 * percent / 100)),
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '$percent%',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper variables
  List<Map<String, dynamic>> get categories => [
        {
          'name': 'Food & Drinks',
          'amount': 5240.0,
          'percent': 32,
          'icon': Icons.restaurant
        },
        {
          'name': 'Transportation',
          'amount': 2150.0,
          'percent': 13,
          'icon': Icons.directions_car
        },
        {
          'name': 'Entertainment',
          'amount': 3420.0,
          'percent': 21,
          'icon': Icons.movie
        },
        {
          'name': 'Shopping',
          'amount': 4100.0,
          'percent': 25,
          'icon': Icons.shopping_bag
        },
        {
          'name': 'Others',
          'amount': 1470.0,
          'percent': 9,
          'icon': Icons.more_horiz
        },
      ];
}
