import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DiscoveryService {
  static const int defaultPort = 8080;

  static Future<String?> findServer({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final completer = Completer<String?>();
    Timer? timer;
    final client = http.Client();

    void finish(String? url) {
      if (!completer.isCompleted) {
        if (url != null) {
          debugPrint('[DiscoveryService] >>> SERVER FOUND: $url');
        } else {
          debugPrint('[DiscoveryService] >>> Server discovery ended without result.');
        }
        completer.complete(url);
      }
    }

    try {
      _scanLocalSubnet(client, completer, finish);

      timer = Timer(timeout, () {
        finish(null);
      });

      final result = await completer.future;
      return result;
    } catch (e, stack) {
      debugPrint('[DiscoveryService] Discovery error: $e\n$stack');
      return null;
    } finally {
      timer?.cancel();
      client.close();
    }
  }

  static Future<void> _scanLocalSubnet(
    http.Client client,
    Completer<String?> completer,
    void Function(String?) finish,
  ) async {
    try {
      final prefixes = <String>{};

      // Extract local network interface subnets
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
          includeLoopback: false,
        );

        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4 && parts[0] != '127') {
              prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
            }
          }
        }
      } catch (_) {}

      // Fallback common LAN subnets if none detected
      if (prefixes.isEmpty) {
        prefixes.addAll(['192.168.29.', '192.168.1.', '192.168.0.', '10.0.2.']);
      }

      debugPrint('[DiscoveryService] Subnet scanner scanning prefixes: $prefixes');

      final futures = <Future<void>>[];
      for (final prefix in prefixes) {
        for (int i = 1; i <= 254; i++) {
          if (completer.isCompleted) break;
          final host = '$prefix$i';
          futures.add(_probeHost(client, host, completer, finish));
        }
      }

      await Future.wait(futures);
    } catch (e) {
      debugPrint('[DiscoveryService] Subnet scan error: $e');
    }
  }

  static Future<void> _probeHost(
    http.Client client,
    String host,
    Completer<String?> completer,
    void Function(String?) finish,
  ) async {
    if (completer.isCompleted) return;
    try {
      final uri = Uri.parse('http://$host:$defaultPort/');
      final response = await client.get(uri).timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == 200 && !completer.isCompleted) {
        final body = response.body;
        if (body.contains('Movie Streaming Backend API') || body.contains('online')) {
          finish('http://$host:$defaultPort/api/v1');
        }
      }
    } catch (_) {}
  }
}
