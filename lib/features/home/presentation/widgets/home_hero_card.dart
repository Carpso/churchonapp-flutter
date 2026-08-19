import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';

import 'package:church_on_app/features/finance/presentation/giving_screen.dart';
import 'package:church_on_app/features/connect/presentation/prayer_wall_screen.dart';
import 'package:church_on_app/features/home/presentation/sermon_notes_screen.dart';
import 'package:church_on_app/features/home/presentation/worship_lyrics_screen.dart';
import 'package:church_on_app/features/home/presentation/live_stream_screen.dart';
import 'package:church_on_app/features/bible_study/presentation/bible_study_list_screen.dart';

import '../../data/live_streaming_service.dart';

class HomeHeroCard extends ConsumerWidget {
  const HomeHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    final liveStatus = tenant != null
        ? ref.watch(liveStatusProvider(tenant.id)).value
        : null;

    final bool isLive = liveStatus?.isLive ?? false;
    final String title = isLive
        ? (liveStatus?.title ?? "Live Service")
        : (tenant != null
              ? "${tenant.name} Experience"
              : "Join our Sunday Experience");
    final String subtitle = isLive
        ? "WE ARE LIVE NOW"
        : (tenant != null ? "GLORY TO GOD" : "SUNDAY MORNING");
    final String timeLabel = isLive
        ? "${liveStatus?.viewerCount ?? 0} watching"
        : (tenant != null ? "Next Service: Sunday 09:00" : "Starts in 45 mins");

    final String? banner = tenant?.bannerUrl;
    final String bgImage = (banner != null && banner.isNotEmpty)
        ? banner
        : (tenant?.logoUrl ?? "");

    return Container(
      height: 245,
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppImage(
            bgImage,
            fit: BoxFit.cover,
            placeholder: _buildFallback(context, tenant),
            errorWidget: (_, __) => _buildFallback(context, tenant),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLive)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      "LIVE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDeepLink(
                          context, LucideIcons.bookOpen, "Bible Study"),
                      _buildDeepLink(context, LucideIcons.fileText, "Notes"),
                      _buildDeepLink(context, LucideIcons.music, "Lyrics"),
                      _buildDeepLink(context, LucideIcons.flame, "Prayer"),
                      _buildDeepLink(context, LucideIcons.heart, "Giving"),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Icon(
                      isLive ? LucideIcons.users : LucideIcons.clock,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      timeLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        final streamUrl = liveStatus?.streamUrl;
                        if (isLive &&
                            streamUrl != null &&
                            streamUrl.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LiveStreamScreen(
                                streamUrl: streamUrl,
                                title: liveStatus?.title ?? "Live Service",
                              ),
                            ),
                          );
                        } else {
                          if (tenant == null) {
                            context.push('/select-church');
                          } else {
                            _showServiceSchedule(context, ref, tenant);
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isLive
                              ? Theme.of(context).primaryColor
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isLive ? "JOIN LIVE" : "SCHEDULE",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            color: isLive
                                ? Theme.of(context).colorScheme.secondary
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallback(BuildContext context, Tenant? tenant) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          LucideIcons.church,
          size: 72,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  void _showServiceSchedule(
    BuildContext context,
    WidgetRef ref,
    Tenant tenant,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => _ServiceScheduleSheet(tenant: tenant, ref: ref),
    );
  }

  Widget _buildDeepLink(BuildContext context, IconData icon, String label) {
    String actionDescription;
    String actionTitle;
    if (label == "Giving") {
      actionDescription = "Share tithes and offerings";
      actionTitle = "Tithe & Offerings";
    } else if (label == "Prayer") {
      actionDescription = "Submit prayer requests to the prayer wall";
      actionTitle = "Prayer Wall";
    } else if (label == "Notes") {
      actionDescription = "Save and organize sermon notes digitally";
      actionTitle = "Sermon Notes";
    } else if (label == "Lyrics") {
      actionDescription = "Add and manage worship lyrics";
      actionTitle = "Worship Lyrics";
    } else if (label == "Bible Study") {
      actionDescription = "View this church's Bible studies and group sessions";
      actionTitle = "Bible Studies";
    } else {
      actionDescription = label;
      actionTitle = label;
    }

    return Container(
      margin: const EdgeInsets.only(right: 10),
      child: Semantics(
        label: "$label $actionDescription - $actionTitle",
        button: true,
        hint: actionTitle,
        child: ElevatedButton.icon(
          onPressed: () {
            if (label == "Giving") {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GivingScreen()),
              );
            } else if (label == "Prayer") {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PrayerWallScreen(),
                ),
              );
            } else if (label == "Notes") {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SermonNotesScreen(),
                ),
              );
            } else if (label == "Lyrics") {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WorshipLyricsScreen(),
                ),
              );
            } else if (label == "Bible Study") {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BibleStudyListScreen(),
                ),
              );
            }
          },
          icon: Icon(icon, color: Colors.white, size: 14),
          label: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white12,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceScheduleSheet extends ConsumerStatefulWidget {
  final Tenant tenant;
  final WidgetRef ref;
  const _ServiceScheduleSheet({required this.tenant, required this.ref});

  @override
  ConsumerState<_ServiceScheduleSheet> createState() =>
      _ServiceScheduleSheetState();
}

class _ServiceScheduleSheetState extends ConsumerState<_ServiceScheduleSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 30);
  bool _showScheduler = false;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(25, 25, 25, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.tenant.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "WEEKLY SERVICE SCHEDULE",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          const Divider(height: 30),
          _buildScheduleRow(
            "Sunday Main Service",
            "09:00 AM - 11:30 AM",
            "Main worship experience, sermon, and holy communion.",
            () {
              _titleCtrl.text = "Sunday Main Service";
              setState(() => _showScheduler = true);
            },
          ),
          _buildScheduleRow(
            "Wednesday Midweek",
            "06:00 PM - 07:30 PM",
            "Bible study, interactive teaching, and community prayers.",
            () {
              _titleCtrl.text = "Wednesday Midweek Service";
              setState(() => _showScheduler = true);
            },
          ),
          _buildScheduleRow(
            "Friday Deliverance",
            "06:00 PM - 08:00 PM",
            "Intercession, prayer fortress, and prophetic ministry.",
            () {
              _titleCtrl.text = "Friday Deliverance Service";
              setState(() => _showScheduler = true);
            },
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: () {
                _titleCtrl.clear();
                _descCtrl.clear();
                setState(() => _showScheduler = !_showScheduler);
              },
              icon: Icon(
                _showScheduler ? LucideIcons.chevronUp : LucideIcons.plus,
                size: 16,
              ),
              label: Text(_showScheduler ? "HIDE" : "SCHEDULE NEW EVENT"),
              style: TextButton.styleFrom(
                foregroundColor: Colors.amber.shade700,
              ),
            ),
          ),
          if (_showScheduler) ...[
            const Divider(height: 20),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: "Event Title",
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: "Description (optional)",
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) setState(() => _selectedDate = date);
                    },
                    icon: const Icon(LucideIcons.calendar, size: 14),
                    label: Text("${_selectedDate.month}/${_selectedDate.day}"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _startTime,
                      );
                      if (time != null) setState(() => _startTime = time);
                    },
                    icon: const Icon(LucideIcons.clock, size: 14),
                    label: Text(_startTime.format(context)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _endTime,
                      );
                      if (time != null) setState(() => _endTime = time);
                    },
                    icon: const Icon(LucideIcons.clock, size: 14),
                    label: Text(_endTime.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveEvent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "SAVE EVENT",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }

  Future<void> _saveEvent() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final start = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      final end = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _endTime.hour,
        _endTime.minute,
      );
      await Supabase.instance.client.from('events').insert({
        'tenant_id': widget.tenant.id,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'start_time': start.toIso8601String(),
        'end_time': end.toIso8601String(),
        'type': 'service',
        'status': 'scheduled',
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'hosted_by': Supabase.instance.client.auth.currentUser?.id,
      });
      if (mounted) {
        showAppSnackBar(
          context,
          "Event scheduled!",
          status: AppStatus.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildScheduleRow(
    String title,
    String time,
    String description,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.clock,
              size: 16,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    GestureDetector(
                      onTap: onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.bell,
                              size: 10,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              "SET",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
