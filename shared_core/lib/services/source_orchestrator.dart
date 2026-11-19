import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';
import '../models/stream_progress_event.dart';
import '../models/stream_source.dart';
import 'settings_service.dart';
import 'stream_priority.dart';
import 'stream_ranker.dart';

class MediaScrapeTarget {
  final String imdbId;
  final String title;
  final String mediaType;
  final int? season;
  final int? episode;
  final int? year;
  final String? originalLanguage;
  final String? defaultLanguage;
  final List<String> genres;

  const MediaScrapeTarget({
    required this.imdbId,
    required this.title,
    this.mediaType = 'movie',
    this.season,
    this.episode,
    this.year,
    this.originalLanguage,
    this.defaultLanguage,
    this.genres = const [],
  });

  String get searchTitle {
    if (mediaType == 'tv') {
      final clean = title
          .replaceAll(RegExp(r'\s+S\d+E\d+.*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+Season\s*\d+.*$', caseSensitive: false), '')
          .trim();
      return clean.isNotEmpty ? clean : title;
    }
    return title;
  }

  Map<String, dynamic> toJson() => {
    'imdbId': imdbId,
    'title': searchTitle,
    'displayTitle': title,
    'mediaType': mediaType,
    'season': season ?? 1,
    'episode': episode ?? 1,
    'year': year,
    'originalLanguage': originalLanguage,
    'defaultLanguage': defaultLanguage,
    'genres': genres,
  };
}

class BatchPlan {
  final int batchNumber;
  final List<Map<String, dynamic>> stremioAddons;
  final List<Map<String, dynamic>> jsExtractors;

  const BatchPlan({
    required this.batchNumber,
    required this.stremioAddons,
    required this.jsExtractors,
  });

  bool get isEmpty => stremioAddons.isEmpty && jsExtractors.isEmpty;
}

class BatchScrapeResult {
  final int batchNumber;
  final int totalBatches;
  final List<StreamSource> streams;
  final bool hasQualifiedStreams;
  final bool hasMoreBatches;

  const BatchScrapeResult({
    required this.batchNumber,
    required this.totalBatches,
    required this.streams,
    this.hasQualifiedStreams = false,
    required this.hasMoreBatches,
  });
}

class SourceOrchestrator {
  final Map<String, dynamic> config;
  final String routerCode;
  final Map<String, String> scriptRegistry;
  final http.Client _httpClient;

  static final Map<String, String> _globalScriptRegistry = {};

  static void clearMemoryCache() {
    _globalScriptRegistry.clear();
  }

  static Future<Map<String, dynamic>> applyOverridesToConfig(
    Map<String, dynamic> rawConfig,
  ) async {
    final overrides = await AppSettingsService.instance.getSourceOverrides();
    if (overrides.isEmpty) return rawConfig;

    final config = json.decode(json.encode(rawConfig)) as Map<String, dynamic>;

    void patchList(String key) {
      if (config[key] is List) {
        final list = (config[key] as List).cast<Map<String, dynamic>>();
        for (final item in list) {
          final id = item['id']?.toString();
          if (id != null && overrides.containsKey(id)) {
            final ov = overrides[id];
            if (ov is Map) {
              if (ov.containsKey('enabled')) item['enabled'] = ov['enabled'];
              if (ov.containsKey('custom_url')) {
                final customUrl = ov['custom_url']?.toString();
                if (customUrl != null && customUrl.isNotEmpty) {
                  if (item.containsKey('script_url')) item['script_url'] = customUrl;
                  if (item.containsKey('manifest_url')) item['manifest_url'] = customUrl;
                }
              }
            }
          }
        }
      }
    }

    patchList('stremio_addons');
    patchList('js_extractors');
    return config;
  }

  static Future<({bool success, int sourceCount, String message})> syncRemoteRepo({
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? ApiClient.instance.httpClient;
    final repoUrl = await AppSettingsService.instance.getScraperRepoUrl();
    try {
      final futures = await Future.wait([
        client.get(Uri.parse('$repoUrl/sources.json')).timeout(const Duration(seconds: 6)),
        client.get(Uri.parse('$repoUrl/router.js')).timeout(const Duration(seconds: 6)),
      ]);
      final sourcesRes = futures[0];
      final routerRes = futures[1];

      if (sourcesRes.statusCode != 200 || sourcesRes.body.trim().isEmpty) {
        return (
          success: false,
          sourceCount: 0,
          message: 'Failed to fetch sources.json (HTTP ${sourcesRes.statusCode})'
        );
      }
      final decoded = json.decode(sourcesRes.body) as Map<String, dynamic>?;
      if (decoded == null || decoded.isEmpty) {
        return (success: false, sourceCount: 0, message: 'Invalid sources.json response format');
      }

      await AppSettingsService.instance.cacheSourcesJson(sourcesRes.body);

      if (routerRes.statusCode == 200 && routerRes.body.trim().isNotEmpty) {
        await AppSettingsService.instance.cacheRouterJs(routerRes.body);
      }

      final addons = (decoded['stremio_addons'] as List?)?.length ?? 0;
      final extractors = (decoded['js_extractors'] as List?)?.length ?? 0;
      final total = addons + extractors;

      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} (${now.day}/${now.month})';
      await AppSettingsService.instance.setLastRepoSyncTime(timeStr);
      clearMemoryCache();

      return (
        success: true,
        sourceCount: total,
        message: 'Synced $total extensions ($extractors scrapers, $addons addons) successfully.',
      );
    } catch (e) {
      return (success: false, sourceCount: 0, message: 'Sync error: $e');
    }
  }

  static Future<SourceOrchestrator> createRemoteOrchestrator({
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? ApiClient.instance.httpClient;
    final repoUrl = await AppSettingsService.instance.getScraperRepoUrl();

    Map<String, dynamic>? config = await AppSettingsService.instance.getCachedSourcesJson();
    String? routerCode = await AppSettingsService.instance.getCachedRouterJs();

    try {
      final futures = await Future.wait([
        client.get(Uri.parse('$repoUrl/sources.json')).timeout(const Duration(seconds: 4)),
        client.get(Uri.parse('$repoUrl/router.js')).timeout(const Duration(seconds: 4)),
      ]);
      final sourcesRes = futures[0];
      final routerRes = futures[1];

      if (sourcesRes.statusCode == 200 && sourcesRes.body.trim().isNotEmpty) {
        final decoded = json.decode(sourcesRes.body) as Map<String, dynamic>?;
        if (decoded != null && decoded.isNotEmpty) {
          config = decoded;
          await AppSettingsService.instance.cacheSourcesJson(sourcesRes.body);
        }
      }

      if (routerRes.statusCode == 200 && routerRes.body.trim().isNotEmpty) {
        routerCode = routerRes.body;
        await AppSettingsService.instance.cacheRouterJs(routerRes.body);
      }
    } catch (_) {}

    final patchedConfig = await applyOverridesToConfig(config ?? defaultSourcesConfig);

    return SourceOrchestrator(
      config: patchedConfig,
      routerCode: routerCode,
      scriptRegistry: _globalScriptRegistry,
      httpClient: client,
    );
  }

  SourceOrchestrator({
    Map<String, dynamic>? config,
    String? routerCode,
    Map<String, String>? scriptRegistry,
    http.Client? httpClient,
  })  : config = config ?? defaultSourcesConfig,
        routerCode = routerCode ?? defaultRouterCode,
        scriptRegistry = scriptRegistry ?? _globalScriptRegistry,
        _httpClient = httpClient ?? ApiClient.instance.httpClient;

  static const String defaultRouterCode = r'''
function routeMedia(media, config) {
  var addons = (config && config.stremio_addons) || [];
  var extractors = (config && config.js_extractors) || [];
  return [{
    batchNumber: 1,
    stremio_addons: addons.filter(function(s) { return s && s.enabled !== false; }),
    js_extractors: extractors.filter(function(s) { return s && s.enabled !== false; })
  }];
}
''';

  static const String ezmvPreambleJs = r'''
var _b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
if (typeof btoa === 'undefined') {
  globalThis.btoa = function(input) {
    var str = String(input);
    var output = '';
    for (var block = 0, charCode, i = 0, map = _b64chars;
        str.charAt(i | 0) || (map = '=', i % 1);
        output += map.charAt(63 & block >> 8 - i % 1 * 8)) {
      charCode = str.charCodeAt(i += 3/4);
      if (charCode > 0xFF) throw new Error("'btoa' failed");
      block = block << 8 | charCode;
    }
    return output;
  };
}
if (typeof atob === 'undefined') {
  globalThis.atob = function(input) {
    var str = String(input).replace(/=+$/, '');
    if (str.length % 4 === 1) throw new Error("'atob' failed");
    var output = '';
    for (var bc = 0, bs, buffer, i = 0;
        buffer = str.charAt(i++);
        ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,
          bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
      buffer = _b64chars.indexOf(buffer);
    }
    return output;
  };
}
if (typeof htmlText === 'undefined') {
  globalThis.htmlText = function(str) {
    if (!str) return '';
    return String(str)
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&nbsp;/g, ' ')
      .trim();
  };
}
if (typeof base64ToBytes === 'undefined') {
  globalThis.base64ToBytes = function(b64) {
    var bin = atob(String(b64 || ''));
    var bytes = [];
    for (var i = 0; i < bin.length; i++) bytes.push(bin.charCodeAt(i));
    return bytes;
  };
}
if (typeof bytesToBase64 === 'undefined') {
  globalThis.bytesToBase64 = function(bytes) {
    var bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin);
  };
}
if (typeof absUrl === 'undefined') {
  globalThis.absUrl = function(path, base) {
    if (!path) return '';
    if (/^https?:\/\//i.test(path)) return path;
    base = (base || '').replace(/\/+$/, '');
    path = String(path).replace(/^\/+/, '');
    return base + '/' + path;
  };
}
globalThis.__ezmv_req_id = 0;
globalThis.__ezmv_callbacks = {};
var _ezmvFormat = function(args) {
  var parts = [];
  for (var i = 0; i < args.length; i++) {
    var a = args[i];
    if (a === null) { parts.push('null'); }
    else if (a === undefined) { parts.push('undefined'); }
    else if (typeof a === 'object') {
      try { parts.push(JSON.stringify(a)); } catch (e) { parts.push(String(a)); }
    } else {
      parts.push(String(a));
    }
  }
  return parts.join(' ');
};
globalThis.console = {
  log: function() {
    sendMessage('ezmv_log', JSON.stringify({ level: 'INFO', msg: _ezmvFormat(arguments) }));
  },
  warn: function() {
    sendMessage('ezmv_log', JSON.stringify({ level: 'WARN', msg: _ezmvFormat(arguments) }));
  },
  error: function() {
    sendMessage('ezmv_log', JSON.stringify({ level: 'ERROR', msg: _ezmvFormat(arguments) }));
  },
  info: function() {
    sendMessage('ezmv_log', JSON.stringify({ level: 'INFO', msg: _ezmvFormat(arguments) }));
  }
};
globalThis.__ezmv_resolve = function(id, res) {
  if (globalThis.__ezmv_callbacks && globalThis.__ezmv_callbacks[id]) {
    res.text = function() { return Promise.resolve(res.body); };
    res.json = function() { return Promise.resolve(JSON.parse(res.body)); };
    globalThis.__ezmv_callbacks[id].resolve(res);
    delete globalThis.__ezmv_callbacks[id];
  }
};
globalThis.__ezmv_reject = function(id, err) {
  if (globalThis.__ezmv_callbacks && globalThis.__ezmv_callbacks[id]) {
    globalThis.__ezmv_callbacks[id].reject(new Error(err));
    delete globalThis.__ezmv_callbacks[id];
  }
};
globalThis.fetch = function(url, options) {
  options = options || {};
  return new Promise(function(resolve, reject) {
    var id = ++globalThis.__ezmv_req_id;
    globalThis.__ezmv_callbacks[id] = { resolve: resolve, reject: reject };
    sendMessage('ezmv_fetch', JSON.stringify({
      id: id,
      url: url,
      method: options.method || 'GET',
      headers: options.headers || {},
      body: options.body || null
    }));
  });
};
globalThis.fetch._ezmv = true;
globalThis.__ezmv_run_scrape = function(targetJsonStr) {
  return Promise.resolve()
    .then(function() {
      var target = (typeof targetJsonStr === 'string') ? JSON.parse(targetJsonStr) : targetJsonStr;
      return scrape(target);
    })
    .then(function(res) {
      return JSON.stringify(res || []);
    })
    .catch(function(err) {
      console.error('[EZMV_SCRAPE_ERROR]', (err && err.stack) || err);
      return JSON.stringify([]);
    });
};
''';

  static const Map<String, dynamic> defaultSourcesConfig = {
    'version': 1,
    'stremio_addons': [],
    'js_extractors': [],
  };

  List<BatchPlan> planBatches(MediaScrapeTarget target) {
    JavascriptRuntime? runtime;
    try {
      runtime = getJavascriptRuntime();
      runtime.evaluate(routerCode);
      final mediaJson = json.encode(target.toJson());
      final configJson = json.encode(config);
      final res = runtime.evaluate('JSON.stringify(routeMedia($mediaJson, $configJson))');
      if (res.isError) throw Exception(res.stringResult);
      final rawList = json.decode(res.stringResult) as List? ?? [];
      return rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final bNum = (map['batchNumber'] as num?)?.toInt() ?? 1;
        final addons = (map['stremio_addons'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final extractors = (map['js_extractors'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return BatchPlan(
          batchNumber: bNum,
          stremioAddons: addons,
          jsExtractors: extractors,
        );
      }).toList();
    } catch (_) {
      return _fallbackPlanBatches(target);
    } finally {
      runtime?.dispose();
    }
  }

  List<BatchPlan> _fallbackPlanBatches(MediaScrapeTarget target) {
    final addons = (config['stremio_addons'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) => _fallbackMatches(s, target));

    final extractors = (config['js_extractors'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) => _fallbackMatches(s, target));

    final batchMap = <int, BatchPlan>{};

    void addSource(Map<String, dynamic> s, bool isAddon) {
      final b = (s['batch'] ?? s['priority'] ?? 1) as int;
      final plan = batchMap.putIfAbsent(
        b,
        () => BatchPlan(batchNumber: b, stremioAddons: [], jsExtractors: []),
      );
      if (isAddon) {
        plan.stremioAddons.add(s);
      } else {
        plan.jsExtractors.add(s);
      }
    }

    for (final a in addons) {
      addSource(a, true);
    }
    for (final ex in extractors) {
      addSource(ex, false);
    }

    final sortedBatchNums = batchMap.keys.toList()..sort();
    return sortedBatchNums.map((n) {
      final plan = batchMap[n]!;
      plan.stremioAddons.sort((a, b) => ((a['priority'] ?? 10) as int).compareTo((b['priority'] ?? 10) as int));
      plan.jsExtractors.sort((a, b) => ((a['priority'] ?? 10) as int).compareTo((b['priority'] ?? 10) as int));
      return plan;
    }).toList();
  }

  static bool _fallbackMatches(Map<String, dynamic> source, MediaScrapeTarget target) {
    if (source['enabled'] == false) return false;
    final m = source['match'] as Map<String, dynamic>? ?? {};

    final isAnime = target.genres.any((g) {
      final s = g.toLowerCase();
      return s == 'anime' || s == 'animation';
    }) && (target.originalLanguage?.toLowerCase() == 'ja' ||
           target.genres.any((g) => g.toLowerCase() == 'anime') ||
           target.originalLanguage == null ||
           target.originalLanguage!.isEmpty);

    final mediaTypes = (m['media_types'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    if (mediaTypes != null && mediaTypes.isNotEmpty) {
      if (!mediaTypes.contains(target.mediaType.toLowerCase())) return false;
    }

    final genres = (m['genres'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    if (genres != null && genres.isNotEmpty) {
      final genreMatch = genres.any((mg) {
        if (mg == 'anime' && isAnime) return true;
        return target.genres.any((g) => g.toLowerCase() == mg);
      });
      if (!genreMatch) return false;
    }

    final origLangs = (m['original_languages'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    if (origLangs != null && origLangs.isNotEmpty) {
      final lang = target.originalLanguage?.toLowerCase();
      if (!isAnime && (lang == null || !origLangs.contains(lang))) return false;
    }

    return true;
  }

  Future<List<StreamSource>> _fetchStremioAddon(
    Map<String, dynamic> addon,
    MediaScrapeTarget target,
  ) async {
    final manifestUrl = addon['manifest_url'] as String? ?? '';
    final id = addon['id'] as String? ?? 'addon';
    if (manifestUrl.isEmpty) return [];

    final baseUrl = manifestUrl.replaceAll(RegExp(r'/manifest\.json/?$'), '');
    final streamPath = (target.mediaType == 'tv' && target.season != null && target.episode != null)
        ? '/stream/series/${target.imdbId}:${target.season}:${target.episode}.json'
        : '/stream/movie/${target.imdbId}.json';

    final uri = Uri.parse('$baseUrl$streamPath');
    try {
      final res = await _httpClient.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      final data = json.decode(res.body) as Map<String, dynamic>?;
      final rawStreams = data?['streams'] as List? ?? [];

      final prefAudio = await AppSettingsService.instance.getPreferredAudioLanguage();
      final prefQuality = await AppSettingsService.instance.getPreferredQuality();
      final prefSize = await AppSettingsService.instance.getFileSizePreference();
      final prioAudio = await AppSettingsService.instance.getPrioritizePreferredAudio();

      final out = <StreamSource>[];
      for (final raw in rawStreams) {
        if (raw is Map<String, dynamic>) {
          final s = StreamPriorityCalculator.parseStremioStream(
            raw,
            provider: id,
            defaultLanguage: target.defaultLanguage,
            originalLanguage: target.originalLanguage,
            preferredAudioLanguage: prefAudio,
            preferredQuality: prefQuality.name,
            fileSizeTarget: prefSize.name,
            prioritizeAudio: prioAudio,
          );
          if (s != null) out.add(s);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<StreamSource>> _runJsExtractor(
    Map<String, dynamic> extractor,
    MediaScrapeTarget target,
  ) async {
    if (io.Platform.environment.containsKey('FLUTTER_TEST') && !scriptRegistry.containsKey('test_enable_js')) {
      return [];
    }

    final scriptUrl = extractor['script_url'] as String? ?? '';
    var code = scriptRegistry[scriptUrl] ?? scriptRegistry[extractor['id']];
    if (code == null || code.trim().isEmpty) {
      final filename = scriptUrl.isNotEmpty ? scriptUrl : '${extractor['id']}.js';

      // 1. Persistent SharedPreferences cache
      final cached = await AppSettingsService.instance.getCachedScript(filename);
      if (cached != null && cached.trim().isNotEmpty) {
        code = cached;
      }

      // 2. Remote GitHub repository fetch
      if (code == null || code.trim().isEmpty) {
        final repoUrl = await AppSettingsService.instance.getScraperRepoUrl();
        try {
          final res = await _httpClient.get(
            Uri.parse('$repoUrl/$filename'),
            headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
          ).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
            code = res.body;
            await AppSettingsService.instance.cacheScript(filename, res.body);
          }
        } catch (_) {}
      }

      if (code != null && code.isNotEmpty) {
        scriptRegistry[scriptUrl] = code;
        scriptRegistry[extractor['id']] = code;
      }
    }
    if (code == null || code.trim().isEmpty) return [];

    final extractorId = extractor['id'] ?? 'js';
    JavascriptRuntime? runtime;
    try {
      runtime = getJavascriptRuntime(xhr: false);
      runtime.onMessage('ezmv_log', (dynamic rawArgs) {});
      runtime.onMessage('ezmv_fetch', (dynamic rawArgs) async {
        try {
          final args = rawArgs is String ? json.decode(rawArgs) : rawArgs;
          final id = args['id'];
          final url = args['url'] as String;
          final method = (args['method'] as String? ?? 'GET').toUpperCase();
          final headers = <String, String>{};
          if (args['headers'] is Map) {
            (args['headers'] as Map).forEach((k, v) => headers[k.toString()] = v.toString());
          }
          final body = args['body'];
          final req = http.Request(method, Uri.parse(url));
          headers.forEach((k, v) => req.headers[k] = v);
          if (body != null) req.body = body.toString();
          final streamed = await _httpClient.send(req);
          final resp = await http.Response.fromStream(streamed);
          final resData = json.encode({
            'status': resp.statusCode,
            'body': resp.body,
            'headers': resp.headers,
          });
          runtime?.evaluate('globalThis.__ezmv_resolve($id, $resData);');
        } catch (e) {
          try {
            final args = rawArgs is String ? json.decode(rawArgs) : rawArgs;
            final id = args['id'];
            runtime?.evaluate('globalThis.__ezmv_reject($id, ${json.encode(e.toString())});');
          } catch (_) {}
        }
      });
      runtime.evaluate(ezmvPreambleJs);
      final evalInit = runtime.evaluate(code);
      if (evalInit.isError) {
        return [];
      }

      final targetJson = json.encode(target.toJson());
      final evalResult = runtime.evaluate('globalThis.__ezmv_run_scrape(${json.encode(targetJson)})');
      if (evalResult.isError) {
        return [];
      }
      final resolved = await runtime.handlePromise(evalResult);
      if (resolved.isError) {
        return [];
      }

      final out = <StreamSource>[];
      List<dynamic> items = [];
      try {
        final decoded = json.decode(resolved.stringResult);
        if (decoded is List) {
          items = decoded;
        } else if (decoded is String) {
          final d2 = json.decode(decoded);
          if (d2 is List) items = d2;
        }
      } catch (e) {
        if (resolved.rawResult is List) {
          items = resolved.rawResult as List;
        }
      }
      final prefAudio = await AppSettingsService.instance.getPreferredAudioLanguage();
      final prefQuality = await AppSettingsService.instance.getPreferredQuality();
      final prefSize = await AppSettingsService.instance.getFileSizePreference();
      final prioAudio = await AppSettingsService.instance.getPrioritizePreferredAudio();

      for (final item in items) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final url = map['url']?.toString();
          if (url == null || !url.startsWith('http')) continue;

          final quality = map['quality']?.toString() ?? 'Auto';
          final headers = <String, String>{};
          if (map['headers'] is Map) {
            (map['headers'] as Map).forEach((k, v) => headers[k.toString()] = v.toString());
          }

          final languages = (map['languages'] is List)
              ? (map['languages'] as List).map((l) => l.toString()).toList()
              : <String>[];

          int? sizeBytes;
          if (map['sizeBytes'] is num) {
            sizeBytes = (map['sizeBytes'] as num).toInt();
          } else if (map['size'] is num) {
            sizeBytes = (map['size'] as num).toInt();
          } else {
            final rawSizeStr = map['size']?.toString() ?? map['title']?.toString() ?? map['name']?.toString();
            sizeBytes = StreamRanker.parseSizeBytes(rawSizeStr);
          }

          final priority = StreamPriorityCalculator.calculatePriority(
            provider: extractorId,
            quality: quality,
            languages: languages.isNotEmpty ? languages : null,
            defaultLanguage: target.defaultLanguage,
            originalLanguage: target.originalLanguage,
            preferredAudioLanguage: prefAudio,
            preferredQuality: prefQuality.name,
            fileSizeTarget: prefSize.name,
            prioritizeAudio: prioAudio,
            sizeBytes: sizeBytes,
          );

          out.add(StreamSource(
            url: url,
            quality: quality,
            provider: extractorId,
            headers: headers,
            priority: priority,
            languages: languages,
            sizeBytes: sizeBytes,
          ));
        }
      }
      return out;
    } catch (_) {
      return [];
    } finally {
      runtime?.dispose();
    }
  }

  Future<BatchScrapeResult> scrapeBatch({
    required MediaScrapeTarget target,
    required int batchNumber,
    void Function(String message)? onProgress,
    void Function(String provider, StreamProgressStatus status, int count)? onProviderStatus,
    void Function(ProbingStageEvent event)? onStageProgress,
  }) async {
    final plans = planBatches(target);
    final totalBatches = plans.isEmpty ? 1 : plans.length;
    final plan = plans.firstWhere(
      (p) => p.batchNumber == batchNumber,
      orElse: () => BatchPlan(batchNumber: batchNumber, stremioAddons: [], jsExtractors: []),
    );

    if (plan.isEmpty) {
      return BatchScrapeResult(
        batchNumber: batchNumber,
        totalBatches: totalBatches,
        streams: [],
        hasQualifiedStreams: false,
        hasMoreBatches: batchNumber < totalBatches,
      );
    }

    onProgress?.call('Querying Batch $batchNumber sources...');

    final futures = <Future<List<StreamSource>>>[];
    for (final addon in plan.stremioAddons) {
      final name = addon['name'] as String? ?? addon['id'] as String? ?? 'Stremio';
      onProviderStatus?.call(name, StreamProgressStatus.searching, 0);
      futures.add(_fetchStremioAddon(addon, target).then((res) {
        onProviderStatus?.call(name, StreamProgressStatus.resolved, res.length);
        return res;
      }).catchError((_) {
        onProviderStatus?.call(name, StreamProgressStatus.error, 0);
        return <StreamSource>[];
      }));
    }
    for (final extractor in plan.jsExtractors) {
      final name = extractor['name'] as String? ?? extractor['id'] as String? ?? 'JS Extractor';
      onProviderStatus?.call(name, StreamProgressStatus.searching, 0);
      futures.add(_runJsExtractor(extractor, target).then((res) {
        onProviderStatus?.call(name, StreamProgressStatus.resolved, res.length);
        return res;
      }).catchError((_) {
        onProviderStatus?.call(name, StreamProgressStatus.error, 0);
        return <StreamSource>[];
      }));
    }

    final results = await Future.wait(futures);
    final allCandidates = <StreamSource>[];
    for (final list in results) {
      allCandidates.addAll(list);
    }

    if (allCandidates.isEmpty) {
      return BatchScrapeResult(
        batchNumber: batchNumber,
        totalBatches: totalBatches,
        streams: [],
        hasQualifiedStreams: false,
        hasMoreBatches: batchNumber < totalBatches,
      );
    }

    // Sort all candidates by speed if known, then quality tier
    allCandidates.sort(StreamRanker.compareBySpeed);

    onProgress?.call('Ranking streams (${allCandidates.length} found)...');

    try {
      final ranked = await StreamRanker.rankStreams(
        allCandidates,
        maxProbes: 6,
        targetQualified: 3,
        batchSize: 2,
        client: _httpClient,
        onProgress: (msg, probed, qual) => onProgress?.call(msg),
        onStageProgress: onStageProgress,
      );

      final finalStreams = [
        ranked.topStream,
        ...ranked.fallbackStreams,
        ...ranked.unprobedStreams,
        ...ranked.failedStreams,
      ];

      return BatchScrapeResult(
        batchNumber: batchNumber,
        totalBatches: totalBatches,
        streams: finalStreams,
        hasQualifiedStreams: ranked.hasQualifiedStreams,
        hasMoreBatches: batchNumber < totalBatches,
      );
    } catch (_) {
      return BatchScrapeResult(
        batchNumber: batchNumber,
        totalBatches: totalBatches,
        streams: allCandidates,
        hasQualifiedStreams: false,
        hasMoreBatches: batchNumber < totalBatches,
      );
    }
  }

  Future<List<StreamSource>> scrapeWithBackendFallback({
    required MediaScrapeTarget target,
    void Function(String message)? onProgress,
    void Function(String provider, StreamProgressStatus status, int count)? onProviderStatus,
    void Function(ProbingStageEvent event)? onStageProgress,
    void Function(String reason)? onBackendFallback,
  }) async {
    final plans = planBatches(target);
    final totalBatches = plans.isEmpty ? 1 : plans.length;
    final List<StreamSource> allCollectedStreams = [];

    for (int b = 1; b <= totalBatches; b++) {
      onProgress?.call('Running batch $b of $totalBatches...');
      final batchResult = await scrapeBatch(
        target: target,
        batchNumber: b,
        onProgress: onProgress,
        onProviderStatus: onProviderStatus,
        onStageProgress: onStageProgress,
      );

      if (batchResult.streams.isNotEmpty) {
        allCollectedStreams.addAll(batchResult.streams);
        if (batchResult.hasQualifiedStreams) {
          return allCollectedStreams;
        }
      }
    }

    if (allCollectedStreams.isNotEmpty) {
      return allCollectedStreams;
    }

    final reason = totalBatches <= 1
        ? 'No streams found in batch'
        : 'No streams found across all $totalBatches batches';
    onBackendFallback?.call(reason);
    onProgress?.call('$reason. Falling back to backend scrapers...');
    try {
      final completer = Completer<List<StreamSource>>();
      final stream = ApiClient.instance.getStreamsProgressive(
        target.mediaType,
        target.imdbId,
        season: target.season,
        episode: target.episode,
        originalLanguage: target.originalLanguage,
        defaultLanguage: target.defaultLanguage,
      );

      stream.listen(
        (event) {
          if (event.isDone) {
            if (event.status == StreamProgressStatus.error) {
              if (!completer.isCompleted) completer.completeError(Exception(event.error ?? 'Failed to fetch streams'));
            } else {
              if (!completer.isCompleted) completer.complete(event.streams ?? []);
            }
            return;
          }
          if (event.status == StreamProgressStatus.error) {
            if (event.provider == 'all') {
              if (!completer.isCompleted) {
                completer.completeError(Exception(event.error ?? 'Failed to fetch streams'));
              }
            } else {
              onProviderStatus?.call(event.provider, StreamProgressStatus.error, 0);
            }
          } else if (event.status == StreamProgressStatus.searching) {
            onProgress?.call('${event.provider}: searching...');
            onProviderStatus?.call(event.provider, StreamProgressStatus.searching, 0);
          } else if (event.status == StreamProgressStatus.resolved) {
            onProgress?.call('${event.provider}: resolved (${event.count ?? 0})');
            onProviderStatus?.call(event.provider, StreamProgressStatus.resolved, event.count ?? 0);
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
      );

      final fallbackStreams = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => [],
      );

      if (fallbackStreams.isNotEmpty) {
        return fallbackStreams;
      }
    } catch (err) {
      if (allCollectedStreams.isEmpty) rethrow;
    }

    return allCollectedStreams;
  }
}
