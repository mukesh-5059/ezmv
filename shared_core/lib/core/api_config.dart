import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'discovery_service.dart';
import 'cache_manager.dart';
import 'tmdb_network_client.dart';

enum CatalogSourceMode {
  cdn,    // Self-Serving / Serverless via GitHub Pages CDN (Default)
  server, // Dedicated Self-Hosted FastAPI Backend Server
}

class ApiConfig {
  static const String defaultBaseUrl = 'http://192.168.29.195:8080/api/v1';
  static String _currentBaseUrl = defaultBaseUrl;

  static const String defaultCdnBaseUrl = 'https://mukesh-5059.github.io/ezmv/catalog';
  static String _currentCdnBaseUrl = defaultCdnBaseUrl;

  static CatalogSourceMode _catalogSourceMode = CatalogSourceMode.cdn;
  static String _tmdbApiKey = '';
  static String _traktClientId = '';

  static String get baseUrl => _currentBaseUrl;
  static String get cdnBaseUrl => _currentCdnBaseUrl;
  static CatalogSourceMode get catalogSourceMode => _catalogSourceMode;
  static bool get isServerlessMode => _catalogSourceMode == CatalogSourceMode.cdn;
  static String get tmdbApiKey => _tmdbApiKey;
  static String get traktClientId => _traktClientId;
  static bool get hasTmdbKey => _tmdbApiKey.trim().isNotEmpty;
  static bool get hasTraktKey => _traktClientId.trim().isNotEmpty;

  static Future<bool> testConnection([String? url]) async {
    final target = url ?? _currentBaseUrl;
    try {
      final rootUri = Uri.parse(target.replaceAll(RegExp(r'/api/v1/?$'), ''));
      final response = await http.get(rootUri).timeout(const Duration(milliseconds: 1500));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> autoDiscoverAndConnect() async {
    final discoveredUrl = await DiscoveryService.findServer();
    if (discoveredUrl != null && discoveredUrl.isNotEmpty) {
      await setBaseUrl(discoveredUrl);
      return true;
    }
    return false;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('backend_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _currentBaseUrl = savedUrl;
    } else {
      _currentBaseUrl = defaultBaseUrl;
    }

    final savedMode = prefs.getString('catalog_source_mode');
    if (savedMode == 'server') {
      _catalogSourceMode = CatalogSourceMode.server;
    } else {
      _catalogSourceMode = CatalogSourceMode.cdn;
    }

    _tmdbApiKey = prefs.getString('tmdb_api_key') ?? '';
    _traktClientId = prefs.getString('trakt_client_id') ?? '';

    if (_catalogSourceMode == CatalogSourceMode.server) {
      final isReachable = await testConnection();
      if (!isReachable) {
        await autoDiscoverAndConnect();
      }
    } else {
      CacheManager.cleanExpired();
    }
  }

  static String formatInputToUrl(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return defaultBaseUrl;

    if (!trimmed.startsWith(RegExp(r'^https?://'))) {
      trimmed = 'http://$trimmed';
    }

    if (!trimmed.endsWith('/api/v1') && !trimmed.endsWith('/api/v1/')) {
      if (trimmed.endsWith('/')) {
        trimmed = trimmed.substring(0, trimmed.length - 1);
      }
      trimmed = '$trimmed/api/v1';
    }

    return trimmed;
  }

  static String get displayBaseUrl {
    var display = _currentBaseUrl;
    if (display.startsWith('http://')) {
      display = display.substring(7);
    }
    if (display.endsWith('/api/v1')) {
      display = display.substring(0, display.length - 7);
    } else if (display.endsWith('/api/v1/')) {
      display = display.substring(0, display.length - 8);
    }
    return display;
  }

  static Future<void> setBaseUrl(String input) async {
    final formattedUrl = formatInputToUrl(input);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', formattedUrl);
    _currentBaseUrl = formattedUrl;
  }

  static Future<void> setCatalogSourceMode(CatalogSourceMode mode) async {
    _catalogSourceMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('catalog_source_mode', mode == CatalogSourceMode.server ? 'server' : 'cdn');
    if (mode == CatalogSourceMode.cdn) {
      CacheManager.cleanExpired();
    }
  }

  static Future<void> setServerlessMode(bool enabled) async {
    await setCatalogSourceMode(enabled ? CatalogSourceMode.cdn : CatalogSourceMode.server);
  }

  static Future<void> toggleCatalogSource() async {
    final newMode = _catalogSourceMode == CatalogSourceMode.cdn
        ? CatalogSourceMode.server
        : CatalogSourceMode.cdn;
    await setCatalogSourceMode(newMode);
  }

  static Future<void> setCdnBaseUrl(String url) async {
    _currentCdnBaseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cdn_base_url', _currentCdnBaseUrl);
  }

  static Future<void> setTmdbApiKey(String key) async {
    _tmdbApiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tmdb_api_key', _tmdbApiKey);
  }

  static Future<void> setTraktClientId(String id) async {
    _traktClientId = id.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trakt_client_id', _traktClientId);
  }

  static Future<bool> verifyTmdbKey(String key) async {
    final cleanKey = key.trim();
    if (cleanKey.isEmpty) return false;

    final params = <String, String>{};
    final headers = <String, String>{
      'accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    };

    if (cleanKey.startsWith('eyJ') || cleanKey.length > 50) {
      headers['Authorization'] = 'Bearer $cleanKey';
    } else {
      params['api_key'] = cleanKey;
    }

    final query = params.isNotEmpty ? Uri(queryParameters: params).query : '';
    final fullPath = query.isNotEmpty ? '/3/authentication?$query' : '/3/authentication';

    const hosts = ['api.themoviedb.org', 'api.tmdb.org'];
    for (final host in hosts) {
      final response = await TmdbNetworkClient.tmdbSecureSocketGet(host, fullPath, headers);
      if (response != null) {
        return response.statusCode == 200;
      }
      try {
        final uri = Uri.https(host, '/3/authentication', params.isNotEmpty ? params : null);
        final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 5));
        return resp.statusCode == 200;
      } catch (_) {}
    }
    return false;
  }

  static Future<bool> verifyTraktClientId(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;
    try {
      final url = Uri.parse('https://api.trakt.tv/movies/trending?limit=1');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'trakt-api-version': '2',
        'trakt-api-key': cleanId,
      }).timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
