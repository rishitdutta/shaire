import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/friend_provider.dart';
import '../services/logger_service.dart';

class FriendSelectionWidget extends StatefulWidget {
  final List<String> initialSelectedIds;
  final ValueChanged<List<String>> onSelectionChanged;

  const FriendSelectionWidget({
    super.key,
    this.initialSelectedIds = const [],
    required this.onSelectionChanged,
  });

  @override
  State<FriendSelectionWidget> createState() => _FriendSelectionWidgetState();
}

class _FriendSelectionWidgetState extends State<FriendSelectionWidget> {
  final Set<String> _selectedFriendIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedFriendIds
        .addAll(widget.initialSelectedIds.where((id) => id.isNotEmpty));
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FriendProvider>(
      builder: (context, friendProvider, child) {
        final friends = friendProvider.friends;

        final filteredFriends = friends.where((friend) {
          final name =
              (friend['full_name'] ?? friend['username'] ?? '').toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        }).toList();

        return Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search friends...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface.withAlpha(127),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filteredFriends.length,
                itemBuilder: (context, index) {
                  final friend = filteredFriends[index];
                  // The key issue is here - your data structure uses 'id', not 'user_id'
                  final friendId = friend['id']?.toString() ??
                      friend['user_id']?.toString() ??
                      '';

                  final isSelected = _selectedFriendIds.contains(friendId);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (isChecked) {
                      if (friendId.isEmpty) return;

                      setState(() {
                        if (isChecked == true) {
                          _selectedFriendIds.add(friendId);
                          LoggerService.debug(
                              'Added friend: $friendId, total selected: ${_selectedFriendIds.length}');
                        } else {
                          _selectedFriendIds.remove(friendId);
                          LoggerService.debug(
                              'Removed friend: $friendId, total selected: ${_selectedFriendIds.length}');
                        }
                        widget.onSelectionChanged(_selectedFriendIds.toList());
                      });
                    },
                    title: Text(
                        friend['full_name'] ?? friend['username'] ?? 'Unknown'),
                    subtitle: Text('@${friend['username'] ?? ''}'),
                    secondary: CircleAvatar(
                      backgroundImage: friend['avatar_url'] != null
                          ? NetworkImage(friend['avatar_url'])
                          : null,
                      child: friend['avatar_url'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
