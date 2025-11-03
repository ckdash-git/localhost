import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/server_manager.dart';
import '../services/session_manager.dart' as session;

class ServerWebView extends StatefulWidget {
  final String initialUrl;
  final VoidCallback? onLoadStart;
  final VoidCallback? onLoadFinish;
  final Function(String)? onLoadError;

  const ServerWebView({
    super.key,
    required this.initialUrl,
    this.onLoadStart,
    this.onLoadFinish,
    this.onLoadError,
  });

  @override
  State<ServerWebView> createState() => _ServerWebViewState();
}

class _ServerWebViewState extends State<ServerWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  final ServerManager _serverManager = ServerManager();

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading progress if needed
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
            widget.onLoadStart?.call();
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            widget.onLoadFinish?.call();
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Failed to load page: ${error.description}';
            });
            widget.onLoadError?.call(error.description);
          },
          onNavigationRequest: (NavigationRequest request) {
            // Use session manager's navigation policy
            final decision = session.NavigationPolicy.shouldAllowNavigation(
              request.url,
              widget.initialUrl,
              isUserInitiated: request.isMainFrame,
            );
            
            if (decision == session.NavigationDecision.navigate) {
              return NavigationDecision.navigate;
            } else {
              _showNavigationBlockedDialog(request.url);
              return NavigationDecision.prevent;
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterApp',
        onMessageReceived: (JavaScriptMessage message) {
          // Handle messages from JavaScript if needed
          _handleJavaScriptMessage(message.message);
        },
      );

    // Load the initial URL
    _loadUrl(widget.initialUrl);
  }

  bool _isAllowedUrl(String url) {
    // Only allow localhost URLs and specific schemes
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // Allow localhost URLs
    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      return true;
    }

    // Allow data URLs for inline content
    if (uri.scheme == 'data') {
      return true;
    }

    // Allow about:blank
    if (url == 'about:blank') {
      return true;
    }

    return false;
  }

  void _showNavigationBlockedDialog(String url) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Navigation Blocked'),
          content: Text(
            'Navigation to external URLs is not allowed.\n\nBlocked URL: $url\n\nOnly localhost URLs are permitted within this WebView.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _handleJavaScriptMessage(String message) {
    // Handle JavaScript messages from the web page
    print('JavaScript message received: $message');
    
    // You can add custom handling here based on the message content
    try {
      // Example: Handle JSON messages
      // final data = jsonDecode(message);
      // Handle different message types...
    } catch (e) {
      print('Error parsing JavaScript message: $e');
    }
  }

  Future<void> _loadUrl(String url) async {
    try {
      await _controller.loadRequest(Uri.parse(url));
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load URL: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> reload() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _controller.reload();
  }

  Future<void> goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  Future<void> goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
  }

  Future<void> loadUrl(String url) async {
    if (_isAllowedUrl(url)) {
      await _loadUrl(url);
    } else {
      _showNavigationBlockedDialog(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // WebView
        if (_errorMessage == null)
          WebViewWidget(controller: _controller)
        else
          _buildErrorWidget(),

        // Loading indicator
        if (_isLoading)
          Container(
            color: Colors.white.withOpacity(0.8),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Navigation controls (optional)
        Positioned(
          bottom: 16,
          right: 16,
          child: _buildNavigationControls(),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to Load Page',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    // Check if server is running and restart if needed
                    if (_serverManager.status != ServerStatus.running) {
                      await _serverManager.startServer();
                    }
                    await reload();
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Server'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationControls() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: goBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Go Back',
          ),
          IconButton(
            onPressed: goForward,
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
            tooltip: 'Go Forward',
          ),
          IconButton(
            onPressed: reload,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Reload',
          ),
        ],
      ),
    );
  }
}

// WebView Container Widget with additional features
class ServerWebViewContainer extends StatefulWidget {
  final String serverUrl;
  final bool showNavigationBar;
  final bool showStatusBar;

  const ServerWebViewContainer({
    super.key,
    required this.serverUrl,
    this.showNavigationBar = true,
    this.showStatusBar = true,
  });

  @override
  State<ServerWebViewContainer> createState() => _ServerWebViewContainerState();
}

class _ServerWebViewContainerState extends State<ServerWebViewContainer> {
  final ServerManager _serverManager = ServerManager();
  bool _isWebViewLoading = false;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.serverUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showNavigationBar
          ? AppBar(
              title: const Text('Local Server'),
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              actions: [
                IconButton(
                  onPressed: () {
                    // Show server info dialog
                    _showServerInfoDialog();
                  },
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Server Info',
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          // Status bar
          if (widget.showStatusBar) _buildStatusBar(),
          
          // WebView
          Expanded(
            child: ServerWebView(
              initialUrl: _currentUrl!,
              onLoadStart: () {
                setState(() {
                  _isWebViewLoading = true;
                });
              },
              onLoadFinish: () {
                setState(() {
                  _isWebViewLoading = false;
                });
              },
              onLoadError: (error) {
                setState(() {
                  _isWebViewLoading = false;
                });
                _showErrorSnackBar(error);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return StreamBuilder<ServerStatus>(
      stream: _serverManager.statusStream,
      initialData: _serverManager.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ServerStatus.stopped;
        final color = _getStatusColor(status);
        final text = _getStatusText(status);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: color.withOpacity(0.1),
          child: Row(
            children: [
              Icon(
                _getStatusIcon(status),
                color: color,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (_isWebViewLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        );
      },
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

  String _getStatusText(ServerStatus status) {
    switch (status) {
      case ServerStatus.running:
        return 'Server Running • ${_serverManager.url}';
      case ServerStatus.starting:
        return 'Starting Server...';
      case ServerStatus.stopping:
        return 'Stopping Server...';
      case ServerStatus.error:
        return 'Server Error';
      case ServerStatus.stopped:
        return 'Server Stopped';
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

  void _showServerInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Server Information'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Status', _getStatusText(_serverManager.status)),
              _buildInfoRow('URL', _serverManager.url),
              _buildInfoRow('Port', _serverManager.port.toString()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('WebView Error: $error'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            // Retry loading
            setState(() {
              _currentUrl = widget.serverUrl;
            });
          },
        ),
      ),
    );
  }
}