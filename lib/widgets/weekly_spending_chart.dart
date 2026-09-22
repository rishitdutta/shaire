import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/currency_provider.dart';

class WeeklySpendingChart extends StatelessWidget {
  final List<List<double>> weeklyExpensesData;
  final List<String> weekLabels;
  final int currentWeekIndex;
  final double maxExpense;
  final CurrencyProvider currencyProvider;

  const WeeklySpendingChart({
    super.key,
    required this.weeklyExpensesData,
    required this.weekLabels,
    required this.currentWeekIndex,
    required this.maxExpense,
    required this.currencyProvider,
  });

  Color _getBarColor(BuildContext context, int index) {
    if (index == currentWeekIndex) {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.8);
    } else if (index < currentWeekIndex) {
      return Theme.of(context).colorScheme.primary;
    } else {
      return Colors.grey.shade400;
    }
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
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

  @override
  Widget build(BuildContext context) {
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
              child: weeklyExpensesData.isEmpty
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
                              getTooltipItem:
                                  (group, groupIndex, rod, rodIndex) {
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
                                  if (value < 0 ||
                                      value >= weekLabels.length) {
                                    return const Text('');
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      weekLabels[value.toInt()],
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
                          barGroups: weeklyExpensesData[0]
                              .asMap()
                              .entries
                              .map((entry) {
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
}
