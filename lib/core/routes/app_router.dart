import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';
import 'package:church_on_app/features/auth/presentation/login_screen.dart';
import 'package:church_on_app/features/auth/presentation/signup_screen.dart';
import 'package:church_on_app/features/auth/presentation/onboarding_screen.dart';
import 'package:church_on_app/features/auth/presentation/select_church_screen.dart';
import 'package:church_on_app/features/home/presentation/home_screen.dart';
import 'package:church_on_app/features/home/presentation/sermon_library_screen.dart';
import 'package:church_on_app/features/transport/presentation/ride_request_screen.dart';
import 'package:church_on_app/features/connect/presentation/connect_screen.dart';
import 'package:church_on_app/features/profile/presentation/profile_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/jobs_portal_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/job_details_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/manage_applications_screen.dart';
import 'package:church_on_app/features/modules/jobs/data/job_model.dart';
import 'package:church_on_app/features/connect/presentation/audio_call_screen.dart';
import 'package:church_on_app/features/connect/data/call_service.dart';
import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import '../services/tenant_service.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  final onboardingAsync = ref.watch(onboardingProvider);
  final tenant = ref.watch(currentTenantProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final seenOnboarding = onboardingAsync.value ?? true;
      if (!seenOnboarding && state.uri.path != '/onboarding') {
        return '/onboarding';
      }

      final loggedIn = authState.user != null;
      final isLoggingIn = state.uri.path == '/login';
      final isSelectingChurch = state.uri.path == '/select-church';

      if (!loggedIn) {
        if (tenant == null && !isSelectingChurch) return '/select-church';
        if (tenant != null && !isLoggingIn && !isSelectingChurch) return '/login';
        return null;
      }

      if (loggedIn && (isLoggingIn || isSelectingChurch || state.uri.path == '/onboarding')) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/select-church',
        builder: (context, state) => const SelectChurchScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/jobs',
        builder: (context, state) => const JobsPortalScreen(),
        routes: [
          GoRoute(
            path: 'details',
            builder: (context, state) {
              final job = state.extra as Job;
              return JobDetailsScreen(job: job);
            },
          ),
          GoRoute(
            path: 'manage',
            builder: (context, state) {
              final job = state.extra as Job;
              return ManageApplicationsScreen(job: job);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/call',
        builder: (context, state) {
          final call = state.extra as CallSession;
          return AudioCallScreen(
            userName: "Incoming Spiritual Call",
            userAvatar: "https://i.pravatar.cc/150?u=${call.callerId}",
            callSession: call,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainNavigationShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sermons',
                builder: (context, state) => const SermonLibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ride',
                builder: (context, state) => const RideRequestScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/connect',
                builder: (context, state) => const ConnectScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
