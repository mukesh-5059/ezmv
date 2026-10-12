import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _serverController;

  bool _isSavingServer = false;
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
    loadCacheInfo();
    _testCurrentConnection();
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
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

  Future<void> loadCacheInfo() async {
    try {
      final bytes = await CacheManager.getCacheSizeBytes();
      final count = await CacheManager.getCacheItemCount();
      if (mounted) {
        setState(() {
          _cacheSizeBytes = bytes;
          _cacheItemCount = count;
        });
      }
    } catch (_) {}
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

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent.shade700 : MobileTheme.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: MobileTheme.accent,
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            // BACKEND SERVER CONFIGURATION
            _buildSectionHeader('BACKEND SERVER CONFIGURATION'),
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
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Server API URL / IP',
                      labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      hintText: 'http://192.168.1.X:8080/api/v1',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: _isScanning
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                            )
                          : const Icon(Icons.wifi_find_rounded, size: 18),
                      label: Text(
                        _isScanning ? 'Scanning Network...' : 'Auto-Discover Server on LAN',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      onPressed: _isScanning ? null : _scanLan,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // CLIENT STORAGE & CACHING SECTION
            _buildSectionHeader('CLIENT STORAGE & CACHE'),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Local Data Cache',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$_cacheItemCount cached objects (${_formatBytes(_cacheSizeBytes)})',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 20),
                        tooltip: 'Refresh Stats',
                        onPressed: loadCacheInfo,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MobileTheme.accent,
                        side: BorderSide(color: MobileTheme.accent.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: _isClearingCache
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                            )
                          : const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Clear Storage Cache', style: TextStyle(fontSize: 12.5)),
                      onPressed: _isClearingCache ? null : _clearCache,
                    ),
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
}
