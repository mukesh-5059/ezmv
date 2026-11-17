import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../storage/storage_service.dart';

enum StreamQualityPreference {
  auto('Auto (Default)'),
  fhd('1080p Full HD'),
  uhd('4K Ultra HD'),
  hd('720p HD');

  final String label;
  const StreamQualityPreference(this.label);

  static StreamQualityPreference fromString(String? val) {
    return StreamQualityPreference.values.firstWhere(
      (e) => e.name == val,
      orElse: () => StreamQualityPreference.auto,
    );
  }
}

enum FileSizePreference {
  balanced('Balanced (1 - 4 GB)'),
  dataSaver('Data Saver (< 1.5 GB)'),
  highQuality('High Bitrate (> 4 GB)');

  final String label;
  const FileSizePreference(this.label);

  static FileSizePreference fromString(String? val) {
    return FileSizePreference.values.firstWhere(
      (e) => e.name == val,
      orElse: () => FileSizePreference.balanced,
    );
  }
}

class AppSettingsService {
  static final AppSettingsService instance = AppSettingsService();

  static const String _prefAudioLangKey = 'settings_pref_audio_lang';
  static const String _prefSubtitleLangKey = 'settings_pref_sub_lang';
  static const String _prefQualityKey = 'settings_pref_quality';
  static const String _prefFileSizeKey = 'settings_pref_file_size';
  static const String _prefPrioritizeAudioKey = 'settings_prioritize_audio';
  static const String _customScraperRepoKey = 'settings_scraper_repo';
  static const String _prefSourceOverridesKey = 'settings_source_overrides';
  static const String _lastRepoSyncKey = 'settings_last_repo_sync';

  static const String defaultRepoUrl = 'https://raw.githubusercontent.com/mukesh-5059/ezmvSources/main';

  static const List<String> availableAudioLanguages = [
    'Tamil',
    'English',
    'Hindi',
    'Telugu',
    'Malayalam',
    'Kannada',
    'Japanese',
    'Korean',
  ];

  static const List<String> availableSubtitleLanguages = [
    'English',
    'Tamil',
    'Hindi',
    'Telugu',
    'Malayalam',
    'Off',
  ];

  final SharedPreferences? _prefs;

  AppSettingsService([this._prefs]);

  Future<SharedPreferences> get _instance async =>
      _prefs ?? await SharedPreferences.getInstance();

  // --- AUDIO & SUBTITLE LANGUAGES ---

  Future<String> getPreferredAudioLanguage() async {
    final prefs = await _instance;
    return prefs.getString(_prefAudioLangKey) ?? 'Tamil';
  }

  Future<void> setPreferredAudioLanguage(String lang) async {
    final prefs = await _instance;
    await prefs.setString(_prefAudioLangKey, lang);
  }

  Future<String> getPreferredSubtitleLanguage() async {
    final prefs = await _instance;
    return prefs.getString(_prefSubtitleLangKey) ?? 'English';
  }

  Future<void> setPreferredSubtitleLanguage(String lang) async {
    final prefs = await _instance;
    await prefs.setString(_prefSubtitleLangKey, lang);
  }

  // --- STREAM RANKING PREFERENCES ---

  Future<StreamQualityPreference> getPreferredQuality() async {
    final prefs = await _instance;
    final val = prefs.getString(_prefQualityKey);
    return StreamQualityPreference.fromString(val);
  }

  Future<void> setPreferredQuality(StreamQualityPreference pref) async {
    final prefs = await _instance;
    await prefs.setString(_prefQualityKey, pref.name);
  }

  Future<FileSizePreference> getFileSizePreference() async {
    final prefs = await _instance;
    final val = prefs.getString(_prefFileSizeKey);
    return FileSizePreference.fromString(val);
  }

  Future<void> setFileSizePreference(FileSizePreference pref) async {
    final prefs = await _instance;
    await prefs.setString(_prefFileSizeKey, pref.name);
  }

  Future<bool> getPrioritizePreferredAudio() async {
    final prefs = await _instance;
    return prefs.getBool(_prefPrioritizeAudioKey) ?? true;
  }

  Future<void> setPrioritizePreferredAudio(bool val) async {
    final prefs = await _instance;
    await prefs.setBool(_prefPrioritizeAudioKey, val);
  }

  // --- REPO SOURCE URL ---

  Future<String> getScraperRepoUrl() async {
    final prefs = await _instance;
    return prefs.getString(_customScraperRepoKey) ?? defaultRepoUrl;
  }

  Future<void> setScraperRepoUrl(String url) async {
    final prefs = await _instance;
    await prefs.setString(_customScraperRepoKey, url);
  }

  Future<void> resetScraperRepoUrl() async {
    final prefs = await _instance;
    await prefs.remove(_customScraperRepoKey);
  }

  // --- SOURCE OVERRIDES & CONFIGS ---

  Future<Map<String, dynamic>> getSourceOverrides() async {
    final prefs = await _instance;
    final str = prefs.getString(_prefSourceOverridesKey);
    if (str == null || str.trim().isEmpty) return {};
    try {
      return json.decode(str) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> setSourceOverride({
    required String sourceId,
    bool? enabled,
    String? customUrl,
  }) async {
    final prefs = await _instance;
    final all = await getSourceOverrides();
    final existing = (all[sourceId] is Map)
        ? Map<String, dynamic>.from(all[sourceId] as Map)
        : <String, dynamic>{};
    if (enabled != null) existing['enabled'] = enabled;
    if (customUrl != null) existing['custom_url'] = customUrl;
    all[sourceId] = existing;
    await prefs.setString(_prefSourceOverridesKey, json.encode(all));
  }

  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    await setSourceOverride(sourceId: sourceId, enabled: enabled);
  }

  Future<void> resetSourceOverrides() async {
    final prefs = await _instance;
    await prefs.remove(_prefSourceOverridesKey);
  }

  Future<String?> getLastRepoSyncTime() async {
    final prefs = await _instance;
    return prefs.getString(_lastRepoSyncKey);
  }

  Future<void> setLastRepoSyncTime(String time) async {
    final prefs = await _instance;
    await prefs.setString(_lastRepoSyncKey, time);
  }

  Future<List<Map<String, dynamic>>> getInstalledSources({
    Map<String, dynamic>? fallbackConfig,
  }) async {
    final cached = await getCachedSourcesJson() ?? fallbackConfig ?? {};
    final overrides = await getSourceOverrides();

    final List<Map<String, dynamic>> results = [];

    final addons = (cached['stremio_addons'] as List?) ?? [];
    for (final item in addons) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString() ?? '';
        final ov = overrides[id];
        if (ov is Map) {
          if (ov.containsKey('enabled')) map['enabled'] = ov['enabled'];
          if (ov.containsKey('custom_url')) map['custom_url'] = ov['custom_url'];
        }
        map['source_type'] = 'addon';
        results.add(map);
      }
    }

    final extractors = (cached['js_extractors'] as List?) ?? [];
    for (final item in extractors) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString() ?? '';
        final ov = overrides[id];
        if (ov is Map) {
          if (ov.containsKey('enabled')) map['enabled'] = ov['enabled'];
          if (ov.containsKey('custom_url')) map['custom_url'] = ov['custom_url'];
        }
        map['source_type'] = 'extractor';
        results.add(map);
      }
    }

    return results;
  }

  // --- CACHE & DATA CLEARING ---

  Future<String?> getCachedScript(String filename) async {
    final prefs = await _instance;
    return prefs.getString('cache_script_$filename');
  }

  Future<void> cacheScript(String filename, String code) async {
    final prefs = await _instance;
    await prefs.setString('cache_script_$filename', code);
  }

  Future<Map<String, dynamic>?> getCachedSourcesJson() async {
    final prefs = await _instance;
    final str = prefs.getString('cache_sources_json');
    if (str == null || str.trim().isEmpty) return null;
    try {
      return json.decode(str) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheSourcesJson(String jsonStr) async {
    final prefs = await _instance;
    await prefs.setString('cache_sources_json', jsonStr);
  }

  Future<String?> getCachedRouterJs() async {
    final prefs = await _instance;
    return prefs.getString('cache_router_js');
  }

  Future<void> cacheRouterJs(String code) async {
    final prefs = await _instance;
    await prefs.setString('cache_router_js', code);
  }

  Future<void> clearScraperCache() async {
    final prefs = await _instance;
    final keys = prefs.getKeys().where((k) => k.startsWith('cache_script_') || k == 'cache_sources_json' || k == 'cache_router_js').toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  Future<void> clearWatchHistory() async {
    await StorageService.instance.clearContinueWatching();
  }

  Future<void> resetAllSettings() async {
    final prefs = await _instance;
    await prefs.remove(_prefAudioLangKey);
    await prefs.remove(_prefSubtitleLangKey);
    await prefs.remove(_prefQualityKey);
    await prefs.remove(_prefFileSizeKey);
    await prefs.remove(_prefPrioritizeAudioKey);
    await prefs.remove(_customScraperRepoKey);
    await prefs.remove(_prefSourceOverridesKey);
    await StorageService.instance.resetApiBaseUrl();
    ApiClient.instance = ApiClient();
  }
}
