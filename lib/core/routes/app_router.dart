import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';
import 'package:church_on_app/features/auth/presentation/login_screen.dart';
import 'package:church_on_app/features/auth/presentation/signup_screen.dart';
import 'package:church_on_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:church_on_app/features/auth/presentation/onboarding_screen.dart';
import 'package:church_on_app/features/auth/presentation/select_church_screen.dart';
import 'package:church_on_app/features/auth/presentation/landing_screen.dart';
import 'package:church_on_app/features/auth/presentation/church_onboarding_screen.dart';
import 'package:church_on_app/features/auth/presentation/splash_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:church_on_app/features/connect/presentation/incoming_call_screen.dart';
import 'package:church_on_app/features/connect/data/call_service.dart';
import 'package:church_on_app/features/modules/events/presentation/event_details_screen.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import '../services/tenant_service.dart';
import '../services/navigation_service.dart';
import 'package:church_on_app/features/connect/presentation/chat_messenger_screen.dart';
import 'package:church_on_app/features/bible/presentation/daily_devotions_screen.dart';
import 'package:church_on_app/features/finance/presentation/multi_currency_wallet_screen.dart';
import 'package:church_on_app/features/finance/presentation/receipt_screen.dart';
import 'package:church_on_app/features/finance/presentation/transaction_alerts_screen.dart';
import 'package:church_on_app/features/auth/presentation/join_church_screen.dart';
import 'package:church_on_app/features/connect/presentation/klip_detail_screen.dart';
import 'package:church_on_app/features/connect/presentation/post_detail_screen.dart';
import 'package:church_on_app/features/profile/presentation/privacy_policy_screen.dart';
import 'package:church_on_app/features/profile/presentation/terms_of_service_screen.dart';
import 'package:church_on_app/features/profile/presentation/about_screen.dart';
import 'package:church_on_app/features/support/presentation/support_hub_screen.dart';
import 'package:church_on_app/features/admin/presentation/emergency_shutdown_screen.dart';
import 'package:church_on_app/features/admin/presentation/ad_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/report_creator_screen.dart';
import 'package:church_on_app/features/admin/presentation/job_notifications_screen.dart';
import 'package:church_on_app/features/profile/presentation/role_onboarding_screen.dart';
import 'package:church_on_app/features/profile/presentation/security_screen.dart';
import 'package:church_on_app/features/admin/presentation/role_approval_screen.dart';
import 'package:church_on_app/features/admin/presentation/custom_role_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/writer_approval_screen.dart';
import 'package:church_on_app/features/admin/presentation/order_tracking_screen.dart';
import 'package:church_on_app/features/admin/presentation/pastor_dashboard_screen.dart';
import 'package:church_on_app/features/admin/presentation/apostle_dashboard_screen.dart';
import 'package:church_on_app/features/profile/presentation/church_referral_screen.dart';
import 'package:church_on_app/features/profile/presentation/writer_application_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/cart_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/checkout_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/vendor_dashboard_screen.dart';
import 'package:church_on_app/features/admin/presentation/ministry_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/ministry_schedule_screen.dart';
import 'package:church_on_app/features/admin/presentation/news_management_screen.dart';
import 'package:church_on_app/features/profile/presentation/emergency_contacts_screen.dart';
import 'package:church_on_app/features/connect/presentation/poll_creator_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/bookshop_onboarding_screen.dart';
import 'package:church_on_app/features/profile/presentation/camera_settings_screen.dart';
import 'package:church_on_app/features/connect/presentation/interchurch_network_screen.dart';
import 'package:church_on_app/features/connect/presentation/network_activity_screen.dart';
import 'package:church_on_app/features/connect/presentation/pastors_corner_screen.dart';
import 'package:church_on_app/features/home/presentation/discover_screen.dart';
import 'package:church_on_app/features/admin/presentation/system_docs_screen.dart';
import 'package:church_on_app/features/admin/presentation/database_setup_screen.dart';
import 'package:church_on_app/features/profile/presentation/feature_request_screen.dart';
import 'package:church_on_app/features/auth/presentation/demo_church_screen.dart';

class SplashCompletedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setCompleted(bool val) => state = val;
}

final splashCompletedProvider = NotifierProvider<SplashCompletedNotifier, bool>(SplashCompletedNotifier.new);
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  final onboardingAsync = ref.watch(onboardingProvider);
  final tenant = ref.watch(currentTenantProvider);
  final tenantInit = ref.watch(tenantInitializerProvider);

  return GoRouter(
    navigatorKey: NavigationService.navigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final splashCompleted = ref.watch(splashCompletedProvider);
      if (!splashCompleted && state.uri.path != '/splash') {
        return '/splash';
      }
      if (state.uri.path == '/splash' && !splashCompleted) {
        return null;
      }

      final seenOnboarding = onboardingAsync.value ?? true;
      if (!seenOnboarding && state.uri.path != '/onboarding') {
        return '/onboarding';
      }
      if (seenOnboarding && (state.uri.path == '/onboarding' || state.uri.path == '/splash')) {
        final loggedIn = authState.user != null;
        if (!loggedIn) {
          return kIsWeb ? '/landing' : '/login';
        }
        return tenant != null ? '/' : '/select-church';
      }

      // If tenant storage loading is not yet completed, wait
      if (tenantInit.isLoading) {
        return null;
      }

      final loggedIn = authState.user != null;
      final isLoggingIn = state.uri.path == '/login';
      final isSelectingChurch = state.uri.path == '/select-church';
      final isLanding = state.uri.path == '/landing';
      final isSignUp = state.uri.path == '/signup';
      final isRegisteringChurch = state.uri.path == '/register-church';
      final isForgotPassword = state.uri.path == '/forgot-password';

      // Always require selected tenant/church unless onboarding or registering
      if (tenant == null && !isSelectingChurch && !isRegisteringChurch && state.uri.path != '/onboarding') {
        return '/select-church';
      }

      if (!loggedIn) {
        if (isLoggingIn || isSelectingChurch || isSignUp || 
            state.uri.path == '/onboarding' || 
            isRegisteringChurch ||
            isForgotPassword) {
          return null;
        }
        if (kIsWeb && isLanding) return null;
        if (kIsWeb) return '/landing';
        return '/login';
      }

      if (loggedIn && (isLoggingIn || isLanding || state.uri.path == '/onboarding' || isSelectingChurch)) {
        if (tenant != null) {
          return '/';
        } else {
          return '/select-church';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
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
        path: '/register-church',
        builder: (context, state) => const ChurchOnboardingScreen(),
      ),


      GoRoute(
        path: '/landing',
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/join',
        builder: (context, state) {
          final churchId = state.uri.queryParameters['church'];
          final churchSlug = state.uri.queryParameters['slug'];
          return JoinChurchScreen(churchId: churchId, churchSlug: churchSlug);
        },
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const TermsOfServiceScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => const SupportHubScreen(),
      ),
      GoRoute(
        path: '/security',
        builder: (context, state) => const SecurityScreen(),
      ),
      GoRoute(
        path: '/shutdown',
        builder: (context, state) => const EmergencyShutdownScreen(),
      ),
      GoRoute(
        path: '/ads',
        builder: (context, state) => const AdManagementScreen(),
      ),
      GoRoute(
        path: '/job-notifications',
        builder: (context, state) => const JobNotificationsScreen(),
      ),
      GoRoute(
        path: '/report-creator',
        builder: (context, state) => const ReportCreatorScreen(),
      ),
      GoRoute(
        path: '/onboarding/:role',
        builder: (context, state) {
          final role = state.pathParameters['role']!;
          return RoleOnboardingScreen(role: role);
        },
      ),
      GoRoute(
        path: '/role-approvals',
        builder: (context, state) => const RoleApprovalScreen(),
      ),
      GoRoute(
        path: '/custom-roles',
        builder: (context, state) => const CustomRoleManagementScreen(),
      ),
      GoRoute(
        path: '/writer-approvals',
        builder: (context, state) => const WriterApprovalScreen(),
      ),
      GoRoute(
        path: '/apply-writer',
        builder: (context, state) => const WriterApplicationScreen(),
      ),
      GoRoute(
        path: '/pastor-dashboard',
        builder: (context, state) => const PastorDashboardScreen(),
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrderTrackingScreen(),
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: '/refer-church',
        builder: (context, state) => const ChurchReferralScreen(),
      ),
      GoRoute(
        path: '/apostle-dashboard',
        builder: (context, state) => const ApostleDashboardScreen(),
      ),
      GoRoute(
        path: '/cart',
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: '/vendor-dashboard',
        builder: (context, state) => const VendorDashboardScreen(),
      ),
      GoRoute(
        path: '/ministry-management',
        builder: (context, state) => const MinistryManagementScreen(),
      ),
      GoRoute(
        path: '/ministry-schedule',
        builder: (context, state) => const MinistryScheduleScreen(),
      ),
      GoRoute(
        path: '/news-management',
        builder: (context, state) => const NewsManagementScreen(),
      ),
      GoRoute(
        path: '/system-docs',
        builder: (context, state) => const SystemDocsScreen(),
      ),
      GoRoute(
        path: '/database-setup',
        builder: (context, state) => const DatabaseSetupScreen(),
      ),
      GoRoute(
        path: '/feature-request',
        builder: (context, state) => const FeatureRequestScreen(),
      ),
      GoRoute(
        path: '/demo-church',
        builder: (context, state) => const DemoChurchScreen(),
      ),
      GoRoute(
        path: '/news-management',
        builder: (context, state) => const NewsManagementScreen(),
      ),
      GoRoute(
        path: '/interchurch-network',
        builder: (context, state) => const InterchurchNetworkScreen(),
      ),
      GoRoute(
        path: '/network-activity',
        builder: (context, state) => const NetworkActivityScreen(),
      ),
      GoRoute(
        path: '/pastors-corner',
        builder: (context, state) => const PastorsCornerScreen(),
      ),
      GoRoute(
        path: '/discover',
        builder: (context, state) => const DiscoverScreen(),
      ),
      GoRoute(
        path: '/daily-devotions',
        builder: (context, state) => const DailyDevotionsScreen(),
      ),
      GoRoute(
        path: '/klips/:id',
        builder: (context, state) {
          final klipId = state.pathParameters['id']!;
          return KlipDetailScreen(klipId: klipId);
        },
      ),
      GoRoute(
        path: '/posts/:id',
        builder: (context, state) {
          final postId = state.pathParameters['id']!;
          return PostDetailScreen(postId: postId);
        },
      ),
      GoRoute(
        path: '/events/:id',
        builder: (context, state) {
          final eventId = state.pathParameters['id']!;
          final extraMap = state.extra as Map<String, dynamic>?;
          if (extraMap != null) {
            return EventDetailsScreen(event: extraMap);
          }
          return FutureBuilder<Map<String, dynamic>?>(
            future: ref.read(eventServiceProvider).getEventById(eventId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator(color: Colors.amber)),
                );
              }
              if (!snapshot.hasData || snapshot.data == null) {
                return const Scaffold(
                  body: Center(child: Text("Event not found")),
                );
              }
              return EventDetailsScreen(event: snapshot.data!);
            },
          );
        },
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
        path: '/chat/:id',
        builder: (context, state) {
          final messageId = state.pathParameters['id']!;
          return ChatMessengerScreen(
            userName: 'Chat',
            userAvatar: '',
            receiverId: messageId,
          );
        },
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => const MultiCurrencyWalletScreen(),
      ),
      GoRoute(
        path: '/receipt/:reference',
        builder: (context, state) {
          final reference = state.pathParameters['reference']!;
          return ReceiptScreen(reference: reference);
        },
      ),
      GoRoute(
        path: '/alerts',
        builder: (context, state) => const TransactionAlertsScreen(),
      ),
      GoRoute(
        path: '/notifications/:type/:id',
        redirect: (context, state) {
          final type = state.pathParameters['type']!;
          final id = state.pathParameters['id']!;
          switch (type) {
            case 'chat':
              return '/chat/$id';
            case 'post':
              return '/connect';
            case 'payment':
              return '/wallet';
            case 'announcement':
              return '/';
            default:
              return '/';
          }
        },
      ),
      GoRoute(
        path: '/call',
        builder: (context, state) {
          final call = state.extra as CallSession;
          if (call.status == CallStatus.dialing) {
            return IncomingCallScreen(callSession: call);
          }
          return AudioCallScreen(
            userName: "Incoming Spiritual Call",
            userAvatar: "https://i.pravatar.cc/150?u=${call.callerId}",
            callSession: call,
          );
        },
      ),
      GoRoute(
        path: '/emergency-contacts',
        builder: (context, state) => const EmergencyContactsScreen(),
      ),
      GoRoute(
        path: '/poll-creator',
        builder: (context, state) => const PollCreatorScreen(),
      ),
      GoRoute(
        path: '/bookshop-onboarding',
        builder: (context, state) => const BookshopOnboardingScreen(),
      ),
      GoRoute(
        path: '/camera-settings',
        builder: (context, state) => const CameraSettingsScreen(),
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

