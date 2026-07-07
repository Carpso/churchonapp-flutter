import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

class EntityOption {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;

  const EntityOption({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
  });
}

Future<void> showEntitySelector({
  required BuildContext context,
  required List<EntityOption> options,
  required void Function(EntityOption selected) onSelected,
  String title = 'Select Entity',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EntitySelectorSheet(
      options: options,
      onSelected: onSelected,
      title: title,
    ),
  );
}

class _EntitySelectorSheet extends StatefulWidget {
  final List<EntityOption> options;
  final void Function(EntityOption selected) onSelected;
  final String title;

  const _EntitySelectorSheet({
    required this.options,
    required this.onSelected,
    required this.title,
  });

  @override
  State<_EntitySelectorSheet> createState() => _EntitySelectorSheetState();
}

class _EntitySelectorSheetState extends State<_EntitySelectorSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  List<EntityOption> get _filtered {
    if (_query.isEmpty) return widget.options;
    final q = _query.toLowerCase();
    return widget.options.where((o) =>
      o.name.toLowerCase().contains(q) ||
      o.subtitle.toLowerCase().contains(q)
    ).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFFFFFAEB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.inter(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.searchX, size: 40, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text(
                        'No results found',
                        style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final option = _filtered[index];
                    return GestureDetector(
                      onTap: () {
                        widget.onSelected(option);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFAEB),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(option.icon, color: Colors.black87, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.name,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    option.subtitle,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              LucideIcons.chevronRight,
                              size: 16,
                              color: Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
