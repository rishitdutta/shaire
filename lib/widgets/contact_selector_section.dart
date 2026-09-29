import 'package:flutter/material.dart';
import 'add_friend_dialog.dart';

class ContactSelectorSection extends StatefulWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final List<Map<String, dynamic>> availableContacts;
  final List<Map<String, dynamic>> selectedContacts;
  final ValueChanged<Map<String, dynamic>> onContactSelected;
  final ValueChanged<Map<String, dynamic>> onContactRemoved;
  final ValueChanged<Map<String, dynamic>>? onFriendAdded;

  const ContactSelectorSection({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.availableContacts,
    required this.selectedContacts,
    required this.onContactSelected,
    required this.onContactRemoved,
    this.onFriendAdded,
  });

  @override
  State<ContactSelectorSection> createState() => _ContactSelectorSectionState();
}

class _ContactSelectorSectionState extends State<ContactSelectorSection> {
  final FocusNode _focusNode = FocusNode();
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus && !_isOpen) {
      setState(() => _isOpen = true);
    }
  }

  Future<void> _openAddFriendDialog() async {
    final newFriend = await AddFriendDialog.show(
      context,
      defaultNameOnly: true,
    );
    if (newFriend != null) {
      widget.onFriendAdded?.call(newFriend);
      setState(() {
        _isOpen = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.searchController.text.trim().toLowerCase();
    final filteredContacts = query.isEmpty
        ? widget.availableContacts
        : widget.availableContacts
            .where((contact) => (contact['name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(query))
            .toList();

    return TapRegion(
      onTapOutside: (_) {
        if (_isOpen) {
          setState(() => _isOpen = false);
          _focusNode.unfocus();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select People or Groups',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),

          // Search bar
          TextField(
            controller: widget.searchController,
            focusNode: _focusNode,
            onTap: () {
              if (!_isOpen) {
                setState(() => _isOpen = true);
              }
            },
            decoration: InputDecoration(
              hintText: 'Search friends or groups',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: widget.searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        widget.searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary, width: 2),
              ),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).cardColor.withValues(alpha: 0.5)
                  : Colors.grey.shade100,
            ),
          ),

          // Dropdown list (stays open until tapped outside, shows full list on focus)
          if (_isOpen)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filteredContacts.length + 1, // +1 for "Add new friend"
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                itemBuilder: (context, index) {
                  // Last item is always the Add Friend button
                  if (index == filteredContacts.length) {
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.person_add_alt_1,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        'Add new friend',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text('Add by name quickly'),
                      trailing: Icon(
                        Icons.add,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onTap: _openAddFriendDialog,
                    );
                  }

                  final contact = filteredContacts[index];
                  final isSelected = widget.selectedContacts.any((c) =>
                      c['id'].toString() == contact['id'].toString() &&
                      c['isGroup'] == contact['isGroup']);

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.grey.shade300,
                      child: Icon(
                        contact['isGroup'] == true ? Icons.group : Icons.person,
                        size: 18,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade700,
                      ),
                    ),
                    title: Text(
                      contact['name'] ?? '',
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      contact['isGroup'] == true
                          ? 'Group'
                          : (contact['is_custom'] == true
                              ? 'Friend (Name only)'
                              : 'Friend'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (_) {
                        if (isSelected) {
                          widget.onContactRemoved(contact);
                        } else {
                          widget.onContactSelected(contact);
                        }
                      },
                    ),
                    onTap: () {
                      // Continuous selection: toggle without closing dropdown
                      if (isSelected) {
                        widget.onContactRemoved(contact);
                      } else {
                        widget.onContactSelected(contact);
                      }
                    },
                  );
                },
              ),
            ),

          // Selected contacts chips
          if (widget.selectedContacts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Selected (${widget.selectedContacts.length}):',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.selectedContacts.map((contact) {
                return Chip(
                  avatar: CircleAvatar(
                    child: Icon(
                      contact['isGroup'] == true ? Icons.group : Icons.person,
                      size: 14,
                    ),
                  ),
                  label: Text(contact['name'] ?? ''),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => widget.onContactRemoved(contact),
                );
              }).toList(),
            ),
          ],

          Divider(height: 32, color: Theme.of(context).dividerColor),
        ],
      ),
    );
  }
}
