import 'package:flutter/material.dart';
import '../services/quick_tags_service.dart';

class EditTagsDialog extends StatefulWidget {
  final List<String> initialTags;

  const EditTagsDialog({super.key, required this.initialTags});

  static Future<List<String>?> show(
      BuildContext context, List<String> currentTags) {
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => EditTagsDialog(initialTags: currentTags),
    );
  }

  @override
  State<EditTagsDialog> createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends State<EditTagsDialog> {
  late List<String> _tags;
  final TextEditingController _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final text = _newTagController.text.trim();
    if (text.isEmpty) return;
    if (_tags.contains(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tag already exists')),
      );
      return;
    }
    setState(() {
      _tags.add(text);
      _newTagController.clear();
    });
    QuickTagsService.saveTags(_tags);
  }

  void _removeTag(int index) {
    if (index >= 0 && index < _tags.length) {
      setState(() {
        _tags.removeAt(index);
      });
      QuickTagsService.saveTags(_tags);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _tags.removeAt(oldIndex);
      _tags.insert(newIndex, item);
    });
    QuickTagsService.saveTags(_tags);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.label_outline, color: colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          const Text('Manage Quick Tags'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Add new tag input
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTagController,
                      decoration: InputDecoration(
                        hintText: 'e.g. 🍿 Movies or Books',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Add Tag',
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _addTag,
                      child: const Icon(Icons.add, size: 20, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Reorderable list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: _tags.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('No tags yet. Add one above!'),
                    )
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      itemCount: _tags.length,
                      // ignore: deprecated_member_use
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final tag = _tags[index];
                        return ListTile(
                          key: ValueKey(tag),
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: Icon(
                              Icons.drag_indicator,
                              size: 20,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          title: Text(
                            tag,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            color: colorScheme.error,
                            onPressed: () => _removeTag(index),
                            tooltip: 'Delete tag',
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        TextButton(
          onPressed: () {
            // Restore defaults
            setState(() {
              _tags = List<String>.from(QuickTagsService.defaultTags);
            });
            QuickTagsService.saveTags(_tags);
          },
          child: const Text('Reset Defaults'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _tags),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
