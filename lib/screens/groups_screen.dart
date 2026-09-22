import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/currency_provider.dart';
import '../providers/friend_provider.dart'; // <-- Import
import '../providers/group_provider.dart'; // <-- Import
// Import detail screens if they exist, otherwise keep placeholders
import '../widgets/friend_selection_widget.dart';
import 'friend_details_screen.dart';
import 'group_details_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Controllers for dialogs
  final TextEditingController _addFriendController = TextEditingController();
  final TextEditingController _joinGroupController = TextEditingController();
  final TextEditingController _createGroupController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.index = 0;
    _searchController.addListener(_updateSearchQuery);
    _tabController.addListener(_tabChanged);

    // Fetch initial data using the providers
    // Use WidgetsBinding to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<FriendProvider>(context, listen: false)
          .fetchFriendsAndRequests();
      Provider.of<GroupProvider>(context, listen: false).fetchGroups();
    });
  }

  void _updateSearchQuery() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  void _tabChanged() {
    // Only update if the tab is actually changing
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_tabChanged);
    _tabController.dispose();
    _searchController.removeListener(_updateSearchQuery);
    _searchController.dispose();
    _addFriendController.dispose();
    _joinGroupController.dispose();
    _createGroupController.dispose();
    _joinGroupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get providers for easy access in build methods if needed (though Consumer is often better)
    // final friendProvider = Provider.of<FriendProvider>(context);
    // final groupProvider = Provider.of<GroupProvider>(context);

    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimaryColor = Theme.of(context).colorScheme.onPrimary;
    final Color surfaceColor = Theme.of(context).colorScheme.surface;

    //final Color secondaryColor = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: primaryColor,
        iconTheme: IconThemeData(color: onPrimaryColor),
        title: Text(
          'Friends & Groups',
          style: TextStyle(color: onPrimaryColor),
        ),
        centerTitle: true,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'FRIENDS'),
              Tab(text: 'GROUPS'),
            ],
            indicatorColor: onPrimaryColor,
            dividerColor: onPrimaryColor,
            labelColor: onPrimaryColor,
            unselectedLabelColor: onPrimaryColor.withAlpha((0.7 * 255).round()),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    'Search ${_tabController.index == 0 ? "Friends" : "Groups"}...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                // --- FIX: Replace withOpacity with withAlpha ---
                fillColor: surfaceColor.withAlpha((0.5 * 255).round()),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Consumer<FriendProvider>(
                    builder: (context, friendProvider, child) {
                  if (friendProvider.isLoading &&
                      friendProvider.friends.isEmpty &&
                      friendProvider.pendingReceived.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (friendProvider.error != null) {
                    return Center(
                        child: Text("Error: ${friendProvider.error}"));
                  }
                  return _buildFriendsTabContent(friendProvider);
                }),
                Consumer<GroupProvider>(
                    builder: (context, groupProvider, child) {
                  if (groupProvider.isLoading && groupProvider.groups.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (groupProvider.error != null) {
                    return Center(child: Text("Error: ${groupProvider.error}"));
                  }
                  return _buildGroupsTabContent(groupProvider);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Modified Friends Tab ---
  Widget _buildFriendsTabContent(FriendProvider friendProvider) {
    final currencyProvider = Provider.of<CurrencyProvider>(context);
    final Color secondaryColor = Theme.of(context).colorScheme.secondary;
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color onPrimaryColor = Theme.of(context).colorScheme.onPrimary;

    final List<Map<String, dynamic>> pendingRequests =
        friendProvider.pendingReceived;
    final List<Map<String, dynamic>> filteredFriends = friendProvider.friends
        .where((friend) => (friend['full_name'] ?? friend['username'] ?? '')
            .toLowerCase()
            .contains(_searchQuery.toLowerCase()))
        .toList();

    final List<Map<String, dynamic>> displayItems = [
      ...pendingRequests.map((req) => {...req, '_type': 'pending'}),
      ...filteredFriends.map((friend) => {...friend, '_type': 'friend'}),
    ];

    final itemCount = displayItems.length;

    return Stack(
      children: [
        itemCount == 0 && _searchQuery.isEmpty && !friendProvider.isLoading
            ? const Center(
                child: Text(
                    'No friends or requests yet.\nUse the + button to add friends.'))
            : itemCount == 0 && _searchQuery.isNotEmpty
                ? const Center(
                    child: Text('No friends found matching your search.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      final item = displayItems[index];
                      final itemType = item['_type'];

                      if (itemType == 'pending') {
                        final sender = item['sender_profile'] ?? {};
                        final friendshipId = item['friendship_id'] as int;
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  Theme.of(context).colorScheme.secondary,
                              child: const Icon(Icons.person_add,
                                  color: Colors.white),
                            ),
                            title: Text(sender['full_name'] ??
                                sender['username'] ??
                                ''),
                            subtitle: const Text('Wants to be your friend'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Accept
                                IconButton(
                                  icon: const Icon(Icons.check,
                                      color: Colors.green),
                                  //tooltip: 'Accept',
                                  onPressed: () async {
                                    // Store reference to the context at the current scope
                                    final currentContext = context;

                                    try {
                                      await friendProvider
                                          .respondToFriendRequest(
                                              friendshipId, true);

                                      if (!mounted) return;

                                      // Use the stored context reference
                                      ScaffoldMessenger.of(currentContext)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Friend request accepted!')),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;

                                      // Use the stored context reference
                                      ScaffoldMessenger.of(currentContext)
                                          .showSnackBar(
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    }
                                  },
                                ),

// Reject
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  //tooltip: 'Reject',
                                  onPressed: () async {
                                    //final messenger = ScaffoldMessenger.of(context);
                                    try {
                                      await friendProvider
                                          .respondToFriendRequest(
                                              friendshipId, false);
                                      if (!mounted) return;
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Friend request rejected!')),
                                        );
                                      });
                                    } catch (e) {
                                      if (!mounted) return;
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(content: Text('Error: $e')),
                                        );
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      } else if (itemType == 'friend') {
                        final friendId = item['id'].toString();
                        final isCustom = item['is_custom'] == true;
                        final isLinked = item['linked_user_id'] != null;
                        final balance = friendProvider.friendBalances[friendId] ??
                            {'youOwe': 0.0, 'youAreOwed': 0.0};
                        final youGet = balance['youAreOwed'] ?? 0.0;
                        final youOwe = balance['youOwe'] ?? 0.0;
                        final netBalance = youGet - youOwe;
                        final displayName = item['full_name'] ??
                            item['username'] ??
                            'Unknown';

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  primaryColor.withAlpha((0.8 * 255).round()),
                              child: Icon(
                                isCustom && !isLinked
                                    ? Icons.person_outline
                                    : Icons.person,
                                color: onPrimaryColor,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(displayName),
                                ),
                                if (isCustom && !isLinked)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Name only',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: isCustom && !isLinked
                                ? Row(
                                    children: [
                                      Icon(Icons.link,
                                          size: 13,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Tap to connect account',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ],
                                  )
                                : (netBalance > 0
                                    ? Text(
                                        'You get ${currencyProvider.format(netBalance)}',
                                        style: const TextStyle(
                                            color: Colors.green),
                                      )
                                    : netBalance < 0
                                        ? Text(
                                            'You owe ${currencyProvider.format(netBalance.abs())}',
                                            style: const TextStyle(
                                                color: Colors.red),
                                          )
                                        : const Text('Settled up')),
                            onTap: () {
                              if (isCustom && !isLinked) {
                                _showLinkFriendDialog(
                                    friendProvider, friendId, displayName);
                              } else {
                                final targetId =
                                    item['linked_user_id'] ?? friendId;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        FriendDetailsScreen(friendId: targetId),
                                  ),
                                );
                              }
                            },
                          ),
                        );
                      } else {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'addFriendFab',
            backgroundColor: primaryColor,
            foregroundColor: onPrimaryColor,
            onPressed: () {
              _showAddFriendDialog(friendProvider);
            },
            child: const Icon(Icons.person_add),
          ),
        ),
      ],
    );
  }

  // --- Modified Groups Tab ---
  Widget _buildGroupsTabContent(GroupProvider groupProvider) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color onPrimaryColor = Theme.of(context).colorScheme.onPrimary;
    final Color secondaryColor = Theme.of(context).colorScheme.secondary;
    final Color onSecondaryColor = Theme.of(context).colorScheme.onSecondary;

    final List<Map<String, dynamic>> filteredGroups = groupProvider.groups
        .where((group) => (group['name'] ?? '')
            .toLowerCase()
            .contains(_searchQuery.toLowerCase()))
        .toList();
    final itemCount = filteredGroups.length;

    return Stack(
      children: [
        itemCount == 0 && _searchQuery.isEmpty && !groupProvider.isLoading
            ? const Center(
                child: Text(
                    'No groups found.\nUse the buttons to create or join.'))
            : itemCount == 0 && _searchQuery.isNotEmpty
                ? const Center(
                    child: Text('No groups found matching your search.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 150),
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      final group = filteredGroups[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            // --- FIX: Replace withOpacity with withAlpha ---
                            backgroundColor:
                                primaryColor.withAlpha((0.8 * 255).round()),
                            child: Icon(Icons.group, color: onPrimaryColor),
                          ),
                          title: Text(group['name'] ?? 'Unnamed Group'),
                          subtitle:
                              Text('Members: ${group['member_count'] ?? 0}'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroupDetailsScreen(
                                  groupId: group['id'] as int,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'joinGroupFab',
                tooltip: 'Join Group',
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                onPressed: () => _showJoinGroupDialog(groupProvider),
                child: const Icon(Icons.group_add),
              ),
              const SizedBox(height: 16),
              FloatingActionButton(
                heroTag: 'createGroupFab',
                tooltip: 'Create Group',
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                onPressed: () => _showCreateGroupDialog(groupProvider),
                child: const Icon(Icons.create),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddFriendDialog(FriendProvider friendProvider) {
    _addFriendController.clear();
    final outer = context; // <— capture screen context
    bool isNameOnly = false;

    showDialog(
      context: outer,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Friend'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Shaire User'),
                      icon: Icon(Icons.person_search),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Name Only'),
                      icon: Icon(Icons.badge_outlined),
                    ),
                  ],
                  selected: {isNameOnly},
                  onSelectionChanged: (newSelection) {
                    setDialogState(() {
                      isNameOnly = newSelection.first;
                      _addFriendController.clear();
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _addFriendController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText:
                        isNameOnly ? "Friend's Name" : "Username or Email",
                    hintText: isNameOnly
                        ? "e.g. Alex"
                        : "e.g. alex or alex@gmail.com",
                    helperText: isNameOnly
                        ? "Quickly add now, link to account later"
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final input = _addFriendController.text.trim();
                  if (input.isEmpty) return;

                  Navigator.pop(dialogCtx);
                  try {
                    if (isNameOnly) {
                      await friendProvider.addCustomFriend(input);
                      if (!mounted) return;
                      ScaffoldMessenger.of(outer).showSnackBar(
                        SnackBar(content: Text('Friend "$input" added!')),
                      );
                    } else {
                      await friendProvider.sendFriendRequest(input);
                      if (!mounted) return;
                      ScaffoldMessenger.of(outer).showSnackBar(
                        const SnackBar(content: Text('Friend request sent!')),
                      );
                    }
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(outer).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}')),
                    );
                  }
                },
                child: Text(isNameOnly ? 'ADD FRIEND' : 'SEND REQUEST'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLinkFriendDialog(FriendProvider friendProvider,
      String customFriendId, String friendName) {
    final linkController = TextEditingController();
    final outer = context;

    showDialog(
      context: outer,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Connect $friendName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Link $friendName to their Shaire account to sync shared expenses and balances.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: linkController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Username or Email",
                hintText: "e.g. alex or alex@gmail.com",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_search),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final input = linkController.text.trim();
              if (input.isEmpty) return;

              Navigator.pop(dialogCtx);
              try {
                await friendProvider.linkCustomFriend(customFriendId, input);
                if (!mounted) return;
                ScaffoldMessenger.of(outer).showSnackBar(
                  SnackBar(content: Text('$friendName connected to $input!')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(outer).showSnackBar(
                  SnackBar(content: Text('Error: ${e.toString()}')),
                );
              }
            },
            child: const Text('CONNECT'),
          ),
        ],
      ),
    );
  }

  void _showJoinGroupDialog(GroupProvider groupProvider) {
    final outerCtx = context;
    _joinGroupController.clear();

    showDialog(
      context: outerCtx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Join Group'),
        content: TextField(
          controller: _joinGroupController,
          decoration: const InputDecoration(labelText: 'Invite Code'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = _joinGroupController.text.trim();
              if (code.isEmpty) {
                ScaffoldMessenger.of(outerCtx).showSnackBar(
                  const SnackBar(content: Text('Please enter an invite code')),
                );
                return;
              }
              Navigator.pop(dialogCtx);
              try {
                await groupProvider.joinGroup(code);
                if (!mounted) return;
                ScaffoldMessenger.of(outerCtx).showSnackBar(
                  const SnackBar(content: Text('Joined group successfully!')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(outerCtx).showSnackBar(
                  SnackBar(content: Text('Error joining group: $e')),
                );
              }
            },
            child: const Text('JOIN'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog(GroupProvider groupProvider) {
    _createGroupController.clear();
    List<String> selectedFriends = [];
    final outer = context;

    showDialog(
      context: outer,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Create Group'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _createGroupController,
                decoration: const InputDecoration(labelText: 'Group Name'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text('Add friends to group:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: FriendSelectionWidget(
                  onSelectionChanged: (selectedIds) {
                    selectedFriends = selectedIds;
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('CANCEL'),
          ),
          // In your _showCreateGroupDialog method:
          ElevatedButton(
            onPressed: () async {
              final name = _createGroupController.text;
              if (name.trim().isEmpty) {
                ScaffoldMessenger.of(outer).showSnackBar(
                  const SnackBar(content: Text('Please enter a group name')),
                );
                return;
              }

              Navigator.pop(dialogCtx);
              try {
                // Create group first
                final groupId = await groupProvider.createGroup(name, null);

                // Add selected friends to the group (this was the issue)
                if (selectedFriends.isNotEmpty) {
                  await groupProvider.addMembersToGroup(
                      groupId, selectedFriends);

                  // Show success toast
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Group created with ${selectedFriends.length} members!')),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

// --- Placeholder Detail Screens ---
// Replace these with actual implementations using providers to fetch data by ID
}
