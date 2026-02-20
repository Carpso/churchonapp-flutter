import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tenant_service.dart';

class KingdomLogo extends ConsumerWidget {
  final double size;
  final bool white;

  const KingdomLogo({
    super.key,
    this.size = 40,
    this.white = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);

    if (tenant?.logoUrl != null) {
      return Image.network(
        tenant!.logoUrl!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildDefaultLogo(context),
      );
    }

    return _buildDefaultLogo(context);
  }

  Widget _buildDefaultLogo(BuildContext context) {
    // Default logo is the app icon (Sunflower style)
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: white ? Colors.white : Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.church,
          color: white ? Theme.of(context).primaryColor : Colors.black,
          size: size * 0.6,
        ),
      ),
    );
  }
}
