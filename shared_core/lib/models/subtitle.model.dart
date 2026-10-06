class SubtitleTrackInfo {
  final String? id;
  final String language;
  final String code;
  final String url;
  final String format;
  final String? release;

  SubtitleTrackInfo({
    this.id,
    required this.language,
    required this.code,
    required this.url,
    required this.format,
    this.release,
  });

  factory SubtitleTrackInfo.fromJson(Map<String, dynamic> json) {
    return SubtitleTrackInfo(
      id: json['id']?.toString(),
      language: json['language'] ?? 'Unknown',
      code: json['code'] ?? 'und',
      url: json['url'] ?? '',
      format: json['format'] ?? 'vtt',
      release: json['release']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'language': language,
      'code': code,
      'url': url,
      'format': format,
      'release': release,
    };
  }

  String get label {
    final base = '$language (${code.toUpperCase()})';
    if (release != null && release!.isNotEmpty) {
      return '$base • $release';
    }
    return base;
  }

  String get name => label;
  bool get isExternal => url.isNotEmpty;
  bool get isEnglish => code.toLowerCase().startsWith('en') || language.toLowerCase().contains('eng');
}

class SubtitleResponse {
  final int tmdbId;
  final String? imdbId;
  final String mediaType;
  final int? season;
  final int? episode;
  final List<SubtitleTrackInfo> subtitles;

  SubtitleResponse({
    required this.tmdbId,
    this.imdbId,
    required this.mediaType,
    this.season,
    this.episode,
    required this.subtitles,
  });

  factory SubtitleResponse.fromJson(Map<String, dynamic> json) {
    final list = json['subtitles'] as List? ?? [];
    return SubtitleResponse(
      tmdbId: json['tmdb_id'] ?? 0,
      imdbId: json['imdb_id']?.toString(),
      mediaType: json['media_type'] ?? 'movie',
      season: json['season'],
      episode: json['episode'],
      subtitles: list
          .map((s) => SubtitleTrackInfo.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
    );
  }
}
