import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraSettingsScreen extends ConsumerStatefulWidget {
  const CameraSettingsScreen({super.key});

  @override
  ConsumerState<CameraSettingsScreen> createState() => _CameraSettingsScreenState();
}

class _CameraSettingsScreenState extends ConsumerState<CameraSettingsScreen> {
  PermissionStatus? _cameraStatus;
  bool _isChecking = true;
  String _currentQuality = 'medium';
  bool _isEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentQuality = prefs.getString('camera_quality') ?? 'medium';
      _isEnabled = prefs.getBool('camera_enabled') ?? false;
    });
  }

  Future<void> _checkPermission() async {
    setState(() => _isChecking = true);
    final status = await Permission.camera.status;
    setState(() {
      _cameraStatus = status;
      _isChecking = false;
    });
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    setState(() => _cameraStatus = status);
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<void> _setQuality(String quality) async {
    setState(() => _currentQuality = quality);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('camera_quality', quality);
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _isEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('camera_enabled', value);
    if (value && _cameraStatus != null && !_cameraStatus!.isGranted) {
      await _requestPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final qualities = [
      {'key': 'low', 'label': 'Low', 'desc': '480p - Saves storage'},
      {'key': 'medium', 'label': 'Medium', 'desc': '720p - Balanced'},
      {'key': 'high', 'label': 'High', 'desc': '1080p - Best quality'},
    ];

    String permissionLabel;
    Color permissionColor;
    IconData permissionIcon;

    if (_isChecking) {
      permissionLabel = 'Checking...';
      permissionColor = Colors.grey;
      permissionIcon = LucideIcons.hourglass;
    } else if (_cameraStatus == null) {
      permissionLabel = 'Unknown';
      permissionColor = Colors.grey;
      permissionIcon = LucideIcons.helpCircle;
    } else if (_cameraStatus!.isGranted) {
      permissionLabel = 'Granted';
      permissionColor = Colors.green;
      permissionIcon = LucideIcons.checkCircle;
    } else if (_cameraStatus!.isPermanentlyDenied) {
      permissionLabel = 'Denied (Open Settings)';
      permissionColor = Colors.red;
      permissionIcon = LucideIcons.shieldAlert;
    } else {
      permissionLabel = 'Not Granted';
      permissionColor = Colors.orange;
      permissionIcon = LucideIcons.xCircle;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('Camera Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildPermissionCard(theme, permissionColor, permissionIcon, permissionLabel),
          const SizedBox(height: 16),
          _buildEnabledCard(theme),
          const SizedBox(height: 16),
          _buildQualityCard(theme, qualities),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(ThemeData theme, Color permissionColor, IconData permissionIcon, String permissionLabel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERMISSION STATUS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: permissionColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(permissionIcon, color: permissionColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Camera Access',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      permissionLabel,
                      style: TextStyle(
                        color: permissionColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_cameraStatus != null && !_cameraStatus!.isGranted)
                TextButton(
                  onPressed: _cameraStatus!.isPermanentlyDenied
                      ? _openSettings
                      : _requestPermission,
                  child: Text(
                    _cameraStatus!.isPermanentlyDenied ? 'SETTINGS' : 'ALLOW',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnabledCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CAMERA ENABLED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
              Switch(
                value: _isEnabled,
                onChanged: _setEnabled,
                activeThumbColor: theme.primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Disable to prevent camera usage across the app',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityCard(ThemeData theme, List<Map<String, String>> qualities) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUALITY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          ...qualities.map((q) {
            final isSelected = _currentQuality == q['key'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _setQuality(q['key']!),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.primaryColor.withValues(alpha: 0.1)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? theme.primaryColor
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? theme.primaryColor
                            : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q['label']!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              q['desc']!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
