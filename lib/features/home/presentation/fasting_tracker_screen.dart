import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import '../data/fasting_service.dart';
import '../../connect/data/user_activity_service.dart';
import 'package:church_on_app/core/services/dnd_service.dart';
import 'fasting_history_screen.dart';

class FastingTrackerScreen extends ConsumerStatefulWidget {
  const FastingTrackerScreen({super.key});

  @override
  ConsumerState<FastingTrackerScreen> createState() => _FastingTrackerScreenState();
}

class _FastingTrackerScreenState extends ConsumerState<FastingTrackerScreen> with WidgetsBindingObserver {
  String _selectedFastType = "Daniel Fast";
  int _selectedDurationDays = 3;
  UserFast? _activeFast;
  bool _isLoading = true;
  bool _dndEnabled = false;

  Timer? _timer;
  Duration _timeLeft = Duration.zero;
  double _percentComplete = 0.0;

  final List<String> _fastTypes = ["Daniel Fast", "Partial Fast", "Full Water Fast", "Esther Fast (Dry)", "Tech Fast"];
  final List<Map<String, String>> _scriptures = [
    {"ref": "Isaiah 58:6", "text": "Is not this the fast that I have chosen? to loose the bands of wickedness, to undo the heavy burdens..."},
    {"ref": "Matthew 6:16", "text": "Moreover when ye fast, be not, as the hypocrites, of a sad countenance..."},
    {"ref": "Ezra 8:23", "text": "So we fasted and besought our God for this: and he was intreated of us."},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadActiveFast();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTimer();
    }
  }

  Future<void> _loadActiveFast() async {
    final fast = await ref.read(fastingServiceProvider).getActiveFast();
    if (mounted) {
      setState(() {
        _activeFast = fast;
        _isLoading = false;
        if (fast != null) {
          _selectedFastType = fast.fastType;
          _selectedDurationDays = fast.durationDays;
          _startTimer(fast);
        }
      });
    }
  }

  void _startTimer(UserFast fast) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshTimer());
    _refreshTimer();
  }

  void _refreshTimer() {
    final fast = _activeFast;
    if (fast == null) return;
    final now = DateTime.now();
    if (now.isAfter(fast.endTime)) {
      _timer?.cancel();
      _completeFast();
    } else {
      if (mounted) {
        setState(() {
          _timeLeft = fast.endTime.difference(now);
          _percentComplete = fast.percentComplete;
        });
      }
    }
  }

  Future<void> _startFast() async {
    try {
      final fast = await ref.read(fastingServiceProvider).startFast(_selectedFastType, _selectedDurationDays);
      ref.read(userActivityServiceProvider).logActivity(
        type: ActivityType.fastStarted,
        description: "Started a $_selectedFastType for $_selectedDurationDays days",
        coinsEarned: 15,
      );
      if (mounted) {
        setState(() {
          _activeFast = fast;
          _timeLeft = fast.endTime.difference(DateTime.now());
          _percentComplete = 0.0;
        });
        _startTimer(fast);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Fast started! 🕊️ +15 Church Coins"), backgroundColor: Colors.brown),
        );
      }
      ref.invalidate(activeFastProvider);
      ref.invalidate(fastHistoryProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error starting fast: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _stopFast() async {
    final fast = _activeFast;
    if (fast == null) return;
    _timer?.cancel();
    await DndService.disable();
    await DndService.stopAppMonitor();
    try {
      await ref.read(fastingServiceProvider).endFast(fast.id);
      if (mounted) {
        setState(() {
          _activeFast = null;
          _timeLeft = Duration.zero;
          _percentComplete = 0.0;
          _dndEnabled = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Fast ended"), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error ending fast: $e"), backgroundColor: Colors.red));
      }
    }
    ref.invalidate(activeFastProvider);
    ref.invalidate(fastHistoryProvider);
  }

  void _completeFast() async {
    final fast = _activeFast;
    if (fast == null) return;
    await DndService.disable();
    await DndService.stopAppMonitor();
    try {
      await ref.read(fastingServiceProvider).endFast(fast.id);
      ref.read(userActivityServiceProvider).logActivity(
        type: ActivityType.fastCompleted,
        description: "Completed a ${fast.fastType}",
        coinsEarned: 50,
      );
    } catch (e) {
      debugPrint("Error auto-completing fast: $e");
    }
    if (mounted) {
      setState(() {
        _activeFast = null;
        _dndEnabled = false;
      });
      _showVictoryDialog();
    }
    ref.invalidate(activeFastProvider);
    ref.invalidate(fastHistoryProvider);
  }

  Future<void> _toggleDnd(bool enable) async {
    if (enable) {
      final hasPerm = await DndService.hasPermission();
      if (hasPerm) {
        await DndService.enable();
      } else if (mounted) {
        await DndService.requestPermissionWithRationale(context);
        final nowHasPerm = await DndService.hasPermission();
        if (nowHasPerm) await DndService.enable();
      }

      if (mounted) {
        final hasUsage = await DndService.hasUsagePermission();
        if (!hasUsage && mounted) {
          await DndService.requestUsagePermissionWithRationale(context);
        }
      }

      await DndService.startAppMonitor();

      if (mounted) {
        setState(() => _dndEnabled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Focus Mode & App Blocker active — notifications silenced & social apps monitored! 🕊️"), backgroundColor: Colors.brown),
        );
      }
    } else {
      await DndService.disable();
      await DndService.stopAppMonitor();
      if (mounted) setState(() => _dndEnabled = false);
    }
  }

  void _showVictoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFDEFD5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.flame, color: Colors.orange, size: 70),
            SizedBox(height: 20),
            Text("FAST COMPLETED!", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.brown)),
            SizedBox(height: 10),
            Text("Well done! Your dedication and spiritual discipline are highly edifying.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$hours:$mins:$secs";
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text("Fasting Tracker", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.brown,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Spiritual Fasting Tracker", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.history),
            tooltip: "Fasting History",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FastingHistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            if (_activeFast == null) _buildSetupView() else _buildTimerView(),
            const SizedBox(height: 30),
            _buildScripturesCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupView() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.brown.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Begin a Spiritual Fast", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
          const SizedBox(height: 20),
          const Text("Fast Type", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedFastType,
            decoration: InputDecoration(
              fillColor: const Color(0xFFF8FAFC),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
            items: _fastTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
            onChanged: (val) => setState(() => _selectedFastType = val!),
          ),
          const SizedBox(height: 20),
          const Text("Duration (Days)", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [1, 3, 7, 21, 40].map((days) {
              final isSelected = _selectedDurationDays == days;
              return GestureDetector(
                onTap: () => setState(() => _selectedDurationDays = days),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.brown : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "$days d",
                    style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 35),
          ElevatedButton.icon(
            onPressed: _startFast,
            icon: const Icon(LucideIcons.play),
            label: const Text("START FAST"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.brown,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTimerView() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.brown.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Text(_selectedFastType.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 25),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: CircularProgressIndicator(
                  value: _percentComplete,
                  strokeWidth: 10,
                  backgroundColor: const Color(0xFFF1F5F9),
                  color: Colors.orange,
                ),
              ),
              Column(
                children: [
                  const Text("TIME REMAINING", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_formatDuration(_timeLeft), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const SizedBox(height: 5),
                  Text("${(_percentComplete * 100).toStringAsFixed(1)}% Completed", style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(LucideIcons.moon, color: _dndEnabled ? Colors.indigo : Colors.grey, size: 20),
              const SizedBox(width: 8),
              const Text("Focus Mode", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              Switch(
                value: _dndEnabled,
                onChanged: _toggleDnd,
                activeThumbColor: Colors.indigo,
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _stopFast,
                  icon: const Icon(LucideIcons.square),
                  label: const Text("END FAST"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildScripturesCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.brown.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.bookOpen, color: Colors.brown, size: 20),
              SizedBox(width: 10),
              Text("Scriptures on Fasting", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 20),
          ..._scriptures.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s["ref"]!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown)),
                const SizedBox(height: 5),
                Text('"${s["text"]!}"', style: const TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
