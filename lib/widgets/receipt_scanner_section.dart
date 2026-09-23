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
  final VoidCallback? onDownloadPdf;
  final VoidCallback? onAddCharge;
  final Function(int index)? onDeleteItem;

  const ReceiptScannerSection({
    super.key,
    required this.billEntries,
    required this.onBatchAssign,
    required this.onEditItem,
    this.onDownloadPdf,
    this.onAddCharge,
    this.onDeleteItem,
  });

  @override
  Widget build(BuildContext context) {
    if (billEntries.isEmpty) {
      if (onAddCharge == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Add Custom Charge (Tax, Discount, Tip, etc.)'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
          ),
          onPressed: onAddCharge,
        ),
      );
    }

    final currencyProvider = Provider.of<CurrencyProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title with Item Count
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Receipt Items',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${billEntries.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Action Buttons Row (Wrap to prevent overflow on all screen sizes)
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (onAddCharge != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add Charge'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: onAddCharge,
              ),
            if (onBatchAssign != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.people_outline, size: 16),
                label: const Text('Batch Assign'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: onBatchAssign,
              ),
            if (onDownloadPdf != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('Download PDF'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: onDownloadPdf,
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Bill items list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: billEntries.length,
          itemBuilder: (context, index) {
            final item = billEntries[index];

            return Card(
              margin: const EdgeInsets.only(bottom: 8.0),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (item.type == BillEntryType.discount)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Discount',
                                style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                          )
                        else if (item.type == BillEntryType.tax)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Tax/Fee',
                                style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        Expanded(
                          child: Text(
                            item.description,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${item.type == BillEntryType.discount ? "-" : ""}${currencyProvider.format(item.amount)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: item.type == BillEntryType.discount ? Colors.green : null,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Assigned: ', style: TextStyle(fontSize: 13, color: Colors.grey)),
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              if (item.assignedTo.isEmpty)
                                const Chip(label: Text('No one'), visualDensity: VisualDensity.compact),
                              ...item.assignedTo.map((name) => Chip(
                                    label: Text(name),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  )),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Assign people',
                          onPressed: () => onEditItem(item, index),
                        ),
                        if (onDeleteItem != null)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                            tooltip: 'Remove',
                            onPressed: () => onDeleteItem!(index),
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
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);
          },
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            widget.onSave(selectedNames);
            Navigator.pop(context);
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

class AddCustomChargeDialog extends StatefulWidget {
  final List<String> allNames;
  final Function({
    required String description,
    required double amount,
    required BillEntryType type,
    required List<String> assignedTo,
  }) onAdd;

  const AddCustomChargeDialog({
    super.key,
    required this.allNames,
    required this.onAdd,
  });

  @override
  State<AddCustomChargeDialog> createState() => _AddCustomChargeDialogState();
}

class _AddCustomChargeDialogState extends State<AddCustomChargeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _amountController = TextEditingController();

  BillEntryType _selectedType = BillEntryType.tax;
  bool _splitWithEveryone = true;
  late List<String> _selectedAssignees;

  @override
  void initState() {
    super.initState();
    _selectedAssignees = List<String>.from(widget.allNames);
  }

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  List<String> get _quickSuggestions {
    switch (_selectedType) {
      case BillEntryType.tax:
        return ['GST (5%)', 'Service Fee', 'Delivery', 'Packaging'];
      case BillEntryType.discount:
        return ['Promo Discount', 'Flat Off', 'Coupon', 'Special Offer'];
      case BillEntryType.item:
        return ['Tip', 'Extra Dish', 'Drinks', 'Cover Charge'];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Custom Charge'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Charge Type Selector
              SegmentedButton<BillEntryType>(
                segments: const [
                  ButtonSegment(
                    value: BillEntryType.tax,
                    label: Text('Tax/Fee', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: BillEntryType.discount,
                    label: Text('Discount', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: BillEntryType.item,
                    label: Text('Item/Other', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (Set<BillEntryType> newSelection) {
                  setState(() {
                    _selectedType = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descController,
                decoration: InputDecoration(
                  labelText: 'Description / Name',
                  hintText: _selectedType == BillEntryType.discount
                      ? 'e.g. Promo Code'
                      : _selectedType == BillEntryType.tax
                          ? 'e.g. GST (5%)'
                          : 'e.g. Service Tip',
                  isDense: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),

              // Quick preset chips
              Wrap(
                spacing: 6,
                children: _quickSuggestions.map((suggestion) {
                  return ActionChip(
                    label: Text(suggestion, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _descController.text = suggestion;
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _selectedType == BillEntryType.discount
                      ? 'Discount Amount'
                      : 'Charge Amount',
                  prefixText: _selectedType == BillEntryType.discount ? '- ' : '+ ',
                  isDense: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter an amount';
                  }
                  final parsed = double.tryParse(val.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Please enter a valid amount > 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Assignee Selection
              const Text('Who shares this charge?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              RadioGroup<bool>(
                groupValue: _splitWithEveryone,
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _splitWithEveryone = val;
                    if (val) {
                      _selectedAssignees = List<String>.from(widget.allNames);
                    }
                  });
                },
                child: const Column(
                  children: [
                    RadioListTile<bool>(
                      title: Text('Split with everyone', style: TextStyle(fontSize: 13)),
                      value: true,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile<bool>(
                      title: Text('Select specific people', style: TextStyle(fontSize: 13)),
                      value: false,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ),
              ),

              if (!_splitWithEveryone) ...[
                const Divider(),
                ...widget.allNames.map((name) {
                  return CheckboxListTile(
                    title: Text(name, style: const TextStyle(fontSize: 13)),
                    value: _selectedAssignees.contains(name),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (bool? checked) {
                      setState(() {
                        if (checked == true) {
                          if (!_selectedAssignees.contains(name)) {
                            _selectedAssignees.add(name);
                          }
                        } else {
                          _selectedAssignees.remove(name);
                        }
                      });
                    },
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);
          },
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              if (_selectedAssignees.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select at least one person to assign')),
                );
                return;
              }

              FocusManager.instance.primaryFocus?.unfocus();
              final amount = double.parse(_amountController.text.trim());
              widget.onAdd(
                description: _descController.text.trim(),
                amount: amount,
                type: _selectedType,
                assignedTo: _selectedAssignees,
              );
              Navigator.pop(context);
            }
          },
          child: const Text('ADD'),
        ),
      ],
    );
  }
}
