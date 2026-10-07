import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

enum KeyStatus {
  notConfigured,
  configured,
  unverified,
  invalid,
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _serverController;
  late TextEditingController _tmdbController;
  late TextEditingController _traktController;
  late TextEditingController _cdnController;

  CatalogSourceMode _sourceMode = ApiClient.catalogSourceMode;
  bool _obscureTmdb = true;

  KeyStatus _tmdbStatus = KeyStatus.notConfigured;
  KeyStatus _traktStatus = KeyStatus.notConfigured;

  bool _isSavingServer = false;
  bool _isSavingTmdb = false;
  bool _isSavingTrakt = false;
  bool _isSavingCdn = false;
  bool _isScanning = false;
  bool _isTesting = false;
  bool? _isConnected;

  int _cacheSizeBytes = 0;
  int _cacheItemCount = 0;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: ApiClient.baseUrl);
    _tmdbController = TextEditingController(text: ApiClient.tmdbApiKey);
    _traktController = TextEditingController(text: ApiClient.traktClientId);
    _cdnController = TextEditingController(text: ApiClient.cdnBaseUrl);
    _sourceMode = ApiClient.catalogSourceMode;

    _tmdbStatus = ApiClient.hasTmdbKey ? KeyStatus.configured : KeyStatus.notConfigured;
    _traktStatus = ApiClient.hasTraktKey ? KeyStatus.configured : KeyStatus.notConfigured;

    _tmdbController.addListener(_onTmdbChanged);
    _traktController.addListener(_onTraktChanged);

    loadCacheInfo();

    if (_sourceMode == CatalogSourceMode.server) {
      _testCurrentConnection();
    }
  }

  @override
  void dispose() {
    _tmdbController.removeListener(_onTmdbChanged);
    _traktController.removeListener(_onTraktChanged);
    _serverController.dispose();
    _tmdbController.dispose();
    _traktController.dispose();
    _cdnController.dispose();
    super.dispose();
  }

  void _onTmdbChanged() {
    final text = _tmdbController.text.trim();
    if (text.isEmpty) {
      if (_tmdbStatus != KeyStatus.notConfigured) {
        setState(() => _tmdbStatus = KeyStatus.notConfigured);
      }
    } else if (text == ApiClient.tmdbApiKey && ApiClient.hasTmdbKey) {
      if (_tmdbStatus != KeyStatus.configured) {
        setState(() => _tmdbStatus = KeyStatus.configured);
      }
    } else {
      if (_tmdbStatus != KeyStatus.unverified && _tmdbStatus != KeyStatus.invalid) {
        setState(() => _tmdbStatus = KeyStatus.unverified);
      }
    }
  }

  void _onTraktChanged() {
    final text = _traktController.text.trim();
    if (text.isEmpty) {
      if (_traktStatus != KeyStatus.notConfigured) {
        setState(() => _traktStatus = KeyStatus.notConfigured);
      }
    } else if (text == ApiClient.traktClientId && ApiClient.hasTraktKey) {
      if (_traktStatus != KeyStatus.configured) {
        setState(() => _traktStatus = KeyStatus.configured);
      }
    } else {
      if (_traktStatus != KeyStatus.unverified && _traktStatus != KeyStatus.invalid) {
        setState(() => _traktStatus = KeyStatus.unverified);
      }
    }
  }

  Future<void> _setSourceMode(CatalogSourceMode mode) async {
    setState(() => _sourceMode = mode);
    await ApiClient.setCatalogSourceMode(mode);
    if (mode == CatalogSourceMode.server && _isConnected == null) {
      _testCurrentConnection();
    }
  }

  Future<void> _testCurrentConnection([String? url]) async {
    setState(() => _isTesting = true);
    final ok = await ApiClient.testConnection(url ?? _serverController.text.trim());
    if (mounted) {
      setState(() {
        _isConnected = ok;
        _isTesting = false;
      });
    }
  }

  Future<void> _scanLan() async {
    setState(() => _isScanning = true);
    final found = await ApiClient.autoDiscoverAndConnect();
    if (mounted) {
      setState(() {
        _isScanning = false;
        if (found) {
          _serverController.text = ApiClient.baseUrl;
          _isConnected = true;
        }
      });

      _showToast(
        found ? 'Server discovered: ${ApiClient.baseUrl}' : 'No EzMV server found on LAN',
        isError: !found,
      );
    }
  }

  Future<void> _saveServer() async {
    final newUrl = _serverController.text.trim();
    if (newUrl.isEmpty) return;

    setState(() => _isSavingServer = true);
    final formatted = ApiClient.formatInputToUrl(newUrl);
    await ApiClient.setBaseUrl(formatted);
    _serverController.text = formatted;
    await _testCurrentConnection(formatted);

    if (mounted) {
      setState(() => _isSavingServer = false);
      _showToast('Server URL saved');
    }
  }

  Future<void> _saveTmdbKey() async {
    final key = _tmdbController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _isSavingTmdb = true;
        _tmdbStatus = KeyStatus.notConfigured;
      });
      await ApiClient.setTmdbApiKey('');
      if (mounted) {
        setState(() => _isSavingTmdb = false);
        _showToast('TMDb key cleared');
      }
      return;
    }

    setState(() => _isSavingTmdb = true);
    final isValid = await ApiClient.verifyTmdbKey(key);
    if (mounted) {
      if (isValid) {
        await ApiClient.setTmdbApiKey(key);
        setState(() {
          _tmdbStatus = KeyStatus.configured;
          _isSavingTmdb = false;
        });
        _showToast('TMDb key verified and configured successfully');
      } else {
        setState(() {
          _tmdbStatus = KeyStatus.invalid;
          _isSavingTmdb = false;
        });
        _showToast('Invalid TMDb key. Please verify and retry.', isError: true);
      }
    }
  }

  Future<void> _saveTraktKey() async {
    final id = _traktController.text.trim();
    if (id.isEmpty) {
      setState(() {
        _isSavingTrakt = true;
        _traktStatus = KeyStatus.notConfigured;
      });
      await ApiClient.setTraktClientId('');
      if (mounted) {
        setState(() => _isSavingTrakt = false);
        _showToast('Trakt Client ID cleared');
      }
      return;
    }

    setState(() => _isSavingTrakt = true);
    final isValid = await ApiClient.verifyTraktClientId(id);
    if (mounted) {
      if (isValid) {
        await ApiClient.setTraktClientId(id);
        setState(() {
          _traktStatus = KeyStatus.configured;
          _isSavingTrakt = false;
        });
        _showToast('Trakt Client ID verified and configured');
      } else {
        setState(() {
          _traktStatus = KeyStatus.invalid;
          _isSavingTrakt = false;
        });
        _showToast('Invalid Trakt Client ID. Please verify and retry.', isError: true);
      }
    }
  }

  Future<void> _saveCdnUrl() async {
    final url = _cdnController.text.trim();
    if (url.isEmpty) return;
    setState(() => _isSavingCdn = true);
    await ApiClient.setCdnBaseUrl(url);
    if (mounted) {
      setState(() => _isSavingCdn = false);
      _showToast('CDN Base URL saved');
    }
  }

  void _showToast(String message, {bool isError = false}) {
    final bgColor = isError ? const Color(0xFFB91C1C) : const Color(0xFF15803D);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> loadCacheInfo() async {
    final bytes = await CacheManager.getCacheSizeBytes();
    final count = await CacheManager.getCacheItemCount();
    if (mounted) {
      setState(() {
        _cacheSizeBytes = bytes;
        _cacheItemCount = count;
      });
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isClearingCache = true);
    await CacheManager.clearAll();
    await loadCacheInfo();
    if (mounted) {
      setState(() => _isClearingCache = false);
      _showToast('Client storage cache cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isServerless = _sourceMode == CatalogSourceMode.cdn;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        color: MobileTheme.accent,
        backgroundColor: MobileTheme.surfaceElevated,
        onRefresh: loadCacheInfo,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
          // SOURCE MODE SELECTION CARD
          _buildSectionHeader('METADATA & CATALOG SOURCE'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MobileTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isServerless
                    ? MobileTheme.accent.withValues(alpha: 0.4)
                    : Colors.white12,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isServerless
                            ? MobileTheme.accent.withValues(alpha: 0.15)
                            : Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isServerless ? Icons.cloud_done_rounded : Icons.dns_rounded,
                        color: isServerless ? MobileTheme.accent : Colors.white70,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isServerless ? 'Self-Serving (Serverless)' : 'Dedicated Backend Server',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isServerless
                                ? 'Loads Tamil catalog via GitHub CDN & direct public APIs'
                                : 'Routes all catalog & search through FastAPI server',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildModeOption(
                        title: 'Self-Serving',
                        subtitle: 'Serverless CDN',
                        icon: Icons.public_rounded,
                        selected: isServerless,
                        onTap: () => _setSourceMode(CatalogSourceMode.cdn),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildModeOption(
                        title: 'Dedicated',
                        subtitle: 'Local / Remote Server',
                        icon: Icons.storage_rounded,
                        selected: !isServerless,
                        onTap: () => _setSourceMode(CatalogSourceMode.server),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // SERVERLESS CONFIGURATION SECTION
          if (isServerless) ...[
            _buildSectionHeader('API KEYS & SERVERLESS CONFIGURATION'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MobileTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TMDB Key Field
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TMDb Access Token / API Key',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 12.5),
                      ),
                      _buildStatusBadge(
                        _tmdbStatus,
                        notConfiguredLabel: 'Required for Search',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tmdbController,
                    obscureText: _obscureTmdb,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.normal),
                    decoration: InputDecoration(
                      hintText: 'Bearer Token (eyJ...) or 32-char API Key',
                      isDense: true,
                      filled: true,
                      fillColor: MobileTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MobileTheme.accent, width: 1.2),
                      ),
                      prefixIcon: const Icon(Icons.vpn_key_rounded, size: 18, color: Colors.white54),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscureTmdb ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 18,
                              color: Colors.white54,
                            ),
                            onPressed: () => setState(() => _obscureTmdb = !_obscureTmdb),
                          ),
                          _isSavingTmdb
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.save_rounded, color: MobileTheme.accent),
                                  tooltip: 'Save TMDb Key',
                                  onPressed: _saveTmdbKey,
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enables live movie search, TV episode guides, cast filmography, and detailed metadata. Get a free key at themoviedb.org.',
                    style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 20),

                  // Trakt Key Field
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Trakt.tv Client ID',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 12.5),
                      ),
                      _buildStatusBadge(
                        _traktStatus,
                        notConfiguredLabel: 'Optional (Lists)',
                        isOptional: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _traktController,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.normal),
                    decoration: InputDecoration(
                      hintText: 'Trakt Application Client ID',
                      isDense: true,
                      filled: true,
                      fillColor: MobileTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MobileTheme.accent, width: 1.2),
                      ),
                      prefixIcon: const Icon(Icons.list_alt_rounded, size: 18, color: Colors.white54),
                      suffixIcon: _isSavingTrakt
                          ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                                ),
                              )
                          : IconButton(
                              icon: const Icon(Icons.save_rounded, color: MobileTheme.accent),
                              tooltip: 'Save Trakt Client ID',
                              onPressed: _saveTraktKey,
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enables searching and browsing community curated movie & TV lists. Get a free client ID at trakt.tv/oauth/applications.',
                    style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 20),

                  // GitHub CDN URL Field
                  const Text(
                    'Catalog CDN Base URL',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 12.5),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cdnController,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.normal),
                    decoration: InputDecoration(
                      hintText: 'https://mukesh-5059.github.io/ezmv/catalog',
                      isDense: true,
                      filled: true,
                      fillColor: MobileTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MobileTheme.accent, width: 1.2),
                      ),
                      prefixIcon: const Icon(Icons.link_rounded, size: 18, color: Colors.white54),
                      suffixIcon: _isSavingCdn
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.save_rounded, color: MobileTheme.accent),
                              tooltip: 'Save CDN URL',
                              onPressed: _saveCdnUrl,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            // DEDICATED BACKEND SERVER CONFIGURATION SECTION
            _buildSectionHeader('DEDICATED BACKEND SERVER'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MobileTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isConnected == true
                              ? Colors.green.withValues(alpha: 0.15)
                              : (_isConnected == false ? MobileTheme.accent.withValues(alpha: 0.15) : Colors.white10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isConnected == true
                              ? Icons.cloud_done_rounded
                              : (_isConnected == false ? Icons.cloud_off_rounded : Icons.cloud_sync_rounded),
                          color: _isConnected == true
                              ? Colors.greenAccent
                              : (_isConnected == false ? MobileTheme.accent : Colors.white60),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isConnected == true
                              ? 'Server Online'
                              : (_isConnected == false ? 'Server Offline' : 'Checking Connection...'),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                      IconButton(
                        icon: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                              )
                            : const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                        tooltip: 'Test Connection',
                        onPressed: _isTesting ? null : () => _testCurrentConnection(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _serverController,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.normal),
                    decoration: InputDecoration(
                      labelText: 'Server API URL / IP',
                      labelStyle: const TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w500),
                      hintText: 'http://192.168.1.100:8080/api/v1',
                      isDense: true,
                      filled: true,
                      fillColor: MobileTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MobileTheme.accent, width: 1.2),
                      ),
                      suffixIcon: _isSavingServer
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.save_rounded, color: MobileTheme.accent),
                              tooltip: 'Save URL',
                              onPressed: _saveServer,
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isScanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                            )
                          : const Icon(Icons.wifi_find_rounded, color: MobileTheme.accent, size: 20),
                      label: Text(_isScanning ? 'Scanning Local Network...' : 'Auto-Discover Server on LAN'),
                      onPressed: _isScanning ? null : _scanLan,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Preferences & History & Cache
          _buildSectionHeader('PREFERENCES & STORAGE'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: MobileTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cached_rounded, color: Colors.white70),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Client Storage Cache',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: loadCacheInfo,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.refresh_rounded, size: 14, color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    _cacheItemCount > 0
                        ? '${CacheManager.formatBytes(_cacheSizeBytes)} • $_cacheItemCount cached items'
                        : '0 B • No cached entries',
                    style: TextStyle(
                      color: _cacheSizeBytes > 0 ? Colors.white70 : Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
                  trailing: _isClearingCache
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                        )
                      : TextButton(
                          onPressed: _cacheSizeBytes > 0 ? _clearCache : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            'Clear',
                            style: TextStyle(
                              color: _cacheSizeBytes > 0 ? Colors.redAccent : Colors.white24,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                ),
                const Divider(height: 1, color: Colors.white10),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
                  title: Text('Clear Watch History', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13.5, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Delete saved playback checkpoints & resume states', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: MobileTheme.surfaceElevated,
                        title: const Text('Clear Watch History?', style: TextStyle(color: Colors.white)),
                        content: const Text('This will remove all progress and history from this device.', style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: MobileTheme.accent),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await LocalStorage.clearHistory();
                      if (context.mounted) {
                        _showToast('Watch history cleared');
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // About App Section
          _buildSectionHeader('ABOUT'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MobileTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('EzMV Mobile Client', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600, fontSize: 13.5)),
                    const Text('v1.0.0', style: TextStyle(color: MobileTheme.accent, fontWeight: FontWeight.w600, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Hybrid serverless streaming engine with GitHub Actions catalog pipeline, direct TMDb & Trakt discovery, and subtitle integration powered by shared_core.',
                  style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    ),
  );
}

  Widget _buildModeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? MobileTheme.accent.withValues(alpha: 0.12)
              : MobileTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? MobileTheme.accent : Colors.white10,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? MobileTheme.accent : Colors.white60,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: selected ? MobileTheme.accent : Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    KeyStatus status, {
    String? notConfiguredLabel,
    bool isOptional = false,
  }) {
    Color bg;
    Color border;
    Color textColor;
    String label;

    switch (status) {
      case KeyStatus.configured:
        bg = const Color(0xFF15803D).withValues(alpha: 0.15);
        border = Colors.greenAccent.withValues(alpha: 0.5);
        textColor = Colors.greenAccent;
        label = 'Configured ✓';
        break;
      case KeyStatus.invalid:
        bg = const Color(0xFFB91C1C).withValues(alpha: 0.15);
        border = Colors.redAccent.withValues(alpha: 0.5);
        textColor = Colors.redAccent;
        label = 'Invalid Key ✗';
        break;
      case KeyStatus.unverified:
        bg = Colors.amber.withValues(alpha: 0.15);
        border = Colors.amberAccent.withValues(alpha: 0.5);
        textColor = Colors.amberAccent;
        label = 'Unsaved / Tap Save';
        break;
      case KeyStatus.notConfigured:
        bg = isOptional ? Colors.white10 : Colors.amber.withValues(alpha: 0.15);
        border = isOptional ? Colors.white24 : Colors.amber.withValues(alpha: 0.5);
        textColor = isOptional ? Colors.white60 : Colors.amberAccent;
        label = notConfiguredLabel ?? (isOptional ? 'Optional (Lists)' : 'Required for Search');
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}
