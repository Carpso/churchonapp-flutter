import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/admin/presentation/bookshop_dashboard_screen.dart';
import 'package:church_on_app/features/admin/presentation/order_tracking_screen.dart';
import 'package:church_on_app/features/profile/presentation/account_settings_screen.dart';
import 'marketplace_screen.dart';

/// Retail workspace used only when the selected tenant is a bookshop.
/// Church users remain on MainNavigationShell and its locked tab set.
class BookshopWorkspaceScreen extends ConsumerStatefulWidget {
  const BookshopWorkspaceScreen({super.key});

  @override
  ConsumerState<BookshopWorkspaceScreen> createState() =>
      _BookshopWorkspaceScreenState();
}

class _BookshopWorkspaceScreenState
    extends ConsumerState<BookshopWorkspaceScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final primary = tenant?.primaryColor ?? const Color(0xFF1D4ED8);

    final pages = <Widget>[
      const MarketplaceScreen(initialCategory: 'bookshop'),
      const BookshopDashboardScreen(),
      const OrderTrackingScreen(),
      const AccountSettingsScreen(),
    ];

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: primary),
      ),
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          indicatorColor: primary.withValues(alpha: 0.14),
          destinations: [
            const NavigationDestination(
              icon: Icon(LucideIcons.store),
              selectedIcon: Icon(LucideIcons.store),
              label: 'Storefront',
            ),
            const NavigationDestination(
              icon: Icon(LucideIcons.package),
              selectedIcon: Icon(LucideIcons.package),
              label: 'Inventory',
            ),
            const NavigationDestination(
              icon: Icon(LucideIcons.shoppingBag),
              selectedIcon: Icon(LucideIcons.shoppingBag),
              label: 'Orders',
            ),
            const NavigationDestination(
              icon: Icon(LucideIcons.user),
              selectedIcon: Icon(LucideIcons.user),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
