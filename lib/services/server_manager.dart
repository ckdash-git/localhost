import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'error_handler.dart';
import 'package:path/path.dart' as path;

enum ServerStatus { stopped, starting, running, stopping, error }

class ServerManager {
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;
  ServerManager._internal();

  HttpServer? _server;
  ServerStatus _status = ServerStatus.stopped;
  final int _port = 3000;
  final String _host = 'localhost';
  Timer? _healthCheckTimer;
  final ErrorHandler _errorHandler = ErrorHandler();

  // Stream controllers for status updates
  final StreamController<ServerStatus> _statusController = StreamController<ServerStatus>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  // Getters
  ServerStatus get status => _status;
  int get port => _port;
  String get host => _host;
  String get url => 'http://$_host:$_port';
  Stream<ServerStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;

  // Start the server
  Future<bool> startServer() async {
    if (_status == ServerStatus.running || _status == ServerStatus.starting) {
      _log('Server is already running');
      return true;
    }

    try {
      _updateStatus(ServerStatus.starting);
      _log('Starting server on $url...');

      // Create a router for handling requests
      final router = Router();

      // Add a simple home route
      router.get('/', (Request request) {
        return Response.ok(_getHomePageHtml(), headers: {
          'Content-Type': 'text/html',
        });
      });

      // Add API endpoints
      router.get('/api/status', (Request request) {
        return Response.ok('{"status": "running", "timestamp": "${DateTime.now().toIso8601String()}"}', 
          headers: {'Content-Type': 'application/json'});
      });

      router.get('/api/hello', (Request request) {
        return Response.ok('{"message": "Hello from Flutter Server!", "timestamp": "${DateTime.now().toIso8601String()}"}', 
          headers: {'Content-Type': 'application/json'});
      });

      // Certificate download route
      router.get('/cert', (Request request) async {
        return await _serveCertificate();
      });

      // Create middleware pipeline
      final handler = Pipeline()
          .addMiddleware(logRequests())
          .addMiddleware(_corsMiddleware())
          .addHandler(router);

      // Start the server
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        _port,
      );

      _updateStatus(ServerStatus.running);
      _log('Server started successfully on $url');
      _startHealthCheck();
      
      print('Server running on ${_server!.address.host}:${_server!.port}');
      return true;

    } on SocketException catch (e, stackTrace) {
      if (e.osError?.errorCode == 48 || e.message.contains('Address already in use')) {
        _errorHandler.handlePortInUseError(_port, details: e.message, stackTrace: stackTrace);
      } else {
        _errorHandler.handleServerStartupError('Socket error: ${e.message}', details: e.toString(), stackTrace: stackTrace);
      }
      _updateStatus(ServerStatus.error);
      print('Server start error: $e');
      return false;
    } catch (e, stackTrace) {
      _errorHandler.handleServerStartupError('Failed to start server: $e', details: e.toString(), stackTrace: stackTrace);
      _updateStatus(ServerStatus.error);
      print('Server start error: $e');
      return false;
    }
  }

  // Stop the server
  Future<bool> stopServer() async {
    if (_status == ServerStatus.stopped || _status == ServerStatus.stopping) {
      return true;
    }

    try {
      _updateStatus(ServerStatus.stopping);
      _log('Stopping server...');
      _stopHealthCheck();

      if (_server != null) {
        await _server!.close(force: true);
        _server = null;
      }

      _updateStatus(ServerStatus.stopped);
      _log('Server stopped successfully');
      print('Server stopped successfully');
      return true;

    } catch (e, stackTrace) {
       _errorHandler.handleServerStartupError('Failed to stop server: $e', details: e.toString(), stackTrace: stackTrace);
       _updateStatus(ServerStatus.error);
       return false;
     }
  }

  // Restart the server
  Future<bool> restartServer() async {
    await stopServer();
    await Future.delayed(const Duration(milliseconds: 500));
    return await startServer();
  }

  // Check if server is healthy
  Future<bool> isServerHealthy() async {
    if (_server == null || _status != ServerStatus.running) {
      return false;
    }

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('$url/api/status'));
      request.headers.set('Connection', 'close');
      final response = await request.close();
      client.close();
      
      return response.statusCode == 200;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }

  // Private methods
  void _updateStatus(ServerStatus newStatus) {
    _status = newStatus;
    _statusController.add(_status);
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_status == ServerStatus.running) {
        final isHealthy = await isServerHealthy();
        if (!isHealthy) {
           _errorHandler.handleServerConnectionError('Server health check failed');
           _updateStatus(ServerStatus.error);
           timer.cancel();
         }
      }
    });
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final response = await handler(request);
        
        return response.change(headers: {
          ...response.headers,
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        });
      };
    };
  }

  String _getHomePageHtml() {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flutter Local Server</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        h1 {
            text-align: center;
            margin-bottom: 30px;
            font-size: 2.5em;
        }
        .status {
            background: rgba(255, 255, 255, 0.2);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .api-endpoints {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .endpoint {
            background: rgba(255, 255, 255, 0.1);
            padding: 10px;
            margin: 10px 0;
            border-radius: 5px;
            font-family: monospace;
        }
        .timestamp {
            font-size: 0.9em;
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Flutter Local Server</h1>
        
        <div class="status">
            <h2>Server Status</h2>
            <p><strong>Status:</strong> Running ✅</p>
            <p><strong>Port:</strong> $_port</p>
            <p><strong>Started:</strong> <span class="timestamp">${DateTime.now().toString()}</span></p>
        </div>

        <div class="api-endpoints">
            <h2>Available Endpoints</h2>
            <div class="endpoint">
                <strong>GET /</strong> - This home page
            </div>
            <div class="endpoint">
                <strong>GET /api/status</strong> - Server status JSON
            </div>
            <div class="endpoint">
                <strong>GET /api/hello</strong> - Hello message JSON
            </div>
        </div>

        <p style="text-align: center; margin-top: 30px;">
            <em>This server is running from your Flutter application!</em>
        </p>
    </div>

    <script>
        // Auto-refresh status every 30 seconds
        setTimeout(() => {
            location.reload();
        }, 30000);
    </script>
</body>
</html>
    ''';
  }

  // Serve certificate file for iOS download
  Future<Response> _serveCertificate() async {
    try {
      // Load certificate from assets
      final ByteData data = await rootBundle.load('assets/certificates/c1-ca.crt');
      final Uint8List bytes = data.buffer.asUint8List();
      
      return Response.ok(
        bytes,
        headers: {
          'Content-Type': 'application/x-x509-ca-cert',
          'Content-Disposition': 'attachment; filename="localhost.crt"',
          'Cache-Control': 'no-cache',
        },
      );
    } catch (e) {
      _log('Error serving certificate: $e');
      return Response.internalServerError(
        body: 'Error loading certificate file',
      );
    }
  }

  // Add logging method
  void _log(String message) {
    _logController.add(message);
    print(message);
  }

  // Cleanup resources
  void dispose() {
    _stopHealthCheck();
    _statusController.close();
    _logController.close();
    stopServer();
  }
}