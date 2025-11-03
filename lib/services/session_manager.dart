import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'server_manager.dart';

/// Session data model
class SessionData {
  final bool wasServerRunning;
  final bool wasWebViewVisible;
  final String? lastUrl;
  final DateTime timestamp;

  SessionData({
    required this.wasServerRunning,
    required this.wasWebViewVisible,
    this.lastUrl,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'wasServerRunning': wasServerRunning,
      'wasWebViewVisible': wasWebViewVisible,
      'lastUrl': lastUrl,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      wasServerRunning: json['wasServerRunning'] ?? false,
      wasWebViewVisible: json['wasWebViewVisible'] ?? false,
      lastUrl: json['lastUrl'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

/// URL validation and restriction utilities
class UrlValidator {
  static const List<String> _allowedHosts = [
    'localhost',
    '127.0.0.1',
    '0.0.0.0',
  ];

  static const List<int> _allowedPorts = [3000, 8000, 8080, 3001, 5000];

  /// Check if URL is allowed for navigation
  static bool isUrlAllowed(String url) {
    try {
      final uri = Uri.parse(url);
      
      // Allow only HTTP/HTTPS protocols
      if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
        return false;
      }

      // Check if host is in allowed list
      if (!_allowedHosts.contains(uri.host.toLowerCase())) {
        return false;
      }

      // Check if port is allowed (if specified)
      if (uri.hasPort && !_allowedPorts.contains(uri.port)) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get user-friendly message for blocked URL
  static String getBlockedUrlMessage(String url) {
    try {
      final uri = Uri.parse(url);
      
      if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
        return 'Only HTTP and HTTPS protocols are allowed';
      }

      if (!_allowedHosts.contains(uri.host.toLowerCase())) {
        return 'Navigation is restricted to localhost only';
      }

      if (uri.hasPort && !_allowedPorts.contains(uri.port)) {
        return 'Port ${uri.port} is not allowed. Allowed ports: ${_allowedPorts.join(', ')}';
      }

      return 'URL is not allowed';
    } catch (e) {
      return 'Invalid URL format';
    }
  }

  /// Check if URL is the server URL
  static bool isServerUrl(String url, String serverUrl) {
    try {
      final urlUri = Uri.parse(url);
      final serverUri = Uri.parse(serverUrl);
      
      return urlUri.host == serverUri.host && 
             urlUri.port == serverUri.port &&
             urlUri.scheme == serverUri.scheme;
    } catch (e) {
      return false;
    }
  }
}

/// Session management service
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  static const String _sessionKey = 'server_app_session';
  static const Duration _sessionTimeout = Duration(hours: 24);

  SessionData? _currentSession;
  Timer? _saveTimer;

  /// Initialize session manager
  Future<void> initialize() async {
    await _loadSession();
    _startPeriodicSave();
  }

  /// Get current session data
  SessionData? get currentSession => _currentSession;

  /// Save current application state
  Future<void> saveSession({
    required bool isServerRunning,
    required bool isWebViewVisible,
    String? currentUrl,
  }) async {
    _currentSession = SessionData(
      wasServerRunning: isServerRunning,
      wasWebViewVisible: isWebViewVisible,
      lastUrl: currentUrl,
      timestamp: DateTime.now(),
    );

    await _persistSession();
  }

  /// Restore session if valid
  Future<SessionData?> restoreSession() async {
    if (_currentSession == null) {
      return null;
    }

    // Check if session is not expired
    final now = DateTime.now();
    final sessionAge = now.difference(_currentSession!.timestamp);
    
    if (sessionAge > _sessionTimeout) {
      await clearSession();
      return null;
    }

    return _currentSession;
  }

  /// Clear session data
  Future<void> clearSession() async {
    _currentSession = null;
    await _persistSession();
  }

  /// Check if session should be restored
  bool shouldRestoreSession() {
    if (_currentSession == null) return false;
    
    final sessionAge = DateTime.now().difference(_currentSession!.timestamp);
    return sessionAge <= _sessionTimeout;
  }

  /// Load session from storage
  Future<void> _loadSession() async {
    try {
      // In a real app, you would use SharedPreferences or similar
      // For this demo, we'll use a simple in-memory approach
      // You can extend this to use actual persistent storage
      
      if (kDebugMode) {
        print('SessionManager: Loading session data...');
      }
      
      // Simulate loading from storage
      // In production, implement actual storage mechanism
      
    } catch (e) {
      if (kDebugMode) {
        print('SessionManager: Failed to load session: $e');
      }
    }
  }

  /// Persist session to storage
  Future<void> _persistSession() async {
    try {
      if (kDebugMode) {
        print('SessionManager: Saving session data...');
        if (_currentSession != null) {
          print('Session: ${jsonEncode(_currentSession!.toJson())}');
        }
      }
      
      // In production, implement actual storage mechanism
      // Example: SharedPreferences, SQLite, etc.
      
    } catch (e) {
      if (kDebugMode) {
        print('SessionManager: Failed to save session: $e');
      }
    }
  }

  /// Start periodic session saving
  void _startPeriodicSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_currentSession != null) {
        _persistSession();
      }
    });
  }

  /// Auto-restore server state based on session
  Future<bool> autoRestoreServerState(ServerManager serverManager) async {
    final session = await restoreSession();
    if (session == null || !session.wasServerRunning) {
      return false;
    }

    try {
      if (kDebugMode) {
        print('SessionManager: Auto-restoring server state...');
      }
      
      final success = await serverManager.startServer();
      if (success && kDebugMode) {
        print('SessionManager: Server state restored successfully');
      }
      
      return success;
    } catch (e) {
      if (kDebugMode) {
        print('SessionManager: Failed to restore server state: $e');
      }
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _saveTimer?.cancel();
  }
}

/// Navigation policy for WebView
class NavigationPolicy {
  static const int maxRedirects = 5;
  static const Duration navigationTimeout = Duration(seconds: 30);

  /// Determine if navigation should be allowed
  static NavigationDecision shouldAllowNavigation(
    String url,
    String serverUrl, {
    bool isUserInitiated = false,
  }) {
    // Always allow server URL
    if (UrlValidator.isServerUrl(url, serverUrl)) {
      return NavigationDecision.navigate;
    }

    // Check if URL is in allowed list
    if (!UrlValidator.isUrlAllowed(url)) {
      return NavigationDecision.prevent;
    }

    // Allow user-initiated navigation to localhost
    if (isUserInitiated && UrlValidator.isUrlAllowed(url)) {
      return NavigationDecision.navigate;
    }

    // Prevent automatic redirects to external sites
    return NavigationDecision.prevent;
  }

  /// Get navigation decision message
  static String getNavigationMessage(NavigationDecision decision, String url) {
    switch (decision) {
      case NavigationDecision.navigate:
        return 'Navigating to $url';
      case NavigationDecision.prevent:
        return 'Navigation blocked: ${UrlValidator.getBlockedUrlMessage(url)}';
    }
  }
}

/// Navigation decision enum
enum NavigationDecision {
  navigate,
  prevent,
}