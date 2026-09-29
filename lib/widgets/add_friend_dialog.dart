import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/friend_provider.dart';

class AddFriendDialog extends StatefulWidget {
  final bool defaultNameOnly;

  const AddFriendDialog({
    super.key,
    this.defaultNameOnly = false,
  });

  /// Helper to show the dialog and return the added contact (if name-only friend added)
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    bool defaultNameOnly = false,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AddFriendDialog(defaultNameOnly: defaultNameOnly),
    );
  }

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  final TextEditingController _controller = TextEditingController();
  late bool _isNameOnly;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isNameOnly = widget.defaultNameOnly;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = _isNameOnly
            ? 'Please enter a name'
            : 'Please enter a username or email';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final friendProvider = Provider.of<FriendProvider>(context, listen: false);

    try {
      if (_isNameOnly) {
        final newFriend = await friendProvider.addCustomFriend(input);
        if (mounted) {
          Navigator.pop(context, newFriend);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Friend "$input" added!')),
          );
        }
      } else {
        await friendProvider.sendFriendRequest(input);
        if (mounted) {
          Navigator.pop(context, null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Friend request sent!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            selected: {_isNameOnly},
            onSelectionChanged: _isSubmitting
                ? null
                : (newSelection) {
                    setState(() {
                      _isNameOnly = newSelection.first;
                      _controller.clear();
                      _errorMessage = null;
                    });
                  },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isSubmitting,
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
            onSubmitted: (_) => _handleSubmit(),
            decoration: InputDecoration(
              labelText: _isNameOnly ? "Friend's Name" : "Username or Email",
              hintText:
                  _isNameOnly ? "e.g. Alex" : "e.g. alex or alex@gmail.com",
              helperText: _isNameOnly
                  ? "Quickly add now, link to account later"
                  : null,
              errorText: _errorMessage,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isNameOnly ? 'ADD FRIEND' : 'SEND REQUEST'),
        ),
      ],
    );
  }
}
