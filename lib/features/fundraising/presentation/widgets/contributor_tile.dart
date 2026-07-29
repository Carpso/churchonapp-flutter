import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_models.dart';

class ContributorTile extends StatelessWidget {
  final FundraisingContribution contribution;

  const ContributorTile({super.key, required this.contribution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAnonymous = contribution.isAnonymous;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAnonymous ? Colors.grey.shade200 : theme.primaryColor.withValues(alpha: 0.15),
            ),
            child: Center(
              child: isAnonymous
                  ? Icon(LucideIcons.user, size: 20, color: Colors.grey.shade400)
                  : Text(
                      contribution.displayName.isNotEmpty
                          ? contribution.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: theme.primaryColor,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      contribution.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB300).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        contribution.formattedAmount,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Color(0xFFFFB300),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      contribution.timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
                if (contribution.message != null && contribution.message!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    contribution.message!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
