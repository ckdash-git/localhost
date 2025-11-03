import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'services/server_manager.dart';
import 'services/error_handler.dart';
import 'services/session_manager.dart';
import 'widgets/server_webview.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Certificate Install Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ServerControlPage(),
    );
  }
}

class ServerControlPage extends StatefulWidget {
  const ServerControlPage({super.key});

  @override
  State<ServerControlPage> createState() => _ServerControlPageState();
}

class _ServerControlPageState extends State<ServerControlPage> {
  final ServerManager _serverManager = ServerManager();
  final ErrorHandler _errorHandler = ErrorHandler();
  final SessionManager _sessionManager = SessionManager();
  bool _isLoading = false;
  bool _showWebView = false;
  StreamSubscription<ServerStatus>? _statusSubscription;
  StreamSubscription<AppError>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _statusSubscription = _serverManager.statusStream.listen(_onStatusChanged);
    _errorSubscription = _errorHandler.errorStream.listen(_onErrorReceived);
    
    // Initialize session manager
    await _sessionManager.initialize();
    
    // Try to restore previous session
    await _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (_sessionManager.shouldRestoreSession()) {
      final restored = await _sessionManager.autoRestoreServerState(_serverManager);
      if (restored) {
        final session = _sessionManager.currentSession;
        if (session != null && session.wasWebViewVisible) {
          setState(() {
            _showWebView = true;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _errorSubscription?.cancel();
    _serverManager.dispose();
    super.dispose();
  }

  void _onStatusChanged(ServerStatus status) {
    setState(() {
      _isLoading = status == ServerStatus.starting || status == ServerStatus.stopping;
      // Update UI based on server status
      if (status == ServerStatus.running && !_showWebView) {
        // Automatically show WebView when server starts
        _showWebView = true;
      } else if (status == ServerStatus.stopped) {
        _showWebView = false;
      }
    });

    // Show status messages
    _showStatusMessage(status);
  }

  void _onErrorReceived(AppError error) {
    if (mounted) {
      ErrorHandler.showErrorDialog(context, error);
    }
  }

  void _showStatusMessage(ServerStatus status) {
    String message;
    Color backgroundColor;
    
    switch (status) {
      case ServerStatus.running:
        message = 'Server started successfully on ${_serverManager.url}';
        backgroundColor = Colors.green;
        break;
      case ServerStatus.stopped:
        message = 'Server stopped';
        backgroundColor = Colors.grey;
        break;
      case ServerStatus.error:
        message = 'Server error occurred';
        backgroundColor = Colors.red;
        break;
      default:
        return; // Don't show messages for starting/stopping states
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _startServer() async {
    await _serverManager.startServer();
    // Save session state when server starts
    await _sessionManager.saveSession(
      isServerRunning: _serverManager.status == ServerStatus.running,
      isWebViewVisible: _showWebView,
      currentUrl: _serverManager.url,
    );
  }

  Future<void> _stopServer() async {
    await _serverManager.stopServer();
    // Save session state when server stops
    await _sessionManager.saveSession(
      isServerRunning: _serverManager.status == ServerStatus.running,
      isWebViewVisible: _showWebView,
      currentUrl: _serverManager.url,
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startServer(); // Retry
              },
              child: const Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _installCertificate() async {
    try {
      final certUrl = '${_serverManager.url}/cert';
      
      // Use InAppBrowser to open the certificate download URL
      // This will trigger the native iOS download prompt
      await InAppBrowser.openWithSystemBrowser(
        url: WebUri(certUrl),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening certificate download...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening certificate: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleWebView() {
    setState(() {
      _showWebView = !_showWebView;
    });
    
    // Save session state when WebView visibility changes
    _sessionManager.saveSession(
      isServerRunning: _serverManager.status == ServerStatus.running,
      isWebViewVisible: _showWebView,
      currentUrl: _serverManager.url,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Server Control'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
           if (_serverManager.status == ServerStatus.running)
             IconButton(
               onPressed: _toggleWebView,
               icon: Icon(_showWebView ? Icons.web_asset_off : Icons.web),
               tooltip: _showWebView ? 'Hide WebView' : 'Show WebView',
             ),
         ],
      ),
      body: _showWebView && _serverManager.status == ServerStatus.running
          ? ServerWebViewContainer(
              serverUrl: _serverManager.url,
              showNavigationBar: false,
            )
          : _buildControlPanel(),
    );
  }

  Widget _buildControlPanel() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Server Status Card
          _buildServerStatusCard(),
          
          const SizedBox(height: 24),
          
          // Control Buttons
          _buildControlButtons(),
          
          const SizedBox(height: 24),
          
          // Server Information
          _buildServerInfoCard(),
          
          const Spacer(),
          
          // Instructions
          _buildInstructionsCard(),
        ],
      ),
    );
  }

  Widget _buildServerStatusCard() {
    return StreamBuilder<ServerStatus>(
      stream: _serverManager.statusStream,
      initialData: _serverManager.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ServerStatus.stopped;
        final color = _getStatusColor(status);
        final icon = _getStatusIcon(status);
        final text = _getStatusText(status);

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 48,
                  color: color,
                ),
                const SizedBox(height: 12),
                Text(
                  'Server Status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 16,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlButtons() {
    return StreamBuilder<ServerStatus>(
      stream: _serverManager.statusStream,
      initialData: _serverManager.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ServerStatus.stopped;
        final isLoading = status == ServerStatus.starting || status == ServerStatus.stopping;

        return Column(
          children: [
            // Run Server Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: (status == ServerStatus.stopped || status == ServerStatus.error) && !isLoading
                    ? _startServer
                    : null,
                icon: isLoading && status == ServerStatus.starting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  isLoading && status == ServerStatus.starting
                      ? 'Starting Server...'
                      : 'Run Server',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Stop Server Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: status == ServerStatus.running && !isLoading
                    ? _stopServer
                    : null,
                icon: isLoading && status == ServerStatus.stopping
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.stop),
                label: Text(
                  isLoading && status == ServerStatus.stopping
                      ? 'Stopping Server...'
                      : 'Stop Server',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Open WebView Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: status == ServerStatus.running
                    ? () {
                        setState(() {
                          _showWebView = true;
                        });
                      }
                    : null,
                icon: const Icon(Icons.web),
                label: const Text('Open in WebView'),
                style: OutlinedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Install Certificate Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: status == ServerStatus.running
                    ? _installCertificate
                    : null,
                icon: const Icon(Icons.security),
                label: const Text('Install Certificate'),
                style: OutlinedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildServerInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server Information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Port', _serverManager.port.toString()),
            _buildInfoRow('URL', _serverManager.url),
            _buildInfoRow('Type', 'HTTP Server (Shelf)'),
            _buildInfoRow('WebView', 'Safari WebView (WKWebView)'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      elevation: 2,
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Instructions',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Click "Run Server" to start the localhost server\n'
              '2. The server will start on port 3000\n'
              '3. Click "Open in WebView" to view the server in the app\n'
              '4. All navigation is restricted to localhost URLs\n'
              '5. Use "Stop Server" to properly shut down the server',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(ServerStatus status) {
    switch (status) {
      case ServerStatus.running:
        return Colors.green;
      case ServerStatus.starting:
      case ServerStatus.stopping:
        return Colors.orange;
      case ServerStatus.error:
        return Colors.red;
      case ServerStatus.stopped:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(ServerStatus status) {
    switch (status) {
      case ServerStatus.running:
        return Icons.check_circle;
      case ServerStatus.starting:
      case ServerStatus.stopping:
        return Icons.hourglass_empty;
      case ServerStatus.error:
        return Icons.error;
      case ServerStatus.stopped:
        return Icons.stop_circle;
    }
  }

  String _getStatusText(ServerStatus status) {
    switch (status) {
      case ServerStatus.running:
        return 'Server is running on ${_serverManager.url}';
      case ServerStatus.starting:
        return 'Starting server...';
      case ServerStatus.stopping:
        return 'Stopping server...';
      case ServerStatus.error:
        return 'Server encountered an error';
      case ServerStatus.stopped:
        return 'Server is stopped';
    }
  }
}
