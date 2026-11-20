import '../models/movie_summary.dart';
import '../models/trakt_list_summary.dart';

class ListSorter {
  /// Sort a list of [MovieSummary] items by [sortBy] and [sortOrder].
  ///
  /// Supported criteria for [sortBy]:
  /// - 'rank': Preserves list order if 'asc', reverses if 'desc'.
  /// - 'added': Preserves list order if 'asc', reverses if 'desc'.
  /// - 'title': Case-insensitive alphabetical sort.
  /// - 'released': Chronological sort by release date / year.
  /// - 'popularity': Sort by rating score (descending = highest score first).
  /// - 'runtime': Sort by runtime in minutes.
  /// - 'votes': Sort by total vote count (descending = most votes first).
  ///
  /// Supported values for [sortOrder]: 'asc', 'desc'.
  ///
  /// Returns a new list without modifying the input list.
  static List<MovieSummary> sort(
    List<MovieSummary> items, {
    required String sortBy,
    String sortOrder = 'asc',
  }) {
    if (items.length <= 1) return List<MovieSummary>.of(items);

    final isDesc = sortOrder.trim().toLowerCase() == 'desc';
    final normalizedSortBy = sortBy.trim().toLowerCase();
    final list = List<MovieSummary>.of(items);

    switch (normalizedSortBy) {
      case 'rank':
      case 'added':
        return isDesc ? list.reversed.toList() : list;

      case 'title':
        list.sort((a, b) {
          int cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          if (cmp == 0) cmp = a.imdbId.compareTo(b.imdbId);
          return isDesc ? -cmp : cmp;
        });
        return list;

      case 'released':
      case 'release_date':
      case 'year':
        list.sort((a, b) {
          int cmp = a.releaseDate.compareTo(b.releaseDate);
          if (cmp == 0) cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          return isDesc ? -cmp : cmp;
        });
        return list;

      case 'popularity':
      case 'rating':
        list.sort((a, b) {
          int cmp = a.ratingScore.compareTo(b.ratingScore);
          if (cmp == 0) cmp = a.voteCount.compareTo(b.voteCount);
          return isDesc ? -cmp : cmp;
        });
        return list;

      case 'runtime':
        list.sort((a, b) {
          final aRt = a.runtime ?? 0;
          final bRt = b.runtime ?? 0;
          int cmp = aRt.compareTo(bRt);
          if (cmp == 0) cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          return isDesc ? -cmp : cmp;
        });
        return list;

      case 'votes':
      case 'vote_count':
        list.sort((a, b) {
          int cmp = a.voteCount.compareTo(b.voteCount);
          if (cmp == 0) cmp = a.ratingScore.compareTo(b.ratingScore);
          return isDesc ? -cmp : cmp;
        });
        return list;

      default:
        return isDesc ? list.reversed.toList() : list;
    }
  }

  /// Sort a list of [TraktListSummary] items by [sortBy] and [sortOrder].
  ///
  /// Supported criteria for [sortBy]:
  /// - 'rank' / 'added': Preserves list order if 'asc', reverses if 'desc'.
  /// - 'name' / 'title': Case-insensitive alphabetical sort.
  /// - 'likes' / 'popularity': Sort by number of likes.
  /// - 'items' / 'item_count': Sort by number of items.
  ///
  /// Supported values for [sortOrder]: 'asc', 'desc'.
  ///
  /// Returns a new list without modifying the input list.
  static List<TraktListSummary> sortLists(
    List<TraktListSummary> items, {
    required String sortBy,
    String sortOrder = 'asc',
  }) {
    if (items.length <= 1) return List<TraktListSummary>.of(items);

    final isDesc = sortOrder.trim().toLowerCase() == 'desc';
    final normalizedSortBy = sortBy.trim().toLowerCase();
    final list = List<TraktListSummary>.of(items);

    switch (normalizedSortBy) {
      case 'rank':
      case 'added':
        return isDesc ? list.reversed.toList() : list;

      case 'name':
      case 'title':
        list.sort((a, b) {
          int cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          if (cmp == 0) cmp = a.id.compareTo(b.id);
          return isDesc ? -cmp : cmp;
        });
        return list;

      case 'likes':
      case 'popularity':
        list.sort((a, b) {
          int cmp = a.likes.compareTo(b.likes);
          if (cmp == 0) cmp = a.id.compareTo(b.id);
          return isDesc ? -cmp : cmp;
        });
        return list;

      case 'items':
      case 'item_count':
      case 'itemcount':
        list.sort((a, b) {
          int cmp = a.itemCount.compareTo(b.itemCount);
          if (cmp == 0) cmp = a.id.compareTo(b.id);
          return isDesc ? -cmp : cmp;
        });
        return list;

      default:
        return isDesc ? list.reversed.toList() : list;
    }
  }
}
