import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _serverController;
  late TextEditingController _tmdbController;
  late TextEditingController _traktController;
  late TextEditingController _cdnController;

  CatalogSourceMode _sourceMode = ApiClient.catalogSourceMode;
  bool _obscureTmdb = true;

  bool _isSavingServer = false;
  bool _isSavingTmdb = false;
  bool _isSavingTrakt = false;
  bool _isSavingCdn = false;
  bool _isScanning = false;
  bool _isTesting = false;
  bool? _isConnected;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: ApiClient.baseUrl);
    _tmdbController = TextEditingController(text: ApiClient.tmdbApiKey);
    _traktController = TextEditingController(text: ApiClient.traktClientId);
    _cdnController = TextEditingController(text: ApiClient.cdnBaseUrl);
    _sourceMode = ApiClient.catalogSourceMode;

    if (_sourceMode == CatalogSourceMode.server) {
      _testCurrentConnection();
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _tmdbController.dispose();
    _traktController.dispose();
    _cdnController.dispose();
    super.dispose();
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(found ? 'Server discovered: ${ApiClient.baseUrl}' : 'No EzMV server found on LAN'),
          backgroundColor: MobileTheme.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
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
    setState(() => _isSavingTmdb = true);
    await ApiClient.setTmdbApiKey(_tmdbController.text.trim());
    if (mounted) {
      setState(() => _isSavingTmdb = false);
      _showToast(ApiClient.hasTmdbKey ? 'TMDb key configured successfully' : 'TMDb key cleared');
    }
  }

  Future<void> _saveTraktKey() async {
    setState(() => _isSavingTrakt = true);
    await ApiClient.setTraktClientId(_traktController.text.trim());
    if (mounted) {
      setState(() => _isSavingTrakt = false);
      _showToast(ApiClient.hasTraktKey ? 'Trakt Client ID configured' : 'Trakt Client ID cleared');
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

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: MobileTheme.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isServerless = _sourceMode == CatalogSourceMode.cdn;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
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
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
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
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      _buildStatusBadge(
                        configured: ApiClient.hasTmdbKey,
                        activeLabel: 'Configured ✓',
                        inactiveLabel: 'Required for Search',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tmdbController,
                    obscureText: _obscureTmdb,
                    decoration: InputDecoration(
                      hintText: 'Bearer Token (eyJ...) or 32-char API Key',
                      isDense: true,
                      filled: true,
                      fillColor: MobileTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MobileTheme.accent),
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
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      _buildStatusBadge(
                        configured: ApiClient.hasTraktKey,
                        activeLabel: 'Configured ✓',
                        inactiveLabel: 'Optional (Lists)',
                        isOptional: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _traktController,
                    decoration: InputDecoration(
                      hintText: 'Trakt Application Client ID',
                      isDense: true,
                      filled: true,
                      fillColor: MobileTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MobileTheme.accent),
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
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cdnController,
                    decoration: InputDecoration(
                      hintText: 'https://mukesh-5059.github.io/ezmv/catalog',
                      isDense: true,
                      filled: true,
                      fillColor: MobileTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MobileTheme.accent),
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
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
                    decoration: InputDecoration(
                      labelText: 'Server API URL / IP',
                      labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
                      hintText: 'http://192.168.1.100:8080/api/v1',
                      isDense: true,
                      filled: true,
                      fillColor: MobileTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MobileTheme.accent),
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

          // Preferences & History
          _buildSectionHeader('PREFERENCES & DATA'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: MobileTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
              title: const Text('Clear Watch History', style: TextStyle(color: Colors.white, fontSize: 14)),
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('EzMV Mobile Client', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('v1.0.0', style: TextStyle(color: MobileTheme.accent, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Hybrid serverless streaming engine with GitHub Actions catalog pipeline, direct TMDb & Trakt discovery, and subtitle integration powered by shared_core.',
                  style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
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
                fontWeight: FontWeight.bold,
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

  Widget _buildStatusBadge({
    required bool configured,
    required String activeLabel,
    required String inactiveLabel,
    bool isOptional = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: configured
            ? Colors.green.withValues(alpha: 0.15)
            : (isOptional ? Colors.white10 : Colors.amber.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: configured
              ? Colors.greenAccent.withValues(alpha: 0.5)
              : (isOptional ? Colors.white24 : Colors.amber.withValues(alpha: 0.5)),
          width: 0.8,
        ),
      ),
      child: Text(
        configured ? activeLabel : inactiveLabel,
        style: TextStyle(
          color: configured
              ? Colors.greenAccent
              : (isOptional ? Colors.white60 : Colors.amberAccent),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }
}
