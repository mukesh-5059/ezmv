import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/tv_focus_button.dart';
import '../widgets/tv_shortcuts.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedCategory = 0; // 0: Audio & Subs, 1: Stream Ranking, 2: Cache & Storage, 3: Server Endpoint

  String _preferredAudio = 'Tamil';
  String _preferredSubtitle = 'English';
  StreamQualityPreference _preferredQuality = StreamQualityPreference.auto;
  FileSizePreference _fileSizePref = FileSizePreference.balanced;
  bool _prioritizeAudio = true;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _repoController = TextEditingController();

  late final List<FocusNode> _categoryFocusNodes = List.generate(
    _categories.length,
    (_) => FocusNode(),
  );
  final FocusNode _firstSettingFocus = FocusNode();
  final FocusNode _serverInputFocusNode = FocusNode();
  final FocusNode _saveServerButtonFocus = FocusNode();
  final FocusNode _resetServerButtonFocus = FocusNode();
  final FocusNode _repoInputFocusNode = FocusNode();
  final FocusNode _syncRepoButtonFocus = FocusNode();
  final FocusNode _saveRepoButtonFocus = FocusNode();
  final FocusNode _resetRepoButtonFocus = FocusNode();
  final FocusNode _resetOverridesButtonFocus = FocusNode();
  final FocusNode _backButtonFocus = FocusNode();

  final Map<String, FocusNode> _sourceFocusNodes = {};
  String? _lastRepoSyncTime;
  List<Map<String, dynamic>> _installedSources = [];
  bool _isSyncingRepo = false;

  late final FocusScopeNode _navScopeNode = FocusScopeNode(
    debugLabel: 'NavScope',
  )..directionalTraversalEdgeBehavior = TraversalEdgeBehavior.stop;

  late final FocusScopeNode _contentScopeNode = FocusScopeNode(
    debugLabel: 'ContentScope',
  )..directionalTraversalEdgeBehavior = TraversalEdgeBehavior.stop;

  String _lastFocusedTarget = 'Screen Mount';

  void _logFocusTransition(String toTarget) {
    if (_lastFocusedTarget == toTarget) return;
    debugPrint('[TV-NAV][Settings] Focus: from [$_lastFocusedTarget] -> to [$toTarget]');
    _lastFocusedTarget = toTarget;
  }

  FocusNode _getSourceFocusNode(String id) {
    return _sourceFocusNodes.putIfAbsent(id, () => FocusNode());
  }

  bool _isLoading = true;
  String? _statusBanner;

  final List<({String title, String subtitle, IconData icon})> _categories = const [
    (title: 'Audio & Subtitles', subtitle: 'Preferred playback tracks', icon: Icons.audiotrack),
    (title: 'Stream Ranking', subtitle: 'Quality & size scoring', icon: Icons.tune),
    (title: 'Extension Repo', subtitle: 'Scraper repo & source configs', icon: Icons.extension),
    (title: 'Data & Cache', subtitle: 'Storage & scrapers reset', icon: Icons.cleaning_services),
    (title: 'Server Endpoint', subtitle: 'EzMV backend address', icon: Icons.dns),
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('[TV-NAV][Settings] Screen mounted, initializing settings');
    _serverInputFocusNode.addListener(_onServerInputFocus);
    _serverInputFocusNode.onKeyEvent = _handleServerInputKeyEvent;
    _repoInputFocusNode.addListener(_onRepoInputFocus);
    _repoInputFocusNode.onKeyEvent = _handleRepoInputKeyEvent;
    _loadSettings();
  }

  void _onServerInputFocus() {
    if (_serverInputFocusNode.hasFocus) {
      _logFocusTransition('Input: Backend API Base URL');
    }
  }

  void _onRepoInputFocus() {
    if (_repoInputFocusNode.hasFocus) {
      _logFocusTransition('Input: Scraper Repository URL');
    }
  }

  KeyEventResult _handleRepoInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.goBack) {
        debugPrint('[TV-NAV][Settings] Back/Escape key in Repo URL field -> returning to Category nav');
        node.unfocus();
        _categoryFocusNodes[_selectedCategory].requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        debugPrint('[TV-NAV][Settings] D-pad Down from [Input: Scraper Repo URL] -> Sync button');
        _syncRepoButtonFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_repoController.selection.baseOffset <= 0) {
          debugPrint('[TV-NAV][Settings] D-pad Left from [Input: Scraper Repo URL] -> back to Category nav');
          node.unfocus();
          _categoryFocusNodes[_selectedCategory].requestFocus();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleServerInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.goBack) {
        debugPrint('[TV-NAV][Settings] Back/Escape key in TextField -> returning to Category nav');
        node.unfocus();
        _categoryFocusNodes[_selectedCategory].requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        debugPrint('[TV-NAV][Settings] D-pad Down from [Input: Backend API Base URL] -> Save button');
        _saveServerButtonFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_ipController.selection.baseOffset <= 0) {
          debugPrint('[TV-NAV][Settings] D-pad Left from [Input: Backend API Base URL] -> back to Category nav');
          node.unfocus();
          _categoryFocusNodes[_selectedCategory].requestFocus();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadSettings() async {
    final audio = await AppSettingsService.instance.getPreferredAudioLanguage();
    final sub = await AppSettingsService.instance.getPreferredSubtitleLanguage();
    final quality = await AppSettingsService.instance.getPreferredQuality();
    final size = await AppSettingsService.instance.getFileSizePreference();
    final prioAudio = await AppSettingsService.instance.getPrioritizePreferredAudio();
    final repoUrl = await AppSettingsService.instance.getScraperRepoUrl();
    final lastSync = await AppSettingsService.instance.getLastRepoSyncTime();
    final sources = await AppSettingsService.instance.getInstalledSources(
      fallbackConfig: SourceOrchestrator.defaultSourcesConfig,
    );
    _ipController.text = ApiClient.instance.baseUrl;
    _repoController.text = repoUrl;

    debugPrint('[TV-SETTINGS] Loaded: audio=$audio, sub=$sub, quality=${quality.label}, size=${size.label}, prioritizeAudio=$prioAudio, repo=$repoUrl, sources=${sources.length}');

    if (mounted) {
      setState(() {
        _preferredAudio = audio;
        _preferredSubtitle = sub;
        _preferredQuality = quality;
        _fileSizePref = size;
        _prioritizeAudio = prioAudio;
        _lastRepoSyncTime = lastSync;
        _installedSources = sources;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _categoryFocusNodes[0].requestFocus();
      });
    }
  }

  @override
  void dispose() {
    debugPrint('[TV-NAV][Settings] Disposing SettingsScreen');
    _serverInputFocusNode.removeListener(_onServerInputFocus);
    _serverInputFocusNode.dispose();
    _repoInputFocusNode.removeListener(_onRepoInputFocus);
    _repoInputFocusNode.dispose();
    _ipController.dispose();
    _repoController.dispose();
    _syncRepoButtonFocus.dispose();
    _saveRepoButtonFocus.dispose();
    _resetRepoButtonFocus.dispose();
    _resetOverridesButtonFocus.dispose();
    for (final node in _sourceFocusNodes.values) {
      node.dispose();
    }
    for (final node in _categoryFocusNodes) {
      node.dispose();
    }
    _firstSettingFocus.dispose();
    _saveServerButtonFocus.dispose();
    _resetServerButtonFocus.dispose();
    _backButtonFocus.dispose();
    _navScopeNode.dispose();
    _contentScopeNode.dispose();
    super.dispose();
  }

  Future<void> _saveRepoUrl() async {
    final input = _repoController.text.trim();
    if (input.isNotEmpty) {
      await AppSettingsService.instance.setScraperRepoUrl(input);
      debugPrint('[TV-SETTINGS][Repo] Saved custom repo URL: $input');
      _showFeedback('Scraper repository URL saved.');
    }
  }

  Future<void> _resetRepoUrl() async {
    await AppSettingsService.instance.resetScraperRepoUrl();
    _repoController.text = AppSettingsService.defaultRepoUrl;
    debugPrint('[TV-SETTINGS][Repo] Repo URL reset to default');
    _showFeedback('Repository URL reset to default.');
  }

  Future<void> _syncExtensions() async {
    if (_isSyncingRepo) return;
    setState(() => _isSyncingRepo = true);
    debugPrint('[TV-SETTINGS][Sync] Syncing extensions from ${_repoController.text}');
    _showFeedback('Fetching scraper extensions and router manifest...');
    final result = await SourceOrchestrator.syncRemoteRepo();
    final sources = await AppSettingsService.instance.getInstalledSources(
      fallbackConfig: SourceOrchestrator.defaultSourcesConfig,
    );
    final lastSync = await AppSettingsService.instance.getLastRepoSyncTime();
    if (mounted) {
      setState(() {
        _isSyncingRepo = false;
        _installedSources = sources;
        _lastRepoSyncTime = lastSync;
      });
      _showFeedback(result.message);
    }
  }

  Future<void> _toggleSource(String id, bool currentVal, String name) async {
    final nextVal = !currentVal;
    debugPrint('[TV-SETTINGS][Source] Toggling $name ($id): $currentVal -> $nextVal');
    await AppSettingsService.instance.setSourceEnabled(id, nextVal);
    final sources = await AppSettingsService.instance.getInstalledSources(
      fallbackConfig: SourceOrchestrator.defaultSourcesConfig,
    );
    if (mounted) {
      setState(() => _installedSources = sources);
      _showFeedback('$name: ${nextVal ? "ENABLED" : "DISABLED"}');
    }
  }

  Future<void> _resetAllOverrides() async {
    debugPrint('[TV-SETTINGS][Source] Resetting all source overrides');
    await AppSettingsService.instance.resetSourceOverrides();
    final sources = await AppSettingsService.instance.getInstalledSources(
      fallbackConfig: SourceOrchestrator.defaultSourcesConfig,
    );
    if (mounted) {
      setState(() => _installedSources = sources);
      _showFeedback('All source configs restored to manifest defaults.');
    }
  }

  void _showFeedback(String msg) {
    if (!mounted) return;
    debugPrint('[TV-SETTINGS][Feedback] $msg');
    setState(() => _statusBanner = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _statusBanner == msg) {
        setState(() => _statusBanner = null);
      }
    });
  }

  Future<void> _saveServerEndpoint() async {
    var input = _ipController.text.trim();
    if (input.isNotEmpty) {
      if (!input.startsWith('http://') && !input.startsWith('https://')) {
        input = input.contains(':') && !input.contains('.') ? 'http://$input' : 'https://$input';
      }
      ApiClient.instance = ApiClient(baseUrl: input);
      await StorageService.instance.setApiBaseUrl(input);
      debugPrint('[TV-SETTINGS][Server] Base URL updated to: $input');
      _showFeedback('Server URL saved: $input');
    }
  }

  Future<void> _resetServerEndpoint() async {
    await StorageService.instance.resetApiBaseUrl();
    ApiClient.instance = ApiClient();
    _ipController.text = ApiClient.defaultBaseUrl;
    debugPrint('[TV-SETTINGS][Server] Base URL reset to default: ${ApiClient.defaultBaseUrl}');
    _showFeedback('Server URL reset to default.');
  }

  Widget _buildCategoryNav() {
    return Container(
      width: 270,
      decoration: const BoxDecoration(
        color: TVTheme.surface,
        border: Border(right: BorderSide(color: Colors.white12, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: TVTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: TVTheme.primary.withValues(alpha: 0.6)),
                ),
                child: const Icon(Icons.settings, color: TVTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    'EzMV TV Preferences',
                    style: TextStyle(fontSize: 11, color: TVTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (int i = 0; i < _categories.length; i++)
                  _buildCategoryTile(
                    index: i,
                    category: _categories[i],
                    focusNode: _categoryFocusNodes[i],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TvFocusButton(
            focusNode: _backButtonFocus,
            label: 'Exit Settings',
            icon: Icons.arrow_back,
            isPrimary: false,
            onFocusChanged: (f) {
              if (f) _logFocusTransition('Button: Exit Settings');
            },
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  debugPrint('[TV-NAV][Settings] D-pad Right from [Button: Exit Settings] -> moving to setting options');
                  if (_selectedCategory == 2) {
                    _repoInputFocusNode.requestFocus();
                  } else if (_selectedCategory == 4) {
                    _serverInputFocusNode.requestFocus();
                  } else {
                    _firstSettingFocus.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _categoryFocusNodes[_categories.length - 1].requestFocus();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            onPressed: () {
              debugPrint('[TV-NAV][Settings] Exit button pressed');
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required int index,
    required ({String title, String subtitle, IconData icon}) category,
    FocusNode? focusNode,
  }) {
    final isSelected = _selectedCategory == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (f) {
          if (f) {
            _logFocusTransition('Category: ${category.title}');
            setState(() => _selectedCategory = index);
          }
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              debugPrint('[TV-NAV][Settings] D-pad Right from [Category: ${category.title}] -> moving to setting options');
              if (index == 2) {
                _repoInputFocusNode.requestFocus();
              } else if (index == 4) {
                _serverInputFocusNode.requestFocus();
              } else {
                _firstSettingFocus.requestFocus();
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final isFocused = Focus.of(ctx).hasFocus;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isFocused
                    ? TVTheme.primary
                    : isSelected
                        ? TVTheme.surfaceElevated
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFocused ? Colors.white : (isSelected ? TVTheme.primary.withValues(alpha: 0.5) : Colors.transparent),
                  width: isFocused ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    category.icon,
                    size: 20,
                    color: isFocused ? Colors.white : (isSelected ? TVTheme.primary : TVTheme.textMuted),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isFocused || isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isFocused || isSelected ? Colors.white : TVTheme.textSecondary,
                          ),
                        ),
                        Text(
                          category.subtitle,
                          style: TextStyle(
                            fontSize: 10,
                            color: isFocused ? Colors.white70 : TVTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCycleOptionTile({
    required String title,
    required String subtitle,
    required String currentValue,
    required List<String> options,
    required ValueChanged<String> onChanged,
    FocusNode? focusNode,
  }) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) {
        if (f) _logFocusTransition('Setting: $title ($currentValue)');
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _categoryFocusNodes[_selectedCategory].requestFocus();
            debugPrint('[TV-NAV][Settings] D-pad Left from [Setting: $title] -> back to Category nav');
            return KeyEventResult.handled;
          }
          if (TvShortcuts.isActivateKey(event.logicalKey) || event.logicalKey == LogicalKeyboardKey.arrowRight) {
            final idx = options.indexOf(currentValue);
            final next = options[(idx + 1) % options.length];
            debugPrint('[TV-SETTINGS] Cycled [$title]: $currentValue -> $next');
            onChanged(next);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isFocused ? TVTheme.surfaceElevated : TVTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFocused ? TVTheme.primary : Colors.white12,
                width: isFocused ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: TVTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: isFocused ? TVTheme.primary : Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isFocused ? Colors.white30 : Colors.white12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chevron_left, size: 16, color: Colors.white70),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          currentValue,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: Colors.white70),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    FocusNode? focusNode,
  }) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) {
        if (f) _logFocusTransition('Toggle: $title (${value ? "ON" : "OFF"})');
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _categoryFocusNodes[_selectedCategory].requestFocus();
            debugPrint('[TV-NAV][Settings] D-pad Left from [Toggle: $title] -> back to Category nav');
            return KeyEventResult.handled;
          }
          if (TvShortcuts.isActivateKey(event.logicalKey) || event.logicalKey == LogicalKeyboardKey.arrowRight) {
            debugPrint('[TV-SETTINGS] Toggled [$title]: $value -> ${!value}');
            onChanged(!value);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isFocused ? TVTheme.surfaceElevated : TVTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFocused ? TVTheme.primary : Colors.white12,
                width: isFocused ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: TVTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: value ? TVTheme.primary : Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    value ? 'ON' : 'OFF',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: value ? Colors.white : TVTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required String buttonLabel,
    required IconData icon,
    required VoidCallback onAction,
    bool isDestructive = false,
    FocusNode? focusNode,
  }) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) {
        if (f) _logFocusTransition('Action: $title [$buttonLabel]');
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _categoryFocusNodes[_selectedCategory].requestFocus();
            debugPrint('[TV-NAV][Settings] D-pad Left from [Action: $title] -> back to Category nav');
            return KeyEventResult.handled;
          }
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            debugPrint('[TV-SETTINGS] Action triggered: [$title]');
            onAction();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isFocused ? TVTheme.surfaceElevated : TVTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFocused ? (isDestructive ? Colors.redAccent : TVTheme.primary) : Colors.white12,
                width: isFocused ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 12, color: TVTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFocused
                        ? (isDestructive ? Colors.red.shade900 : TVTheme.primary)
                        : Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: onAction,
                  icon: Icon(icon, size: 16),
                  label: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMiniActionButton({
    required FocusNode focusNode,
    required IconData icon,
    String? label,
    String? tooltip,
    required VoidCallback onPressed,
    bool isPrimary = false,
    bool escapeToCategoryOnLeft = false,
    FocusNode? leftFocusNode,
    FocusNode? rightFocusNode,
    FocusNode? downFocusNode,
    FocusNode? upFocusNode,
  }) {
    final displayLabel = label ?? tooltip ?? 'Action';
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) {
        if (f) _logFocusTransition('Button: $displayLabel');
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (leftFocusNode != null) {
              debugPrint('[TV-NAV][Settings] D-pad Left from [Button: $displayLabel] -> previous button');
              leftFocusNode.requestFocus();
              return KeyEventResult.handled;
            } else if (escapeToCategoryOnLeft) {
              debugPrint('[TV-NAV][Settings] D-pad Left from [Button: $displayLabel] -> back to Category nav');
              _categoryFocusNodes[_selectedCategory].requestFocus();
              return KeyEventResult.handled;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && rightFocusNode != null) {
            debugPrint('[TV-NAV][Settings] D-pad Right from [Button: $displayLabel] -> next button');
            rightFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && downFocusNode != null) {
            debugPrint('[TV-NAV][Settings] D-pad Down from [Button: $displayLabel] -> below');
            downFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && upFocusNode != null) {
            debugPrint('[TV-NAV][Settings] D-pad Up from [Button: $displayLabel] -> above');
            upFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          if (label == null || label.isEmpty) {
            return Tooltip(
              message: tooltip ?? displayLabel,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFocused
                      ? TVTheme.primary
                      : (isPrimary ? TVTheme.primary.withValues(alpha: 0.8) : TVTheme.surfaceElevated),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(10),
                  minimumSize: const Size(40, 40),
                  side: BorderSide(
                    color: isFocused ? Colors.white : Colors.transparent,
                    width: isFocused ? 2 : 1,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: onPressed,
                child: Icon(icon, size: 18),
              ),
            );
          }
          return ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isFocused
                  ? TVTheme.primary
                  : (isPrimary ? TVTheme.primary.withValues(alpha: 0.8) : TVTheme.surfaceElevated),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              side: BorderSide(
                color: isFocused ? Colors.white : Colors.transparent,
                width: isFocused ? 2 : 1,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          );
        },
      ),
    );
  }

  Widget _buildSourceCard(Map<String, dynamic> source) {
    final id = source['id']?.toString() ?? 'unknown';
    final name = source['name']?.toString() ?? id;
    final isExtractor = source['source_type'] == 'extractor';
    final isEnabled = source['enabled'] != false;
    final scriptOrUrl = isExtractor ? (source['script_url'] ?? '') : (source['manifest_url'] ?? '');
    final node = _getSourceFocusNode(id);

    return Focus(
      focusNode: node,
      onFocusChange: (f) {
        if (f) _logFocusTransition('Source: $name (${isEnabled ? "ON" : "OFF"})');
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            debugPrint('[TV-NAV][Settings] D-pad Left from [Source: $name] -> back to Category nav');
            _categoryFocusNodes[_selectedCategory].requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
              _installedSources.isNotEmpty &&
              id == _installedSources.first['id']?.toString()) {
            debugPrint('[TV-NAV][Settings] D-pad Up from first source -> Reset Overrides button');
            _resetOverridesButtonFocus.requestFocus();
            return KeyEventResult.handled;
          }
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            _toggleSource(id, isEnabled, name);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isFocused ? TVTheme.surfaceElevated : TVTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isFocused ? TVTheme.primary : (isEnabled ? Colors.white12 : Colors.white10),
                width: isFocused ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isExtractor ? Icons.javascript : Icons.hub,
                      size: 20,
                      color: isFocused ? TVTheme.primary : (isEnabled ? Colors.white70 : TVTheme.textMuted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isEnabled ? Colors.white : TVTheme.textMuted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isExtractor
                                      ? Colors.orange.shade900.withValues(alpha: 0.4)
                                      : Colors.blue.shade900.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isExtractor ? 'QuickJS' : 'Addon',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isExtractor ? Colors.orangeAccent : Colors.lightBlueAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'ID: $id • $scriptOrUrl',
                            style: const TextStyle(fontSize: 11, color: TVTheme.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isEnabled ? TVTheme.primary : Colors.white10,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isEnabled ? 'ON' : 'OFF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? Colors.white : TVTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isFocused) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Press OK to Toggle On/Off',
                    style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: TVTheme.primary));
    }

    Widget content;
    switch (_selectedCategory) {
      case 0:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCycleOptionTile(
              focusNode: _firstSettingFocus,
              title: 'Preferred Audio Language',
              subtitle: 'Prioritizes audio stream tracks matching this language.',
              currentValue: _preferredAudio,
              options: AppSettingsService.availableAudioLanguages,
              onChanged: (lang) async {
                setState(() => _preferredAudio = lang);
                await AppSettingsService.instance.setPreferredAudioLanguage(lang);
                _showFeedback('Audio preference set to $lang');
              },
            ),
            _buildCycleOptionTile(
              title: 'Preferred Subtitle Language',
              subtitle: 'Automatically activates subtitle tracks in this language.',
              currentValue: _preferredSubtitle,
              options: AppSettingsService.availableSubtitleLanguages,
              onChanged: (sub) async {
                setState(() => _preferredSubtitle = sub);
                await AppSettingsService.instance.setPreferredSubtitleLanguage(sub);
                _showFeedback('Subtitle preference set to $sub');
              },
            ),
          ],
        );
        break;

      case 1:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCycleOptionTile(
              focusNode: _firstSettingFocus,
              title: 'Target Stream Quality',
              subtitle: 'Boosts resolution tiers in the automated ranking formula.',
              currentValue: _preferredQuality.label,
              options: StreamQualityPreference.values.map((v) => v.label).toList(),
              onChanged: (label) async {
                final pref = StreamQualityPreference.values.firstWhere((v) => v.label == label);
                setState(() => _preferredQuality = pref);
                await AppSettingsService.instance.setPreferredQuality(pref);
                _showFeedback('Quality preference set to ${pref.label}');
              },
            ),
            _buildCycleOptionTile(
              title: 'File Size Target',
              subtitle: 'Prefers smaller files for quick playback or higher bitrates.',
              currentValue: _fileSizePref.label,
              options: FileSizePreference.values.map((v) => v.label).toList(),
              onChanged: (label) async {
                final pref = FileSizePreference.values.firstWhere((v) => v.label == label);
                setState(() => _fileSizePref = pref);
                await AppSettingsService.instance.setFileSizePreference(pref);
                _showFeedback('File size preference set to ${pref.label}');
              },
            ),
            _buildToggleTile(
              title: 'Prioritize Audio Match in Ranking',
              subtitle: 'Forces streams with your preferred audio language to top ranks.',
              value: _prioritizeAudio,
              onChanged: (val) async {
                setState(() => _prioritizeAudio = val);
                await AppSettingsService.instance.setPrioritizePreferredAudio(val);
                _showFeedback('Audio ranking boost: ${val ? "ON" : "OFF"}');
              },
            ),
          ],
        );
        break;

      case 2:
        final activeCount = _installedSources.where((s) => s['enabled'] != false).length;
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TVTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Scraper Repository URL',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (_lastRepoSyncTime != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: TVTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            'Last Sync: $_lastRepoSyncTime',
                            style: const TextStyle(fontSize: 11, color: TVTheme.textSecondary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Remote endpoint hosting sources.json manifest and QuickJS scraper extractors.',
                    style: TextStyle(fontSize: 12, color: TVTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    focusNode: _repoInputFocusNode,
                    controller: _repoController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: TVTheme.surfaceElevated,
                      hintText: AppSettingsService.defaultRepoUrl,
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: TVTheme.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _buildMiniActionButton(
                        focusNode: _syncRepoButtonFocus,
                        icon: _isSyncingRepo ? Icons.hourglass_top : Icons.sync,
                        label: _isSyncingRepo ? 'Syncing...' : 'Sync & Update Now',
                        isPrimary: true,
                        escapeToCategoryOnLeft: true,
                        rightFocusNode: _saveRepoButtonFocus,
                        upFocusNode: _repoInputFocusNode,
                        downFocusNode: _installedSources.isNotEmpty ? _resetOverridesButtonFocus : null,
                        onPressed: _syncExtensions,
                      ),
                      _buildMiniActionButton(
                        focusNode: _saveRepoButtonFocus,
                        icon: Icons.save,
                        label: 'Save Repo URL',
                        isPrimary: false,
                        leftFocusNode: _syncRepoButtonFocus,
                        rightFocusNode: _resetRepoButtonFocus,
                        upFocusNode: _repoInputFocusNode,
                        downFocusNode: _installedSources.isNotEmpty ? _resetOverridesButtonFocus : null,
                        onPressed: _saveRepoUrl,
                      ),
                      _buildMiniActionButton(
                        focusNode: _resetRepoButtonFocus,
                        icon: Icons.restore,
                        label: 'Reset Repo',
                        isPrimary: false,
                        leftFocusNode: _saveRepoButtonFocus,
                        upFocusNode: _repoInputFocusNode,
                        downFocusNode: _installedSources.isNotEmpty ? _resetOverridesButtonFocus : null,
                        onPressed: _resetRepoUrl,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Installed Sources & Overrides',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$activeCount of ${_installedSources.length} active. Press OK to Toggle.',
                      style: const TextStyle(fontSize: 12, color: TVTheme.textMuted),
                    ),
                  ],
                ),
                if (_installedSources.isNotEmpty)
                  _buildMiniActionButton(
                    focusNode: _resetOverridesButtonFocus,
                    icon: Icons.restart_alt,
                    tooltip: 'Reset Overrides',
                    escapeToCategoryOnLeft: true,
                    upFocusNode: _resetRepoButtonFocus,
                    downFocusNode: _installedSources.isNotEmpty
                        ? _getSourceFocusNode(_installedSources.first['id']?.toString() ?? '')
                        : null,
                    isPrimary: false,
                    onPressed: _resetAllOverrides,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final source in _installedSources)
              _buildSourceCard(source),
          ],
        );
        break;

      case 3:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActionTile(
              focusNode: _firstSettingFocus,
              title: 'Clear Continue Watching',
              subtitle: 'Resets all active playback progress and resume points.',
              buttonLabel: 'Clear History',
              icon: Icons.history,
              isDestructive: true,
              onAction: () async {
                debugPrint('[TV-CACHE] Clearing continue watching history');
                await AppSettingsService.instance.clearWatchHistory();
                _showFeedback('Watch history cleared successfully.');
              },
            ),
            _buildActionTile(
              title: 'Clear Scraper Scripts Cache',
              subtitle: 'Removes local cache of JS extractors and forces fresh remote pull.',
              buttonLabel: 'Purge Cache',
              icon: Icons.cached,
              onAction: () async {
                debugPrint('[TV-CACHE] Purging scraper cache');
                await AppSettingsService.instance.clearScraperCache();
                SourceOrchestrator.clearMemoryCache();
                _showFeedback('Scraper cache purged. Next search will fetch latest scrapers.');
              },
            ),
            _buildActionTile(
              title: 'Reset Settings to Default',
              subtitle: 'Restores all audio, quality, endpoint, repo, and source preferences.',
              buttonLabel: 'Reset All',
              icon: Icons.restore,
              isDestructive: true,
              onAction: () async {
                debugPrint('[TV-SETTINGS] Resetting all settings to default');
                await AppSettingsService.instance.resetAllSettings();
                await _loadSettings();
                _showFeedback('All settings restored to defaults.');
              },
            ),
          ],
        );
        break;

      case 4:
      default:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TVTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Backend API Base URL',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'EzMV Cloudflare Worker or local backend endpoint address.',
                    style: TextStyle(fontSize: 12, color: TVTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    focusNode: _serverInputFocusNode,
                    controller: _ipController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onSubmitted: (_) {
                      _saveServerEndpoint();
                      _saveServerButtonFocus.requestFocus();
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: TVTheme.surfaceElevated,
                      hintText: 'https://backend-revised.mkdummy2025.workers.dev',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: TVTheme.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildMiniActionButton(
                        focusNode: _saveServerButtonFocus,
                        icon: Icons.save,
                        label: 'Save Server URL',
                        isPrimary: true,
                        escapeToCategoryOnLeft: true,
                        rightFocusNode: _resetServerButtonFocus,
                        upFocusNode: _serverInputFocusNode,
                        onPressed: _saveServerEndpoint,
                      ),
                      const SizedBox(width: 12),
                      _buildMiniActionButton(
                        focusNode: _resetServerButtonFocus,
                        icon: Icons.restore,
                        label: 'Reset to Default',
                        leftFocusNode: _saveServerButtonFocus,
                        upFocusNode: _serverInputFocusNode,
                        onPressed: _resetServerEndpoint,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_contentScopeNode.hasFocus) {
          debugPrint('[TV-NAV][Settings] Back key in content panel -> returning to Category nav');
          _contentScopeNode.unfocus();
          _categoryFocusNodes[_selectedCategory].requestFocus();
          return;
        }
        debugPrint('[TV-NAV][Settings] Back key in Category nav -> exiting screen');
        Navigator.of(context).pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: TVTheme.background,
        body: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack) {
                if (_contentScopeNode.hasFocus) {
                  debugPrint('[TV-NAV][Settings] Escape key in content panel -> returning to Category nav');
                  _contentScopeNode.unfocus();
                  _categoryFocusNodes[_selectedCategory].requestFocus();
                  return KeyEventResult.handled;
                }
                debugPrint('[TV-NAV][Settings] Escape key in Category nav -> exiting screen');
                Navigator.of(context).pop();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: SafeArea(
            child: Column(
              children: [
                if (_statusBanner != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    color: TVTheme.primary,
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusBanner!,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      FocusScope(
                        node: _navScopeNode,
                        child: FocusTraversalGroup(
                          policy: WidgetOrderTraversalPolicy(),
                          child: _buildCategoryNav(),
                        ),
                      ),
                      Expanded(
                        child: FocusScope(
                          node: _contentScopeNode,
                          child: FocusTraversalGroup(
                            policy: WidgetOrderTraversalPolicy(),
                            child: _buildSettingsContent(),
                          ),
                        ),
                      ),
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
}
