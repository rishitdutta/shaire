import 'package:flutter/material.dart';
import '../providers/currency_provider.dart';

class CategoryBreakdownList extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final CurrencyProvider currencyProvider;

  const CategoryBreakdownList({
    super.key,
    required this.categories,
    required this.currencyProvider,
  });

  Widget _buildCategoryItem(
      BuildContext context,
      CurrencyProvider currencyProvider,
      String name,
      double amount,
      int percent,
      IconData icon) {
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
          Expanded(
            flex: 1,
            child: Text(
              '$percent%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
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
}
