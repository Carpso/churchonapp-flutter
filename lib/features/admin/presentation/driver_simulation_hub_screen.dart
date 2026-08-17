import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../transport/data/transport_service.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/utils/location_permission_helper.dart';

class DriverSimulationHubScreen extends ConsumerStatefulWidget {
  const DriverSimulationHubScreen({super.key});

  @override
  ConsumerState<DriverSimulationHubScreen> createState() => _DriverSimulationHubScreenState();
}

class _DriverSimulationHubScreenState extends ConsumerState<DriverSimulationHubScreen> {
  Timer? _simTimer;
  bool _isSimulating = false;
  LatLng _currentPos = const LatLng(-15.3875, 28.3228); // Lusaka Center
  String _statusMessage = "Live GPS Ready";

  void _toggleSimulation() async {
    if (_isSimulating) {
      _simTimer?.cancel();
      setState(() {
        _isSimulating = false;
        _statusMessage = "Live GPS Stopped";
      });
    } else {
      final profile = ref.read(profileProvider).value;
      if (profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Profile not loaded")));
        return;
      }

      final granted = await LocationPermissionHelper.showDisclosureIfNeeded(
        context,
        purpose: 'Push your live GPS position to the church VPS so ride requests can reach you.',
      );
      if (!granted || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Location permission required to broadcast live GPS")),
          );
        }
        return;
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        setState(() {
          _currentPos = LatLng(pos.latitude, pos.longitude);
          _isSimulating = true;
          _statusMessage = "Broadcasting Live GPS...";
        });
        await ref.read(transportServiceProvider).updateLocation(pos.latitude, pos.longitude);
      } catch (e) {
        if (mounted) {
          setState(() => _statusMessage = "GPS Error: $e");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not read device GPS: $e"), backgroundColor: Colors.red),
          );
        }
        return;
      }

      _simTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        if (!mounted) return;
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          setState(() {
            _currentPos = LatLng(pos.latitude, pos.longitude);
          });
          await ref.read(transportServiceProvider).updateLocation(pos.latitude, pos.longitude);
        } catch (e) {
          debugPrint('Live GPS broadcast error: $e');
        }
      });
    }
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Live GPS Broadcast", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 30),
            _buildControlPanel(),
            const Spacer(),
            _buildSimulationInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: _isSimulating ? Colors.green[700] : Colors.blueGrey[800],
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
      ),
      child: Column(
        children: [
          Icon(_isSimulating ? LucideIcons.zap : LucideIcons.satellite, size: 40, color: Colors.white),
          const SizedBox(height: 15),
          Text(_statusMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          Text(
            "Lat: ${_currentPos.latitude.toStringAsFixed(5)} | Lng: ${_currentPos.longitude.toStringAsFixed(5)}",
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _toggleSimulation,
          icon: Icon(_isSimulating ? LucideIcons.stopCircle : LucideIcons.playCircle),
          label: Text(_isSimulating ? "STOP BROADCASTING" : "INITIATE LIVE GPS"),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isSimulating ? Colors.red : Colors.amber,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        const SizedBox(height: 15),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _currentPos = const LatLng(-15.3875, 28.3228);
            });
          },
          icon: const Icon(LucideIcons.refreshCcw),
          label: const Text("RESET COORDINATES"),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ],
    );
  }

  Widget _buildSimulationInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(LucideIcons.info, color: Theme.of(context).primaryColor),
          const SizedBox(width: 15),
          const Expanded(
            child: Text(
              "This simulator pushes real-time coordinate updates to your private VPS, allowing you to test Rider matching and tracking in a live environment.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

