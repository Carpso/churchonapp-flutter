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

    final logo = tenant?.logoUrl;
    if (logo != null && logo.isNotEmpty) {
      final pixelSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
      return Image.network(
        logo,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: pixelSize,
        cacheHeight: pixelSize,
        errorBuilder: (context, error, stackTrace) => _buildDefaultLogo(context),
      );
    }

    return _buildDefaultLogo(context);
  }

  Widget _buildDefaultLogo(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: white ? Colors.white : Colors.white, // Standardize on white background for logo
        borderRadius: BorderRadius.circular(size * 0.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Image.asset(
          'assets/app_logo.png',
          width: size * 0.8,
          height: size * 0.8,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.church,
            color: Theme.of(context).primaryColor,
            size: size * 0.6,
          ),
        ),
      ),
    );
  }
}

