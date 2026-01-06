import 'package:flutter/material.dart';
import 'package:term_deck/services/toast_service.dart';
import 'package:term_deck/theme/app_theme.dart';

class ToastOverlay extends StatefulWidget {
  final Widget child;

  const ToastOverlay({
    super.key,
    required this.child,
  });

  @override
  State<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<ToastOverlay>
    with SingleTickerProviderStateMixin {
  final ToastService _toastService = ToastService();
  ToastMessage? _currentToast;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _toastService.messageStream.listen((toast) {
      setState(() {
        _currentToast = toast;
      });
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismissToast() {
    _animationController.reverse().then((_) {
      setState(() {
        _currentToast = null;
      });
      _toastService.dismiss();
    });
  }

  IconData _getIconForType(ToastType type) {
    switch (type) {
      case ToastType.success:
        return Icons.check_circle;
      case ToastType.error:
        return Icons.cancel;
      case ToastType.warning:
        return Icons.warning;
      case ToastType.info:
        return Icons.info;
    }
  }

  Color _getColorForType(ToastType type) {
    switch (type) {
      case ToastType.success:
        return AppColors.green;
      case ToastType.error:
        return AppColors.red;
      case ToastType.warning:
        return AppColors.yellow;
      case ToastType.info:
        return AppColors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_currentToast != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _slideAnimation,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _ToastCard(
                    message: _currentToast!.message,
                    type: _currentToast!.type,
                    icon: _getIconForType(_currentToast!.type),
                    color: _getColorForType(_currentToast!.type),
                    onDismiss: _dismissToast,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  final String message;
  final ToastType type;
  final IconData icon;
  final Color color;
  final VoidCallback onDismiss;

  const _ToastCard({
    required this.message,
    required this.type,
    required this.icon,
    required this.color,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface0,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.text,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                color: AppColors.subtext0,
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
