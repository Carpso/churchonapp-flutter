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

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

import 'core/widgets/error_boundary.dart';
import 'core/providers/global_state_provider.dart';
import 'core/routes/app_router.dart';
import 'package:audio_service/audio_service.dart';
import 'core/services/audio_handler.dart';
import 'core/providers/audio_provider.dart' as ap;

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  
  // Phase 7: Global Error Boundary Trapping - Move to start
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };
  
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Global Dispatcher Error: $error');
    debugPrint('Stack: $stack');
    return true; 
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return CustomErrorBoundary(errorDetails: details);
  };

  try {
    debugPrint('Starting services initialization...');
    
    // 1. Environment MUST be loaded first
    await dotenv.load(fileName: ".env");
    debugPrint('Environment loaded.');

    // 2. Remaining services in parallel
    await Future.wait([
      // Audio Service
      AudioService.init(
        builder: () => MyAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.churchonapp.channel.audio',
          androidNotificationChannelName: 'Kingdom Radio',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      ).then((handler) => ap.audioHandler = handler),
      
      // Supabase
      SupabaseService.initialize(),
    ]);
    
    debugPrint('Services initialized successfully.');
  } catch (e, stack) {
    debugPrint('CRITICAL Initialization error: $e');
    debugPrint('Stack trace: $stack');
    // We should probably show a critical error screen instead of just continuing
  }


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
    final theme = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);
    
    // Initialize tenant data
    ref.watch(tenantInitializerProvider);
    // Observe global config
    ref.watch(globalStateProvider);

    return MaterialApp.router(
      title: 'Church On App',
      theme: theme,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}

