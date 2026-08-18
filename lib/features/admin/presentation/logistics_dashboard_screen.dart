import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

/// Logistics Command — church bus fleet dashboard (tenant-scoped).
/// Superadmins/COA see the whole fleet; church admins see their own buses.
class LogisticsDashboardScreen extends ConsumerStatefulWidget {
  const LogisticsDashboardScreen({super.key});

  @override
  ConsumerState<LogisticsDashboardScreen> createState() => _LogisticsDashboardScreenState();
}

class _LogisticsDashboardScreenState extends ConsumerState<LogisticsDashboardScreen> {
  List<Map<String, dynamic>> _buses = [];
  bool _isLoading = true;
  String? _error;
  String _loadedFor = '';
  UserProfile? _profile;

  bool get _isGlobal =>
      _profile?.role == 'superadmin' || _profile?.role == 'coa_employee';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBuses(null));
  }

  /// Reloads whenever the signed-in profile (role/tenant) changes.
  void _listenToProfile() {
    ref.listen(profileProvider, (prev, next) {
      final profile = next.value;
      final key = profile == null ? '' : '${profile.role}|${profile.tenantId}';
      if (key != _loadedFor) {
        _loadedFor = key;
        _loadBuses(profile);
      }
    });
  }

  Future<void> _loadBuses(UserProfile? userProfile) async {
    setState(() => _isLoading = true);
    _error = null;
    _profile = userProfile;
    try {
      final client = Supabase.instance.client;

      dynamic query = client.from('church_buses').select('*');
      if (!_isGlobal) {
        final tenantId = userProfile?.tenantId;
        if (tenantId == null || tenantId.isEmpty) {
          _buses = [];
        } else {
          query = query.eq('tenant_id', tenantId);
        }
      }
      final res = await query.order('created_at', ascending: false);
      _buses = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Logistics dashboard load failed: $e');
      _error = e.toString();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _isLive(Map<String, dynamic> bus) {
    final updated = DateTime.tryParse(bus['updated_at']?.toString() ?? '');
    return (bus['is_active'] as bool? ?? false) &&
        updated != null &&
        updated.isAfter(DateTime.now().subtract(const Duration(minutes: 5)));
  }

  int _stopCount(Map<String, dynamic> bus) {
    final stops = bus['stops'];
    if (stops is List) return stops.length;
    if (stops is String) {
      try {
        return (jsonDecode(stops) as List).length;
      } catch (_) {}
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    _listenToProfile();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text("Logistics Command", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: () => _loadBuses(_profile))],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : _error != null
              ? Center(child: Text("Error: $_error", style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: () => _loadBuses(null),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(25),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHighlightGrid(theme),
                        const SizedBox(height: 40),
                        Text(
                          _isGlobal ? "Church Bus Fleet" : "Our Bus Fleet",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                        ),
                        const SizedBox(height: 20),
                        if (_buses.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              children: [
                                Icon(LucideIcons.bus, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                                const SizedBox(height: 15),
                                Text(
                                  _isGlobal ? "No church buses registered yet." : "Your church hasn't registered a bus yet.",
                                  style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._buses.map((bus) => _buildBusCard(theme, bus)),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHighlightGrid(ThemeData theme) {
    final active = _buses.where((b) => _isLive(b)).length;
    final routes = _buses.map((b) => b['route']?.toString() ?? '').where((r) => r.isNotEmpty).toSet().length;
    final totalStops = _buses.fold<int>(0, (s, b) => s + _stopCount(b));

    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 15,
      mainAxisSpacing: 15,
      childAspectRatio: 1.2,
      children: [
        _buildHighlightCard(theme, "FLEET", "${_buses.length} buses", LucideIcons.bus, theme.primaryColor),
        _buildHighlightCard(theme, "LIVE NOW", "$active on route", LucideIcons.radio, Colors.green),
        _buildHighlightCard(theme, "ROUTES", "$routes active routes", LucideIcons.map, Colors.amber),
        _buildHighlightCard(theme, "STOPS", "$totalStops total stops", LucideIcons.mapPin, theme.primaryColor.withValues(alpha: 0.7)),
      ],
    );
  }

  Widget _buildHighlightCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis),
          Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildBusCard(ThemeData theme, Map<String, dynamic> bus) {
    final live = _isLive(bus);
    final name = bus['name']?.toString() ?? 'Church Bus';
    final route = bus['route']?.toString() ?? 'No route set';
    final nextStop = bus['next_stop']?.toString();
    final eta = bus['eta']?.toString();
    final stops = _stopCount(bus);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (live ? Colors.green : theme.colorScheme.onSurface).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(live ? LucideIcons.radio : LucideIcons.bus, color: live ? Colors.green : theme.colorScheme.onSurface.withValues(alpha: 0.6), size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                    Text(route, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (live ? Colors.green : Colors.grey).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  live ? "LIVE" : "OFFLINE",
                  style: TextStyle(color: live ? Colors.green : Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1),
                ),
              ),
            ],
          ),
          if (nextStop != null || eta != null) ...[
            const SizedBox(height: 15),
            Row(
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    nextStop != null ? "Next stop: $nextStop" : "On route",
                    style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ),
                if (eta != null)
                  Text("ETA $eta", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            "$stops stops on this route",
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11),
          ),
        ],
      ),
    );
  }
}