import 'dart:async';

enum ToastType {
  success,
  error,
  warning,
  info,
}

class ToastMessage {
  final String message;
  final ToastType type;
  final DateTime timestamp;

  ToastMessage({
    required this.message,
    required this.type,
  }) : timestamp = DateTime.now();
}

class ToastService {
  static final ToastService _instance = ToastService._internal();
  factory ToastService() => _instance;
  ToastService._internal();

  final StreamController<ToastMessage> _messageController =
      StreamController<ToastMessage>.broadcast();
  Stream<ToastMessage> get messageStream => _messageController.stream;

  final List<ToastMessage> _queue = [];
  bool _isShowing = false;

  void success(String message) {
    _addToast(ToastMessage(message: message, type: ToastType.success));
  }

  void error(String message) {
    _addToast(ToastMessage(message: message, type: ToastType.error));
  }

  void warning(String message) {
    _addToast(ToastMessage(message: message, type: ToastType.warning));
  }

  void info(String message) {
    _addToast(ToastMessage(message: message, type: ToastType.info));
  }

  void _addToast(ToastMessage toast) {
    if (_isShowing) {
      _queue.add(toast);
    } else {
      _showToast(toast);
    }
  }

  void _showToast(ToastMessage toast) {
    _isShowing = true;
    _messageController.add(toast);

    // Auto dismiss after 5 seconds
    Timer(const Duration(seconds: 5), () {
      _isShowing = false;
      if (_queue.isNotEmpty) {
        final nextToast = _queue.removeAt(0);
        _showToast(nextToast);
      }
    });
  }

  void dismiss() {
    _isShowing = false;
    if (_queue.isNotEmpty) {
      final nextToast = _queue.removeAt(0);
      _showToast(nextToast);
    }
  }

  void dispose() {
    _messageController.close();
  }
}
