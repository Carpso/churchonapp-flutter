import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../home/presentation/home_screen.dart';
import '../../connect/presentation/connect_screen.dart';
import '../../bible/presentation/bible_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../transport/presentation/ride_request_screen.dart';
import 'ride_on_scanner_screen.dart';
// Theme via context

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(),
          BibleScreen(),
          RideRequestScreen(),
          ConnectScreen(),
          ProfileScreen(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() => _currentIndex = 2);
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _currentIndex == 2 ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.secondary,
            boxShadow: [
              BoxShadow(
                color: (_currentIndex == 2 ? Theme.of(context).primaryColor : Colors.black).withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(
            LucideIcons.car, 
            color: _currentIndex == 2 ? Theme.of(context).colorScheme.secondary : Colors.white, 
            size: 30
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, LucideIcons.home, "Home"),
            _buildNavItem(1, LucideIcons.bookOpen, "Disciple"),
            const SizedBox(width: 48), // Space for FAB
            _buildNavItem(3, LucideIcons.users, "Connect"),
            _buildNavItem(4, LucideIcons.user, "Steward"),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final bool isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? Theme.of(context).primaryColor : Colors.grey,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Theme.of(context).primaryColor : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
