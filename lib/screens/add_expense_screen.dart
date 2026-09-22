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
import 'package:image/image.dart' as img;
import '../providers/friend_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/split_options_widget.dart';
import '../widgets/contact_selector_section.dart';
import '../widgets/receipt_scanner_section.dart';
import '../widgets/loading_spinner.dart';

class AddExpenseScreen extends StatefulWidget {
  final int? groupId;
  final String? groupName;
  final dynamic friendId;
  final String? friendName;

  const AddExpenseScreen({
    super.key,
    this.groupId,
    this.groupName,
    this.friendId,
    this.friendName,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen>
    with SingleTickerProviderStateMixin {
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

  // Services
  final BillService _billService = BillService();
  final ReceiptService _receiptService = ReceiptService();
  int? _currentReceiptId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);

    _searchController.addListener(_updateSearchQuery);
    _totalAmountController.addListener(_updateSplitAmounts);

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

  Future<void> _loadContactsData() async {
    try {
      setState(() => _isLoading = true);

      final friendProvider =
          Provider.of<FriendProvider>(context, listen: false);
      final groupProvider =
          Provider.of<GroupProvider>(context, listen: false);

      await Future.wait([
        friendProvider.fetchFriendsAndRequests(),
        groupProvider.fetchGroups(),
      ]);

      final Map<String, Map<String, dynamic>> contactMap = {};

      // 1. Add all friends (including custom name-only friends) from friendProvider
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Expense',
            style: Theme.of(context).textTheme.headlineMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner_outlined),
            tooltip: 'Scan receipt',
            onPressed: _scanReceipt,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingSpinner(
              initialMessage: 'Saving expense & updating balances...',
              wakeUpMessage: 'Please wait as the backend wakes up...',
            )
          : _buildMainContent(),
      bottomNavigationBar: _buildBottomButton(),
    );
  }

  Widget _buildMainContent() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
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
                      _searchController.clear();
                    },
                    onContactRemoved: _removeSelectedContact,
                  ),
                  _buildBasicExpenseDetails(),
                  SplitOptionsWidget(
                    tabController: _tabController,
                    splitType: _splitType,
                    selectedContacts: _selectedContactsData,
                    totalAmountController: _totalAmountController,
                    individualAmountControllers: _individualAmountControllers,
                    individualPercentControllers: _individualPercentControllers,
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
                  ),
                  const SizedBox(height: 80), // Space for button
                ],
              ),
            ),
          ),
        ],
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
            border: OutlineInputBorder(),
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
              border: OutlineInputBorder(),
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
            border: OutlineInputBorder(),
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
            border: const OutlineInputBorder(),
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

        Divider(height: 32, color: Colors.grey.shade300),
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
  final image = img.decodeImage(await file.readAsBytes());
  final resized = img.copyResize(image!, width: 1024);
  return File(file.path)
    ..writeAsBytesSync(img.encodeJpg(resized, quality: 85));
}

  Future<void> _getImageAndProcess(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: source);

      if (pickedFile == null) return;
      
      setState(() => _isLoading = true);

      final file = File(pickedFile.path);
      Map<String, dynamic> billResult = {};

      try {
        // Upload receipt
        final compressedFile = await _compressImage(file);

        // Process image with OCR
        billResult = await _billService.extractBillInfo(compressedFile);
        LoggerService.debug('Bill OCR result: $billResult');

        setState(() {
        // Update controllers and bill entries for UI
        if (billResult.containsKey('merchant_name')) {
          _descriptionController.text = billResult['merchant_name'].toString();
          _guessCategory();
        }
        if (billResult.containsKey('total_amount')) {
          _totalAmountController.text = billResult['total_amount'].toString();
        }
        _billEntries.clear();
        if (billResult.containsKey('items') && billResult['items'] is List) {
          for (final item in billResult['items']) {
            if (item is Map && item.containsKey('description') && item.containsKey('amount')) {
              _billEntries.add(
                BillEntry(
                  description: item['description'].toString(),
                  amount: double.tryParse(item['amount'].toString()) ?? 0.0,
                  assignedTo: [],
                  type: BillEntryType.item,
                ),
              );
            }
          }
        }
      });

      } catch (e) {
        LoggerService.error('OCR processing failed', e);
        billResult = {}; // Empty result if OCR fails
      }

      // Process OCR results
      if (billResult.containsKey('items') && billResult['items'] is List) {
        final items = billResult['items'] as List;
        _billEntries.clear();

        // Add items from OCR
        for (final item in items) {
          if (item is Map && item.containsKey('description')) {
            final price = item['price'] ?? item['amount'];
            if (price != null) {
              _billEntries.add(
                BillEntry(
                  description: item['description'].toString(),
                  amount: double.tryParse(price.toString()) ?? 0.0,
                  assignedTo: [],
                  type: BillEntryType.item,
                ),
              );
            }
          }
        }

        // Set total amount if available
        if (billResult.containsKey('total')) {
          _totalAmountController.text = billResult['total'].toString();
        }

        // Set description (merchant name)
        if (billResult.containsKey('merchant')) {
          _descriptionController.text = billResult['merchant'].toString();
          _guessCategory(); // Guess category from description
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      LoggerService.error('Error processing receipt image', e);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing receipt: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
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
  
  // Switch to manual split
  _tabController.animateTo(SplitType.manual.index);
  _splitType = SplitType.manual;
  
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
    
    // Add to each person's total
    for (final assignee in item.assignedTo) {
      personAmounts[assignee] = (personAmounts[assignee] ?? 0) + perPersonAmount;
    }
  }
  
  // Update controllers for each contact
  for (final contact in _selectedContactsData) {
    final id = contact['id'].toString();
    final name = contact['name'] as String;
    _individualAmountControllers[id]?.text = 
        (personAmounts[name] ?? 0).toStringAsFixed(2);
  }
  
  // Update "You" controller
  _individualAmountControllers['you']?.text = 
      (personAmounts['You'] ?? 0).toStringAsFixed(2);
  
  setState(() {});
}


  void _assignItemToContacts(BillEntry item, int index) {
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

        setState(() => _isLoading = true);

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
    // 1. Gather all participant user IDs (expanding group members if a group is selected)
    final Set<String> participantIds = {currentUserId};

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
            participantIds.add(uid);
          }
        }
      } else {
        final uid = contact['id'].toString();
        participantIds.add(uid);
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
          participantIds.add(uid);
        }
      }
    }

    final int count = participantIds.length;
    final Map<String, double> userShares = {};

    switch (splitType) {
      case SplitType.equal:
        final perPerson = totalAmount / count;
        for (final uid in participantIds) {
          userShares[uid] = perPerson;
        }
        break;

      case SplitType.manual:
        double totalAssigned = 0.0;
        for (final uid in participantIds) {
          if (uid == currentUserId) continue;
          final amount = double.tryParse(manualAmounts[uid] ?? '0') ?? 0.0;
          userShares[uid] = amount;
          totalAssigned += amount;
        }
        final yourAmt = double.tryParse(manualAmounts['you'] ?? '') ?? (totalAmount - totalAssigned);
        userShares[currentUserId] = yourAmt;
        break;

      case SplitType.percentage:
        for (final uid in participantIds) {
          if (uid == currentUserId) continue;
          final pct = double.tryParse(percentageAmounts[uid] ?? '0') ?? 0.0;
          userShares[uid] = (pct / 100.0) * totalAmount;
        }
        final yourPct = double.tryParse(percentageAmounts['you'] ?? '0') ?? 0.0;
        userShares[currentUserId] = (yourPct / 100.0) * totalAmount;
        break;
    }

    // Build participant rows
    final participants = participantIds.map((uid) {
      return {
        'expense_id': expenseId,
        'user_id': uid,
        'share_amount': userShares[uid] ?? 0.0,
        'paid_amount': (uid == currentUserId) ? totalAmount : 0.0,
        'settled': false,
      };
    }).toList();

    LoggerService.debug('Inserting ${participants.length} participants for expense $expenseId');
    await _supabase.from('expense_participants').insert(participants);

    // Update balances table for each non-payer participant
    final balanceService = BalanceService();
    for (final p in participants) {
      final uid = p['user_id'] as String;
      if (uid != currentUserId) {
        final share = (p['share_amount'] as num).toDouble();
        if (share > 0) {
          await balanceService.adjustBalance(
            fromUserId: currentUserId,
            toUserId: uid,
            deltaAmount: share,
            currency: currencyCode,
            groupId: groupId,
          );
        }
      }
    }

    LoggerService.info('Successfully added ${participants.length} participants and updated balances for expense $expenseId');
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