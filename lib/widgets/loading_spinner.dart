import 'dart:async';
import 'package:flutter/material.dart';

class LoadingSpinner extends StatefulWidget {
  final String? initialMessage;
  final String wakeUpMessage;
  final Duration wakeUpThreshold;
  final bool compact;
  final Color? color;

  const LoadingSpinner({
    super.key,
    this.initialMessage,
    this.wakeUpMessage = 'Please wait as the backend wakes up...',
    this.wakeUpThreshold = const Duration(seconds: 10),
    this.compact = false,
    this.color,
  });

  @override
  State<LoadingSpinner> createState() => _LoadingSpinnerState();
}

class _LoadingSpinnerState extends State<LoadingSpinner> {
  Timer? _timer;
  bool _showWakeUpMessage = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.wakeUpThreshold, () {
      if (mounted) {
        setState(() {
          _showWakeUpMessage = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = widget.color ?? theme.colorScheme.primary;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
        ),
        if (widget.initialMessage != null && !_showWakeUpMessage) ...[
          const SizedBox(height: 16),
          Text(
            widget.initialMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
        if (_showWakeUpMessage) ...[
          const SizedBox(height: 16),
          AnimatedOpacity(
            opacity: _showWakeUpMessage ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.wakeUpMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (!widget.compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Free cloud instances take a moment to spin up',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );

    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(child: content),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: content,
      ),
    );
  }
}
