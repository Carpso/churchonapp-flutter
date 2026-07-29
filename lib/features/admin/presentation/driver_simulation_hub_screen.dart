import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import '../../transport/data/transport_service.dart';
import '../../../core/providers/profile_provider.dart';

class DriverSimulationHubScreen extends ConsumerStatefulWidget {
  const DriverSimulationHubScreen({super.key});

  @override
  ConsumerState<DriverSimulationHubScreen> createState() => _DriverSimulationHubScreenState();
}

class _DriverSimulationHubScreenState extends ConsumerState<DriverSimulationHubScreen> {
  Timer? _simTimer;
  bool _isSimulating = false;
  LatLng _currentPos = const LatLng(-15.3875, 28.3228); // Lusaka Center
  String _statusMessage = "Simulator Ready";

  // Simulate a path toward a destination
  final LatLng _destination = const LatLng(-15.4166, 28.2833); // Cathedral Hill

  void _toggleSimulation() async {
    if (_isSimulating) {
      _simTimer?.cancel();
      setState(() {
        _isSimulating = false;
        _statusMessage = "Simulator Stopped";
      });
    } else {
      final profile = ref.read(profileProvider).value;
      if (profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Profile not loaded")));
        return;
      }

      setState(() {
        _isSimulating = true;
        _statusMessage = "Simulating Driver Movement...";
      });

      _simTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (!mounted) return;

        // Move 1% closer to destination each step
        double latStep = (_destination.latitude - _currentPos.latitude) * 0.05;
        double lngStep = (_destination.longitude - _currentPos.longitude) * 0.05;

        setState(() {
          _currentPos = LatLng(
            _currentPos.latitude + latStep,
            _currentPos.longitude + lngStep,
          );
        });

        // Push update to VPS
        await ref.read(transportServiceProvider).updateLocation(
          _currentPos.latitude,
          _currentPos.longitude,
        );
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
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("GPS Simulator", style: TextStyle(fontWeight: FontWeight.bold)),
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
          label: Text(_isSimulating ? "TERMINATE SIMULATION" : "INITIATE LIVE MOVEMENT"),
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
          const Icon(LucideIcons.info, color: Colors.blue),
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

