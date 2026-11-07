class SubtitleTrack {
  final String name;
  final String language;
  final String url;
  final int popularity;

  const SubtitleTrack({
    required this.name,
    required this.language,
    required this.url,
    this.popularity = 0,
  });

  bool get isEnglish => language.toLowerCase().contains('eng');
  String get label {
    final lang = language.trim();
    if (lang.isNotEmpty) {
      return '[${lang.toUpperCase()}] ${name.isNotEmpty ? name : 'Track'}';
    }
    return name.isNotEmpty ? name : 'Unknown';
  }

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) => SubtitleTrack(
    name: json['name'] as String? ?? '',
    language: json['language'] as String? ?? '',
    url: json['url'] as String? ?? '',
    popularity: (json['popularity'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'language': language,
    'url': url,
    'popularity': popularity,
  };
}

typedef SubtitleTrackInfo = SubtitleTrack;
