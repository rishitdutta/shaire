import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/currency_provider.dart';

enum SplitType { equal, manual, percentage }

class SplitOptionsWidget extends StatelessWidget {
  final TabController tabController;
  final SplitType splitType;
  final List<Map<String, dynamic>> selectedContacts;
  final TextEditingController totalAmountController;
  final Map<String, TextEditingController> individualAmountControllers;
  final Map<String, TextEditingController> individualPercentControllers;
  final ValueChanged<SplitType> onSplitTypeChanged;
  final VoidCallback onAmountsChanged;

  const SplitOptionsWidget({
    super.key,
    required this.tabController,
    required this.splitType,
    required this.selectedContacts,
    required this.totalAmountController,
    required this.individualAmountControllers,
    required this.individualPercentControllers,
    required this.onSplitTypeChanged,
    required this.onAmountsChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedContacts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text('Add friends or groups to split the expense'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Split Details',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),

        // Split type tabs
        TabBar(
          controller: tabController,
          tabs: const [
            Tab(text: 'Equal'),
            Tab(text: 'Manual'),
            Tab(text: 'Percentage'),
          ],
          dividerColor: Colors.grey.shade300,
          onTap: (index) {
            onSplitTypeChanged(SplitType.values[index]);
          },
        ),

        const SizedBox(height: 16),

        // Tab content
        SizedBox(
          height: (selectedContacts.length + 1) * 60.0,
          child: TabBarView(
            controller: tabController,
            children: [
              _buildEqualSplitTab(context),
              _buildManualSplitTab(context),
              _buildPercentageSplitTab(context),
            ],
          ),
        ),

        Divider(height: 32, color: Colors.grey.shade300),
      ],
    );
  }

  Widget _buildEqualSplitTab(BuildContext context) {
    final totalAmount = double.tryParse(totalAmountController.text) ?? 0;
    final totalParticipants = selectedContacts.length + 1;
    final perPersonAmount =
        totalParticipants > 0 ? totalAmount / totalParticipants : 0.0;
    final currencyProvider =
        Provider.of<CurrencyProvider>(context, listen: false);

    return ListView(
      children: [
        // Current user (you)
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: const Text('You (paid)'),
          trailing: Text(
            currencyProvider.format(perPersonAmount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),

        // Selected contacts
        ...selectedContacts.map((contact) => ListTile(
              leading: CircleAvatar(
                child: Icon(
                    contact['isGroup'] == true ? Icons.group : Icons.person),
              ),
              title: Text(contact['name'] ?? ''),
              trailing: Text(
                currencyProvider.format(perPersonAmount),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )),
      ],
    );
  }

  Widget _buildManualSplitTab(BuildContext context) {
    final currencyProvider =
        Provider.of<CurrencyProvider>(context, listen: false);
    final totalAmount = double.tryParse(totalAmountController.text) ?? 0;

    // Ensure controller for "You" exists
    individualAmountControllers['you'] ??= TextEditingController(
      text: (totalAmount / (selectedContacts.length + 1)).toStringAsFixed(2),
    );

    return ListView(
      children: [
        // Current user (you)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person)),
              const SizedBox(width: 16),
              const Expanded(child: Text('You (paid)')),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: individualAmountControllers['you'],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    prefixText: currencyProvider.currencySymbol,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  onChanged: (_) => onAmountsChanged(),
                ),
              ),
            ],
          ),
        ),

        // Selected contacts
        ...selectedContacts.map((contact) {
          final id = contact['id'].toString();

          individualAmountControllers[id] ??= TextEditingController(
            text:
                (totalAmount / (selectedContacts.length + 1)).toStringAsFixed(2),
          );

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                CircleAvatar(
                  child: Icon(
                      contact['isGroup'] == true ? Icons.group : Icons.person),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(contact['name'] ?? '')),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: individualAmountControllers[id],
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixText: currencyProvider.currencySymbol,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    onChanged: (_) => onAmountsChanged(),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPercentageSplitTab(BuildContext context) {
    final currencyProvider =
        Provider.of<CurrencyProvider>(context, listen: false);
    final totalAmount = double.tryParse(totalAmountController.text) ?? 0;
    final defaultPercentage = 100 / (selectedContacts.length + 1);

    individualPercentControllers['you'] ??=
        TextEditingController(text: defaultPercentage.toStringAsFixed(0));
    individualAmountControllers['you'] ??= TextEditingController(
      text: ((defaultPercentage / 100) * totalAmount).toStringAsFixed(2),
    );

    return ListView(
      children: [
        // Current user (you)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person)),
              const SizedBox(width: 16),
              const Expanded(child: Text('You (paid)')),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: individualPercentControllers['you'],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        suffixText: '%',
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (_) => onAmountsChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(currencyProvider.format(
                    double.tryParse(
                            individualAmountControllers['you']?.text ?? '0') ??
                        ((defaultPercentage / 100) * totalAmount),
                  )),
                ],
              ),
            ],
          ),
        ),

        // Selected contacts
        ...selectedContacts.map((contact) {
          final id = contact['id'].toString();

          individualPercentControllers[id] ??=
              TextEditingController(text: defaultPercentage.toStringAsFixed(0));

          individualAmountControllers[id] ??= TextEditingController(
            text:
                ((defaultPercentage / 100) * totalAmount).toStringAsFixed(2),
          );

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                CircleAvatar(
                  child: Icon(
                      contact['isGroup'] == true ? Icons.group : Icons.person),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(contact['name'] ?? '')),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: individualPercentControllers[id],
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          suffixText: '%',
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        onChanged: (_) => onAmountsChanged(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(currencyProvider.format(double.tryParse(
                            individualAmountControllers[id]?.text ?? '0') ??
                        0.0)),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
