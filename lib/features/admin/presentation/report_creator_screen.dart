import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

enum ReportType { weekly, monthly, custom }

class ReportData {
  final int attendance;
  final double giving;
  final int newMembers;
  final int events;
  final int sermons;

  ReportData({
    this.attendance = 0,
    this.giving = 0.0,
    this.newMembers = 0,
    this.events = 0,
    this.sermons = 0,
  });
}

final reportCreatorServiceProvider = Provider((ref) => ReportCreatorService(Supabase.instance.client));

class ReportCreatorService {
  final SupabaseClient _client;
  ReportCreatorService(this._client);

  Future<int> getAttendance(String tenantId, DateTime start, DateTime end) async {
    final res = await _client
        .from('attendance_logs')
        .select('id')
        .eq('tenant_id', tenantId)
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String());
    return (res as List).length;
  }

  Future<double> getGiving(String tenantId, DateTime start, DateTime end) async {
    final res = await _client
        .from('transactions')
        .select('amount, currency')
        .eq('tenant_id', tenantId)
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String());
    final data = res as List;
    return data.fold<double>(0.0, (sum, item) {
      final amt = item['amount'];
      if (amt == null) return sum;
      return sum + (amt as num).toDouble();
    });
  }

  Future<int> getNewMembers(String tenantId, DateTime start, DateTime end) async {
    final res = await _client
        .from('profiles')
        .select('id')
        .eq('tenant_id', tenantId)
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String());
    return (res as List).length;
  }

  Future<int> getEvents(String tenantId, DateTime start, DateTime end) async {
    final res = await _client
        .from('events')
        .select('id')
        .eq('tenant_id', tenantId)
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String());
    return (res as List).length;
  }

  Future<int> getSermons(String tenantId, DateTime start, DateTime end) async {
    final res = await _client
        .from('sermons')
        .select('id')
        .eq('tenant_id', tenantId)
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String());
    return (res as List).length;
  }

  Future<ReportData> generateReport({
    required String tenantId,
    required DateTime start,
    required DateTime end,
    required bool includeAttendance,
    required bool includeGiving,
    required bool includeNewMembers,
    required bool includeEvents,
    required bool includeSermons,
  }) async {
    final futures = <Future>[];
    int? attendance;
    double? giving;
    int? newMembers;
    int? events;
    int? sermons;

    if (includeAttendance) futures.add(getAttendance(tenantId, start, end).then((v) => attendance = v));
    if (includeGiving) futures.add(getGiving(tenantId, start, end).then((v) => giving = v));
    if (includeNewMembers) futures.add(getNewMembers(tenantId, start, end).then((v) => newMembers = v));
    if (includeEvents) futures.add(getEvents(tenantId, start, end).then((v) => events = v));
    if (includeSermons) futures.add(getSermons(tenantId, start, end).then((v) => sermons = v));

    await Future.wait(futures);

    return ReportData(
      attendance: attendance ?? 0,
      giving: giving ?? 0.0,
      newMembers: newMembers ?? 0,
      events: events ?? 0,
      sermons: sermons ?? 0,
    );
  }
}

class ReportCreatorScreen extends ConsumerStatefulWidget {
  const ReportCreatorScreen({super.key});

  @override
  ConsumerState<ReportCreatorScreen> createState() => _ReportCreatorScreenState();
}

class _ReportCreatorScreenState extends ConsumerState<ReportCreatorScreen> {
  ReportType _reportType = ReportType.weekly;
  DateTimeRange? _dateRange;
  bool _includeAttendance = true;
  bool _includeGiving = true;
  bool _includeNewMembers = true;
  bool _includeEvents = true;
  bool _includeSermons = true;
  bool _isGenerating = false;
  ReportData? _reportData;

  @override
  void initState() {
    super.initState();
    _updateDateRangeForType();
  }

  void _updateDateRangeForType() {
    final now = DateTime.now();
    switch (_reportType) {
      case ReportType.weekly:
        final weekday = now.weekday;
        final start = now.subtract(Duration(days: weekday - 1));
        _dateRange = DateTimeRange(start: DateTime(start.year, start.month, start.day), end: DateTime(now.year, now.month, now.day));
        break;
      case ReportType.monthly:
        _dateRange = DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month, now.day));
        break;
      case ReportType.custom:
        break;
    }
  }

  void _onReportTypeChanged(ReportType? type) {
    if (type == null) return;
    setState(() {
      _reportType = type;
      if (type != ReportType.custom) {
        _updateDateRangeForType();
      }
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: Colors.amber.shade700),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _generateReport() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;
    if (_dateRange == null) return;

    setState(() {
      _isGenerating = true;
      _reportData = null;
    });

    try {
      final service = ref.read(reportCreatorServiceProvider);
      final data = await service.generateReport(
        tenantId: tenant.id,
        start: _dateRange!.start,
        end: _dateRange!.end,
        includeAttendance: _includeAttendance,
        includeGiving: _includeGiving,
        includeNewMembers: _includeNewMembers,
        includeEvents: _includeEvents,
        includeSermons: _includeSermons,
      );
      if (!mounted) return;
      setState(() {
        _reportData = data;
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error generating report: $e")));
    }
  }

  void _shareReport() {
    if (_reportData == null || _dateRange == null) return;
    final df = DateFormat('MMM d, yyyy');
    final buf = StringBuffer();
    buf.writeln("Church Report");
    buf.writeln("${df.format(_dateRange!.start)} - ${df.format(_dateRange!.end)}");
    buf.writeln("");

    if (_includeAttendance) buf.writeln("Attendance: ${_reportData!.attendance}");
    if (_includeGiving) buf.writeln("Giving: K ${_reportData!.giving.toStringAsFixed(2)}");
    if (_includeNewMembers) buf.writeln("New Members: ${_reportData!.newMembers}");
    if (_includeEvents) buf.writeln("Events: ${_reportData!.events}");
    if (_includeSermons) buf.writeln("Sermons: ${_reportData!.sermons}");

    SharePlus.instance.share(ShareParams(text: buf.toString()));
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (userProfile) {
        if (tenant == null) {
          return Scaffold(
            backgroundColor: const Color(0xFFFFFAEB),
            appBar: AppBar(title: const Text("Report Creator")),
            body: const Center(child: Text("No Church Context")),
          );
        }
        return Scaffold(
          backgroundColor: const Color(0xFFFFFAEB),
          appBar: AppBar(
            title: Text("Report Creator", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildReportTypeSelector(),
                const SizedBox(height: 20),
                _buildDateRangeCard(),
                const SizedBox(height: 20),
                _buildMetricsCard(),
                const SizedBox(height: 20),
                _buildGenerateButton(),
                const SizedBox(height: 20),
                if (_isGenerating) _buildLoadingState(),
                if (_reportData != null && !_isGenerating) _buildPreviewSection(),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildReportTypeSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Report Period", style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: _buildTypeChip(ReportType.weekly, "Weekly", LucideIcons.calendarDays)),
              const SizedBox(width: 10),
              Expanded(child: _buildTypeChip(ReportType.monthly, "Monthly", LucideIcons.calendarRange)),
              const SizedBox(width: 10),
              Expanded(child: _buildTypeChip(ReportType.custom, "Custom", LucideIcons.sliders)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(ReportType type, String label, IconData icon) {
    final isSelected = _reportType == type;
    return GestureDetector(
      onTap: () => _onReportTypeChanged(type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withValues(alpha: 0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? Colors.amber : Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: isSelected ? Colors.amber.shade700 : Colors.grey),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.amber.shade700 : Colors.grey,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeCard() {
    final df = DateFormat('MMM d, yyyy');
    return GestureDetector(
      onTap: _pickDateRange,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(LucideIcons.calendar, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Date Range", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    _dateRange != null
                        ? "${df.format(_dateRange!.start)} - ${df.format(_dateRange!.end)}"
                        : "Tap to select dates",
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Metrics to Include", style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          _buildMetricCheckbox(LucideIcons.users, "Attendance", _includeAttendance, (v) => setState(() => _includeAttendance = v ?? false)),
          _buildMetricCheckbox(LucideIcons.banknote, "Giving", _includeGiving, (v) => setState(() => _includeGiving = v ?? false)),
          _buildMetricCheckbox(LucideIcons.userPlus, "New Members", _includeNewMembers, (v) => setState(() => _includeNewMembers = v ?? false)),
          _buildMetricCheckbox(LucideIcons.calendarCheck, "Events", _includeEvents, (v) => setState(() => _includeEvents = v ?? false)),
          _buildMetricCheckbox(LucideIcons.mic2, "Sermons", _includeSermons, (v) => setState(() => _includeSermons = v ?? false)),
        ],
      ),
    );
  }

  Widget _buildMetricCheckbox(IconData icon, String label, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.amber.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: (_isGenerating || _dateRange == null) ? null : _generateReport,
        icon: _isGenerating
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(LucideIcons.fileBarChart),
        label: Text(_isGenerating ? "Generating..." : "Generate Report",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber.shade700,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(color: Colors.amber),
          SizedBox(height: 20),
          Text("Compiling church data...", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPreviewSection() {
    if (_reportData == null) return const SizedBox.shrink();
    final data = _reportData!;
    final df = DateFormat('MMM d, yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.fileBarChart, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Church Report", style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                        "${df.format(_dateRange!.start)} - ${df.format(_dateRange!.end)}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 30),
              if (_includeAttendance) _buildMetricRow(LucideIcons.users, "Attendance", "${data.attendance}", Colors.blue),
              if (_includeGiving) _buildMetricRow(LucideIcons.banknote, "Giving", "K ${data.giving.toStringAsFixed(2)}", Colors.green),
              if (_includeNewMembers) _buildMetricRow(LucideIcons.userPlus, "New Members", "${data.newMembers}", Colors.purple),
              if (_includeEvents) _buildMetricRow(LucideIcons.calendarCheck, "Events", "${data.events}", Colors.orange),
              if (_includeSermons) _buildMetricRow(LucideIcons.mic2, "Sermons", "${data.sermons}", Colors.teal),
            ],
          ),
        ),
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _shareReport,
            icon: const Icon(LucideIcons.share2),
            label: const Text("Export / Share", style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}
