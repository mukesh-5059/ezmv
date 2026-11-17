import '../models/stream_source.dart';

const Map<String, String> languageMap = {
  'ta': 'Tamil',
  'tam': 'Tamil',
  'tamil': 'Tamil',
  'te': 'Telugu',
  'tel': 'Telugu',
  'telugu': 'Telugu',
  'hi': 'Hindi',
  'hin': 'Hindi',
  'hindi': 'Hindi',
  'mal': 'Malayalam',
  'ml': 'Malayalam',
  'malayalam': 'Malayalam',
  'kan': 'Kannada',
  'kn': 'Kannada',
  'kannada': 'Kannada',
  'en': 'English',
  'eng': 'English',
  'english': 'English',
  'bn': 'Bengali',
  'ben': 'Bengali',
  'bengali': 'Bengali',
  'mr': 'Marathi',
  'mar': 'Marathi',
  'marathi': 'Marathi',
  'pa': 'Punjabi',
  'pan': 'Punjabi',
  'punjabi': 'Punjabi',
  'gu': 'Gujarati',
  'guj': 'Gujarati',
  'gujarati': 'Gujarati',
  'fr': 'French',
  'fre': 'French',
  'fra': 'French',
  'french': 'French',
  'es': 'Spanish',
  'spa': 'Spanish',
  'spanish': 'Spanish',
  'de': 'German',
  'ger': 'German',
  'deu': 'German',
  'german': 'German',
  'ja': 'Japanese',
  'jap': 'Japanese',
  'jpn': 'Japanese',
  'japanese': 'Japanese',
  'ko': 'Korean',
  'kor': 'Korean',
  'korean': 'Korean',
  'zh': 'Chinese',
  'chi': 'Chinese',
  'zho': 'Chinese',
  'chinese': 'Chinese',
  'ru': 'Russian',
  'rus': 'Russian',
  'russian': 'Russian',
  'it': 'Italian',
  'ita': 'Italian',
  'italian': 'Italian',
};

const Set<String> indianLanguages = {
  'Tamil',
  'Telugu',
  'Hindi',
  'Malayalam',
  'Kannada',
  'Bengali',
  'Marathi',
  'Punjabi',
  'Gujarati',
};

class StreamPriorityCalculator {
  static String? normalizeLanguage(String? langOrCode) {
    if (langOrCode == null || langOrCode.trim().isEmpty) return null;
    final clean = langOrCode.trim().toLowerCase();
    return languageMap[clean] ?? (clean[0].toUpperCase() + clean.substring(1));
  }

  static bool isIndianLanguage(String? langOrCode) {
    if (langOrCode == null) return false;
    final norm = normalizeLanguage(langOrCode);
    return norm != null && indianLanguages.contains(norm);
  }

  static List<String> parseLanguages(String text, {String? defaultLanguage}) {
    final normDefault = normalizeLanguage(defaultLanguage);
    if (text.isEmpty) return normDefault != null ? [normDefault] : [];

    final tokens = text.toLowerCase().split(RegExp(r'[^a-z0-9]+'));
    final detected = <String>{};

    for (final token in tokens) {
      final lang = languageMap[token];
      if (lang != null) detected.add(lang);
    }

    if (detected.isNotEmpty) return detected.toList();
    return normDefault != null ? [normDefault] : [];
  }

  static String parseQuality(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('2160') || lower.contains('4k') || lower.contains('uhd')) return '4K UHD';
    if (lower.contains('1080') || lower.contains('fhd')) return '1080p';
    if (lower.contains('720') || lower.contains('hd')) return '720p';
    if (lower.contains('480') || lower.contains('sd')) return '480p SD';
    return 'Auto';
  }

  static String? extractFilename(Map<String, dynamic> raw) {
    final hints = raw['behaviorHints'] as Map<String, dynamic>?;
    final hintFilename = hints?['filename'] as String?;
    if (hintFilename != null && hintFilename.isNotEmpty) {
      return hintFilename.split('|^|')[0].trim();
    }

    final desc = raw['description'] as String?;
    if (desc != null && desc.isNotEmpty) {
      final lines = desc.split('\n');
      final fileLine = lines.firstWhere(
        (l) => RegExp(r'\.(mkv|mp4|avi|webm)', caseSensitive: false).hasMatch(l),
        orElse: () => lines.first,
      );
      final cleaned = fileLine.replaceAll(RegExp(r'^(\[[^\]]+\]\s*)+'), '').trim();
      if (cleaned.length > 5) return cleaned.split('|^|')[0].trim();
    }

    final title = ((raw['title'] ?? raw['name'] ?? '') as String).replaceAll('\n', ' ').trim();
    return title.isNotEmpty ? title.split('|^|')[0].trim() : null;
  }

  static String? formatSizeBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.round()} MB';
  }

  static int calculatePriority({
    required String provider,
    required String quality,
    List<String>? languages,
    String? defaultLanguage,
    String? host,
    int? sizeBytes,
    String? originalLanguage,
    String? preferredAudioLanguage,
    String? preferredQuality,
    String? fileSizeTarget,
    bool prioritizeAudio = true,
  }) {
    int score = 100;

    if (host != null && host.isNotEmpty) {
      final hLow = host.toLowerCase();
      if (hLow.contains('pixeldrain') ||
          hLow.contains('googleusercontent') ||
          hLow.contains('hubcloud') ||
          hLow.contains('workers.dev')) {
        score -= 15;
      } else if (hLow.contains('vidvault') ||
          hLow.contains('streamtape') ||
          hLow.contains('dood')) {
        score += 20;
      }
    }

    if (sizeBytes != null && sizeBytes > 0) {
      final gb = sizeBytes / (1024 * 1024 * 1024);
      if (fileSizeTarget == 'dataSaver') {
        if (gb <= 1.5) score -= 20;
        else if (gb > 4.0) score += 30;
      } else if (fileSizeTarget == 'highQuality') {
        if (gb >= 4.0) score -= 20;
        else if (gb < 1.0) score += 15;
      } else {
        if (gb <= 3.5) score -= 5;
        else if (gb > 25) score += 5;
      }
    }

    if (prioritizeAudio && preferredAudioLanguage != null && preferredAudioLanguage.isNotEmpty) {
      final normPref = normalizeLanguage(preferredAudioLanguage);
      if (normPref != null && (languages?.any((l) => l.toLowerCase() == normPref.toLowerCase()) ?? false)) {
        score -= 35;
      }
    }

    final isIndian = isIndianLanguage(originalLanguage);
    final normOrig = normalizeLanguage(originalLanguage);
    final normDefault = normalizeLanguage(defaultLanguage);

    if (isIndian) {
      final hasTamil = languages?.any((l) => l.toLowerCase() == 'tamil') ?? false;
      if (hasTamil) {
        score -= 30;
      } else if (normOrig != null && (languages?.any((l) => l.toLowerCase() == normOrig.toLowerCase()) ?? false)) {
        score -= 20;
      } else if (normDefault != null && (languages?.any((l) => l.toLowerCase() == normDefault.toLowerCase()) ?? false)) {
        score -= 15;
      }
    } else if (originalLanguage != null && originalLanguage.isNotEmpty) {
      if (normOrig != null && (languages?.any((l) => l.toLowerCase() == normOrig.toLowerCase()) ?? false)) {
        score -= 30;
      } else if (normDefault != null && (languages?.any((l) => l.toLowerCase() == normDefault.toLowerCase()) ?? false)) {
        score -= 15;
      }
    } else {
      final hasTamil = languages?.any((l) => l.toLowerCase() == 'tamil') ?? false;
      if (hasTamil) {
        score -= 30;
      } else if (normDefault != null && (languages?.any((l) => l.toLowerCase() == normDefault.toLowerCase()) ?? false)) {
        score -= 15;
      }
    }

    final qLow = quality.toLowerCase();
    if (preferredQuality != null && preferredQuality != 'auto') {
      final pqLow = preferredQuality.toLowerCase();
      if (pqLow.contains('4k') || pqLow.contains('uhd')) {
        if (qLow.contains('4k') || qLow.contains('2160') || qLow.contains('uhd')) score -= 25;
      } else if (pqLow.contains('1080') || pqLow.contains('fhd')) {
        if (qLow.contains('1080') || qLow.contains('fhd')) score -= 25;
      } else if (pqLow.contains('720') || pqLow.contains('hd')) {
        if (qLow.contains('720') || qLow.contains('hd')) score -= 20;
      } else if (pqLow.contains('480') || pqLow.contains('sd')) {
        if (qLow.contains('480') || qLow.contains('sd')) score -= 20;
      }
    } else {
      if (quality == '1080p') {
        score -= 20;
      } else if (quality == '4K UHD') {
        score -= 10;
      } else if (quality == '720p') {
        score -= 5;
      }
    }

    return score;
  }

  static StreamSource? parseStremioStream(
    Map<String, dynamic> raw, {
    required String provider,
    String? defaultLanguage,
    String? originalLanguage,
    String? preferredAudioLanguage,
    String? preferredQuality,
    String? fileSizeTarget,
    bool prioritizeAudio = true,
  }) {
    final url = raw['url'] as String?;
    if (url == null || !url.startsWith('http')) return null;

    final filename = extractFilename(raw);
    final fullText = '${raw['name'] ?? ''} ${raw['description'] ?? ''} ${filename ?? ''}';

    if (RegExp(r'donation|support the project|discord\.gg', caseSensitive: false).hasMatch(fullText) &&
        (raw['behaviorHints']?['videoSize'] == null)) {
      return null;
    }

    final quality = parseQuality(fullText);

    final languages = parseLanguages(fullText, defaultLanguage: defaultLanguage ?? originalLanguage);
    final rawSize = raw['behaviorHints']?['videoSize'];
    final sizeBytes = (rawSize is num && rawSize > 0) ? rawSize.toInt() : null;

    String? host;
    try {
      host = Uri.parse(url).host;
    } catch (_) {}

    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    };
    final proxyHeaders = raw['behaviorHints']?['proxyHeaders']?['request'] as Map<String, dynamic>?;
    if (proxyHeaders != null) {
      proxyHeaders.forEach((k, v) => headers[k] = v.toString());
    }

    final priority = calculatePriority(
      provider: provider,
      quality: quality,
      languages: languages,
      defaultLanguage: defaultLanguage,
      host: host,
      sizeBytes: sizeBytes,
      originalLanguage: originalLanguage,
      preferredAudioLanguage: preferredAudioLanguage,
      preferredQuality: preferredQuality,
      fileSizeTarget: fileSizeTarget,
      prioritizeAudio: prioritizeAudio,
    );

    return StreamSource(
      url: url,
      quality: quality,
      filename: filename,
      sizeBytes: sizeBytes,
      formattedSize: formatSizeBytes(sizeBytes),
      priority: priority,
      provider: provider,
      host: host,
      languages: languages,
      headers: headers,
    );
  }
}
