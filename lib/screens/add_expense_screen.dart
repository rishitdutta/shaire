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

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Load friends
      final friendsData = await _supabase
          .rpc('get_user_friends', params: {'p_user_id': userId});

      // Load groups
      final groupsData = await _supabase
          .from('group_members')
          .select('group_id, groups:group_id(id, name)')
          .eq('user_id', userId);

      // Format the data
      List<Map<String, dynamic>> friends = [];
      for (final f in friendsData) {
        friends.add({
          'id': f['user_id'],
          'name': f['full_name'] ?? f['username'] ?? 'Unknown',
          'username': f['username'],
          'avatar_url': f['avatar_url'],
          'isGroup': false,
        });
      }

      List<Map<String, dynamic>> groups = [];
      for (final g in groupsData) {
        final group = g['groups'] as Map<String, dynamic>;
        groups.add({
          'id': group['id'],
          'name': group['name'],
          'isGroup': true,
        });
      }

      // Combine friends and groups
      setState(() {
        _availableContacts = [...friends, ...groups];
        _isLoading = false;
      });

      LoggerService.debug(
          'Loaded ${_availableContacts.length} contacts (${friends.length} friends, ${groups.length} groups)');
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
          ? const Center(child: CircularProgressIndicator())
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
                  _buildContactsSection(),
                  _buildBasicExpenseDetails(),
                  _buildSplitSection(),
                  if (_billEntries.isNotEmpty) _buildBillItems(),
                  const SizedBox(height: 80), // Space for button
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select People or Groups',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),

        // Search bar
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search friends or groups',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).cardColor.withValues(alpha: 0.5)
                : Colors.grey.shade200,
          ),
        ),

        // Search results (only show when searching)
        if (_searchQuery.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _availableContacts
                  .where((contact) => contact['name']
                      .toString()
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase()))
                  .length,
              itemBuilder: (context, index) {
                final filteredContacts = _availableContacts
                    .where((contact) => contact['name']
                        .toString()
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()))
                    .toList();

                if (index >= filteredContacts.length) return const SizedBox();

                final contact = filteredContacts[index];
                final isSelected = _selectedContactsData.any((c) =>
                    c['id'] == contact['id'] &&
                    c['isGroup'] == contact['isGroup']);

                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(contact['isGroup'] == true
                        ? Icons.group
                        : Icons.person),
                  ),
                  title: Text(contact['name']),
                  subtitle:
                      Text(contact['isGroup'] == true ? 'Group' : 'Friend'),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.add_circle_outline),
                  onTap: () {
                    if (isSelected) {
                      _removeSelectedContact(contact);
                    } else {
                      _addSelectedContact(contact);
                      // Clear search after selection
                      _searchController.clear();
                    }
                  },
                );
              },
            ),
          ),

        // Selected contacts chips
        if (_selectedContactsData.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Selected:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedContactsData.map((contact) {
              return Chip(
                avatar: CircleAvatar(
                  child: Icon(
                    contact['isGroup'] == true ? Icons.group : Icons.person,
                    size: 16,
                  ),
                ),
                label: Text(contact['name']),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeSelectedContact(contact),
              );
            }).toList(),
          ),
        ],

        Divider(height: 32, color: Colors.grey.shade300),
      ],
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

  Widget _buildSplitSection() {
    if (_selectedContactsData.isEmpty) {
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
          controller: _tabController,
          tabs: const [
            Tab(text: 'Equal'),
            Tab(text: 'Manual'),
            Tab(text: 'Percentage'),
          ],
          dividerColor: Colors.grey.shade300,
          onTap: (index) {
            setState(() {
              _splitType = SplitType.values[index];
              _updateSplitAmounts();
            });
          },
        ),

        const SizedBox(height: 16),

        // Tab content
        SizedBox(
          height: (_selectedContactsData.length + 1) *
              60.0, // Height based on number of participants
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildEqualSplitTab(),
              _buildManualSplitTab(),
              _buildPercentageSplitTab(),
            ],
          ),
        ),

        Divider(height: 32, color: Colors.grey.shade300),
      ],
    );
  }

  Widget _buildEqualSplitTab() {
    final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;
    final totalParticipants =
        _selectedContactsData.length + 1; // +1 for current user
    final perPersonAmount =
        totalParticipants > 0 ? totalAmount / totalParticipants : 0;
    final currencyProvider =
        Provider.of<CurrencyProvider>(context, listen: false);

    return ListView(
      children: [
        // Current user (you)
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: const Text('You (paid)'),
          trailing: Text(
            currencyProvider.format(perPersonAmount.toDouble()),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),

        // Selected contacts
        ..._selectedContactsData.map((contact) => ListTile(
              leading: CircleAvatar(
                child: Icon(
                    contact['isGroup'] == true ? Icons.group : Icons.person),
              ),
              title: Text(contact['name']),
              trailing: Text(
                currencyProvider.format(perPersonAmount.toDouble()),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )),
      ],
    );
  }

  Widget _buildManualSplitTab() {
    final currencyProvider =
        Provider.of<CurrencyProvider>(context, listen: false);
    final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;

    // Ensure controller for "You" exists
    _individualAmountControllers['you'] ??=
        TextEditingController(text: (totalAmount / (_selectedContactsData.length + 1)).toStringAsFixed(2));

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
                  controller: _individualAmountControllers['you'],
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
                ),
              ),
            ],
          ),
        ),

        // Selected contacts
        ..._selectedContactsData.map((contact) {
          final id = contact['id'].toString();

          // Ensure controller exists for each contact
          _individualAmountControllers[id] ??= TextEditingController(
              text: (totalAmount / (_selectedContactsData.length + 1)).toStringAsFixed(2));

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                CircleAvatar(
                  child: Icon(
                      contact['isGroup'] == true ? Icons.group : Icons.person),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(contact['name'])),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _individualAmountControllers[id],
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
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPercentageSplitTab() {
    final currencyProvider =
        Provider.of<CurrencyProvider>(context, listen: false);
    final totalAmount = double.tryParse(_totalAmountController.text) ?? 0;
    final defaultPercentage = 100 / (_selectedContactsData.length + 1);

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
                      controller: TextEditingController(
                          text: defaultPercentage.toStringAsFixed(0)),
                      onChanged: (_) => _updateSplitAmounts(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(currencyProvider
                      .format((defaultPercentage / 100) * totalAmount)),
                ],
              ),
            ],
          ),
        ),

        // Selected contacts
        ..._selectedContactsData.map((contact) {
          final id = contact['id'].toString();

          // Create controllers if they don't exist
          _individualPercentControllers[id] ??=
              TextEditingController(text: defaultPercentage.toStringAsFixed(0));

          _individualAmountControllers[id] ??= TextEditingController(
              text:
                  ((defaultPercentage / 100) * totalAmount).toStringAsFixed(2));

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                CircleAvatar(
                  child: Icon(
                      contact['isGroup'] == true ? Icons.group : Icons.person),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(contact['name'])),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _individualPercentControllers[id],
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
                        onChanged: (_) => _updateSplitAmounts(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(currencyProvider.format(double.parse(
                        _individualAmountControllers[id]?.text ?? '0'))),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBillItems() {
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
              onPressed:
                  _billEntries.isNotEmpty ? _showBatchAssignmentOptions : null,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Bill items list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _billEntries.length,
          itemBuilder: (context, index) {
            final item = _billEntries[index];

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
                          Provider.of<CurrencyProvider>(context)
                              .format(item.amount),
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
                          onPressed: () => _assignItemToContacts(item, index),
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
      Receipt? receipt;

      try {
        // Upload receipt
        final compressedFile = await _compressImage(file);

        // Process image with OCR
        billResult = await _billService.extractBillInfo(file);
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
      builder: (context) => _AssignItemDialog(
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
        setState(() => _isLoading = true);

        // Get the current user ID
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) throw Exception('User not authenticated');

        try {
          await _ensureUserProfileExists(user.id);
        } catch (e) {
          throw Exception('Profile creation failed: $e');
        }

        final currencyProvider =
            Provider.of<CurrencyProvider>(context, listen: false);
        final expenseProvider =
            Provider.of<ExpenseProvider>(context, listen: false);

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
        final currencyCode = Provider.of<CurrencyProvider>(context, listen: false).currencyCode;
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

// Support classes
enum SplitType { equal, manual, percentage }

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

enum BillEntryType { item, tax, discount }

class _AssignItemDialog extends StatefulWidget {
  final String itemDescription;
  final List<String> allNames;
  final List<String> initialSelectedNames;
  final Function(List<String>) onSave;

  const _AssignItemDialog({
    required this.itemDescription,
    required this.allNames,
    required this.initialSelectedNames,
    required this.onSave,
  });

  @override
  State<_AssignItemDialog> createState() => _AssignItemDialogState();
}

class _AssignItemDialogState extends State<_AssignItemDialog> {
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