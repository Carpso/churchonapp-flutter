import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_service.dart';
import 'core/services/tenant_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/fcm_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

import 'core/widgets/error_boundary.dart';
import 'core/providers/global_state_provider.dart';
import 'core/routes/app_router.dart';
import 'package:audio_service/audio_service.dart';
import 'core/services/audio_handler.dart';
import 'core/providers/audio_provider.dart' as ap;
import 'core/config/env.dart';
import 'package:app_links/app_links.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
    try {
      await dotenv.load(fileName: ".env");
      debugPrint('Environment loaded.');
    } catch (e) {
      debugPrint('Error loading .env file: $e');
      // Fallback or handle missing env
    }
    
    if (Env.supabaseUrl.isEmpty) {
      debugPrint('WARNING: SUPABASE_URL is empty. check your .env file.');
    }

    // 2. Remaining services in parallel
    await Future.wait([
      // Audio Service
      AudioService.init(
        builder: () => MyAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.churchonapp.channel.audio',
          androidNotificationChannelName: 'Kingdom Radio',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: true,
        ),
      ).then((handler) {
        ap.audioHandler = handler;
        return handler;
      }).catchError((e) {
        debugPrint('AudioService init error: $e');
        return MyAudioHandler(); // Fallback dummy handler
      }),
      
      // Supabase
      SupabaseService.initialize().catchError((e) {
        debugPrint('Supabase init error: $e');
      }),
    ]);
    
    debugPrint('Services initialized successfully.');
  } catch (e, stack) {
    debugPrint('CRITICAL Initialization error: $e');
    debugPrint('Stack trace: $stack');
  }


  runApp(
    const ProviderScope(
      child: ChurchOnApp(),
    ),
  );
}


class ChurchOnApp extends ConsumerStatefulWidget {
  const ChurchOnApp({super.key});

  @override
  ConsumerState<ChurchOnApp> createState() => _ChurchOnAppState();
}

class _ChurchOnAppState extends ConsumerState<ChurchOnApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    final appLinks = AppLinks();

    appLinks.getInitialLink().then((uri) {
      if (uri != null && mounted) {
        _handleDeepLink(uri);
      }
    });

    appLinks.uriLinkStream.listen((uri) {
      if (mounted) {
        _handleDeepLink(uri);
      }
    });
  }

  void _handleDeepLink(Uri uri) {
    final router = ref.read(routerProvider);
    if (uri.scheme == 'churchonapp' || uri.host == 'churchonapp.com' || uri.host == 'www.churchonapp.com') {
      final path = uri.path.isEmpty ? '/' : uri.path;
      if (uri.queryParameters.isNotEmpty) {
        final queryString = uri.query;
        router.go('$path?$queryString');
      } else {
        router.go(path);
      }
    }
  }

  Future<void> _initNotifications() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final notifService = container.read(notificationServiceProvider);
    await notifService.init();

    try {
      final fcm = FcmService(ref);
      await fcm.init();
    } catch (e) {
      debugPrint('FCM init skipped: $e');
    }

    // Start Realtime listeners once the user is authenticated
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final tenant = container.read(currentTenantProvider);
      final tenantId = tenant?.id ?? user.id;
      notifService.startListening(user.id, tenantId);
    }

    // Also listen for future auth state changes (e.g. after login)
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn && event.session?.user != null) {
        final u = event.session!.user;
        final tenant = container.read(currentTenantProvider);
        notifService.startListening(u.id, tenant?.id ?? u.id);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      ap.audioHandler?.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);
    final tenant = ref.watch(currentTenantProvider);

    // Initialize tenant data
    ref.watch(tenantInitializerProvider);
    // Observe global config
    ref.watch(globalStateProvider);

    final primaryColor = tenant?.primaryColor ?? const Color(0xFFFFD700);
    final isDark = themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: primaryColor.withValues(alpha: 0.15),
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp.router(
      title: 'Church On App',
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}

