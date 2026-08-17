import 'package:flutter/material.dart';
import 'package:church_on_app/core/i18n/l10n.dart';

class GivingCategorySelector extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;
  final Color? activeColor;

  const GivingCategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategoryChanged,
    this.activeColor,
  });

  static const _categoryIcons = {
    "Tithe": Icons.account_balance,
    "Offering": Icons.card_giftcard,
    "Mission": Icons.public,
    "Building Fund": Icons.construction,
    "First Fruits": Icons.celebration,
    "Other": Icons.more_horiz,
  };

  static const _presetAmounts = {
    "Tithe": [50.0, 100.0, 250.0, 500.0],
    "Offering": [10.0, 25.0, 50.0, 100.0],
    "Mission": [20.0, 50.0, 100.0, 200.0],
    "Building Fund": [50.0, 100.0, 500.0, 1000.0],
    "First Fruits": [100.0, 250.0, 500.0, 1000.0],
    "Other": [10.0, 25.0, 50.0, 100.0],
  };

  static List<double> getPresetAmounts(String category) {
    return _presetAmounts[category] ?? _presetAmounts["Other"]!;
  }

  static String formatZmw(double amount) {
    if (amount == amount.roundToDouble() && amount < 10000) {
      return "K ${amount.toInt()}";
    }
    final formatted = amount.toStringAsFixed(2);
    final parts = formatted.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return "K $intPart.${parts[1]}";
  }

  static String formatZmwInput(String raw) {
    if (raw.isEmpty) return "";
    final amount = double.tryParse(raw);
    if (amount == null) return raw;
    if (amount == amount.roundToDouble() && amount < 10000) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final secondary = activeColor ?? Theme.of(context).colorScheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr("Giving Category"),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 45,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = selectedCategory == cat;
              final icon = _categoryIcons[cat] ?? Icons.help_outline;
              return GestureDetector(
                onTap: () => onCategoryChanged(cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? secondary : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isSelected
                          ? secondary
                          : Colors.grey.withValues(alpha: 0.15),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: secondary.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: isSelected ? Colors.white : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.tr(cat),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
