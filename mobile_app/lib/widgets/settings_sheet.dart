import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SettingsSheet(),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late TextEditingController _serverController;
  bool _isSaving = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: ApiClient.baseUrl);
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _scanLan() async {
    setState(() => _isScanning = true);
    final found = await ApiClient.autoDiscoverAndConnect();
    if (mounted) {
      setState(() {
        _isScanning = false;
        if (found) {
          _serverController.text = ApiClient.baseUrl;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(found ? 'Server found: ${ApiClient.baseUrl}' : 'No server discovered on LAN'),
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
    await ApiClient.setBaseUrl(newUrl);
    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backend server updated to $newUrl'),
          backgroundColor: MobileTheme.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: MobileTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(Icons.settings_rounded, color: MobileTheme.accent, size: 22),
                SizedBox(width: 10),
                Text(
                  'Settings & Server',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 20),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              children: [
                // Server URL Section
                const Text(
                  'BACKEND SERVER URL',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _serverController,
                  decoration: InputDecoration(
                    hintText: 'http://192.168.1.x:8000',
                    isDense: true,
                    filled: true,
                    fillColor: MobileTheme.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check_rounded, color: MobileTheme.accent),
                      onPressed: _isSaving ? null : _saveServer,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Point this to your EzMV FastAPI backend server running on your local network or VPS.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 24),

                // Auto-Discover & Network
                const Text(
                  'LOCAL NETWORK',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Material(
                  color: MobileTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    leading: _isScanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                          )
                        : const Icon(Icons.wifi_find_rounded, color: MobileTheme.accent),
                    title: const Text('Auto-Discover Server on LAN', style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: const Text('Scan local network subnet for active EzMV servers', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                    onTap: _isScanning ? null : _scanLan,
                  ),
                ),
                const SizedBox(height: 24),

                // App Info
                const Text(
                  'ABOUT EZMV',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MobileTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EzMV Mobile Client v1.0.0', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      SizedBox(height: 4),
                      Text('High-performance Dart/Flutter streaming client powered by shared_core.', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
