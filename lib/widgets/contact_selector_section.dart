import 'package:flutter/material.dart';

class ContactSelectorSection extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final List<Map<String, dynamic>> availableContacts;
  final List<Map<String, dynamic>> selectedContacts;
  final ValueChanged<Map<String, dynamic>> onContactSelected;
  final ValueChanged<Map<String, dynamic>> onContactRemoved;

  const ContactSelectorSection({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.availableContacts,
    required this.selectedContacts,
    required this.onContactSelected,
    required this.onContactRemoved,
  });

  @override
  Widget build(BuildContext context) {
    final filteredContacts = availableContacts
        .where((contact) => (contact['name'] ?? '')
            .toString()
            .toLowerCase()
            .contains(searchQuery.toLowerCase()))
        .toList();

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
          controller: searchController,
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
        if (searchQuery.isNotEmpty)
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
              itemCount: filteredContacts.length,
              itemBuilder: (context, index) {
                final contact = filteredContacts[index];
                final isSelected = selectedContacts.any((c) =>
                    c['id'] == contact['id'] &&
                    c['isGroup'] == contact['isGroup']);

                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(contact['isGroup'] == true
                        ? Icons.group
                        : Icons.person),
                  ),
                  title: Text(contact['name'] ?? ''),
                  subtitle: Text(
                    contact['isGroup'] == true
                        ? 'Group'
                        : (contact['is_custom'] == true
                            ? 'Friend (Name only)'
                            : 'Friend'),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.add_circle_outline),
                  onTap: () {
                    if (isSelected) {
                      onContactRemoved(contact);
                    } else {
                      onContactSelected(contact);
                    }
                  },
                );
              },
            ),
          ),

        // Selected contacts chips
        if (selectedContacts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Selected:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedContacts.map((contact) {
              return Chip(
                avatar: CircleAvatar(
                  child: Icon(
                    contact['isGroup'] == true ? Icons.group : Icons.person,
                    size: 16,
                  ),
                ),
                label: Text(contact['name'] ?? ''),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => onContactRemoved(contact),
              );
            }).toList(),
          ),
        ],

        Divider(height: 32, color: Colors.grey.shade300),
      ],
    );
  }
}
