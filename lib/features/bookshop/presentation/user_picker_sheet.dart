import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/bookshop_service.dart';

/// Searchable user picker used to add bookshop staff.
///
/// Mirrors the picker pattern in `role_approval_screen.dart`: search by name or
/// email, showing name + email + current role. Callers scope the candidate list
/// (platform staff load everyone; a shop owner loads only their tenant).
Future<BookshopUser?> showBookshopUserPicker(
  BuildContext context, {
  required List<BookshopUser> candidates,
  String title = 'SELECT A USER',
  String hint = 'Search by name or email…',
}) {
  return showModalBottomSheet<BookshopUser>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var search = '';
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered =
              candidates.where((u) => u.matches(search)).toList();
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.75,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 12),
                TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: hint,
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: (v) => setSheet(() => search = v.trim()),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('No users found',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final u = filtered[i];
                            final name = u.displayName;
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(name[0].toUpperCase()),
                              ),
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              subtitle: Text(
                                '${u.email.isEmpty ? "no email" : u.email} · '
                                '${u.role.replaceAll('_', ' ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(ctx, u),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
