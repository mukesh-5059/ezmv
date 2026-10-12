class StreamSource {
  final String url;
  final String quality;
  final List<String> languages;
  final double? sizeMb;
  final String? formattedSize;
  final int? bitrateKbps;
  final String? bitrateStr;
  final String provider;
  final String? source;
  final String? host;
  final Map<String, String> headers;
  final int priority;
  final int? createdAt;
  final int? expiresAt;
  final int? ttl;
  final int remainingTtl;
  final String? filename;

  StreamSource({
    required this.url,
    required this.quality,
    this.languages = const [],
    this.sizeMb,
    this.formattedSize,
    this.bitrateKbps,
    this.bitrateStr,
    required this.provider,
    this.source,
    this.host,
    this.headers = const {},
    this.priority = 10,
    this.createdAt,
    this.expiresAt,
    this.ttl,
    this.remainingTtl = 0,
    this.filename,
  });

  factory StreamSource.fromJson(Map<String, dynamic> json) {
    List<String> parseLanguages(dynamic raw) {
      if (raw is List) {
        return raw
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (raw is String && raw.trim().isNotEmpty) {
        return raw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    Map<String, String> parseHeaders(dynamic raw) {
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return const {};
    }

    double? parseDouble(dynamic raw) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }

    int? parseInt(dynamic raw) {
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw);
      return null;
    }

    final expiresAt = parseInt(json['expires_at']);
    final ttl = parseInt(json['ttl']);
    int remaining = parseInt(json['remaining_ttl']) ?? 0;
    if (remaining <= 0 && expiresAt != null) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      remaining = (expiresAt - nowSec).clamp(0, 99999999);
    }

    return StreamSource(
      url: json['url']?.toString() ?? '',
      quality: json['quality']?.toString() ?? 'Auto',
      languages: parseLanguages(json['languages']),
      sizeMb: parseDouble(json['size_mb']),
      formattedSize: json['formatted_size']?.toString(),
      bitrateKbps: parseInt(json['bitrate_kbps']),
      bitrateStr: json['bitrate_str']?.toString(),
      provider: json['provider']?.toString() ?? 'Direct',
      source: json['source']?.toString(),
      host: json['host']?.toString(),
      headers: parseHeaders(json['headers']),
      priority: parseInt(json['priority']) ?? 10,
      createdAt: parseInt(json['created_at']),
      expiresAt: expiresAt,
      ttl: ttl,
      remainingTtl: remaining,
      filename: json['filename']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'quality': quality,
      'languages': languages,
      if (sizeMb != null) 'size_mb': sizeMb,
      if (formattedSize != null) 'formatted_size': formattedSize,
      if (bitrateKbps != null) 'bitrate_kbps': bitrateKbps,
      if (bitrateStr != null) 'bitrate_str': bitrateStr,
      'provider': provider,
      if (source != null) 'source': source,
      if (host != null) 'host': host,
      'headers': headers,
      'priority': priority,
      if (createdAt != null) 'created_at': createdAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (ttl != null) 'ttl': ttl,
      'remaining_ttl': remainingTtl,
      if (filename != null) 'filename': filename,
    };
  }

  bool get isExpired => remainingTtl <= 0 && (expiresAt != null || ttl != null);

  String get formattedRemainingTtl {
    if (remainingTtl <= 0) return 'Expired';
    final hours = remainingTtl ~/ 3600;
    final minutes = (remainingTtl % 3600) ~/ 60;
    final seconds = remainingTtl % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${seconds}s';
  }

  String get displaySize {
    if (formattedSize != null && formattedSize!.trim().isNotEmpty) {
      return formattedSize!;
    }
    if (sizeMb != null && sizeMb! > 0) {
      if (sizeMb! >= 1024) {
        return '${(sizeMb! / 1024).toStringAsFixed(1)} GB';
      }
      return '${sizeMb!.toStringAsFixed(0)} MB';
    }
    return '';
  }

  String get sourceHierarchy {
    final parts = <String>[];
    if (provider.isNotEmpty) parts.add(provider);
    if (source != null &&
        source!.trim().isNotEmpty &&
        source!.toLowerCase() != provider.toLowerCase()) {
      parts.add(source!);
    }
    if (host != null &&
        host!.trim().isNotEmpty &&
        host!.toLowerCase() != provider.toLowerCase() &&
        host!.toLowerCase() != source?.toLowerCase()) {
      parts.add(host!);
    }
    return parts.join(' • ');
  }

  StreamSource copyWith({int? remainingTtl}) {
    return StreamSource(
      url: url,
      quality: quality,
      languages: languages,
      sizeMb: sizeMb,
      formattedSize: formattedSize,
      bitrateKbps: bitrateKbps,
      bitrateStr: bitrateStr,
      provider: provider,
      source: source,
      host: host,
      headers: headers,
      priority: priority,
      createdAt: createdAt,
      expiresAt: expiresAt,
      ttl: ttl,
      remainingTtl: remainingTtl ?? this.remainingTtl,
      filename: filename,
    );
  }
}
