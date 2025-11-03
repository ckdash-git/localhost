import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';

/// Error types for the server application
enum ErrorType {
  serverStartup,
  serverConnection,
  webViewLoad,
  networkTimeout,
  portInUse,
  unknown,
}

/// Error severity levels
enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

/// Application error class with detailed information
class AppError {
  final ErrorType type;
  final ErrorSeverity severity;
  final String message;
  final String? details;
  final DateTime timestamp;
  final StackTrace? stackTrace;

  AppError({
    required this.type,
    required this.severity,
    required this.message,
    this.details,
    this.stackTrace,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'AppError(type: $type, severity: $severity, message: $message, timestamp: $timestamp)';
  }
}

/// Centralized error handling service
class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  final StreamController<AppError> _errorController = StreamController<AppError>.broadcast();
  Stream<AppError> get errorStream => _errorController.stream;

  /// Handle and log errors
  void handleError(AppError error) {
    // Log to console/developer tools
    developer.log(
      error.message,
      name: 'ErrorHandler',
      error: error.details,
      stackTrace: error.stackTrace,
      level: _getLogLevel(error.severity),
    );

    // Broadcast error to listeners
    _errorController.add(error);
  }

  /// Create and handle server startup errors
  void handleServerStartupError(String message, {String? details, StackTrace? stackTrace}) {
    handleError(AppError(
      type: ErrorType.serverStartup,
      severity: ErrorSeverity.high,
      message: message,
      details: details,
      stackTrace: stackTrace,
    ));
  }

  /// Create and handle server connection errors
  void handleServerConnectionError(String message, {String? details, StackTrace? stackTrace}) {
    handleError(AppError(
      type: ErrorType.serverConnection,
      severity: ErrorSeverity.medium,
      message: message,
      details: details,
      stackTrace: stackTrace,
    ));
  }

  /// Create and handle WebView loading errors
  void handleWebViewError(String message, {String? details, StackTrace? stackTrace}) {
    handleError(AppError(
      type: ErrorType.webViewLoad,
      severity: ErrorSeverity.medium,
      message: message,
      details: details,
      stackTrace: stackTrace,
    ));
  }

  /// Create and handle port in use errors
  void handlePortInUseError(int port, {String? details, StackTrace? stackTrace}) {
    handleError(AppError(
      type: ErrorType.portInUse,
      severity: ErrorSeverity.high,
      message: 'Port $port is already in use',
      details: details ?? 'Another application is using port $port. Please stop it or choose a different port.',
      stackTrace: stackTrace,
    ));
  }

  /// Create and handle network timeout errors
  void handleNetworkTimeoutError(String message, {String? details, StackTrace? stackTrace}) {
    handleError(AppError(
      type: ErrorType.networkTimeout,
      severity: ErrorSeverity.medium,
      message: message,
      details: details,
      stackTrace: stackTrace,
    ));
  }

  /// Get user-friendly error message
  String getUserFriendlyMessage(AppError error) {
    switch (error.type) {
      case ErrorType.serverStartup:
        return 'Failed to start server: ${error.message}';
      case ErrorType.serverConnection:
        return 'Server connection issue: ${error.message}';
      case ErrorType.webViewLoad:
        return 'Failed to load page: ${error.message}';
      case ErrorType.networkTimeout:
        return 'Network timeout: ${error.message}';
      case ErrorType.portInUse:
        return error.message;
      case ErrorType.unknown:
        return 'An unexpected error occurred: ${error.message}';
    }
  }

  /// Get suggested actions for error recovery
  List<String> getSuggestedActions(AppError error) {
    switch (error.type) {
      case ErrorType.serverStartup:
        return [
          'Check if port 3000 is available',
          'Restart the application',
          'Check network permissions',
        ];
      case ErrorType.serverConnection:
        return [
          'Check your internet connection',
          'Restart the server',
          'Try again in a few moments',
        ];
      case ErrorType.webViewLoad:
        return [
          'Check if server is running',
          'Reload the page',
          'Check network connection',
        ];
      case ErrorType.networkTimeout:
        return [
          'Check your internet connection',
          'Try again later',
          'Restart the application',
        ];
      case ErrorType.portInUse:
        return [
          'Stop other applications using port 3000',
          'Restart your device',
          'Try a different port',
        ];
      case ErrorType.unknown:
        return [
          'Restart the application',
          'Check system resources',
          'Contact support if issue persists',
        ];
    }
  }

  /// Convert error severity to log level
  int _getLogLevel(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return 500; // INFO
      case ErrorSeverity.medium:
        return 900; // WARNING
      case ErrorSeverity.high:
        return 1000; // SEVERE
      case ErrorSeverity.critical:
        return 1200; // SHOUT
    }
  }

  /// Show error dialog to user
  static void showErrorDialog(BuildContext context, AppError error) {
    final errorHandler = ErrorHandler();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getErrorIcon(error.severity),
              color: _getErrorColor(error.severity),
            ),
            const SizedBox(width: 8),
            const Text('Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errorHandler.getUserFriendlyMessage(error)),
            if (error.details != null) ...[
              const SizedBox(height: 8),
              Text(
                'Details: ${error.details}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            const Text('Suggested actions:'),
            ...errorHandler.getSuggestedActions(error).map(
              (action) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text('• $action'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Get icon for error severity
  static IconData _getErrorIcon(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return Icons.info_outline;
      case ErrorSeverity.medium:
        return Icons.warning_amber_outlined;
      case ErrorSeverity.high:
        return Icons.error_outline;
      case ErrorSeverity.critical:
        return Icons.dangerous_outlined;
    }
  }

  /// Get color for error severity
  static Color _getErrorColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.low:
        return Colors.blue;
      case ErrorSeverity.medium:
        return Colors.orange;
      case ErrorSeverity.high:
        return Colors.red;
      case ErrorSeverity.critical:
        return Colors.red.shade900;
    }
  }

  /// Dispose resources
  void dispose() {
    _errorController.close();
  }
}