import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class PickupDropoffInputs extends StatelessWidget {
  final TextEditingController pickupController;
  final TextEditingController dropoffController;
  final TextEditingController? itemDescController;
  final String selectedCategory;
  final String selectedWeight;
  final String? pinModeFor;
  final ValueChanged<String>? onWeightChanged;
  final VoidCallback? onPickupTap;
  final VoidCallback? onDropoffTap;
  final VoidCallback? onUseMyLocation;
  final bool isLocating;

  const PickupDropoffInputs({
    super.key,
    required this.pickupController,
    required this.dropoffController,
    this.itemDescController,
    required this.selectedCategory,
    required this.selectedWeight,
    this.pinModeFor,
    this.onWeightChanged,
    this.onPickupTap,
    this.onDropoffTap,
    this.onUseMyLocation,
    this.isLocating = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDelivery =
        selectedCategory == 'marketplace' || selectedCategory == 'bookshop';

    return Column(
      children: [
        _buildTextField(
          context,
          controller: pickupController,
          icon: LucideIcons.mapPin,
          hint: "Pickup Location",
          field: 'pickup',
        ),
        if (onUseMyLocation != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onUseMyLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLocating)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).primaryColor,
                        ),
                      )
                    else
                      Icon(LucideIcons.navigation,
                          size: 13, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      isLocating ? "Detecting location..." : "Use my current location",
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
          ),
        ],
        const SizedBox(height: 15),
        _buildTextField(
          context,
          controller: dropoffController,
          icon: LucideIcons.navigation,
          hint: "Destination",
          field: 'destination',
        ),
        if (isDelivery && itemDescController != null) ...[
          const SizedBox(height: 15),
          _buildTextField(
            context,
            controller: itemDescController!,
            icon: LucideIcons.package,
            hint: "What are we delivering? (e.g. 5 Books, Bible Study Kit)",
            field: 'item',
          ),
          const SizedBox(height: 15),
          _buildWeightSelector(context),
        ],
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    required String field,
  }) {
    final theme = Theme.of(context);
    final isPickup = hint.contains('Pickup');
    final onTap = isPickup ? onPickupTap : onDropoffTap;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: AbsorbPointer(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: theme.primaryColor, size: 20),
              hintText: pinModeFor == field ? 'Tap map or search...' : hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeightSelector(BuildContext context) {
    final weights = ["Light", "Medium", "Heavy"];
    return Row(
      children: weights.map((w) {
        final isSelected = selectedWeight == w;
        return Expanded(
          child: GestureDetector(
            onTap: () => onWeightChanged?.call(w),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  w,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.secondary
                        : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
