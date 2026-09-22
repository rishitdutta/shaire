import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/currency_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/loading_spinner.dart';
import 'add_expense_screen.dart';

class GroupDetailsScreen extends StatefulWidget {
  final int groupId;
  const GroupDetailsScreen({super.key, required this.groupId});

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true, _error = false;
  String? _errorMsg;
  String? _groupName, _inviteCode;
  final List<Map<String, dynamic>> _members = [];
  final List<Map<String, dynamic>> _activities = [];
  final Map<String, Map<String, double>> _memberBalances = {};
  late TabController _tabController;
  String? _currentUserId;
  String? _createdById; // Track the creator ID to check admin permissions
  final _currencyFormatter = NumberFormat.currency(symbol: '\$');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final groupProvider = Provider.of<GroupProvider>(context, listen: false);
    _currentUserId = groupProvider.currentUserId;
    _loadAll();

    // Listen for tab changes to update FAB
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get isAdmin {
    if (_currentUserId == null) return false;

    // Check if the current user is the creator or has admin role
    if (_currentUserId == _createdById) return true;

    final adminMember = _members.firstWhere(
      (m) => m['user_id'] == _currentUserId && m['role'] == 'admin',
      orElse: () => {},
    );
    return adminMember.isNotEmpty;
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final groupProvider =
          Provider.of<GroupProvider>(context, listen: false);
      final details = await groupProvider.fetchGroupDetails(widget.groupId);

      if (!mounted) return;
      setState(() {
        _groupName = details['groupName'];
        _inviteCode = details['inviteCode'];
        _createdById = details['createdById'];
        _members.clear();
        _members.addAll(List<Map<String, dynamic>>.from(details['members']));
        _activities.clear();
        _activities.addAll(
            List<Map<String, dynamic>>.from(details['activities']));
        _memberBalances.clear();
        _memberBalances.addAll(
            Map<String, Map<String, double>>.from(details['memberBalances']));
        _error = false;
        _errorMsg = null;
      });
    } catch (e) {
      _error = true;
      _errorMsg = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _copyInvite() {
    final code = _inviteCode ?? '';
    if (code.isEmpty) return;

    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied to clipboard!')),
    );
  }

  void _navigateToAddExpense() {
    // Navigate to the existing expense screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          groupId: widget.groupId,
          groupName: _groupName ?? 'Group',
        ),
      ),
    ).then((_) => _loadAll()); // Refresh when we return
  }

  Future<void> _editGroupInfo() async {
    final TextEditingController nameController =
        TextEditingController(text: _groupName);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Group Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == true) {
      final newName = nameController.text.trim();

      if (newName.isNotEmpty) {
        setState(() => _loading = true);
        try {
          final groupProvider =
              Provider.of<GroupProvider>(context, listen: false);
          await groupProvider.updateGroupName(widget.groupId, newName);

          if (!mounted) return;
          setState(() {
            _groupName = newName;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group name updated successfully')),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating group: $e')),
          );
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      }
    }

    nameController.dispose();
  }

  // TODO: Add member removal functionality in the future

  Future<void> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
            'Are you sure you want to delete this group? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == true) {
      setState(() => _loading = true);
      try {
        final groupProvider =
            Provider.of<GroupProvider>(context, listen: false);
        await groupProvider.deleteGroup(widget.groupId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group deleted')),
        );

        Navigator.pop(context); // Return to groups list
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting group: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool hasMultipleMembers = _members.length > 1;
    final primaryColor = colorScheme.primary;
    final onPrimaryColor = colorScheme.onPrimary;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.black87;

    if (_loading && _groupName == null) {
      return const Scaffold(
        body: LoadingSpinner(
          initialMessage: 'Loading group details...',
          wakeUpMessage: 'Please wait as the backend wakes up...',
        ),
      );
    }
    if (_error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Details')),
        body: Center(child: Text('Error: $_errorMsg')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: onPrimaryColor,
        iconTheme: IconThemeData(color: onPrimaryColor),
        actionsIconTheme: IconThemeData(color: onPrimaryColor),
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: onPrimaryColor,
            ),
        title: Text(_groupName ?? 'Group Details'),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _editGroupInfo();
                } else if (value == 'delete') {
                  _confirmDelete();
                }
              },
              icon: Icon(Icons.more_vert, color: onPrimaryColor),
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: textColor), // Match text color
                      const SizedBox(width: 8),
                      const Text('Edit Group Name'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Group', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: onPrimaryColor,
          dividerColor: onPrimaryColor,
          labelColor: onPrimaryColor,
          unselectedLabelColor: onPrimaryColor.withAlpha((0.7 * 255).round()),
          tabs: const [
            Tab(text: 'MEMBERS'),
            Tab(text: 'EXPENSES'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Invite code section - simplified if multiple members
          hasMultipleMembers
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ElevatedButton.icon(
                    onPressed: _copyInvite,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Invite Code'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: onPrimaryColor,
                    ),
                  ),
                )
              : Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.people_alt),
                            const SizedBox(width: 8),
                            Text(
                              'Invite Friends',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Share this code with friends so they can join this group:',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _copyInvite,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _inviteCode ?? '',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontFamily: 'monospace',
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Icon(
                                  Icons.copy,
                                  color: colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Members Tab
                _members.isEmpty
                    ? const Center(child: Text('No members found'))
                    : ListView.builder(
                        itemCount: _members.length,
                        itemBuilder: (context, i) {
                          final m = _members[i];
                          final isCurrentUser = m['user_id'] == _currentUserId;
                          final isAdmin = m['role'] == 'admin';

                          final memberId = m['user_id'] as String;
                          final balances = _memberBalances[memberId] ?? {'youOwe': 0.0, 'youAreOwed': 0.0};
                          final double youOwe = isCurrentUser ? 0.0 : (balances['youOwe'] ?? 0.0);
                          final double youAreOwed = isCurrentUser ? 0.0 : (balances['youAreOwed'] ?? 0.0);
                          final currencyProvider = Provider.of<CurrencyProvider>(context, listen: false);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: m['avatar_url'] != null
                                      ? NetworkImage(m['avatar_url'])
                                      : null,
                                  backgroundColor:
                                      colorScheme.primary.withValues(alpha: .2),
                                  child: m['avatar_url'] == null
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m['full_name'] ??
                                            m['username'] ??
                                            'Unknown',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCurrentUser)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'YOU',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    if (isAdmin)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'ADMIN',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('@${m['username'] ?? ''}'),
                                    if (!isCurrentUser) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (youOwe > 0)
                                            Chip(
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              backgroundColor:
                                                  Colors.red.shade50,
                                              label: Text(
                                                'You owe: ${currencyProvider.format(youOwe)}',
                                                style: const TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          if (youOwe > 0 && youAreOwed > 0)
                                            const SizedBox(width: 8),
                                          if (youAreOwed > 0)
                                            Chip(
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              backgroundColor:
                                                  Colors.green.shade50,
                                              label: Text(
                                                'Owes you: ${currencyProvider.format(youAreOwed)}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          if (youOwe == 0 && youAreOwed == 0)
                                            Chip(
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              backgroundColor:
                                                  Colors.grey.shade100,
                                              label: const Text(
                                                'Settled up',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                                isThreeLine: !isCurrentUser,
                              ),
                            ),
                          );
                        },
                      ),

                // Activity/Expenses Tab
                _activities.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No expenses yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _navigateToAddExpense,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: onPrimaryColor,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Add an expense'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _activities.length,
                        itemBuilder: (ctx, i) {
                          final a = _activities[i];
                          final ts = a['when'] as DateTime;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: const Icon(Icons.receipt_long),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    _currencyFormatter.format(a['amount']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '• ${a['actor']}',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a['desc']),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('MMM d, yyyy').format(ts),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              onPressed: _navigateToAddExpense,
              backgroundColor: primaryColor,
              foregroundColor: onPrimaryColor,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
