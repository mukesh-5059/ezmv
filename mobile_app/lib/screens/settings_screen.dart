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
  bool _isSaving = false;
  bool _isScanning = false;
  bool _isTesting = false;
  bool? _isConnected;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: ApiClient.baseUrl);
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
    setState(() {
      _isScanning = true;
    });

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
          content: Text(found ? 'Server discovered & connected: ${ApiClient.baseUrl}' : 'No EzMV server found on LAN'),
          backgroundColor: MobileTheme.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveServer() async {
    final newUrl = _serverController.text.trim();
    if (newUrl.isEmpty) return;

    setState(() => _isSaving = true);
    final formatted = ApiClient.formatInputToUrl(newUrl);
    await ApiClient.setBaseUrl(formatted);
    _serverController.text = formatted;
    await _testCurrentConnection(formatted);

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server endpoint updated to $formatted'),
          backgroundColor: MobileTheme.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          // Connection Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MobileTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isConnected == true
                    ? Colors.green.withValues(alpha: 0.5)
                    : (_isConnected == false ? MobileTheme.accent.withValues(alpha: 0.5) : Colors.white12),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
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
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isConnected == true
                            ? 'Server Connected'
                            : (_isConnected == false ? 'Connection Offline' : 'Checking Connection...'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ApiClient.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _isTesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                        )
                      : const Icon(Icons.refresh_rounded, color: Colors.white70),
                  tooltip: 'Test Connection',
                  onPressed: _isTesting ? null : () => _testCurrentConnection(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Backend Configuration Section
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
                    suffixIcon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                              ),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.save_rounded, color: MobileTheme.accent),
                            tooltip: 'Save URL',
                            onPressed: _saveServer,
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Enter local IP (e.g. 192.168.1.50) or full URL. Supports automatic protocol/port formatting.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
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

          // Subtitles & Preferences
          _buildSectionHeader('PREFERENCES & DATA'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: MobileTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
                  title: const Text('Clear Watch History', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Delete saved playback history & resume checkpoints', style: TextStyle(color: Colors.white38, fontSize: 11)),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Watch history cleared'),
                            backgroundColor: MobileTheme.surfaceElevated,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
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
                  'High-performance streaming engine with dual scrapers, real-time SSE progress, and subtitle sync powered by shared_core.',
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
