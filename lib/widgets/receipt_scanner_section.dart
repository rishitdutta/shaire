import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/currency_provider.dart';

enum BillEntryType { item, tax, discount }

class BillEntry {
  final String description;
  final double amount;
  final List<String> assignedTo;
  final BillEntryType type;

  BillEntry({
    required this.description,
    required this.amount,
    required this.assignedTo,
    this.type = BillEntryType.item,
  });
}

class ReceiptScannerSection extends StatelessWidget {
  final List<BillEntry> billEntries;
  final VoidCallback? onBatchAssign;
  final Function(BillEntry item, int index) onEditItem;

  const ReceiptScannerSection({
    super.key,
    required this.billEntries,
    required this.onBatchAssign,
    required this.onEditItem,
  });

  @override
  Widget build(BuildContext context) {
    if (billEntries.isEmpty) return const SizedBox.shrink();

    final currencyProvider = Provider.of<CurrencyProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Receipt Items',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton.icon(
              icon: const Icon(Icons.people),
              label: const Text('Batch Assign'),
              onPressed: onBatchAssign,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Bill items list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: billEntries.length,
          itemBuilder: (context, index) {
            final item = billEntries[index];

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.description,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          currencyProvider.format(item.amount),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Assigned to: '),
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            children: [
                              if (item.assignedTo.isEmpty)
                                const Chip(label: Text('No one')),
                              ...item.assignedTo.map((name) => Chip(
                                    label: Text(name),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  )),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => onEditItem(item, index),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const Divider(height: 32),
      ],
    );
  }
}

class AssignItemDialog extends StatefulWidget {
  final String itemDescription;
  final List<String> allNames;
  final List<String> initialSelectedNames;
  final Function(List<String>) onSave;

  const AssignItemDialog({
    super.key,
    required this.itemDescription,
    required this.allNames,
    required this.initialSelectedNames,
    required this.onSave,
  });

  @override
  State<AssignItemDialog> createState() => _AssignItemDialogState();
}

class _AssignItemDialogState extends State<AssignItemDialog> {
  late List<String> selectedNames;

  @override
  void initState() {
    super.initState();
    selectedNames = List<String>.from(widget.initialSelectedNames);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Assign "${widget.itemDescription}"'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.allNames.length,
          itemBuilder: (context, i) {
            final name = widget.allNames[i];
            return CheckboxListTile(
              title: Text(name),
              value: selectedNames.contains(name),
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    if (!selectedNames.contains(name)) {
                      selectedNames.add(name);
                    }
                  } else {
                    selectedNames.remove(name);
                  }
                });
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(selectedNames);
            Navigator.pop(context);
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}
