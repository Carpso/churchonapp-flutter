import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/navigation/presentation/main_navigation_shell.dart';
import 'core/services/supabase_service.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/select_church_screen.dart';
import 'core/providers/auth_provider.dart';
import 'core/services/tenant_service.dart';
import 'features/auth/presentation/onboarding_screen.dart';
import 'core/providers/onboarding_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await SupabaseService.initialize();

  runApp(
    const ProviderScope(
      child: ChurchOnApp(),
    ),
  );
}

class ChurchOnApp extends ConsumerWidget {
  const ChurchOnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final theme = ref.watch(themeProvider);
    
    // Initialize tenant data
    ref.watch(tenantInitializerProvider);
    final tenant = ref.watch(currentTenantProvider);
    final seenOnboarding = ref.watch(onboardingProvider);

    return MaterialApp(
      title: 'Church On App',
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: seenOnboarding.when(
        data: (seen) {
          if (!seen) return const OnboardingScreen();
          if (tenant == null) return const SelectChurchScreen();
          return authState.user == null ? const LoginScreen() : const MainNavigationShell();
        },
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, s) => Scaffold(body: Center(child: Text(e.toString()))),
      ),
    );
  }
}
