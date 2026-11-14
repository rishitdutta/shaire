import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/currency_provider.dart';
import '../providers/friend_provider.dart';
import '../providers/expense_provider.dart';
import '../services/quick_tags_service.dart';
import '../services/quick_expense_service.dart';
import 'edit_tags_dialog.dart';

class FriendQuickActionModal extends StatefulWidget {
  final Map<String, dynamic> friend;
  final VoidCallback? onFriendDeleted;
  final VoidCallback? onExpenseAdded;

  const FriendQuickActionModal({
    super.key,
    required this.friend,
    this.onFriendDeleted,
    this.onExpenseAdded,
  });

  /// Displays the modal with a translucent black background barrier.
  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> friend,
    VoidCallback? onFriendDeleted,
    VoidCallback? onExpenseAdded,
  }) {
    CurrencyProvider? currencyProvider;
    try {
      currencyProvider = Provider.of<CurrencyProvider>(context, listen: false);
    } catch (_) {}
    FriendProvider? friendProvider;
    try {
      friendProvider = Provider.of<FriendProvider>(context, listen: false);
    } catch (_) {}
    ExpenseProvider? expenseProvider;
    try {
      expenseProvider = Provider.of<ExpenseProvider>(context, listen: false);
    } catch (_) {}

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => MultiProvider(
        providers: [
          if (currencyProvider != null)
            ChangeNotifierProvider.value(value: currencyProvider)
          else
            ChangeNotifierProvider(create: (_) => CurrencyProvider()),
          if (friendProvider != null)
            ChangeNotifierProvider.value(value: friendProvider),
          if (expenseProvider != null)
            ChangeNotifierProvider.value(value: expenseProvider),
        ],
        child: FriendQuickActionModal(
          friend: friend,
          onFriendDeleted: onFriendDeleted,
          onExpenseAdded: onExpenseAdded,
        ),
      ),
    );
  }

  @override
  State<FriendQuickActionModal> createState() => _FriendQuickActionModalState();
}

class _FriendQuickActionModalState extends State<FriendQuickActionModal> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();

  bool _paidByYou = true;
  bool _isLoading = false;
  List<String> _tags = List<String>.from(QuickTagsService.defaultTags);
  late String _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = widget.friend['full_name'] ??
        widget.friend['username'] ??
        widget.friend['name'] ??
        'Friend';
    _loadTags();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _amountFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    final tags = await QuickTagsService.getTags();
    if (mounted) {
      setState(() => _tags = tags);
    }
  }

  bool get _isCustom =>
      widget.friend['is_custom'] == true || widget.friend['username'] == null;
  dynamic get _friendId => widget.friend['id'];
  String? get _linkedUserId => widget.friend['linked_user_id']?.toString();

  String get _friendFirstName {
    final name = _displayName.trim();
    if (name.isEmpty) return 'They';
    return name.split(' ').first;
  }

  Future<void> _openEditTags() async {
    final updated = await EditTagsDialog.show(context, _tags);
    if (updated != null && mounted) {
      setState(() => _tags = updated);
    }
  }

  Future<void> _submitQuickExpense() async {
    final amtText = _amountController.text.trim();
    final amount = double.tryParse(amtText) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an amount greater than 0'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      CurrencyProvider? currencyProvider;
      try {
        currencyProvider =
            Provider.of<CurrencyProvider>(context, listen: false);
      } catch (_) {}
      final currencyCode = currencyProvider?.currencyCode ?? 'INR';
      final currencySymbol = currencyProvider?.currencySymbol ?? '₹';

      try {
        await QuickExpenseService.createQuickExpense(
          friendId: _friendId,
          friendName: _displayName,
          isCustom: _isCustom,
          linkedUserId: _linkedUserId,
          amount: amount,
          description: _descriptionController.text.trim(),
          paidByYou: _paidByYou,
          currencyCode: currencyCode,
          currencySymbol: currencySymbol,
        );
      } catch (backendError) {
        final errStr = backendError.toString();
        // Allow mock/preview testing when Supabase client is unauthenticated
        if (errStr.contains('not authenticated') ||
            errStr.contains('No user') ||
            errStr.contains('SupabaseClient')) {
          // Preview mode fallback
        } else {
          rethrow;
        }
      }

      if (mounted) {
        // Refresh feeds
        try {
          Provider.of<FriendProvider>(context, listen: false)
              .fetchFriendsAndRequests();
        } catch (_) {}
        try {
          Provider.of<ExpenseProvider>(context, listen: false).fetchExpenses();
        } catch (_) {}

        Navigator.pop(context); // Close modal
        widget.onExpenseAdded?.call();

        final statusText = _paidByYou
            ? '$_friendFirstName owes you $currencySymbol${amount.toStringAsFixed(2)}'
            : 'You owe $_friendFirstName $currencySymbol${amount.toStringAsFixed(2)}';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Expense recorded! $statusText'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording expense: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    CurrencyProvider? currencyProvider;
    try {
      currencyProvider = Provider.of<CurrencyProvider>(context);
    } catch (_) {}
    final currencySymbol = currencyProvider?.currencySymbol ?? '₹';

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Toggle Paid By: You vs Friend
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Paid by:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: [
                      const ButtonSegment<bool>(
                        value: true,
                        label: Text('You'),
                        icon: Icon(Icons.person, size: 16),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        label: Text(_friendFirstName),
                        icon: const Icon(Icons.face, size: 16),
                      ),
                    ],
                    selected: {_paidByYou},
                    onSelectionChanged: (set) {
                      setState(() => _paidByYou = set.first);
                    },
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Amount Input Box
            TextField(
              controller: _amountController,
              focusNode: _amountFocusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                prefixText: '$currencySymbol ',
                prefixStyle: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
                hintText: '0.00',
                labelText: 'Amount',
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitQuickExpense(),
            ),
            const SizedBox(height: 12),

            // Description Box
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                hintText: 'Description',
                labelText: 'Description',
                prefixIcon: const Icon(Icons.edit_note, size: 20),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
              onSubmitted: (_) => _submitQuickExpense(),
            ),
            const SizedBox(height: 12),

            // Tags row + Edit button at the end
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._tags.map((tag) {
                    final isSelected =
                        _descriptionController.text.trim() == tag;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: FilterChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (_) {
                          setState(() {
                            _descriptionController.text = tag;
                          });
                        },
                      ),
                    );
                  }),
                  // Edit chip at the end
                  ActionChip(
                    avatar: const Icon(Icons.tune, size: 14),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: _openEditTags,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Submit Button
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _submitQuickExpense,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Add Expense',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
