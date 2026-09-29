import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shaire/database/expense.dart';
import 'package:shaire/providers/expense_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/bill_service.dart';
import '../services/logger_service.dart';
import '../providers/currency_provider.dart';
import '../database/receipt.dart';
import '../database/balance.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'package:image/image.dart' as img;
import '../providers/friend_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/split_options_widget.dart';
import '../widgets/contact_selector_section.dart';
import 'dart:async';
import '../widgets/receipt_scanner_section.dart';
import '../widgets/loading_spinner.dart';
import '../services/pdf_service.dart';
import '../services/expense_draft_service.dart';
import '../services/custom_friend_balance_service.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class AddExpenseScreen extends StatefulWidget {
  final int? groupId;
  final String? groupName;
  final dynamic friendId;
  final String? friendName;
  final bool resumeDraft;

  const AddExpenseScreen({
    super.key,
    this.groupId,
    this.groupName,
    this.friendId,
    this.friendName,
    this.resumeDraft = false,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Form key for validation
  final _formKey = GlobalKey<FormState>();

  // Tab controller
  late TabController _tabController;

  // Selected split type
  SplitType _splitType = SplitType.equal;

  // Friends & Groups data
  var _availableContacts = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _selectedContactsData = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final _supabase = Supabase.instance.client;

  // Form fields
  final TextEditingController _descriptionController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  final TextEditingController _totalAmountController = TextEditingController();

  // Individual amount/percentage controllers (created dynamically)
  final Map<String, TextEditingController> _individualAmountControllers = {};
  final Map<String, TextEditingController> _individualPercentControllers = {};

  // Available categories
  final List<String> _categories = [
    'Food & Drinks',
    'Transportation',
    'Entertainment',
    'Shopping',
    'Utilities',
    'Rent',
    'Other'
  ];

  // Bill entries from receipt scan
  final List<BillEntry> _billEntries = [];

  // Loading state
  bool _isLoading = false;
  String _loadingMessage = 'Saving expense & updating balances...';

  // Services
  final BillService _billService = BillService();
  final ReceiptService _receiptService = ReceiptService();
  int? _currentReceiptId;
  File? _receiptImageFile;

  Timer? _debounceTimer;
  String _payerId = 'you';
  String _payerName = 'You';
  bool _isDiscardedOrSaved = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveCurrentDraft();
    }
  }

  void _scheduleAutoSave() {
    if (_isDiscardedOrSaved) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveCurrentDraft();
    });
  }

  bool get _hasMeaningfulContent {
    if (_isDiscardedOrSaved) return false;
    if (_descriptionController.text.trim().isNotEmpty) return true;
    final amt = double.tryParse(_totalAmountController.text) ?? 0;
    if (amt > 0) return true;
    if (_billEntries.isNotEmpty) return true;
    if (_receiptImageFile != null) return true;

    final int prefilledCount =
        (widget.groupId != null ? 1 : 0) + (widget.friendId != null ? 1 : 0);
    if (_selectedContactsData.length > prefilledCount) return true;

    return false;
  }

  Future<void> _saveCurrentDraft() async {
    if (_isDiscardedOrSaved) return;
    if (!_hasMeaningfulContent) {
      await ExpenseDraftService.clearDraft();
      return;
    }

    final draft = ExpenseDraft(
      description: _descriptionController.text,
      totalAmount: double.tryParse(_totalAmountController.text),
      category: _selectedCategory,
      date: _selectedDate,
      splitType: _getSplitTypeString(_splitType),
      selectedContacts: _selectedContactsData,
      individualAmounts:
          _individualAmountControllers.map((k, v) => MapEntry(k, v.text)),
      individualPercents:
          _individualPercentControllers.map((k, v) => MapEntry(k, v.text)),
      billEntries: _billEntries,
      receiptImagePath: _receiptImageFile?.path,
      currentReceiptId: _currentReceiptId,
      groupId: widget.groupId,
      groupName: widget.groupName,
      friendId: widget.friendId,
      friendName: widget.friendName,
      payerId: _payerId,
      payerName: _payerName,
    );
    await ExpenseDraftService.saveDraft(draft);
  }

  Future<void> _checkAndLoadDraft() async {
    if (widget.resumeDraft) {
      await _loadDraftFromStorage();
    } else if (widget.groupId == null && widget.friendId == null) {
      final draft = await ExpenseDraftService.getDraft();
      if (draft != null && draft.hasContent) {
        await _applyDraft(draft);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resumed unfinished expense draft'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadDraftFromStorage() async {
    final draft = await ExpenseDraftService.getDraft();
    if (draft != null && mounted) {
      await _applyDraft(draft);
    }
  }

  Future<void> _applyDraft(ExpenseDraft draft) async {
    setState(() {
      _descriptionController.text = draft.description;
      if (draft.totalAmount != null && draft.totalAmount! > 0) {
        _totalAmountController.text = draft.totalAmount!.toStringAsFixed(2);
      }
      _selectedCategory = draft.category;
      _selectedDate = draft.date;
      _payerId = draft.payerId;
      _payerName = draft.payerName;

      if (draft.splitType == 'exact' || draft.splitType == 'manual') {
        _splitType = SplitType.manual;
        _tabController.index = 1;
      } else if (draft.splitType == 'percentage') {
        _splitType = SplitType.percentage;
        _tabController.index = 2;
      } else {
        _splitType = SplitType.equal;
        _tabController.index = 0;
      }

      _selectedContactsData.clear();
      for (final c in draft.selectedContacts) {
        _selectedContactsData.add(c);
        final id = c['id'].toString();
        _individualAmountControllers[id] = TextEditingController(
          text: draft.individualAmounts[id] ?? '0.00',
        );
        _individualPercentControllers[id] = TextEditingController(
          text: draft.individualPercents[id] ?? '0',
        );
      }

      if (draft.individualAmounts.containsKey('you')) {
        _individualAmountControllers['you'] = TextEditingController(
          text: draft.individualAmounts['you'] ?? '',
        );
      }
      if (draft.individualPercents.containsKey('you')) {
        _individualPercentControllers['you'] = TextEditingController(
          text: draft.individualPercents['you'] ?? '0',
        );
      }

      _billEntries.clear();
      _billEntries.addAll(draft.billEntries);

      if (draft.receiptImagePath != null) {
        final f = File(draft.receiptImagePath!);
        if (f.existsSync()) {
          _receiptImageFile = f;
        }
      }
      _currentReceiptId = draft.currentReceiptId;
    });

    _updateSplitAmounts();
  }

  String _getCurrentUserName() {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final fullName = userProvider.userData?['full_name'] as String?;
      if (fullName != null && fullName.trim().isNotEmpty) {
        return fullName.trim();
      }
      final username = userProvider.userData?['username'] as String?;
      if (username != null && username.trim().isNotEmpty) {
        return username.trim();
      }
    } catch (_) {}

    final user = _supabase.auth.currentUser;
    final metaName = user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) {
      return metaName.trim();
    }
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email!.split('@').first;
    }
    return 'User';
  }

  Future<bool?> _showDiscardDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Expense?'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to discard this expense?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  void _showPayerSelectionDialog() {
    final List<Map<String, dynamic>> payerOptions = [
      {'id': 'you', 'name': 'You (Current User)'},
      ..._selectedContactsData.where((c) => c['isGroup'] != true),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Who paid for this expense?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: payerOptions.length,
            itemBuilder: (context, index) {
              final option = payerOptions[index];
              final optionId = option['id'].toString();
              final isCurrent = _payerId == optionId;

              return ListTile(
                leading: CircleAvatar(
                  child: Icon(optionId == 'you' ? Icons.person : Icons.face),
                ),
                title: Text(option['name'] as String),
                trailing: isCurrent
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() {
                    _payerId = optionId;
                    _payerName = optionId == 'you'
                        ? 'You'
                        : (option['name'] as String);
                  });
                  Navigator.pop(ctx);
                  _scheduleAutoSave();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);

    _searchController.addListener(_updateSearchQuery);
    _totalAmountController.addListener(_updateSplitAmounts);
    _descriptionController.addListener(_scheduleAutoSave);
    _totalAmountController.addListener(_scheduleAutoSave);

    _loadContactsData();

    // Pre-fill group info if provided
    if (widget.groupName != null && widget.groupId != null) {
      _addSelectedContact({
        'id': widget.groupId,
        'name': widget.groupName!,
        'isGroup': true,
      });
    }

    // Pre-fill friend info if provided
    if (widget.friendName != null && widget.friendId != null) {
      _addSelectedContact({
        'id': widget.friendId,
        'name': widget.friendName!,
        'isGroup': false,
      });
    }

    _checkAndLoadDraft();
  }

  void _handleTabChange() {
    if (!mounted) return;
    setState(() {
      _splitType = SplitType.values[_tabController.index];
      _updateSplitAmounts();
    });
  }

  void _updateSearchQuery() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  void _updateSplitAmounts() {
    if (!mounted || _selectedContactsData.isEmpty) return;

    // Equal split calculation
    if (_splitType == SplitType.equal) {
      final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;
      final totalParticipants = _selectedContactsData.length + 1; // You + friends
      final perPersonAmount =
          totalParticipants > 0 ? totalAmount / totalParticipants : 0;

      // Update YOUR share (paid full amount)
      if (_selectedContactsData.isNotEmpty) {
        _individualAmountControllers['you']?.text =
            perPersonAmount.toStringAsFixed(2);
      }

      // Update friends' shares
      for (final contact in _selectedContactsData) {
        final id = contact['id'].toString();
        _individualAmountControllers[id]?.text =
            perPersonAmount.toStringAsFixed(2);
      }
    }
    // For percentage splits, update amounts based on percentages
    else if (_splitType == SplitType.percentage) {
      final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;

      for (final contact in _selectedContactsData) {
        final id = contact['id'].toString();
        final percentage =
            double.tryParse(_individualPercentControllers[id]?.text ?? '0') ??
                0;
        _individualAmountControllers[id]?.text =
            ((percentage / 100) * totalAmount).toStringAsFixed(2);
      }
    }

    setState(() {});
  }

  void _addSelectedContact(Map<String, dynamic> contact) {
    if (_selectedContactsData.any((c) =>
        c['id'] == contact['id'] && c['isGroup'] == contact['isGroup'])) {
      return; // Already selected
    }

    setState(() {
      _selectedContactsData.add(contact);

      // Create controllers for this contact
      final id = contact['id'].toString();
      _individualAmountControllers[id] = TextEditingController();
      _individualPercentControllers[id] = TextEditingController(text: '0');

      // Set default values
      _updateSplitAmounts();
    });
  }

  void _removeSelectedContact(Map<String, dynamic> contact) {
    setState(() {
      _selectedContactsData.removeWhere((c) =>
          c['id'] == contact['id'] && c['isGroup'] == contact['isGroup']);

      // Clean up controllers
      final id = contact['id'].toString();
      _individualAmountControllers[id]?.dispose();
      _individualPercentControllers[id]?.dispose();
      _individualAmountControllers.remove(id);
      _individualPercentControllers.remove(id);

      // Recalculate splits
      _updateSplitAmounts();
    });
  }

  void _populateContactsFromProviders(
      FriendProvider friendProvider, GroupProvider groupProvider) {
    final Map<String, Map<String, dynamic>> contactMap = {};

    for (final f in friendProvider.friends) {
      final id = f['id'].toString();
      final isCustom = f['is_custom'] == true;
      contactMap[id] = {
        'id': id,
        'name': f['full_name'] ?? f['username'] ?? 'Friend',
        'username': f['username'],
        'avatar_url': f['avatar_url'],
        'is_custom': isCustom,
        'linked_user_id': f['linked_user_id']?.toString(),
        'isGroup': false,
      };
    }

    final List<Map<String, dynamic>> groups = groupProvider.groups.map((g) {
      return {
        'id': g['id'],
        'name': g['name'],
        'isGroup': true,
      };
    }).toList();

    final allFriends = contactMap.values.toList();
    _availableContacts = [...allFriends, ...groups];
  }

  Future<void> _loadContactsData() async {
    try {
      final friendProvider =
          Provider.of<FriendProvider>(context, listen: false);
      final groupProvider =
          Provider.of<GroupProvider>(context, listen: false);

      // If providers already have cached contacts, populate immediately with no spinner!
      final bool hasCached = friendProvider.friends.isNotEmpty || groupProvider.groups.isNotEmpty;
      if (hasCached) {
        setState(() {
          _populateContactsFromProviders(friendProvider, groupProvider);
        });
      } else {
        setState(() {
          _isLoading = true;
          _loadingMessage = 'Loading friends and groups...';
        });
      }

      await Future.wait([
        friendProvider.fetchFriendsAndRequests(),
        groupProvider.fetchGroups(),
      ]);

      final Map<String, Map<String, dynamic>> contactMap = {};

      // 1. Add all friends from friendProvider
      for (final f in friendProvider.friends) {
        final id = f['id'].toString();
        final isCustom = f['is_custom'] == true;
        contactMap[id] = {
          'id': id,
          'name': f['full_name'] ?? f['username'] ?? 'Friend',
          'username': f['username'],
          'avatar_url': f['avatar_url'],
          'is_custom': isCustom,
          'linked_user_id': f['linked_user_id']?.toString(),
          'isGroup': false,
        };
      }

      // 2. Also query custom_friends directly as a guaranteed fallback
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        try {
          final customRes = await _supabase
              .from('custom_friends')
              .select('id, name, linked_user_id')
              .eq('user_id', userId);
          for (final c in customRes) {
            final id = c['id'].toString();
            contactMap.putIfAbsent(id, () => {
              'id': id,
              'name': c['name'] ?? 'Friend',
              'username': null,
              'avatar_url': null,
              'is_custom': true,
              'linked_user_id': c['linked_user_id']?.toString(),
              'isGroup': false,
            });
          }
        } catch (err) {
          LoggerService.warning('Direct custom_friends query fallback: $err');
        }
      }

      // 3. Add groups from groupProvider
      final List<Map<String, dynamic>> groups = groupProvider.groups.map((g) {
        return {
          'id': g['id'],
          'name': g['name'],
          'isGroup': true,
        };
      }).toList();

      final allFriends = contactMap.values.toList();

      if (!mounted) return;
      setState(() {
        _availableContacts = [...allFriends, ...groups];
        _isLoading = false;
      });

      LoggerService.debug(
          'Loaded ${_availableContacts.length} contacts (${allFriends.length} friends, ${groups.length} groups)');
    } catch (e) {
      LoggerService.error('Error loading contacts', e);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load contacts: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();

    _searchController.removeListener(_updateSearchQuery);
    _totalAmountController.removeListener(_updateSplitAmounts);
    _descriptionController.removeListener(_scheduleAutoSave);
    _totalAmountController.removeListener(_scheduleAutoSave);
    _tabController.removeListener(_handleTabChange);

    _searchController.dispose();
    _descriptionController.dispose();
    _totalAmountController.dispose();
    _tabController.dispose();

    // Dispose individual controllers
    for (var controller in _individualAmountControllers.values) {
      controller.dispose();
    }
    for (var controller in _individualPercentControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasMeaningfulContent,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await _showDiscardDialog();
        if (shouldDiscard == true) {
          _isDiscardedOrSaved = true;
          _debounceTimer?.cancel();
          await ExpenseDraftService.clearDraft();
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Add Expense',
              style: Theme.of(context).textTheme.headlineMedium),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Download Split PDF',
              onPressed: _downloadSplitPdf,
            ),
            IconButton(
              icon: const Icon(Icons.document_scanner_outlined),
              tooltip: 'Scan receipt',
              onPressed: _scanReceipt,
            ),
          ],
        ),
        body: _isLoading
            ? LoadingSpinner(
                initialMessage: _loadingMessage,
                wakeUpMessage: 'Please wait as the backend wakes up...',
              )
            : _buildMainContent(),
        bottomNavigationBar: _buildBottomButton(),
      ),
    );
  }

  Widget _buildMainContent() {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContactSelectorSection(
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    availableContacts: _availableContacts,
                    selectedContacts: _selectedContactsData,
                    onContactSelected: (contact) {
                      _addSelectedContact(contact);
                      _scheduleAutoSave();
                    },
                    onContactRemoved: (contact) {
                      _removeSelectedContact(contact);
                      _scheduleAutoSave();
                    },
                    onFriendAdded: (newFriend) {
                      setState(() {
                        _availableContacts.add(newFriend);
                        _addSelectedContact(newFriend);
                      });
                      _scheduleAutoSave();
                    },
                  ),
                  _buildBasicExpenseDetails(),
                  SplitOptionsWidget(
                    tabController: _tabController,
                    splitType: _splitType,
                    selectedContacts: _selectedContactsData,
                    totalAmountController: _totalAmountController,
                    individualAmountControllers: _individualAmountControllers,
                    individualPercentControllers: _individualPercentControllers,
                    payerId: _payerId,
                    onSplitTypeChanged: (type) {
                      setState(() {
                        _splitType = type;
                        _updateSplitAmounts();
                      });
                    },
                    onAmountsChanged: () {
                      _updateSplitAmounts();
                    },
                  ),
                  ReceiptScannerSection(
                    billEntries: _billEntries,
                    onBatchAssign: _billEntries.isNotEmpty
                        ? _showBatchAssignmentOptions
                        : null,
                    onEditItem: _assignItemToContacts,
                    onAddCharge: _showAddCustomChargeDialog,
                    onDeleteItem: _deleteBillEntry,
                  ),
                  const SizedBox(height: 80), // Space for button
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildBasicExpenseDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expense Details',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),

        // Description
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            labelText: 'Description',
            prefixIcon: Icon(Icons.description),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a description';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Date
        InkWell(
          onTap: () => _selectDate(context),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date',
              prefixIcon: Icon(Icons.calendar_today),
            ),
            child: Text(
              DateFormat('MMM dd, yyyy').format(_selectedDate),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Category
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: const InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(Icons.category),
          ),
          items: _categories.map((String category) {
            return DropdownMenuItem<String>(
              value: category,
              child: Text(category),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCategory = value;
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please select a category';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Total Amount
        TextFormField(
          controller: _totalAmountController,
          decoration: InputDecoration(
            labelText: 'Total Amount',
            //prefixIcon: const Icon(Icons.attach_money),
            prefixText: Provider.of<CurrencyProvider>(context, listen: false)
                .currencySymbol,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
          ],
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter the total amount';
            }
            if (double.tryParse(value) == null) {
              return 'Please enter a valid amount';
            }
            return null;
          },
          onChanged: (_) => _updateSplitAmounts(),
        ),
        const SizedBox(height: 16),

        // Paid by selector
        Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              'Paid by:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: Icon(
                _payerId == 'you' ? Icons.person : Icons.face,
                size: 16,
              ),
              label: Text(_payerName),
              onPressed: _showPayerSelectionDialog,
            ),
          ],
        ),

        Divider(height: 32, color: Theme.of(context).dividerColor),
      ],
    );
  }
  Widget _buildBottomButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _saveExpense,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          child: const Text('SAVE EXPENSE', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _scanReceipt() async {
    try {
      // Show image source options
      showDialog(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Select Image Source'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                _getImageAndProcess(ImageSource.camera);
              },
              child: const ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Camera'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                _getImageAndProcess(ImageSource.gallery);
              },
              child: const ListTile(
                leading: Icon(Icons.photo_library),
                title: Text('Gallery'),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      LoggerService.error('Error showing image source dialog', e);
    }
  }

  Future<File> _compressImage(File file) async {
    // 1. Try native platform compression first (5-10x faster, background thread)
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        minWidth: 1024,
        minHeight: 1024,
        quality: 80,
      );
      if (result != null) {
        return File(result.path);
      }
    } catch (e) {
      LoggerService.warning('Native image compression unavailable, falling back: $e');
    }

    // 2. Pure Dart fallback if native compression is not supported
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        LoggerService.warning('Could not decode image for compression, using original file.');
        return file;
      }
      final resized = img.copyResize(image, width: 1024);
      final compressedBytes = img.encodeJpg(resized, quality: 80);
      final tempDir = file.parent.path;
      final tempPath = '$tempDir/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final compressedFile = File(tempPath)..writeAsBytesSync(compressedBytes);
      return compressedFile;
    } catch (e) {
      LoggerService.warning('Image compression failed, using original file: $e');
      return file;
    }
  }

  Future<void> _getImageAndProcess(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: source);

      if (pickedFile == null) return;

      setState(() {
        _isLoading = true;
        _loadingMessage = 'Scanning receipt & extracting items...';
      });

      final file = File(pickedFile.path);
      final fileToProcess = await _compressImage(file);
      _receiptImageFile = fileToProcess;

      LoggerService.info('Extracting bill information: ${fileToProcess.path}');
      final billResult = await _billService.extractBillInfo(fileToProcess);
      LoggerService.debug('Bill OCR result: $billResult');

      if (billResult.containsKey('error') && billResult['error'] != null) {
        throw Exception(billResult['error'].toString());
      }

      final List<BillEntry> newEntries = [];

      // Extract merchant name if available
      final merchant = billResult['merchant_name'] ?? billResult['merchant'];
      if (merchant != null && merchant.toString().trim().isNotEmpty) {
        _descriptionController.text = merchant.toString().trim();
        _guessCategory();
      }

      // Extract date if available
      final dateStr = billResult['date']?.toString();
      if (dateStr != null && dateStr.trim().isNotEmpty) {
        final parsedDate = DateTime.tryParse(dateStr.trim());
        if (parsedDate != null) {
          _selectedDate = parsedDate;
        }
      }

      // Extract total amount if available
      final total = billResult['total_amount'] ?? billResult['total'];
      if (total != null) {
        _totalAmountController.text = total.toString();
      }

      // Extract line items
      final rawItems = billResult['items'] ?? billResult['line_items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            final desc = item['description'] ?? item['name'] ?? item['item'];
            final rawPrice = item['amount'] ?? item['price'] ?? item['total'];
            final price = double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;

            if (desc != null && desc.toString().trim().isNotEmpty) {
              newEntries.add(
                BillEntry(
                  description: desc.toString().trim(),
                  amount: price,
                  assignedTo: [],
                  type: _parseBillEntryType(item['type']?.toString()),
                ),
              );
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _billEntries.clear();
          _billEntries.addAll(newEntries);
          _isLoading = false;
        });

        if (newEntries.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No individual items could be identified from the bill.'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Extracted ${newEntries.length} items from receipt!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      LoggerService.error('Error processing receipt image', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading receipt: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  BillEntryType _parseBillEntryType(String? type) {
    if (type == 'tax') return BillEntryType.tax;
    if (type == 'discount') return BillEntryType.discount;
    return BillEntryType.item;
  }

  void _guessCategory() {
    final String description = _descriptionController.text.toLowerCase();

    if (description.contains('restaurant') ||
        description.contains('café') ||
        description.contains('cafe') ||
        description.contains('bar') ||
        description.contains('grill')) {
      _selectedCategory = 'Food & Drinks';
    } else if (description.contains('taxi') ||
        description.contains('uber') ||
        description.contains('lyft') ||
        description.contains('transport')) {
      _selectedCategory = 'Transportation';
    } else if (description.contains('cinema') ||
        description.contains('movie') ||
        description.contains('theatre') ||
        description.contains('theater')) {
      _selectedCategory = 'Entertainment';
    } else if (description.contains('market') ||
        description.contains('shop') ||
        description.contains('store')) {
      _selectedCategory = 'Shopping';
    } else {
      _selectedCategory = 'Other';
    }
  }

  void _showBatchAssignmentOptions() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assign All Items To',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Assign to everyone
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Everyone'),
              onTap: () {
                final allNames = _selectedContactsData
                    .map((c) => c['name'] as String)
                    .toList();
                allNames.add('You'); // Add current user

                for (int i = 0; i < _billEntries.length; i++) {
                  setState(() {
                    _billEntries[i] = BillEntry(
                      description: _billEntries[i].description,
                      amount: _billEntries[i].amount,
                      assignedTo: List.from(allNames),
                      type: _billEntries[i].type,
                    );
                  });
                }
                _updateAmountsBasedOnItemAssignments();
                Navigator.pop(context);
              },
            ),

            // Assign to specific contacts (show list)
            ..._selectedContactsData.map((contact) => ListTile(
                  leading: CircleAvatar(
                    child: Icon(contact['isGroup'] == true
                        ? Icons.group
                        : Icons.person),
                  ),
                  title: Text(contact['name']),
                  onTap: () {
                    for (int i = 0; i < _billEntries.length; i++) {
                      setState(() {
                        _billEntries[i] = BillEntry(
                          description: _billEntries[i].description,
                          amount: _billEntries[i].amount,
                          assignedTo: [contact['name']],
                          type: _billEntries[i].type,
                        );
                      });
                    }
                    _updateAmountsBasedOnItemAssignments();
                    Navigator.pop(context);
                  },
                )),

            // Assign to yourself
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: const Text('You only'),
              onTap: () {
                for (int i = 0; i < _billEntries.length; i++) {
                  setState(() {
                    _billEntries[i] = BillEntry(
                      description: _billEntries[i].description,
                      amount: _billEntries[i].amount,
                      assignedTo: ['You'],
                      type: _billEntries[i].type,
                    );
                  });
                }
                _updateAmountsBasedOnItemAssignments();
                Navigator.pop(context);
              },
            ),

            // Clear all assignments
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Clear all assignments'),
              onTap: () {
                for (int i = 0; i < _billEntries.length; i++) {
                  setState(() {
                    _billEntries[i] = BillEntry(
                      description: _billEntries[i].description,
                      amount: _billEntries[i].amount,
                      assignedTo: [],
                      type: _billEntries[i].type,
                    );
                  });
                }
                _updateAmountsBasedOnItemAssignments();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _updateAmountsBasedOnItemAssignments() {
    // Skip if no items or contacts
    if (_billEntries.isEmpty || _selectedContactsData.isEmpty) return;
    
    // Switch to manual split without triggering repeated tab animations if already manual
    if (_splitType != SplitType.manual) {
      _splitType = SplitType.manual;
      if (_tabController.index != SplitType.manual.index) {
        _tabController.index = SplitType.manual.index;
      }
    }
  
  // Calculate amounts per person based on item assignments
  Map<String, double> personAmounts = {};
  
  // Initialize all people with zero amounts
  for (final contact in _selectedContactsData) {
    personAmounts[contact['name']] = 0;
  }
  personAmounts['You'] = 0; // Current user
  
  // Calculate each person's share based on assigned items
  for (final item in _billEntries) {
    if (item.assignedTo.isEmpty) continue;
    
    // Split item amount equally among assignees
    final perPersonAmount = item.amount / item.assignedTo.length;
    
    // Subtract for discounts, add for taxes/items
    for (final assignee in item.assignedTo) {
      if (item.type == BillEntryType.discount) {
        personAmounts[assignee] =
            (personAmounts[assignee] ?? 0) - perPersonAmount;
      } else {
        personAmounts[assignee] =
            (personAmounts[assignee] ?? 0) + perPersonAmount;
      }
    }
  }
  
  // Update controllers for each contact
  for (final contact in _selectedContactsData) {
    final id = contact['id'].toString();
    final name = contact['name'] as String;
    final amt = personAmounts[name] ?? 0;
    _individualAmountControllers[id]?.text = 
        (amt < 0 ? 0.0 : amt).toStringAsFixed(2);
  }
  
  // Update "You" controller
  final yourAmt = personAmounts['You'] ?? 0;
  _individualAmountControllers['you']?.text = 
      (yourAmt < 0 ? 0.0 : yourAmt).toStringAsFixed(2);
  
  setState(() {});
}

  void _recalculateTotalFromBillEntries() {
    if (_billEntries.isEmpty) return;

    double calculatedTotal = 0.0;
    for (final entry in _billEntries) {
      if (entry.type == BillEntryType.discount) {
        calculatedTotal -= entry.amount;
      } else {
        calculatedTotal += entry.amount;
      }
    }

    if (calculatedTotal > 0) {
      _totalAmountController.text = calculatedTotal.toStringAsFixed(2);
      _updateSplitAmounts();
    }
  }

  void _showAddCustomChargeDialog() {
    FocusManager.instance.primaryFocus?.unfocus();

    final allNames =
        _selectedContactsData.map((c) => c['name'] as String).toList();
    allNames.add('You');

    showDialog(
      context: context,
      builder: (context) => AddCustomChargeDialog(
        allNames: allNames,
        onAdd: ({
          required String description,
          required double amount,
          required BillEntryType type,
          required List<String> assignedTo,
        }) {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _billEntries.add(
              BillEntry(
                description: description,
                amount: amount,
                assignedTo: assignedTo,
                type: type,
              ),
            );

            _recalculateTotalFromBillEntries();
            _updateAmountsBasedOnItemAssignments();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "$description" successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  void _deleteBillEntry(int index) {
    if (index >= 0 && index < _billEntries.length) {
      final removed = _billEntries[index];
      setState(() {
        _billEntries.removeAt(index);
        _recalculateTotalFromBillEntries();
        _updateAmountsBasedOnItemAssignments();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${removed.description}"'),
        ),
      );
    }
  }

  void _assignItemToContacts(BillEntry item, int index) {
    FocusManager.instance.primaryFocus?.unfocus();

    // Get all available names
    final allNames = _selectedContactsData.map((c) => c['name'] as String).toList();
    allNames.add('You'); // Add current user

    showDialog(
      context: context,
      builder: (context) => AssignItemDialog(
        itemDescription: item.description,
        allNames: allNames,
        initialSelectedNames: List<String>.from(item.assignedTo),
        onSave: (selectedNames) {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _billEntries[index] = BillEntry(
              description: item.description,
              amount: item.amount,
              assignedTo: selectedNames,
              type: item.type,
            );
            _updateAmountsBasedOnItemAssignments();
          });
        },
      ),
    );
  }

  String _getSplitTypeString(SplitType splitType) {
    switch (splitType) {
      case SplitType.equal:
        return 'equal';
      case SplitType.manual:
        return 'exact';
      case SplitType.percentage:
        return 'percentage';
    }
  }

  Future<void> _downloadSplitPdf() async {
    try {
      final totalAmount = double.tryParse(_totalAmountController.text) ?? 0.0;
      if (totalAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter an amount before downloading the PDF')),
        );
        return;
      }

      final currencyProvider =
          Provider.of<CurrencyProvider>(context, listen: false);
      final currencySymbol = currencyProvider.currencySymbol;

      final currentUserName = _getCurrentUserName();
      final isUserPayer = _payerId == 'you';
      final effectivePayerName = isUserPayer ? currentUserName : _payerName;

      final List<Map<String, dynamic>> participantShares = [];

      // Add user
      final yourShare =
          double.tryParse(_individualAmountControllers['you']?.text ?? '') ??
              (_selectedContactsData.isEmpty
                  ? totalAmount
                  : totalAmount / (_selectedContactsData.length + 1));

      participantShares.add({
        'name': currentUserName,
        'share': yourShare,
        'paid': isUserPayer ? totalAmount : 0.0,
      });

      // Add friends
      for (final contact in _selectedContactsData) {
        final id = contact['id'].toString();
        final name = contact['name'] as String;
        final isThisFriendPayer = _payerId == id;
        final share =
            double.tryParse(_individualAmountControllers[id]?.text ?? '') ??
                (totalAmount / (_selectedContactsData.length + 1));
        participantShares.add({
          'name': name,
          'share': share,
          'paid': isThisFriendPayer ? totalAmount : 0.0,
        });
      }

      final merchantName = _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : 'Expense';

      Uint8List? receiptImageBytes;
      if (_receiptImageFile != null && await _receiptImageFile!.exists()) {
        try {
          receiptImageBytes = await _receiptImageFile!.readAsBytes();
        } catch (_) {}
      }

      final effectiveBillEntries = _billEntries.map((entry) {
        final updatedAssigned = entry.assignedTo.map((n) {
          if (n.toLowerCase() == 'you') return currentUserName;
          return n;
        }).toList();
        return BillEntry(
          description: entry.description,
          amount: entry.amount,
          type: entry.type,
          assignedTo: updatedAssigned,
        );
      }).toList();

      await PdfService.downloadOrPrintPdf(
        title: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : 'Expense Split',
        merchantName: merchantName,
        date: _selectedDate,
        totalAmount: totalAmount,
        currencySymbol: currencySymbol,
        splitType: _getSplitTypeString(_splitType),
        billEntries: effectiveBillEntries,
        participantShares: participantShares,
        receiptImageBytes: receiptImageBytes,
        payerName: effectivePayerName,
      );
    } catch (e) {
      LoggerService.error('Error generating split PDF', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveExpense() async {
    if (_selectedContactsData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select at least one friend or group')));
      return;
    }

    if (_formKey.currentState!.validate()) {
      try {
        final currencyProvider =
            Provider.of<CurrencyProvider>(context, listen: false);
        final expenseProvider =
            Provider.of<ExpenseProvider>(context, listen: false);
        final currencyCode = currencyProvider.currencyCode;

        setState(() {
          _isLoading = true;
          _loadingMessage = 'Saving expense & updating balances...';
        });

        // Get the current user ID
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) throw Exception('User not authenticated');

        try {
          await _ensureUserProfileExists(user.id);
        } catch (e) {
          throw Exception('Profile creation failed: $e');
        }

        // Convert the string category to an integer ID
        int? categoryId = _getCategoryId(_selectedCategory);

        // Determine effective group ID if a group contact or widget.groupId is present
        int? effectiveGroupId = widget.groupId;
        if (effectiveGroupId == null) {
          final groupContact = _selectedContactsData.where((c) => c['isGroup'] == true).firstOrNull;
          if (groupContact != null) {
            effectiveGroupId = groupContact['id'] as int?;
          }
        }

        // Create the expense
        final now = DateTime.now();
        final newExpense = Expense(
          id: 0,
          description: _descriptionController.text,
          totalAmount: double.parse(_totalAmountController.text),
          currency: currencyCode,
          date: _selectedDate,
          createdBy: user.id,
          groupId: effectiveGroupId,
          categoryId: categoryId,
          receiptImageUrl: null,
          splitType: _getSplitTypeString(_splitType),
          createdAt: now,
          updatedAt: now,
        );

        final success = await expenseProvider.createExpense(newExpense);

        if (!mounted) return;

        if (success) {
          final expenseId = expenseProvider.lastInsertedId;
          final splitType = _splitType;
          final selectedContacts = List<Map<String, dynamic>>.from(_selectedContactsData);
          final Map<String, String> manualAmounts = {};
          final Map<String, String> percentageAmounts = {};

          for (final contact in selectedContacts) {
            final id = contact['id'].toString();
            manualAmounts[id] = _individualAmountControllers[id]?.text ?? '0';
            percentageAmounts[id] = _individualPercentControllers[id]?.text ?? '0';
          }
          manualAmounts['you'] = _individualAmountControllers['you']?.text ?? '';
          percentageAmounts['you'] = _individualPercentControllers['you']?.text ?? '';

          // Save participants
          try {
            await _saveExpenseParticipants(
              expenseId: expenseId,
              currentUserId: user.id,
              totalAmount: double.parse(_totalAmountController.text),
              splitType: splitType,
              selectedContacts: selectedContacts,
              manualAmounts: manualAmounts,
              percentageAmounts: percentageAmounts,
              currencyCode: currencyCode,
              groupId: effectiveGroupId,
            );
            if (!mounted) return;
          } catch (e) {
            LoggerService.error('Error saving participants', e);
            if (!mounted) return;
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error saving participants: $e')),
            );
            return;
          }

          // Link receipt if available
          if (_currentReceiptId != null) {
            await _receiptService.linkReceiptToExpense(_currentReceiptId!, expenseId);
          }
          if (!mounted) return;

          // Clear draft on successful save
          _isDiscardedOrSaved = true;
          _debounceTimer?.cancel();
          await ExpenseDraftService.clearDraft();

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense saved successfully')),
          );
          Navigator.pop(context);
        } else {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        LoggerService.error('Error saving expense', e);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving expense: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<bool> _ensureCustomFriendProfileExists(
      String customFriendId, String name) async {
    try {
      final existing = await _supabase
          .from('profiles')
          .select('id')
          .eq('id', customFriendId)
          .maybeSingle();
      if (existing != null) return true;

      final safeName = name.replaceAll(' ', '').toLowerCase();
      final profileData = {
        'id': customFriendId,
        'username': 'custom_${safeName}_${customFriendId.replaceAll('-', '').substring(0, 4)}',
        'full_name': name,
        'updated_at': DateTime.now().toIso8601String(),
        'currency': 'INR',
        'avatar_url': null,
        'website': null,
      };
      await _supabase.from('profiles').insert(profileData);
      return true;
    } catch (e) {
      LoggerService.warning('Cannot create shadow profile for custom friend: $e');
      return false;
    }
  }

  Future<void> _saveExpenseParticipants({
    required int expenseId,
    required String currentUserId,
    required double totalAmount,
    required SplitType splitType,
    required List<Map<String, dynamic>> selectedContacts,
    required Map<String, String> manualAmounts,
    required Map<String, String> percentageAmounts,
    required String currencyCode,
    int? groupId,
  }) async {
    final String effectivePayerId =
        _payerId == 'you' ? currentUserId : _payerId;

    // 1. Gather all participant IDs, separating registered users from unlinked custom friends
    final Set<String> registeredParticipantIds = {currentUserId};
    final List<Map<String, dynamic>> unlinkedCustomFriends = [];

    for (final contact in selectedContacts) {
      if (contact['isGroup'] == true) {
        final gId = contact['id'];
        final members = await _supabase
            .from('group_members')
            .select('user_id')
            .eq('group_id', gId);
        for (final m in members) {
          final uid = m['user_id'] as String?;
          if (uid != null && uid.isNotEmpty) {
            registeredParticipantIds.add(uid);
          }
        }
      } else {
        final isCustom = contact['is_custom'] == true;
        final linkedId = contact['linked_user_id']?.toString();

        if (isCustom && (linkedId == null || linkedId.isEmpty)) {
          final customFriendId = contact['id'].toString();
          final hasProfile = await _ensureCustomFriendProfileExists(
            customFriendId,
            contact['name']?.toString() ?? 'Friend',
          );
          if (hasProfile) {
            registeredParticipantIds.add(customFriendId);
          } else {
            unlinkedCustomFriends.add(contact);
          }
        } else {
          final uid = (isCustom && linkedId != null)
              ? linkedId
              : contact['id'].toString();
          registeredParticipantIds.add(uid);
        }
      }
    }

    if (groupId != null) {
      final members = await _supabase
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId);
      for (final m in members) {
        final uid = m['user_id'] as String?;
        if (uid != null && uid.isNotEmpty) {
          registeredParticipantIds.add(uid);
        }
      }
    }

    // All distinct participants list (registered + unlinked custom)
    final allParticipantsList = [
      ...registeredParticipantIds.map((id) => {'id': id, 'is_custom_unlinked': false}),
      ...unlinkedCustomFriends.map((c) => {
            'id': c['id'].toString(),
            'is_custom_unlinked': true,
            'name': c['name'] ?? 'Friend',
          }),
    ];

    final int count = allParticipantsList.length;
    final Map<String, double> userShares = {};

    switch (splitType) {
      case SplitType.equal:
        final perPerson = count > 0 ? totalAmount / count : 0.0;
        for (final p in allParticipantsList) {
          userShares[p['id'] as String] = perPerson;
        }
        break;

      case SplitType.manual:
        double totalAssigned = 0.0;
        for (final p in allParticipantsList) {
          final id = p['id'] as String;
          if (id == currentUserId) continue;
          final amount = double.tryParse(manualAmounts[id] ?? '0') ?? 0.0;
          userShares[id] = amount;
          totalAssigned += amount;
        }
        final yourAmt = double.tryParse(manualAmounts['you'] ?? '') ??
            (totalAmount - totalAssigned);
        userShares[currentUserId] = yourAmt;
        break;

      case SplitType.percentage:
        for (final p in allParticipantsList) {
          final id = p['id'] as String;
          if (id == currentUserId) continue;
          final pct = double.tryParse(percentageAmounts[id] ?? '0') ?? 0.0;
          userShares[id] = (pct / 100.0) * totalAmount;
        }
        final yourPct =
            double.tryParse(percentageAmounts['you'] ?? '0') ?? 0.0;
        userShares[currentUserId] = (yourPct / 100.0) * totalAmount;
        break;
    }

    // Build participant rows ONLY for registered profiles (prevents foreign key violation)
    final participants = registeredParticipantIds.map((uid) {
      return {
        'expense_id': expenseId,
        'user_id': uid,
        'share_amount': userShares[uid] ?? 0.0,
        'paid_amount': (uid == effectivePayerId) ? totalAmount : 0.0,
        'settled': false,
      };
    }).toList();

    LoggerService.debug(
        'Inserting ${participants.length} registered participants for expense $expenseId');
    if (participants.isNotEmpty) {
      await _supabase.from('expense_participants').insert(participants);
    }

    // Update balances table for each non-payer registered participant
    final balanceService = BalanceService();
    for (final p in participants) {
      final uid = p['user_id'] as String;
      if (uid != effectivePayerId) {
        final share = (p['share_amount'] as num).toDouble();
        if (share > 0) {
          if (effectivePayerId == currentUserId) {
            // Friend owes you
            await balanceService.adjustBalance(
              fromUserId: currentUserId,
              toUserId: uid,
              deltaAmount: share,
              currency: currencyCode,
              groupId: groupId,
            );
          } else if (uid == currentUserId) {
            // You owe the friend who paid
            await balanceService.adjustBalance(
              fromUserId: currentUserId,
              toUserId: effectivePayerId,
              deltaAmount: -share,
              currency: currencyCode,
              groupId: groupId,
            );
          }
        }
      }
    }

    // For unlinked custom friends: record persistently in CustomFriendBalanceService
    for (final cf in unlinkedCustomFriends) {
      final cfId = cf['id'].toString();
      final share = userShares[cfId] ?? 0.0;
      final paidByYou = effectivePayerId == currentUserId;

      if (paidByYou) {
        // Custom friend owes you their share
        await CustomFriendBalanceService.adjustBalance(
          customFriendId: cfId,
          deltaAmount: share,
        );
      } else if (cfId == effectivePayerId) {
        // Custom friend paid full amount: you owe them your share
        final yourShare = userShares[currentUserId] ?? 0.0;
        await CustomFriendBalanceService.adjustBalance(
          customFriendId: cfId,
          deltaAmount: -yourShare,
        );
      }

      await CustomFriendBalanceService.recordParticipation(
        expenseId: expenseId,
        customFriendId: cfId,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : 'Expense',
        totalAmount: totalAmount,
        friendShare: share,
        paidByYou: paidByYou,
        date: _selectedDate,
        payerId: effectivePayerId,
        paidAmount: (cfId == effectivePayerId) ? totalAmount : 0.0,
      );
    }

    LoggerService.info(
        'Successfully added participants and balances for expense $expenseId');
  }

  Future<void> _ensureUserProfileExists(String userId) async {
    try {
      LoggerService.info('Checking if profile exists for user ID: $userId');

      // Check if profile exists
      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        LoggerService.info('Profile not found, creating new profile');

        // Create profile with required fields
        final profileData = {
          'id': userId,
          'username': userId.substring(0, 8),
          'full_name': 'User',
          'updated_at': DateTime.now().toIso8601String(),
          'currency': 'INR',
          'avatar_url': null,
          'website': null,
          'email': Supabase.instance.client.auth.currentUser?.email,
        };

        await _supabase.from('profiles').insert(profileData);
        LoggerService.info('Profile created successfully');
      } else {
        LoggerService.info('Profile already exists for user: $userId');
      }
    } catch (e) {
      LoggerService.error('Error ensuring profile exists', e);
      throw Exception('Failed to create user profile: $e');
    }
  }

  int? _getCategoryId(String? categoryName) {
    if (categoryName == null) return null;

    final Map<String, int> categoryMap = {
      'Food & Drinks': 1,
      'Transportation': 2,
      'Entertainment': 3,
      'Shopping': 4,
      'Utilities': 5,
      'Rent': 6,
      'Other': 7,
    };

    return categoryMap[categoryName] ?? 7; // Default to 'Other'
  }
}