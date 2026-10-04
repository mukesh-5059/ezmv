class FilterOption {
  final dynamic id;
  final String label;
  final int? yearMin;
  final int? yearMax;

  const FilterOption({
    required this.id,
    required this.label,
    this.yearMin,
    this.yearMax,
  });

  factory FilterOption.fromJson(Map<String, dynamic> json) {
    return FilterOption(
      id: json['id'],
      label: json['label'] ?? '',
      yearMin: json['year_min'] as int?,
      yearMax: json['year_max'] as int?,
    );
  }
}

class FiltersData {
  final List<FilterOption> languages;
  final List<FilterOption> genres;
  final List<FilterOption> years;
  final List<FilterOption> sortOptions;

  const FiltersData({
    this.languages = const [],
    this.genres = const [],
    this.years = const [],
    this.sortOptions = const [],
  });

  factory FiltersData.fromJson(Map<String, dynamic> json) {
    return FiltersData(
      languages: (json['languages'] as List? ?? [])
          .map((item) => FilterOption.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      genres: (json['genres'] as List? ?? [])
          .map((item) => FilterOption.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      years: (json['years'] as List? ?? [])
          .map((item) => FilterOption.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      sortOptions: (json['sort_options'] as List? ?? [])
          .map((item) => FilterOption.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}
