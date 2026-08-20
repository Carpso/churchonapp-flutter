import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:shimmer/shimmer.dart';
import 'package:go_router/go_router.dart';
import '../data/bible_book_model.dart';
import '../data/bible_books_service.dart';

class BibleBooksAuditScreen extends ConsumerWidget {
  const BibleBooksAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(bibleBooksAuditProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Bible Books Audit',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, color: Colors.white),
            onPressed: () => ref.invalidate(bibleBooksAuditProvider),
            tooltip: 'Refresh Audit',
          ),
        ],
      ),
      body: auditAsync.when(
        data: (audit) => _buildAuditView(context, audit, ref),
        loading: () => Padding(
          padding: const EdgeInsets.all(16),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[700]!,
            highlightColor: Colors.grey[500]!,
            child: Column(
              children: List.generate(8, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(height: 70, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(14))),
              )),
            ),
          ),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text("Error: $e", style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(bibleBooksAuditProvider),
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditView(BuildContext context, BibleBookAuditResult audit, WidgetRef ref) {
    final stats = audit.statistics;
    final isComplete = stats['standardCanonMatch'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          _buildHeaderCard(context, isComplete, stats),
          const SizedBox(height: 20),

          // Statistics Grid
          _buildStatisticsGrid(context, stats),
          const SizedBox(height: 20),

          // Missing Books
          if (audit.missingBooks.isNotEmpty) ...[
            _buildMissingBooksSection(context, audit.missingBooks),
            const SizedBox(height: 20),
          ],

          // Duplicate Books
          if (audit.duplicateBooks.isNotEmpty) ...[
            _buildDuplicatesSection(context, audit.duplicateBooks),
            const SizedBox(height: 20),
          ],

          // All Books List
          _buildAllBooksList(context, audit.books),
          const SizedBox(height: 20),

          // Action Buttons
          _buildActionButtons(context, ref),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, bool isComplete, Map<String, dynamic> stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isComplete
              ? [Colors.greenAccent.withAlpha(30), Colors.green.withAlpha(10)]
              : [Colors.orangeAccent.withAlpha(30), Colors.orange.withAlpha(10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isComplete ? Colors.greenAccent.withAlpha(50) : Colors.orangeAccent.withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          Icon(
            stats['standardCanonMatch'] == true
                ? LucideIcons.checkCircle
                : LucideIcons.alertTriangle,
            size: 48,
            color: stats['standardCanonMatch'] == true ? Colors.greenAccent : Colors.orangeAccent,
          ),
          const SizedBox(height: 16),
          Text(
            stats['standardCanonMatch'] == true
                ? 'Canon Audit Complete ✓'
                : 'Canon Audit: Issues Found',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${stats['totalBooks'] ?? 0}/66 books present',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            'Audited: ${_formatDate(DateTime.parse(stats['auditedAt'] ?? DateTime.now().toIso8601String()))}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsGrid(BuildContext context, Map<String, dynamic> stats) {
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _statCard(
          'Total Books',
          '${stats['totalBooks'] ?? 0}',
          LucideIcons.bookOpen,
          Colors.amber,
        ),
        _statCard(
          'Old Testament',
          '${stats['oldTestamentBooks'] ?? 0}',
          LucideIcons.book,
          Colors.amber,
        ),
        _statCard(
          'New Testament',
          '${stats['newTestamentBooks'] ?? 0}',
          LucideIcons.bookOpen,
          Theme.of(context).primaryColor,
        ),
        _statCard(
          'Total Chapters',
          '${stats['totalChapters'] ?? 0}',
          LucideIcons.list,
          Theme.of(context).primaryColor.withValues(alpha: 0.7),
        ),
        _statCard(
          'With Descriptions',
          '${stats['booksWithDescriptions'] ?? 0}',
          LucideIcons.fileText,
          Colors.green,
        ),
        _statCard(
          'Canon Match',
          stats['standardCanonMatch'] == true ? '✓ Yes' : '✗ No',
          stats['standardCanonMatch'] == true ? LucideIcons.checkCircle : LucideIcons.xCircle,
          stats['standardCanonMatch'] == true ? Colors.green : Colors.red,
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMissingBooksSection(BuildContext context, List<String> missingBooks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.alertCircle, size: 20, color: Colors.orangeAccent),
            const SizedBox(width: 8),
            Text(
              'Missing Books (${missingBooks.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: missingBooks.map((book) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orangeAccent.withAlpha(50)),
              ),
              child: Text(
                book,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDuplicatesSection(BuildContext context, List<String> duplicates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.copy, size: 20, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(
              'Duplicate Books (${duplicates.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: duplicates.map((book) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withAlpha(50)),
              ),
              child: Text(
                book,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAllBooksList(BuildContext context, List<BibleBook> books) {
    final otBooks = books.where((b) => b.testament == Testament.old).toList();
    final ntBooks = books.where((b) => b.testament == Testament.nt).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'All Books (${books.length})',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildTestamentSection('Old Testament (${otBooks.length})', otBooks, Colors.amber),
        const SizedBox(height: 16),
        _buildTestamentSection('New Testament (${ntBooks.length})', ntBooks, Theme.of(context).primaryColor),
      ],
    );
  }

  Widget _buildTestamentSection(String title, List<BibleBook> books, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.2,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            return Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF151A2E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withAlpha(40)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    book.abbreviation,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.name,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${book.chapters} ch',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => ref.read(bibleBooksRefreshProvider(true).future).then((_) {
              if (context.mounted) {
                PremiumToast.showSuccess(context, 'Bible books refreshed from public APIs');
              }
            }).catchError((e) {
              if (context.mounted) {
                PremiumToast.showError(context, 'Failed to refresh: $e');
              }
            }),
            icon: const Icon(LucideIcons.downloadCloud, size: 18),
            label: const Text('Refresh from Public APIs'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              context.push('/bible');
            },
            icon: const Icon(LucideIcons.bookOpen, size: 18),
            label: const Text('View Detailed Book Info'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.amber,
              side: BorderSide(color: Colors.amber.withAlpha(80)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class BibleBooksDetailScreen extends ConsumerWidget {
  const BibleBooksDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(bibleBooksProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Bible Books Reference', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: booksAsync.when(
        data: (books) => _buildBooksList(context, books),
        loading: () => Padding(
          padding: const EdgeInsets.all(16),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[700]!,
            highlightColor: Colors.grey[500]!,
            child: Column(
              children: List.generate(8, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(height: 70, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(14))),
              )),
            ),
          ),
        ),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      ),
    );
  }

  Widget _buildBooksList(BuildContext context, List<BibleBook> books) {
    final otBooks = books.where((b) => b.testament == Testament.old).toList();
    final ntBooks = books.where((b) => b.testament == Testament.nt).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDetailSection('Old Testament (${otBooks.length} books)', otBooks, Colors.amber),
        const SizedBox(height: 24),
        _buildDetailSection('New Testament (${ntBooks.length} books)', ntBooks, Theme.of(context).primaryColor),
      ],
    );
  }

  Widget _buildDetailSection(String title, List<BibleBook> books, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 4, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        ...books.map((book) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF151A2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withAlpha(40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      book.abbreviation,
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      book.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${book.chapters} ch',
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                book.description,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              if (book.alternateNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: book.alternateNames.map((alt) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(alt, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  )).toList(),
                ),
              ],
            ],
          ),
        )),
      ],
    );
  }
}