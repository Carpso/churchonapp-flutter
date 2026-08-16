import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import '../data/reporting_service.dart';

class ServiceReportScreen extends ConsumerStatefulWidget {
  const ServiceReportScreen({super.key});

  @override
  ConsumerState<ServiceReportScreen> createState() => _ServiceReportScreenState();
}

class _ServiceReportScreenState extends ConsumerState<ServiceReportScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _attendanceCtrl = TextEditingController();
  final _offeringCtrl = TextEditingController();
  final _testimonyCtrl = TextEditingController();
  String _reportType = 'service';
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (userProfile) {
        if (tenant == null) return const Scaffold(body: Center(child: Text("No Church Context")));

        final reportsAsync = ref.watch(reportsStreamProvider(tenant.id));

        return _buildScreen(context, tenant, userProfile, reportsAsync);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildScreen(BuildContext context, Tenant tenant, UserProfile? userProfile, AsyncValue<List<ServiceReport>> reportsAsync) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Ministry Reports", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildReportActionCard(tenant, userProfile),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            sliver: SliverToBoxAdapter(
              child: Text("Past Reports / Announcements", style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          reportsAsync.when(
            data: (reports) => SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildReportListItem(reports[index]),
                childCount: reports.length,
              ),
            ),
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            error: (e, s) => SliverFillRemaining(child: Center(child: Text("Error loading reports: $e"))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showReportForm(context, tenant, userProfile),
        label: const Text("New Report"),
        icon: const Icon(LucideIcons.plus),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildReportActionCard(Tenant tenant, UserProfile? profile) {
    final summaryAsync = ref.watch(churchServiceSummaryProvider(tenant.id));
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Theme.of(context).primaryColor, Theme.of(context).primaryColor.withValues(alpha: 0.8)]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.barChart3, color: Colors.white, size: 40),
          const SizedBox(height: 20),
          Text(
            "Service Dashboard",
            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            "Track attendance, offerings, and announcements for ${tenant.name}",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
          ),
          const SizedBox(height: 18),
          summaryAsync.when(
            data: (s) {
              final count = (s['service_count'] as num?)?.toInt() ?? 0;
              final attendance = (s['attendance'] as num?)?.toInt() ?? 0;
              final offering = (s['offering'] as num?)?.toDouble() ?? 0;
              final visitors = (s['visitors'] as num?)?.toInt() ?? 0;
              final salvations = (s['salvations'] as num?)?.toInt() ?? 0;
              final online = (s['online_viewers'] as num?)?.toInt() ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "THIS MONTH",
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _summaryChip(LucideIcons.calendarDays, "$count", "Services"),
                      const SizedBox(width: 10),
                      _summaryChip(LucideIcons.users, "$attendance", "Attended"),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _summaryChip(LucideIcons.banknote, "K${offering.toStringAsFixed(0)}", "Offering"),
                      const SizedBox(width: 10),
                      _summaryChip(LucideIcons.eye, "$online", "Online"),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _summaryChip(LucideIcons.userPlus, "$visitors", "Visitors"),
                      const SizedBox(width: 10),
                      _summaryChip(LucideIcons.heartHandshake, "$salvations", "Saved"),
                    ],
                  ),
                ],
              );
            },
            loading: () => SizedBox(
              height: 96,
              child: Center(
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13), overflow: TextOverflow.ellipsis),
                  Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportListItem(ServiceReport report) {
    final isAnnouncement = report.type == 'announcement';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (isAnnouncement ? Colors.amber : Theme.of(context).primaryColor).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  report.type.toUpperCase(),
                  style: TextStyle(color: isAnnouncement ? Colors.orange : Theme.of(context).primaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                "${report.date.day}/${report.date.month}/${report.date.year}",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(report.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(report.description, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          if (report.type == 'service') ...[
            const Divider(height: 30),
            Row(
              children: [
                _buildStatIcon(LucideIcons.users, "${report.attendance}"),
                const SizedBox(width: 25),
                _buildStatIcon(LucideIcons.banknote, "K ${report.offering.toStringAsFixed(0)}"),
              ],
            ),
          ],
          if (report.testimony.isNotEmpty) ...[
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade100)),
              child: Row(
                children: [
                  Icon(LucideIcons.quote, size: 14, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 10),
                  Expanded(child: Text(report.testimony, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatIcon(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  void _showReportForm(BuildContext context, Tenant tenant, UserProfile? profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        padding: const EdgeInsets.all(25),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 25),
              Text("Create New Entry", style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 25),
              
              // TYPE SELECTOR
              Row(
                children: [
                  _buildTypeBtn('service', 'Service Report', LucideIcons.calendar),
                  const SizedBox(width: 15),
                  _buildTypeBtn('announcement', 'Announcement', LucideIcons.megaphone),
                ],
              ),
              const SizedBox(height: 25),

              _buildInputField(_titleCtrl, "Title (e.g. Sunday Morning Glories)", LucideIcons.type),
              const SizedBox(height: 15),
              _buildInputField(_descCtrl, "Description / Key Message", LucideIcons.fileText, maxLines: 3),
              const SizedBox(height: 15),

              if (_reportType == 'service') ...[
                Row(
                  children: [
                    Expanded(child: _buildInputField(_attendanceCtrl, "Attendance", LucideIcons.users, keyboardType: TextInputType.number)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildInputField(_offeringCtrl, "Offering (K)", LucideIcons.banknote, keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 15),
                _buildInputField(_testimonyCtrl, "Key Testimony of the day", LucideIcons.heart, maxLines: 2),
                const SizedBox(height: 25),
              ],

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting ? null : () => _submitReport(tenant, profile),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isSubmitting 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("SUBMIT & SYNC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBtn(String type, String label, IconData icon) {
    bool isSelected = _reportType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _reportType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.grey[50],
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: isSelected ? Theme.of(context).primaryColor : Colors.transparent),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey, size: 20),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: isSelected ? Theme.of(context).primaryColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 20, color: Colors.grey),
        hintText: hint,
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }

  Future<void> _submitReport(Tenant tenant, UserProfile? profile) async {
    if (_titleCtrl.text.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final report = ServiceReport(
        id: '',
        tenantId: tenant.id,
        title: _titleCtrl.text,
        description: _descCtrl.text,
        attendance: int.tryParse(_attendanceCtrl.text) ?? 0,
        offering: double.tryParse(_offeringCtrl.text) ?? 0.0,
        testimony: _testimonyCtrl.text,
        date: DateTime.now(),
        reporterId: profile?.id ?? 'unknown',
        type: _reportType,
      );

      await ref.read(reportingServiceProvider).submitReport(report);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report synced successfully!"), backgroundColor: Colors.green));
        _titleCtrl.clear();
        _descCtrl.clear();
        _attendanceCtrl.clear();
        _offeringCtrl.clear();
        _testimonyCtrl.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sync failed: $e")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

