import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/tenant_service.dart';

class NewsManagementScreen extends ConsumerStatefulWidget {
  const NewsManagementScreen({super.key});

  @override
  ConsumerState<NewsManagementScreen> createState() => _NewsManagementScreenState();
}

class _NewsManagementScreenState extends ConsumerState<NewsManagementScreen> {
  List<Map<String, dynamic>> _articles = [];
  bool _loading = true;
  final Set<String> _categories = {'General', 'Announcement', 'Event', 'Sermon', 'Prayer'};

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    setState(() => _loading = true);
    try {
      final tenantId = ref.read(currentTenantProvider)?.id;
      var query = Supabase.instance.client
          .from('news')
          .select('id, title, content, category, image_url, is_published, created_at, tenant_id, user_id');

      if (tenantId != null) {
        query = query.eq('tenant_id', tenantId);
      }

      final res = await query.order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _articles = List<Map<String, dynamic>>.from(res);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading news articles: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteArticle(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Article'),
        content: const Text('Are you sure you want to delete this article?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('news').delete().eq('id', id);
      await _loadArticles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Article deleted'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveArticle(Map<String, dynamic> data, {String? id}) async {
    try {
      final client = Supabase.instance.client;
      final tenantId = ref.read(currentTenantProvider)?.id;
      final user = client.auth.currentUser;

      if (id != null) {
        await client.from('news').update(data).eq('id', id);
      } else {
        await client.from('news').insert({
          ...data,
          'tenant_id': tenantId,
          'user_id': user?.id,
        });
      }
      await _loadArticles();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(id != null ? 'Article updated' : 'Article created'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showForm({Map<String, dynamic>? article}) {
    final titleCtrl = TextEditingController(text: article?['title'] ?? '');
    final contentCtrl = TextEditingController(text: article?['content'] ?? '');
    final imageUrlCtrl = TextEditingController(text: article?['image_url'] ?? '');
    String category = article?['category'] ?? 'General';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) {
        bool published = (article?['is_published'] ?? true) as bool;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 25, right: 25, top: 25,
                bottom: MediaQuery.of(context).viewInsets.bottom + 25,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 50, height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      article == null ? 'New Article' : 'Edit Article',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 25),
                    _buildFieldLabel('TITLE'),
                    _buildField(titleCtrl, 'e.g. Sunday Service Announcement'),
                    const SizedBox(height: 18),
                    _buildFieldLabel('CONTENT'),
                    _buildField(contentCtrl, 'Article body...', maxLines: 5),
                    const SizedBox(height: 18),
                    _buildFieldLabel('CATEGORY'),
                    _buildCategoryDropdown(category, (val) {
                      setSheetState(() => category = val!);
                    }),
                    const SizedBox(height: 18),
                    _buildFieldLabel('IMAGE URL'),
                    _buildField(imageUrlCtrl, 'https://...'),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Published', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Switch(
                          value: published,
                          onChanged: (val) => setSheetState(() => published = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: () {
                          final data = {
                            'title': titleCtrl.text,
                            'content': contentCtrl.text,
                            'category': category,
                            'image_url': imageUrlCtrl.text.isEmpty ? null : imageUrlCtrl.text,
                            'is_published': published,
                          };
                          _saveArticle(data, id: article?['id']);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 5),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2, color: Colors.grey)),
    );
  }

  Widget _buildField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown(String selected, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (profile) {
        if (profile == null || (!profile.isAdminOrHigher && !profile.isSuperadmin && !profile.isEmployee)) {
          return const Scaffold(
            backgroundColor: Color(0xFFFFFAEB),
            body: Center(child: Text('Unauthorized', style: TextStyle(color: Colors.grey))),
          );
        }
        return _buildScreen();
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFFFFAEB),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: Color(0xFFFFFAEB),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text('News Management'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _showForm(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadArticles,
              child: _articles.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 200),
                        Center(
                          child: Column(
                            children: [
                              Icon(LucideIcons.fileText, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No news articles yet',
                                style: TextStyle(color: Colors.grey, fontSize: 16)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _articles.length,
                      itemBuilder: (context, index) => _buildArticleCard(_articles[index]),
                    ),
            ),
    );
  }

  Widget _buildArticleCard(Map<String, dynamic> article) {
    final createdAt = article['created_at'] != null
        ? DateTime.parse(article['created_at']).toLocal()
        : DateTime.now();
    final isPublished = article['is_published'] == true;
    final dateStr = '${createdAt.day}/${createdAt.month}/${createdAt.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article['title'] ?? 'Untitled',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPublished
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isPublished ? 'Published' : 'Draft',
                  style: TextStyle(
                    color: isPublished ? Colors.green : Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (article['category'] != null) ...[
            const SizedBox(height: 6),
            Text(
              article['category'],
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.pencil, size: 18),
                color: Colors.grey,
                onPressed: () => _showForm(article: article),
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 18),
                color: Colors.red.shade300,
                onPressed: () => _deleteArticle(article['id']?.toString() ?? ''),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
