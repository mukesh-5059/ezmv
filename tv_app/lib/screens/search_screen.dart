import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/tv_focus_button.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_pill_chip.dart';
import '../widgets/tv_shortcuts.dart';
import 'details_screen.dart';

enum SearchFilterDimension {
  type,
  genre,
  year,
  rating,
  sort,
}

/// 10-Foot TV Search Screen with 70/30 Filter Layout.
///
/// Features:
/// - 70/30 Split Layout:
///   - Left 70%: 5-column virtualized movie search grid (full width when no strip is active).
///   - Right 30%: Vertical filter strip for active filter dimension (with checkmarks, autofocus, D-pad Left/Back dismissal).
/// - Top Control Bar:
///   - Search input text field with high-contrast TV focus state. Pressing Enter/Select triggers native TV IME keyboard.
///   - Search history row: Horizontal list of recently searched query chips + "Clear History" action.
///   - Filter pills row: Type (All/Movie/TV), Genre, Year, Rating, Sort By, and Clear Filters button.
/// - Remote Back-Key Hierarchy:
///   - Priority 1: Strip open -> Close strip & refocus active pill chip.
///   - Priority 2: Scrolled down (offset > 20) -> Smooth-scroll to row 0 & focus search bar.
///   - Priority 3: At row 0 & no strip -> Exit / pop screen.
/// - Data & Pagination:
///   - Query via `ApiClient.instance.search(query, type: ..., genre: ..., year: ..., minRating: ...)`.
///   - Infinite scroll pagination: Lookahead prefetch when scrolling past 80% (or index >= items.length - 15).
///   - Skeletons during fetch and clear "End of Catalog" indicator when hasMore == false.
class SearchScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final void Function(MovieSummary movie)? onMovieSelected;

  const SearchScreen({
    super.key,
    this.apiClient,
    this.onMovieSelected,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final ApiClient _apiClient;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();

  // Control bar focus nodes
  late final FocusNode _backButtonFocusNode;
  late final FocusNode _textFieldFocusNode;
  late final FocusNode _searchButtonFocusNode;
  late final FocusNode _clearSearchFocusNode;
  late final FocusNode _clearHistoryFocusNode;

  // Filter pill focus nodes
  late final FocusNode _typePillFocusNode;
  late final FocusNode _genrePillFocusNode;
  late final FocusNode _yearPillFocusNode;
  late final FocusNode _ratingPillFocusNode;
  late final FocusNode _sortPillFocusNode;
  late final FocusNode _clearFiltersFocusNode;
  late final FocusNode _resetFiltersFocusNode;

  final Map<int, FocusNode> _historyFocusNodes = {};
  final Map<int, FocusNode> _cardFocusNodes = {};
  final FocusNode _firstFilterOptionFocusNode = FocusNode();
  int _lastFocusedCardIndex = 0;

  FocusNode? _lastFocusedPillNode;

  // Search History state
  List<String> _history = [];
  static const String _historyKey = 'tv_search_history';

  // Filter selections
  String _selectedType = 'All';
  String _selectedGenre = 'All';
  String _selectedYear = 'All';
  String _selectedRating = 'All';
  String _selectedSort = 'Popular';

  // Active filter dimension strip
  SearchFilterDimension? _activeFilterDimension;

  // Data & Pagination state
  final List<MovieSummary> _items = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _isLoading = false;
  bool _isFetchingMore = false;
  String? _errorMessage;
  bool _hasSearched = false;

  static const List<String> _typeOptions = ['All', 'Movies', 'TV'];

  static const List<String> _genreOptions = [
    'All',
    'Action',
    'Adventure',
    'Animation',
    'Anime',
    'Biography',
    'Comedy',
    'Crime',
    'Documentary',
    'Drama',
    'Family',
    'Fantasy',
    'History',
    'Horror',
    'Music',
    'Mystery',
    'Romance',
    'Sci-Fi',
    'Sports',
    'Thriller',
    'War',
  ];

  static const List<String> _yearOptions = [
    'All',
    '2024',
    '2023',
    '2022',
    '2020s',
    '2010s',
    '2000s',
    '90s',
    'classic',
  ];

  static const List<String> _ratingOptions = [
    'All',
    '9.0+',
    '8.0+',
    '7.0+',
    '6.0+',
  ];

  static const List<String> _sortOptions = [
    'Popular',
    'Top Rated',
    'Newest',
    'Oldest',
    'Title',
  ];

  KeyEventResult _handleBackButtonKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _textFieldFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_history.isNotEmpty) {
        _getHistoryFocusNode(0).requestFocus();
      } else {
        (_lastFocusedPillNode ?? _typePillFocusNode).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleClearHistoryKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _history.isNotEmpty) {
      _getHistoryFocusNode(_history.length - 1).requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _textFieldFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _clearFiltersFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleClearFiltersKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _sortPillFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_history.isNotEmpty) {
        _clearHistoryFocusNode.requestFocus();
      } else {
        _textFieldFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_items.isNotEmpty) {
        _getCardFocusNode(0).requestFocus();
      } else if (_resetFiltersFocusNode.canRequestFocus) {
        _resetFiltersFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleHistoryPillKeyEvent(KeyEvent event, int index) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _textFieldFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      (_lastFocusedPillNode ?? _typePillFocusNode).requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _getHistoryFocusNode(index - 1).requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (index < _history.length - 1) {
        _getHistoryFocusNode(index + 1).requestFocus();
        return KeyEventResult.handled;
      }
      _clearHistoryFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  FocusNode _getHistoryFocusNode(int index) {
    return _historyFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  FocusNode _getCardFocusNode(int index) {
    return _cardFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  void _onCardFocused(int index) {
    _lastFocusedCardIndex = index;
    if (index >= 15 && index >= _items.length - 15 && _hasMore && !_isFetchingMore && !_isLoading) {
      _fetchMore();
    }
  }

  KeyEventResult _handlePillKeyEvent(KeyEvent event, FocusNode currentNode) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_history.isNotEmpty) {
        _getHistoryFocusNode(0).requestFocus();
      } else {
        _textFieldFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_items.isNotEmpty) {
        _getCardFocusNode(0).requestFocus();
      } else if (_resetFiltersFocusNode.canRequestFocus) {
        _resetFiltersFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (currentNode == _typePillFocusNode && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.handled;
    }
    if (currentNode == _sortPillFocusNode && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _clearFiltersFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCardKeyEvent(KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _handleBack();
      return KeyEventResult.handled;
    }

    final col = index % 5;
    final row = index ~/ 5;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp && row == 0) {
      (_lastFocusedPillNode ?? _typePillFocusNode).requestFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_activeFilterDimension != null && (col == 4 || index == _items.length - 1)) {
        _firstFilterOptionFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (index < _items.length - 1) {
        _getCardFocusNode(index + 1).requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _getCardFocusNode(index - 1).requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown && index + 5 >= _items.length) {
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onSearchTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient.instance;
    _searchController.addListener(_onSearchTextChanged);

    _backButtonFocusNode = FocusNode(onKeyEvent: _handleBackButtonKeyEvent);

    _textFieldFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_searchController.text.isEmpty || _searchController.selection.start <= 0) {
              return KeyEventResult.handled;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            _handleBack();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _searchButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_history.isNotEmpty) {
              _getHistoryFocusNode(0).requestFocus();
            } else {
              (_lastFocusedPillNode ?? _typePillFocusNode).requestFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _searchButtonFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_history.isNotEmpty) {
              _getHistoryFocusNode(0).requestFocus();
            } else {
              (_lastFocusedPillNode ?? _typePillFocusNode).requestFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _textFieldFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (_searchController.text.isNotEmpty) {
              _clearSearchFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _clearSearchFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_history.isNotEmpty) {
              _getHistoryFocusNode(0).requestFocus();
            } else {
              _clearFiltersFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _searchButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _clearHistoryFocusNode = FocusNode(onKeyEvent: _handleClearHistoryKeyEvent);

    _typePillFocusNode = FocusNode(onKeyEvent: (node, event) => _handlePillKeyEvent(event, _typePillFocusNode));
    _genrePillFocusNode = FocusNode(onKeyEvent: (node, event) => _handlePillKeyEvent(event, _genrePillFocusNode));
    _yearPillFocusNode = FocusNode(onKeyEvent: (node, event) => _handlePillKeyEvent(event, _yearPillFocusNode));
    _ratingPillFocusNode = FocusNode(onKeyEvent: (node, event) => _handlePillKeyEvent(event, _ratingPillFocusNode));
    _sortPillFocusNode = FocusNode(onKeyEvent: (node, event) => _handlePillKeyEvent(event, _sortPillFocusNode));
    _clearFiltersFocusNode = FocusNode(onKeyEvent: _handleClearFiltersKeyEvent);

    _resetFiltersFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            (_lastFocusedPillNode ?? _typePillFocusNode).requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _loadHistory();
    _gridScrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textFieldFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _gridScrollController.dispose();
    _backButtonFocusNode.dispose();
    _textFieldFocusNode.dispose();
    _searchButtonFocusNode.dispose();
    _clearSearchFocusNode.dispose();
    _clearHistoryFocusNode.dispose();
    _typePillFocusNode.dispose();
    _genrePillFocusNode.dispose();
    _yearPillFocusNode.dispose();
    _ratingPillFocusNode.dispose();
    _sortPillFocusNode.dispose();
    _clearFiltersFocusNode.dispose();
    _resetFiltersFocusNode.dispose();
    for (final node in _historyFocusNodes.values) {
      node.dispose();
    }
    for (final node in _cardFocusNodes.values) {
      node.dispose();
    }
    _firstFilterOptionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? [];
    if (mounted) setState(() => _history = list);
  }

  Future<void> _saveHistory(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? [];
    list.remove(query);
    list.insert(0, query);
    if (list.length > 10) list.removeRange(10, list.length);
    await prefs.setStringList(_historyKey, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) setState(() => _history = []);
  }

  String? _mapTypeParam() {
    if (_selectedType == 'Movies') return 'movie';
    if (_selectedType == 'TV') return 'tv';
    return null;
  }

  String? _mapGenreParam() {
    if (_selectedGenre == 'All') return null;
    return _selectedGenre.toLowerCase();
  }

  int? _mapYearParam() {
    if (_selectedYear == 'All') return null;
    if (_selectedYear == '2020s') return 2020;
    if (_selectedYear == '2010s') return 2010;
    if (_selectedYear == '2000s') return 2000;
    if (_selectedYear == '90s') return 1990;
    if (_selectedYear == 'classic') return 1980;
    return int.tryParse(_selectedYear);
  }

  double? _mapRatingParam() {
    if (_selectedRating == 'All') return null;
    return double.tryParse(_selectedRating.replaceAll('+', ''));
  }

  void _onScroll() {
    if (!_gridScrollController.hasClients) return;
    final maxScroll = _gridScrollController.position.maxScrollExtent;
    final currentScroll = _gridScrollController.position.pixels;
    // Fetch next page when user scrolls past 80%
    if (maxScroll > 0 && currentScroll >= maxScroll * 0.8) {
      if (!_isLoading && !_isFetchingMore && _hasMore) {
        _fetchMore();
      }
    }
  }

  Future<void> _executeSearch({bool reset = true}) async {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _saveHistory(query);
    }

    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _items.clear();
        _currentPage = 1;
        _hasMore = false;
        _hasSearched = true;
      });
    }

    try {
      final response = await _apiClient.search(
        query,
        page: 1,
        type: _mapTypeParam(),
        genre: _mapGenreParam(),
        year: _mapYearParam(),
        minRating: _mapRatingParam(),
      );

      if (!mounted) return;

      var resultItems = response.items;
      _applySort(resultItems);

      setState(() {
        _isLoading = false;
        _currentPage = response.page;
        _hasMore = response.hasMore;
        if (reset) _items.clear();
        _items.addAll(resultItems);
      });

      if (reset && resultItems.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _items.isNotEmpty) {
            _getCardFocusNode(0).requestFocus();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _fetchMore() async {
    if (_isFetchingMore || !_hasMore || _isLoading) return;

    final query = _searchController.text.trim();

    setState(() => _isFetchingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final response = await _apiClient.search(
        query,
        page: nextPage,
        type: _mapTypeParam(),
        genre: _mapGenreParam(),
        year: _mapYearParam(),
        minRating: _mapRatingParam(),
      );

      if (!mounted) return;

      var resultItems = response.items;
      _applySort(resultItems);

      setState(() {
        _isFetchingMore = false;
        _currentPage = response.page;
        _hasMore = response.hasMore;
        _items.addAll(resultItems);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFetchingMore = false);
    }
  }

  void _applySort(List<MovieSummary> items) {
    switch (_selectedSort) {
      case 'Top Rated':
        items.sort((a, b) => b.ratingScore.compareTo(a.ratingScore));
        break;
      case 'Newest':
        items.sort((a, b) => b.year.compareTo(a.year));
        break;
      case 'Oldest':
        items.sort((a, b) => a.year.compareTo(b.year));
        break;
      case 'Title':
        items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'Popular':
      default:
        break;
    }
  }

  DateTime? _lastBackPressTime;

  void _handleBack() {
    final now = DateTime.now();
    if (_lastBackPressTime != null && now.difference(_lastBackPressTime!).inMilliseconds < 400) {
      return;
    }
    _lastBackPressTime = now;

    // Priority 1: Dismiss active filter strip
    if (_activeFilterDimension != null) {
      setState(() => _activeFilterDimension = null);
      _lastFocusedPillNode?.requestFocus();
      return;
    }

    // Priority 2: Jump to Row 0 if scrolled down
    if (_gridScrollController.hasClients && _gridScrollController.offset > 20) {
      _gridScrollController.jumpTo(0);
      _textFieldFocusNode.requestFocus();
      return;
    }

    // Priority 3: Pop screen and return to previous route
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    final hasFilterChanges = _selectedType != 'All' ||
        _selectedGenre != 'All' ||
        _selectedYear != 'All' ||
        _selectedRating != 'All' ||
        _selectedSort != 'Popular';

    if (!hasFilterChanges && _items.isNotEmpty) return;

    setState(() {
      _selectedType = 'All';
      _selectedGenre = 'All';
      _selectedYear = 'All';
      _selectedRating = 'All';
      _selectedSort = 'Popular';
      _activeFilterDimension = null;
    });

    if (_searchController.text.trim().isNotEmpty) {
      _executeSearch(reset: true);
    }
  }

  void _openFilterStrip(SearchFilterDimension dimension, FocusNode pillNode) {
    setState(() {
      _activeFilterDimension = dimension;
      _lastFocusedPillNode = pillNode;
    });
  }

  void _closeFilterStrip() {
    _lastBackPressTime = DateTime.now();
    setState(() => _activeFilterDimension = null);
    if (_items.isNotEmpty) {
      final target = _lastFocusedCardIndex.clamp(0, _items.length - 1);
      _getCardFocusNode(target).requestFocus();
    } else {
      _lastFocusedPillNode?.requestFocus();
    }
  }

  void _applyFilterOption(SearchFilterDimension dimension, String option) {
    setState(() {
      switch (dimension) {
        case SearchFilterDimension.type:
          _selectedType = option;
          break;
        case SearchFilterDimension.genre:
          _selectedGenre = option;
          break;
        case SearchFilterDimension.year:
          _selectedYear = option;
          break;
        case SearchFilterDimension.rating:
          _selectedRating = option;
          break;
        case SearchFilterDimension.sort:
          _selectedSort = option;
          break;
      }
      _activeFilterDimension = null;
    });

    _lastFocusedPillNode?.requestFocus();
    _executeSearch(reset: true);
  }

  List<String> _getFilterStripOptions(SearchFilterDimension dimension) {
    switch (dimension) {
      case SearchFilterDimension.type:
        return _typeOptions;
      case SearchFilterDimension.genre:
        return _genreOptions;
      case SearchFilterDimension.year:
        return _yearOptions;
      case SearchFilterDimension.rating:
        return _ratingOptions;
      case SearchFilterDimension.sort:
        return _sortOptions;
    }
  }

  String _getFilterStripTitle(SearchFilterDimension dimension) {
    switch (dimension) {
      case SearchFilterDimension.type:
        return 'Media Type';
      case SearchFilterDimension.genre:
        return 'Genre';
      case SearchFilterDimension.year:
        return 'Release Year';
      case SearchFilterDimension.rating:
        return 'Minimum Rating';
      case SearchFilterDimension.sort:
        return 'Sort By';
    }
  }

  String _getCurrentFilterValue(SearchFilterDimension dimension) {
    switch (dimension) {
      case SearchFilterDimension.type:
        return _selectedType;
      case SearchFilterDimension.genre:
        return _selectedGenre;
      case SearchFilterDimension.year:
        return _selectedYear;
      case SearchFilterDimension.rating:
        return _selectedRating;
      case SearchFilterDimension.sort:
        return _selectedSort;
    }
  }

  void _navigateToDetails(MovieSummary movie) {
    if (widget.onMovieSelected != null) {
      widget.onMovieSelected!(movie);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          imdbId: movie.imdbId,
          mediaType: movie.mediaType,
          initialMovie: movie,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStripOpen = _activeFilterDimension != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: TVTheme.background,
        body: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack) {
                _handleBack();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 28, 48, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchHeaderRow(),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildSearchHistoryRow(),
                ],
                const SizedBox(height: 14),
                _buildFilterPillsRow(),
                const SizedBox(height: 18),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Area: 5-column Movie Grid (70% when strip is open, 100% when closed)
                      Expanded(
                        flex: isStripOpen ? 7 : 10,
                        child: _buildGridArea(),
                      ),
                      // Right Area: 30% Vertical Filter Strip
                      if (isStripOpen) ...[
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 3,
                          child: _buildFilterStrip(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHeaderRow() {
    return Row(
      children: [
        TvFocusButton(
          focusNode: _backButtonFocusNode,
          onKeyEvent: _handleBackButtonKeyEvent,
          label: 'Back',
          icon: Icons.arrow_back_rounded,
          isPrimary: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          onPressed: _handleBack,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _TvSearchInputField(
            controller: _searchController,
            focusNode: _textFieldFocusNode,
            autofocus: true,
            hintText: 'Search movies, TV shows, actors...',
            onSubmitted: (q) => _executeSearch(reset: true),
          ),
        ),
        const SizedBox(width: 16),
        TvFocusButton(
          focusNode: _searchButtonFocusNode,
          label: 'Search',
          icon: Icons.search_rounded,
          isPrimary: true,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          onPressed: () => _executeSearch(reset: true),
        ),
        if (_searchController.text.isNotEmpty) ...[
          const SizedBox(width: 12),
          TvFocusButton(
            focusNode: _clearSearchFocusNode,
            label: 'Clear',
            icon: Icons.close_rounded,
            isPrimary: false,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            onPressed: () {
              _searchController.clear();
              setState(() {
                _items.clear();
                _hasSearched = false;
                _errorMessage = null;
              });
              _textFieldFocusNode.requestFocus();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSearchHistoryRow() {
    return Row(
      children: [
        const Icon(Icons.history_rounded, size: 16, color: TVTheme.textMuted),
        const SizedBox(width: 8),
        const Text(
          'Recent:',
          style: TextStyle(
            color: TVTheme.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _history.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TvPillChip(
                      focusNode: _getHistoryFocusNode(i),
                      onKeyEvent: (node, event) => _handleHistoryPillKeyEvent(event, i),
                      label: _history[i],
                      isSelected: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      onTap: () {
                        _searchController.value = TextEditingValue(
                          text: _history[i],
                          selection: TextSelection.collapsed(offset: _history[i].length),
                        );
                        _executeSearch(reset: true);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        TvFocusButton(
          focusNode: _clearHistoryFocusNode,
          onKeyEvent: _handleClearHistoryKeyEvent,
          label: 'Clear History',
          icon: Icons.delete_sweep_rounded,
          isPrimary: false,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          onPressed: _clearHistory,
        ),
      ],
    );
  }

  Widget _buildFilterPillsRow() {
    final isTypeOpen = _activeFilterDimension == SearchFilterDimension.type;
    final isGenreOpen = _activeFilterDimension == SearchFilterDimension.genre;
    final isYearOpen = _activeFilterDimension == SearchFilterDimension.year;
    final isRatingOpen = _activeFilterDimension == SearchFilterDimension.rating;
    final isSortOpen = _activeFilterDimension == SearchFilterDimension.sort;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TvPillChip(
                  focusNode: _typePillFocusNode,
                  label: _selectedType == 'All' ? 'Type' : 'Type: $_selectedType',
                  isSelected: _selectedType != 'All' || isTypeOpen,
                  onFocusChanged: (f) {
                    if (f) _lastFocusedPillNode = _typePillFocusNode;
                  },
                  onKeyEvent: (node, event) => _handlePillKeyEvent(event, _typePillFocusNode),
                  onTap: () => _openFilterStrip(SearchFilterDimension.type, _typePillFocusNode),
                ),
                const SizedBox(width: 12),
                TvPillChip(
                  focusNode: _genrePillFocusNode,
                  label: _selectedGenre == 'All' ? 'Genre' : 'Genre: $_selectedGenre',
                  isSelected: _selectedGenre != 'All' || isGenreOpen,
                  onFocusChanged: (f) {
                    if (f) _lastFocusedPillNode = _genrePillFocusNode;
                  },
                  onKeyEvent: (node, event) => _handlePillKeyEvent(event, _genrePillFocusNode),
                  onTap: () => _openFilterStrip(SearchFilterDimension.genre, _genrePillFocusNode),
                ),
                const SizedBox(width: 12),
                TvPillChip(
                  focusNode: _yearPillFocusNode,
                  label: _selectedYear == 'All' ? 'Year' : 'Year: $_selectedYear',
                  isSelected: _selectedYear != 'All' || isYearOpen,
                  onFocusChanged: (f) {
                    if (f) _lastFocusedPillNode = _yearPillFocusNode;
                  },
                  onKeyEvent: (node, event) => _handlePillKeyEvent(event, _yearPillFocusNode),
                  onTap: () => _openFilterStrip(SearchFilterDimension.year, _yearPillFocusNode),
                ),
                const SizedBox(width: 12),
                TvPillChip(
                  focusNode: _ratingPillFocusNode,
                  label: _selectedRating == 'All' ? 'Rating' : 'Rating: $_selectedRating',
                  isSelected: _selectedRating != 'All' || isRatingOpen,
                  onFocusChanged: (f) {
                    if (f) _lastFocusedPillNode = _ratingPillFocusNode;
                  },
                  onKeyEvent: (node, event) => _handlePillKeyEvent(event, _ratingPillFocusNode),
                  onTap: () => _openFilterStrip(SearchFilterDimension.rating, _ratingPillFocusNode),
                ),
                const SizedBox(width: 12),
                TvPillChip(
                  focusNode: _sortPillFocusNode,
                  label: _selectedSort == 'Popular' ? 'Sort' : 'Sort: $_selectedSort',
                  isSelected: _selectedSort != 'Popular' || isSortOpen,
                  onFocusChanged: (f) {
                    if (f) _lastFocusedPillNode = _sortPillFocusNode;
                  },
                  onKeyEvent: (node, event) => _handlePillKeyEvent(event, _sortPillFocusNode),
                  onTap: () => _openFilterStrip(SearchFilterDimension.sort, _sortPillFocusNode),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        TvFocusButton(
          focusNode: _clearFiltersFocusNode,
          onKeyEvent: _handleClearFiltersKeyEvent,
          label: 'Clear Filters',
          icon: Icons.clear_rounded,
          isPrimary: false,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          fontSize: 13,
          onPressed: _clearFilters,
        ),
      ],
    );
  }

  Widget _buildGridArea() {
    if (_isLoading && _items.isEmpty) {
      return _buildSkeletonGrid();
    }

    if (_errorMessage != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: TVTheme.primary),
            const SizedBox(height: 16),
            Text(
              'Failed to search catalog: $_errorMessage',
              style: const TextStyle(color: TVTheme.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TvFocusButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: () => _executeSearch(reset: true),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _hasSearched ? Icons.search_off_rounded : Icons.search_rounded,
              size: 56,
              color: TVTheme.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              _hasSearched
                  ? 'No titles found matching "${_searchController.text.trim()}".'
                  : 'Search movies, TV shows, and actors using the search bar above.',
              style: const TextStyle(color: TVTheme.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (_hasSearched) ...[
              const SizedBox(height: 20),
              TvFocusButton(
                focusNode: _resetFiltersFocusNode,
                label: 'Reset Filters',
                icon: Icons.filter_alt_off_rounded,
                isPrimary: false,
                onPressed: _clearFilters,
              ),
            ],
          ],
        ),
      );
    }

    return CustomScrollView(
      key: const PageStorageKey('tv_search_grid'),
      controller: _gridScrollController,
      cacheExtent: 600,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: 150 / 225,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final movie = _items[index];
                return FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: 162,
                    height: 241,
                    child: TvFocusCard(
                      key: ValueKey('search_movie_${movie.imdbId}_$index'),
                      focusNode: _getCardFocusNode(index),
                      autofocus: index == 0 && _lastFocusedCardIndex == 0,
                      onKeyEvent: (node, event) => _handleCardKeyEvent(event, index),
                      posterUrl: movie.posterUrl,
                      title: movie.title,
                      rating: movie.ratingScore > 0 ? movie.ratingScore : null,
                      year: movie.year.isNotEmpty ? movie.year : null,
                      isTv: movie.isTv,
                      width: 150,
                      height: 225,
                      showTitleBelow: false,
                      onTap: () => _navigateToDetails(movie),
                      onFocusChanged: (focused) {
                        if (focused) {
                          _onCardFocused(index);
                        }
                      },
                    ),
                  ),
                );
              },
              childCount: _items.length,
            ),
          ),
        ),
        if (_isFetchingMore)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: TVTheme.primary),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Loading more titles...',
                    style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else if (!_hasMore && _items.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildEndOfResultsBanner(),
          ),
      ],
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 150 / 225,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: 10,
      itemBuilder: (context, index) => Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: FittedBox(
          fit: BoxFit.contain,
          child: Container(
            width: 150,
            height: 225,
            decoration: BoxDecoration(
              color: TVTheme.surfaceElevated,
              borderRadius: TVTheme.borderRadiusMd,
            ),
            child: const Center(
              child: Icon(
                Icons.movie_filter_outlined,
                size: 40,
                color: TVTheme.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndOfResultsBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 48, child: Divider(color: TVTheme.surfaceElevated, thickness: 1)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'End of Results',
              style: TextStyle(
                color: TVTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 48, child: Divider(color: TVTheme.surfaceElevated, thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildFilterStrip() {
    final dimension = _activeFilterDimension!;
    final title = _getFilterStripTitle(dimension);
    final options = _getFilterStripOptions(dimension);
    final selectedOption = _getCurrentFilterValue(dimension);

    return FocusScope(
      child: Container(
        decoration: BoxDecoration(
          color: TVTheme.surface,
          borderRadius: TVTheme.borderRadiusMd,
          border: Border.all(
            color: TVTheme.surfaceElevated,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: TVTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '‹ Back',
                  style: TextStyle(
                    fontSize: 12,
                    color: TVTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: TVTheme.surfaceElevated, height: 1),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option == selectedOption;
                  return _FilterOptionTile(
                    key: ValueKey('search_filter_option_${dimension.name}_$option'),
                    label: option,
                    isSelected: isSelected,
                    autofocus: isSelected,
                    isFirst: index == 0,
                    isLast: index == options.length - 1,
                    focusNode: index == 0 ? _firstFilterOptionFocusNode : null,
                    onSelect: () => _applyFilterOption(dimension, option),
                    onDismiss: _closeFilterStrip,
                    onLeft: () {
                      final idx = _items.isEmpty ? 0 : _lastFocusedCardIndex.clamp(0, _items.length - 1);
                      if (_items.isNotEmpty) {
                        _getCardFocusNode(idx).requestFocus();
                      } else if (_resetFiltersFocusNode.canRequestFocus) {
                        _resetFiltersFocusNode.requestFocus();
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvSearchInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final String hintText;
  final ValueChanged<String> onSubmitted;

  const _TvSearchInputField({
    required this.controller,
    required this.focusNode,
    this.autofocus = true,
    required this.hintText,
    required this.onSubmitted,
  });

  @override
  State<_TvSearchInputField> createState() => _TvSearchInputFieldState();
}

class _TvSearchInputFieldState extends State<_TvSearchInputField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TvSearchInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      _isFocused = widget.focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
    }
    if (_isFocused != widget.focusNode.hasFocus && mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: TVTheme.focusDuration,
      curve: TVTheme.focusCurve,
      decoration: BoxDecoration(
        color: TVTheme.surface,
        borderRadius: TVTheme.borderRadiusMd,
        border: Border.all(
          color: _isFocused ? Colors.white : Colors.transparent,
          width: _isFocused ? TVTheme.focusBorderWidth : 1.0,
        ),
        boxShadow: _isFocused ? TVTheme.focusShadows : TVTheme.restingShadows,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: TVTheme.textPrimary,
        ),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(color: TVTheme.textMuted, fontSize: 15),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          prefixIcon: const Icon(Icons.search_rounded, color: TVTheme.textMuted, size: 22),
          border: InputBorder.none,
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

class _FilterOptionTile extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool autofocus;
  final bool isFirst;
  final bool isLast;
  final FocusNode? focusNode;
  final VoidCallback onSelect;
  final VoidCallback onDismiss;
  final VoidCallback? onLeft;

  const _FilterOptionTile({
    super.key,
    required this.label,
    required this.isSelected,
    required this.autofocus,
    this.isFirst = false,
    this.isLast = false,
    this.focusNode,
    required this.onSelect,
    required this.onDismiss,
    this.onLeft,
  });

  @override
  State<_FilterOptionTile> createState() => _FilterOptionTileState();
}

class _FilterOptionTileState extends State<_FilterOptionTile> {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    if (widget.isSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Border border;

    if (_isFocused) {
      bgColor = widget.isSelected
          ? TVTheme.primary.withValues(alpha: 0.25)
          : TVTheme.surfaceElevated;
      border = Border.all(
        color: Colors.white,
        width: TVTheme.focusBorderWidth,
      );
    } else if (widget.isSelected) {
      bgColor = TVTheme.surfaceElevated;
      border = Border.all(
        color: TVTheme.primary.withValues(alpha: 0.7),
        width: 1.5,
      );
    } else {
      bgColor = Colors.transparent;
      border = Border.all(
        color: Colors.transparent,
        width: TVTheme.focusBorderWidth,
      );
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration.zero,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            widget.onDismiss();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onLeft?.call();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
          if (widget.isFirst && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            return KeyEventResult.handled;
          }
          if (widget.isLast && event.logicalKey == LogicalKeyboardKey.arrowDown) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: TVTheme.borderRadiusMd,
            border: border,
            boxShadow: _isFocused ? TVTheme.focusShadows : TVTheme.restingShadows,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: (_isFocused || widget.isSelected)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: (_isFocused || widget.isSelected)
                        ? TVTheme.textPrimary
                        : TVTheme.textSecondary,
                  ),
                ),
              ),
              if (widget.isSelected)
                Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: _isFocused ? Colors.white : TVTheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
