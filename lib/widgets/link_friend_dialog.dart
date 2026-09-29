import 'package:flutter/material.dart';
import '../providers/friend_provider.dart';

class LinkFriendDialog extends StatefulWidget {
  final FriendProvider friendProvider;
  final String customFriendId;
  final String friendName;

  const LinkFriendDialog({
    super.key,
    required this.friendProvider,
    required this.customFriendId,
    required this.friendName,
  });

  /// Helper to show the dialog and return true if successfully linked
  static Future<bool?> show(
    BuildContext context, {
    required FriendProvider friendProvider,
    required String customFriendId,
    required String friendName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => LinkFriendDialog(
        friendProvider: friendProvider,
        customFriendId: customFriendId,
        friendName: friendName,
      ),
    );
  }

  @override
  State<LinkFriendDialog> createState() => _LinkFriendDialogState();
}

class _LinkFriendDialogState extends State<LinkFriendDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a username or email';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.friendProvider.linkCustomFriend(widget.customFriendId, input);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.friendName} connected to $input!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Connect ${widget.friendName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Link ${widget.friendName} to their Shaire account to sync shared expenses and balances.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isSubmitting,
            onSubmitted: (_) => _handleSubmit(),
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
            decoration: InputDecoration(
              labelText: 'Username or Email',
              hintText: 'e.g. alex or alex@gmail.com',
              errorText: _errorMessage,
              prefixIcon: const Icon(Icons.person_search),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
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
              : const Text('CONNECT'),
        ),
      ],
    );
  }
}
