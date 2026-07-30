import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/features/admin/data/admin_service.dart';
import 'package:share_plus/share_plus.dart';

/// Searchable, filterable member directory for church leadership.
class MemberDirectoryScreen extends ConsumerStatefulWidget {
  const MemberDirectoryScreen({super.key});

  @override
  ConsumerState<MemberDirectoryScreen> createState() =>
      _MemberDirectoryScreenState();
}

class _MemberDirectoryScreenState
    extends ConsumerState<MemberDirectoryScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterRole = 'all';
  String _sortBy = 'name'; // 'name', 'joined', 'role'
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;

  final List<String> _roles = [
    'all',
    'member',
    'pastor',
    'bishop',
    'deacon',
    'elder',
    'treasurer',
    'worship_leader',
    'youth_leader',
  ];

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  Future<void> _loadMembers() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;

    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, avatar_url, role, phone_number, created_at, email')
          .eq('tenant_id', tenant.id)
          .order('full_name', ascending: true);

      if (mounted) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading members: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredMembers {
    var list = _members.where((m) {
      final name = (m['full_name'] ?? '').toString().toLowerCase();
      final phone = (m['phone_number'] ?? '').toString().toLowerCase();
      final role = (m['role'] ?? 'member').toString().toLowerCase();
      final matchesSearch =
          _searchQuery.isEmpty || name.contains(_searchQuery) || phone.contains(_searchQuery);
      final matchesRole = _filterRole == 'all' || role == _filterRole;
      return matchesSearch && matchesRole;
    }).toList();

    switch (_sortBy) {
      case 'name':
        list.sort((a, b) =>
            (a['full_name'] ?? '').toString().compareTo((b['full_name'] ?? '').toString()));
        break;
      case 'joined':
        list.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
        break;
      case 'role':
        list.sort((a, b) =>
            (a['role'] ?? 'member').toString().compareTo((b['role'] ?? 'member').toString()));
        break;
    }

    return list;
  }

  String _formatRole(String? role) {
    if (role == null || role.isEmpty) return 'Member';
    return role
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  Color _roleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'pastor':
        return Colors.purple;
      case 'bishop':
        return Colors.indigo;
      case 'deacon':
        return Colors.teal;
      case 'elder':
        return Colors.amber.shade800;
      case 'treasurer':
        return Colors.green;
      case 'worship_leader':
        return Colors.pink;
      case 'youth_leader':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> _exportToPdf() async {
    final tenant = ref.read(currentTenantProvider);
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${tenant?.name ?? "Church"} — Member Directory',
            style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
          ),
        ),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${tenant?.name ?? "Church"} Member Directory',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Total: ${_filteredMembers.length}',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Name', 'Role', 'Phone', 'Email', 'Joined'],
            data: _filteredMembers.map((m) {
              return [
                m['full_name'] ?? 'Unknown',
                _formatRole(m['role']),
                m['phone_number'] ?? '',
                m['email'] ?? '',
                (m['created_at'] ?? '').toString().split('T')[0],
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ],
      ),
    );

    try {
      final bytes = await pdf.save();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/member_directory.pdf');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: '${tenant?.name ?? "Church"} Member Directory PDF',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Export failed: $e')),
        );
      }
    }
  }

  Future<void> _exportToCsv() async {
    final tenant = ref.read(currentTenantProvider);
    final csvBuffer = StringBuffer();
    csvBuffer.writeln('Name,Role,Phone,Email,Joined');
    for (final m in _filteredMembers) {
      final name = (m['full_name'] ?? '').toString().replaceAll(',', ' ');
      final role = _formatRole(m['role']);
      final phone = (m['phone_number'] ?? '').toString();
      final email = (m['email'] ?? '').toString();
      final joined = (m['created_at'] ?? '').toString().split('T')[0];
      csvBuffer.writeln('$name,$role,$phone,$email,$joined');
    }

    try {
      await SharePlus.instance.share(ShareParams(
        text: csvBuffer.toString(),
        subject: '${tenant?.name ?? "Church"} Member Directory',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredMembers;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Member Directory',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Refresh Members',
            onPressed: () {
              ref.invalidate(membersProvider);
              _loadMembers();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.download),
            tooltip: 'Export Directory',
            onSelected: (v) {
              if (v == 'csv') _exportToCsv();
              if (v == 'pdf') _exportToPdf();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(LucideIcons.fileSpreadsheet, size: 16),
                    SizedBox(width: 8),
                    Text('Export as CSV'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(LucideIcons.fileText, size: 16),
                    SizedBox(width: 8),
                    Text('Export as PDF Directory'),
                  ],
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.arrowUpDown),
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(LucideIcons.atSign,
                        size: 14,
                        color: _sortBy == 'name'
                            ? theme.primaryColor
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text('Sort by Name'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'joined',
                child: Row(
                  children: [
                    Icon(LucideIcons.clock,
                        size: 14,
                        color: _sortBy == 'joined'
                            ? theme.primaryColor
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text('Sort by Join Date'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'role',
                child: Row(
                  children: [
                    Icon(LucideIcons.shield,
                        size: 14,
                        color: _sortBy == 'role'
                            ? theme.primaryColor
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text('Sort by Role'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone...',
                  hintStyle: TextStyle(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(LucideIcons.search,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),

          // ── Role Filter Chips ──────────────────────
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _roles.length,
              itemBuilder: (context, index) {
                final role = _roles[index];
                final isSelected = _filterRole == role;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterRole = role),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.primaryColor.withValues(alpha: 0.15)
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? theme.primaryColor
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        _formatRole(role == 'all' ? 'all' : role),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? theme.primaryColor
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Count & Status ─────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  '${filtered.length} member${filtered.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          // ── Member List ────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.users,
                                size: 48,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No members match "$_searchQuery"'
                                  : 'No members found',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadMembers,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) =>
                              _buildMemberCard(filtered[index], theme),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(
      Map<String, dynamic> member, ThemeData theme) {
    final name = member['full_name'] ?? 'Unknown';
    final role = member['role'] ?? 'member';
    final avatar = member['avatar_url'] ?? '';
    final phone = member['phone_number'] ?? '';
    final joined = member['created_at'] != null
        ? DateTime.tryParse(member['created_at'])
            ?.toString()
            .split(' ')[0] ??
            ''
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: _roleColor(role).withValues(alpha: 0.15),
          child: avatar.isNotEmpty
              ? ClipOval(child: AppImage(avatar, width: 48, height: 48))
              : Text(
                  (name as String).isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _roleColor(role),
                    fontSize: 18,
                  ),
                ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _roleColor(role).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatRole(role),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _roleColor(role),
                    ),
                  ),
                ),
                if (joined.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Joined $joined',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
            if (phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(LucideIcons.phone,
                        size: 12,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.3)),
                    const SizedBox(width: 4),
                    Text(
                      phone,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: _buildMemberActions(member, theme),
      ),
    );
  }

  Widget _buildMemberActions(
      Map<String, dynamic> member, ThemeData theme) {
    return PopupMenuButton<String>(
      icon: Icon(LucideIcons.moreVertical,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
      onSelected: (action) => _handleMemberAction(action, member),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'view', child: Text('View Profile')),
        const PopupMenuItem(value: 'call', child: Text('Call')),
        const PopupMenuItem(value: 'message', child: Text('Send Message')),
      ],
    );
  }

  void _handleMemberAction(String action, Map<String, dynamic> member) {
    switch (action) {
      case 'view':
        // Navigate to member profile detail
        _showMemberDetail(member);
        break;
      case 'call':
        // Could use url_launcher here
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call ${member['phone_number'] ?? "N/A"}')),
        );
        break;
      case 'message':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message ${member['full_name']}')),
        );
        break;
    }
  }

  void _showMemberDetail(Map<String, dynamic> member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 40,
              backgroundColor:
                  _roleColor(member['role']).withValues(alpha: 0.15),
              child: (member['avatar_url'] ?? '').toString().isNotEmpty
                  ? ClipOval(
                      child: AppImage(member['avatar_url'],
                          width: 80, height: 80))
                  : Text(
                      ((member['full_name'] ?? '?') as String)[0]
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: _roleColor(member['role']),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              member['full_name'] ?? 'Unknown',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _roleColor(member['role']).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatRole(member['role']),
                style: TextStyle(
                  color: _roleColor(member['role']),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildDetailRow(
                LucideIcons.phone, 'Phone', member['phone_number'] ?? 'N/A'),
            _buildDetailRow(
                LucideIcons.mail, 'Email', member['email'] ?? 'N/A'),
            _buildDetailRow(
              LucideIcons.calendar,
              'Joined',
              member['created_at'] != null
                  ? DateTime.tryParse(member['created_at'])
                          ?.toString()
                          .split(' ')[0] ??
                      'N/A'
                  : 'N/A',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
