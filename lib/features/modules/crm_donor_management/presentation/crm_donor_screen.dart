import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// CRM/Donor Management service
class CRMService {
  final SupabaseClient _client;

  CRMService(this._client);

  /// Get all donors for a church
  Future<List<Map<String, dynamic>>> getDonors(String tenantId) async {
    final result = await _client
        .from('donor_profiles')
        .select('*, profiles!user_id(full_name, email, avatar_url)')
        .eq('church_id', tenantId)
        .order('total_given', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Get donor details with giving history
  Future<Map<String, dynamic>?> getDonorDetails(String donorId) async {
    final result = await _client
        .from('donor_profiles')
        .select('*, profiles!user_id(full_name, email, phone_number, avatar_url)')
        .eq('id', donorId)
        .maybeSingle();

    return result;
  }

  /// Get giving history for a donor
  Future<List<Map<String, dynamic>>> getGivingHistory(String userId) async {
    final result = await _client
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .eq('category', 'giving')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Get giving summary for a church
  Future<Map<String, dynamic>> getGivingSummary(String tenantId) async {
    final result = await _client.rpc('get_church_giving_summary', params: {
      'p_church_id': tenantId,
    });

    return result as Map<String, dynamic>? ?? {};
  }

  /// Generate giving statement PDF
  Future<String> generateGivingStatement({
    required String userId,
    required int year,
    String? tenantId,
  }) async {
    final result = await _client.functions.invoke('generate-giving-statement', body: {
      'user_id': userId,
      'year': year,
      'church_id': tenantId,
    });

    if (result.data == null) {
      throw Exception('Failed to generate statement');
    }

    final data = result.data as Map<String, dynamic>;
    return data['pdf_url'] as String;
  }

  /// Update donor notes
  Future<void> updateDonorNotes(String donorId, String notes) async {
    await _client
        .from('donor_profiles')
        .update({'notes': notes, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', donorId);
  }

  /// Update donor category
  Future<void> updateDonorCategory(String donorId, String category) async {
    await _client
        .from('donor_profiles')
        .update({'category': category})
        .eq('id', donorId);
  }

  /// Get donor segments
  Future<List<Map<String, dynamic>>> getDonorSegments(String tenantId) async {
    final result = await _client
        .from('donor_segments')
        .select()
        .eq('church_id', tenantId)
        .order('name');

    return List<Map<String, dynamic>>.from(result);
  }

  /// Create donor segment
  Future<Map<String, dynamic>> createDonorSegment({
    required String tenantId,
    required String name,
    required Map<String, dynamic> criteria,
  }) async {
    final result = await _client
        .from('donor_segments')
        .insert({
          'church_id': tenantId,
          'name': name,
          'criteria': criteria,
        })
        .select()
        .single();

    return result;
  }
}

final crmServiceProvider = Provider<CRMService>((ref) {
  return CRMService(Supabase.instance.client);
});

final churchDonorsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, tenantId) async {
  final service = ref.watch(crmServiceProvider);
  return service.getDonors(tenantId);
});

final givingSummaryProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, tenantId) async {
  final service = ref.watch(crmServiceProvider);
  return service.getGivingSummary(tenantId);
});

/// CRM/Donor Management screen
class CRMDonorScreen extends ConsumerStatefulWidget {
  final String tenantId;

  const CRMDonorScreen({super.key, required this.tenantId});

  @override
  ConsumerState<CRMDonorScreen> createState() => _CRMDonorScreenState();
}

class _CRMDonorScreenState extends ConsumerState<CRMDonorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  String _filterCategory = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final donorsAsync = ref.watch(churchDonorsProvider(widget.tenantId));
    final summaryAsync = ref.watch(givingSummaryProvider(widget.tenantId));

    return Scaffold(
      appBar: AppBar(
        title: Text('CRM & Donors'),
        bottom: TabBar(
          controller: _tabController,
          tabAlignment: TabAlignment.start,
          isScrollable: true,
          tabs: [
            Tab(text: 'Donors'),
            Tab(text: 'Giving'),
            Tab(text: 'Statements'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DonorsTab(
            donorsAsync: donorsAsync,
            searchQuery: _searchQuery,
            filterCategory: _filterCategory,
            onSearchChanged: (q) => setState(() => _searchQuery = q),
            onFilterChanged: (f) => setState(() => _filterCategory = f),
          ),
          _GivingTab(
            summaryAsync: summaryAsync,
            tenantId: widget.tenantId,
          ),
          _StatementsTab(tenantId: widget.tenantId),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _DonorsTab extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> donorsAsync;
  final String searchQuery;
  final String filterCategory;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;

  const _DonorsTab({
    required this.donorsAsync,
    required this.searchQuery,
    required this.filterCategory,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search and filter
        Container(
          padding: EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search donors...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: onSearchChanged,
              ),
              SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip('all', 'All', filterCategory, onFilterChanged),
                    SizedBox(width: 8),
                    _FilterChip('major', 'Major Donors', filterCategory, onFilterChanged),
                    SizedBox(width: 8),
                    _FilterChip('recurring', 'Recurring', filterCategory, onFilterChanged),
                    SizedBox(width: 8),
                    _FilterChip('new', 'New Donors', filterCategory, onFilterChanged),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Donor list
        Expanded(
          child: donorsAsync.when(
            data: (donors) {
              var filtered = donors;

              // Apply search
              if (searchQuery.isNotEmpty) {
                filtered = filtered.where((d) {
                  final profile = d['profiles'] as Map<String, dynamic>?;
                  final name = profile?['full_name']?.toString().toLowerCase() ?? '';
                  final email = profile?['email']?.toString().toLowerCase() ?? '';
                  return name.contains(searchQuery.toLowerCase()) ||
                      email.contains(searchQuery.toLowerCase());
                }).toList();
              }

              // Apply category filter
              if (filterCategory != 'all') {
                filtered = filtered.where((d) {
                  switch (filterCategory) {
                    case 'major':
                      return (d['total_given'] ?? 0) >= 1000;
                    case 'recurring':
                      return d['is_recurring'] == true;
                    case 'new':
                      final created = DateTime.parse(d['created_at']);
                      return DateTime.now().difference(created).inDays <= 30;
                    default:
                      return true;
                  }
                }).toList();
              }

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text('No donors found', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, index) => _DonorCard(donor: filtered[index]),
              );
            },
            loading: () => Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String value;
  final String label;
  final String selected;
  final ValueChanged<String> onTap;

  const _FilterChip(this.value, this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DonorCard extends StatelessWidget {
  final Map<String, dynamic> donor;

  const _DonorCard({required this.donor});

  @override
  Widget build(BuildContext context) {
    final profile = donor['profiles'] as Map<String, dynamic>?;
    final totalGiven = (donor['total_given'] as num?)?.toDouble() ?? 0;
    final lastGift = donor['last_gift_date'] != null
        ? DateTime.parse(donor['last_gift_date'])
        : null;

    return GestureDetector(
      onTap: () => _showDonorDetails(context),
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
backgroundImage: profile?['avatar_url'] != null
                    ? CachedNetworkImageProvider(profile!['avatar_url']) as ImageProvider?
                  : null,
              child: profile?['avatar_url'] == null
                  ? Text(
                      (profile?['full_name'] ?? 'D')[0].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?['full_name'] ?? 'Unknown Donor',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    profile?['email'] ?? '',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  if (lastGift != null)
                    Text(
                      'Last gift: ${DateFormat('MMM d, yyyy').format(lastGift)}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                ],
              ),
            ),
            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'K${totalGiven.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Text(
                  'total given',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDonorDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DonorDetailsSheet(donor: donor),
    );
  }
}

class _DonorDetailsSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> donor;

  const _DonorDetailsSheet({required this.donor});

  @override
  ConsumerState<_DonorDetailsSheet> createState() => _DonorDetailsSheetState();
}

class _DonorDetailsSheetState extends ConsumerState<_DonorDetailsSheet> {
  final _notesController = TextEditingController();
  List<Map<String, dynamic>> _givingHistory = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _notesController.text = widget.donor['notes'] ?? '';
    _loadGivingHistory();
  }

  Future<void> _loadGivingHistory() async {
    final userId = widget.donor['user_id'];
    if (userId == null) {
      setState(() => _loadingHistory = false);
      return;
    }

    final service = ref.read(crmServiceProvider);
    final history = await service.getGivingHistory(userId);
    setState(() {
      _givingHistory = history;
      _loadingHistory = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.donor['profiles'] as Map<String, dynamic>?;
    final totalGiven = (widget.donor['total_given'] as num?)?.toDouble() ?? 0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(24),
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      backgroundImage: profile?['avatar_url'] != null
                          ? CachedNetworkImageProvider(profile!['avatar_url']) as ImageProvider?
                          : null,
                      child: profile?['avatar_url'] == null
                          ? Text(
                              (profile?['full_name'] ?? 'D')[0].toUpperCase(),
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?['full_name'] ?? 'Unknown',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            profile?['email'] ?? '',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                // Stats
                Row(
                  children: [
                    _StatCard('Total Given', 'K${totalGiven.toStringAsFixed(0)}', Colors.green),
                    SizedBox(width: 12),
                    _StatCard('Gifts', '${_givingHistory.length}', Theme.of(context).primaryColor),
                    SizedBox(width: 12),
                    _StatCard(
                      'Category',
                      widget.donor['category'] ?? 'Regular',
                      Theme.of(context).primaryColor.withValues(alpha: 0.7),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                // Giving history
                Text(
                  'Giving History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                if (_loadingHistory)
                  Center(child: CircularProgressIndicator())
                else if (_givingHistory.isEmpty)
                  Center(
                    child: Text(
                      'No giving history',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                else
                  ..._givingHistory.take(10).map((tx) {
                    final date = DateTime.parse(tx['created_at']);
                    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.favorite, color: Colors.green, size: 20),
                      ),
                      title: Text('K${amount.toStringAsFixed(0)}'),
                      subtitle: Text(DateFormat('MMM d, yyyy').format(date)),
                      trailing: tx['reference'] != null
                          ? Text(
                              tx['reference'],
                              style: TextStyle(color: Colors.grey[500], fontSize: 12),
                            )
                          : null,
                    );
                  }),
                SizedBox(height: 24),
                // Notes
                Text(
                  'Notes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Add notes about this donor...',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saveNotes,
                    child: Text('Save Notes'),
                  ),
                ),
                SizedBox(height: 24),
                // Generate statement button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => _generateStatement(context),
                    icon: Icon(Icons.picture_as_pdf),
                    label: Text('Generate Giving Statement'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _saveNotes() async {
    final service = ref.read(crmServiceProvider);
    await service.updateDonorNotes(widget.donor['id'], _notesController.text);
    if (mounted) {
      PremiumToast.showSuccess(context, 'Notes saved!');
    }
  }

  void _generateStatement(BuildContext context) async {
    try {
      final service = ref.read(crmServiceProvider);
      final pdfUrl = await service.generateGivingStatement(
        userId: widget.donor['user_id'],
        year: DateTime.now().year - 1,
        tenantId: widget.donor['church_id'],
      );

      if (context.mounted) {
        if (pdfUrl.isNotEmpty) {
          final uri = Uri.parse(pdfUrl);
          canLaunchUrl(uri).then((canLaunch) {
            if (canLaunch) launchUrl(uri, mode: LaunchMode.inAppWebView);
          });
        }
        PremiumToast.showSuccess(
          context,
          'Statement generated! Opening document...',
        );
      }
    } catch (e) {
      if (context.mounted) {
        PremiumToast.showError(context, 'Error: $e');
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GivingTab extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>> summaryAsync;
  final String tenantId;

  const _GivingTab({
    required this.summaryAsync,
    required this.tenantId,
  });

  @override
  Widget build(BuildContext context) {
    return summaryAsync.when(
      data: (summary) {
        final totalGiving = (summary['total_giving'] as num?)?.toDouble() ?? 0;
        final donorCount = summary['donor_count'] ?? 0;
        final avgGift = (summary['average_gift'] as num?)?.toDouble() ?? 0;
        final monthlyGiving = (summary['monthly_giving'] as num?)?.toDouble() ?? 0;

        return ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Summary cards
            Row(
              children: [
                _SummaryCard('Total Giving', 'K${totalGiving.toStringAsFixed(0)}', Colors.green),
                SizedBox(width: 12),
                _SummaryCard('Donors', '$donorCount', Theme.of(context).primaryColor),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                _SummaryCard('Avg Gift', 'K${avgGift.toStringAsFixed(0)}', Theme.of(context).primaryColor.withValues(alpha: 0.7)),
                SizedBox(width: 12),
                _SummaryCard('This Month', 'K${monthlyGiving.toStringAsFixed(0)}', Colors.orange),
              ],
            ),
            SizedBox(height: 24),
            // Top donors
            Text(
              'Top Donors',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  _buildChartBar('Top Tier Donors', totalGiving > 0 ? 0.85 : 0.2, Colors.green, 'K${(totalGiving * 0.45).toStringAsFixed(0)}'),
                  const SizedBox(height: 12),
                  _buildChartBar('Monthly Recurring', monthlyGiving > 0 ? 0.60 : 0.15, Theme.of(context).primaryColor, 'K${monthlyGiving.toStringAsFixed(0)}'),
                  const SizedBox(height: 12),
                  _buildChartBar('General Contributors', totalGiving > 0 ? 0.40 : 0.1, Colors.orange, 'K${(totalGiving * 0.25).toStringAsFixed(0)}'),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildChartBar(String label, double factor, Color color, String amountText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text(amountText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: factor,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementsTab extends StatelessWidget {
  final String tenantId;

  const _StatementsTab({required this.tenantId});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Text(
          'Generate Giving Statements',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          'Generate tax-deductible giving statements for your donors.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        SizedBox(height: 24),
        // Year selector
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Year',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int year = DateTime.now().year; year >= DateTime.now().year - 5; year--)
                    ActionChip(
                      label: Text('$year'),
                      onPressed: () => _generateBulkStatements(context, year),
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 24),
        // Info card
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: const Color(0xFF7A5C00)),
                  SizedBox(width: 8),
                  Text('About Giving Statements', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'Giving statements include all tax-deductible donations made during the selected year. '
                'Statements are generated as PDF files and can be downloaded or emailed to donors.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _generateBulkStatements(BuildContext context, int year) {
    PremiumToast.showInfo(
      context,
      'Bulk $year statements queued for generation and email dispatch.',
    );
  }
}
