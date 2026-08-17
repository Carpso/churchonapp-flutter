import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/features/navigation/presentation/main_navigation_shell.dart';
import 'package:church_on_app/features/auth/presentation/login_screen.dart';
import 'package:church_on_app/features/auth/presentation/signup_screen.dart';
import 'package:church_on_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:church_on_app/features/auth/presentation/onboarding_screen.dart';
import 'package:church_on_app/features/auth/presentation/select_church_screen.dart'
    show SelectTenantScreen;
import 'package:church_on_app/features/auth/presentation/landing_screen.dart';

import 'package:church_on_app/features/auth/presentation/splash_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:church_on_app/features/home/presentation/home_screen.dart';
import 'package:church_on_app/features/home/presentation/sermon_library_screen.dart';
import 'package:church_on_app/features/transport/presentation/ride_request_screen.dart';
import 'package:church_on_app/features/connect/presentation/connect_screen.dart';
import 'package:church_on_app/features/finance/presentation/giving_screen.dart';
import 'package:church_on_app/features/profile/presentation/profile_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/jobs_portal_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/job_details_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/manage_applications_screen.dart';
import 'package:church_on_app/features/modules/jobs/data/job_model.dart';
import 'package:church_on_app/features/connect/presentation/audio_call_screen.dart';
import 'package:church_on_app/features/connect/presentation/incoming_call_screen.dart';
import 'package:church_on_app/features/connect/presentation/prayer_wall_screen.dart';
import 'package:church_on_app/features/connect/data/call_service.dart';
import 'package:church_on_app/features/modules/events/presentation/event_details_screen.dart';
import 'package:church_on_app/features/modules/events/presentation/events_screen.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/features/finance/presentation/partner_redemption_screen.dart';
import 'package:church_on_app/features/admin/presentation/manage_partners_screen.dart';
import 'package:church_on_app/features/admin/presentation/church_directory_edit_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import '../services/tenant_service.dart';
import '../services/navigation_service.dart';
import 'package:church_on_app/features/connect/presentation/chat_messenger_screen.dart';
import 'package:church_on_app/features/bible/presentation/daily_devotions_screen.dart';
import 'package:church_on_app/features/finance/presentation/multi_currency_wallet_screen.dart';
import 'package:church_on_app/features/finance/presentation/receipt_screen.dart';
import 'package:church_on_app/features/finance/presentation/transaction_alerts_screen.dart';
import 'package:church_on_app/features/admin/presentation/church_invite_screen.dart';
import 'package:church_on_app/features/auth/presentation/join_church_screen.dart';
import 'package:church_on_app/features/connect/presentation/klip_detail_screen.dart';
import 'package:church_on_app/features/connect/presentation/post_detail_screen.dart';
import 'package:church_on_app/features/profile/presentation/privacy_policy_screen.dart';
import 'package:church_on_app/features/profile/presentation/terms_of_service_screen.dart';
import 'package:church_on_app/features/profile/presentation/about_screen.dart';
import 'package:church_on_app/features/support/presentation/support_hub_screen.dart';
import 'package:church_on_app/features/admin/presentation/expansion_leads_screen.dart';
import 'package:church_on_app/features/admin/presentation/member_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/event_scheduler_screen.dart';
import 'package:church_on_app/features/admin/presentation/carpso_driver_approval_screen.dart';
import 'package:church_on_app/features/admin/presentation/emergency_shutdown_screen.dart';
import 'package:church_on_app/features/admin/presentation/ad_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/report_creator_screen.dart';
import 'package:church_on_app/features/admin/presentation/job_notifications_screen.dart';
import 'package:church_on_app/features/profile/presentation/role_onboarding_screen.dart';
import 'package:church_on_app/features/profile/presentation/security_screen.dart';
import 'package:church_on_app/features/profile/presentation/active_sessions_screen.dart';
import 'package:church_on_app/features/admin/presentation/role_approval_screen.dart';
import 'package:church_on_app/features/admin/presentation/custom_role_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/writer_approval_screen.dart';
import 'package:church_on_app/features/admin/presentation/order_tracking_screen.dart';
import 'package:church_on_app/features/admin/presentation/pastor_dashboard_screen.dart';
import 'package:church_on_app/features/admin/presentation/apostle_dashboard_screen.dart';
import 'package:church_on_app/features/admin/presentation/coa_employee_dashboard.dart';
import 'package:church_on_app/features/admin/presentation/bookshop_dashboard_screen.dart';
import 'package:church_on_app/features/admin/presentation/year_planner_screen.dart';
import 'package:church_on_app/features/admin/presentation/pastor_bishop_report_screen.dart';
import 'package:church_on_app/features/admin/presentation/attendance_scanner_screen.dart';
import 'package:church_on_app/features/admin/presentation/admin_hub_screen.dart';
import 'package:church_on_app/features/admin/presentation/ledger_screen.dart';
import 'package:church_on_app/features/modules/navigation/presentation/more_hub_screen.dart';
import 'package:church_on_app/features/home/presentation/fasting_tracker_screen.dart';
import 'package:church_on_app/features/modules/media/presentation/radio_screen.dart';
import 'package:church_on_app/features/modules/media/presentation/kael_chat_screen.dart';
import 'package:church_on_app/features/navigation/presentation/carpso_ride_scanner_screen.dart';
import 'package:church_on_app/features/profile/presentation/account_settings_screen.dart';
import 'package:church_on_app/features/profile/presentation/verification_request_screen.dart';
import 'package:church_on_app/features/profile/presentation/referral_system_screen.dart';
import 'package:church_on_app/features/finance/presentation/coa_missions_donate_screen.dart';
import 'package:church_on_app/features/profile/presentation/church_referral_screen.dart';
import 'package:church_on_app/features/profile/presentation/writer_application_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/cart_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/checkout_screen.dart';
import 'package:church_on_app/features/church/presentation/church_schedule_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/marketplace_screen.dart';
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
import 'package:church_on_app/features/auth/presentation/two_factor_setup_screen.dart';
import 'package:church_on_app/features/disciple/presentation/discipleship_screen.dart';
import 'package:church_on_app/features/notebook/presentation/notebook_screen.dart';
import 'package:church_on_app/features/transport/presentation/rider_onboarding_screen.dart';
import 'package:church_on_app/features/transport/presentation/driver_portal_screen.dart';
import 'package:church_on_app/features/logistics/presentation/church_commute_screen.dart';
import 'package:church_on_app/features/admin/presentation/financial_report_screen.dart';
import 'package:church_on_app/features/admin/presentation/go_live_screen.dart';
import 'package:church_on_app/features/admin/presentation/member_directory_screen.dart';
import 'package:church_on_app/features/admin/presentation/platform_ad_screen.dart';
import 'package:church_on_app/features/admin/presentation/radio_station_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/role_quick_actions.dart';
import 'package:church_on_app/features/admin/presentation/service_report_form_screen.dart';
import 'package:church_on_app/features/admin/presentation/sos_alerts_management_screen.dart';
import 'package:church_on_app/features/admin/presentation/streaming_config_screen.dart';
import 'package:church_on_app/features/modules/live_streaming/presentation/live_stream_studio_screen.dart';
import 'package:church_on_app/features/admin/presentation/turnover_tax_ledger_screen.dart';
import 'package:church_on_app/features/admin/presentation/volunteer_schedule_screen.dart';
import 'package:church_on_app/features/auth/presentation/two_factor_verify_screen.dart';
import 'package:church_on_app/features/bible/presentation/bible_books_audit_screen.dart';
import 'package:church_on_app/features/bible/presentation/bible_screen.dart';
import 'package:church_on_app/features/bible_study/presentation/bible_study_create_screen.dart';
import 'package:church_on_app/features/bible_study/presentation/bible_study_detail_screen.dart';
import 'package:church_on_app/features/bible_study/presentation/bible_study_list_screen.dart';
import 'package:church_on_app/features/connect/presentation/create_klip_screen.dart';
import 'package:church_on_app/features/data_import/presentation/data_import_screen.dart';
import 'package:church_on_app/features/admin/presentation/feature_toggles_screen.dart';
import 'package:church_on_app/features/admin/presentation/platform_analytics_screen.dart';
import 'package:church_on_app/features/modules/kids/presentation/kids_zone_screen.dart';
import 'package:church_on_app/features/connect/presentation/sovereign_matchmaking_screen.dart';
import 'package:church_on_app/features/finance/presentation/giving_history_screen.dart';
import 'package:church_on_app/features/finance/presentation/my_pledges_screen.dart';
import 'package:church_on_app/features/finance/presentation/qr_payment_screen.dart';
import 'package:church_on_app/features/finance/presentation/tithe_card_screen.dart';
import 'package:church_on_app/features/finance/presentation/wallet_screen.dart';
import 'package:church_on_app/features/fundraising/presentation/contribute_screen.dart';
import 'package:church_on_app/features/fundraising/presentation/create_fundraising_screen.dart';
import 'package:church_on_app/features/fundraising/presentation/create_group_contribution_screen.dart';
import 'package:church_on_app/features/fundraising/presentation/fundraising_detail_screen.dart';
import 'package:church_on_app/features/fundraising/presentation/fundraising_list_screen.dart';
import 'package:church_on_app/features/fundraising/presentation/group_contribution_detail_screen.dart';
import 'package:church_on_app/features/fundraising/presentation/group_contribution_list_screen.dart';
import 'package:church_on_app/features/home/presentation/branch_locator_screen.dart';
import 'package:church_on_app/features/home/presentation/news_list_screen.dart';
import 'package:church_on_app/features/home/presentation/song_lyrics_screen.dart';
import 'package:church_on_app/features/home/presentation/tech_fast_blocker.dart';
import 'package:church_on_app/features/modules/ai_sermon_notes/presentation/ai_sermon_notes_screen.dart';
import 'package:church_on_app/features/modules/bible_quiz/presentation/bible_quiz_arena_screen.dart';
import 'package:church_on_app/features/modules/bible_quiz/data/pvp_service.dart';
import 'package:church_on_app/features/modules/bible_quiz/presentation/bible_quiz_hub_screen.dart';
import 'package:church_on_app/features/modules/bible_quiz/presentation/church_competition_lobby_screen.dart';
import 'package:church_on_app/features/modules/bible_quiz/presentation/quiz_invite_handler_screen.dart';
import 'package:church_on_app/features/modules/church_website/presentation/church_website_builder_screen.dart';
import 'package:church_on_app/features/modules/church_website/presentation/public_church_website_screen.dart';
import 'package:church_on_app/features/modules/crm_donor_management/presentation/crm_donor_screen.dart';
import 'package:church_on_app/features/modules/events/presentation/event_ticket_scanner_screen.dart';
import 'package:church_on_app/features/modules/events/presentation/ticket_detail_screen.dart';
import 'package:church_on_app/features/modules/games/presentation/game_arena_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/my_applications_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/my_jobs_screen.dart';
import 'package:church_on_app/features/modules/jobs/presentation/post_job_screen.dart';
import 'package:church_on_app/features/modules/live_streaming/presentation/live_streaming_screen.dart';
import 'package:church_on_app/features/modules/live_streaming/presentation/stream_admin_screen.dart';
import 'package:church_on_app/features/modules/media/presentation/flyer_studio_screen.dart';
import 'package:church_on_app/features/modules/media/presentation/worship_lyrics_screen.dart';
import 'package:church_on_app/features/modules/navigation/presentation/life_hub_screen.dart';
import 'package:church_on_app/features/modules/volunteer_scheduling/presentation/volunteer_scheduling_screen.dart';
import 'package:church_on_app/features/profile/presentation/certificates_screen.dart';
import 'package:church_on_app/features/profile/presentation/membership_card_screen.dart';
import 'package:church_on_app/features/profile/presentation/kyc_verification_screen.dart';
import 'package:church_on_app/features/profile/presentation/notification_preferences_screen.dart';
import 'package:church_on_app/features/profile/presentation/profile_deeplink_handler_screen.dart';
import 'package:church_on_app/features/profile/presentation/rewards_screen.dart';
import 'package:church_on_app/features/profile/presentation/subscription_screen.dart';
import 'package:church_on_app/features/transport/presentation/driver_earnings_screen.dart';
import 'package:church_on_app/features/transport/presentation/ride_history_screen.dart';
import 'package:church_on_app/features/transport/presentation/sos_trigger_screen.dart';
import 'package:church_on_app/features/admin/presentation/bishop_hub_screen.dart';
import 'package:church_on_app/features/admin/presentation/bishop_dashboard_screen.dart';
import 'package:church_on_app/features/admin/presentation/superadmin_hub_screen.dart';
import 'package:church_on_app/features/finance/presentation/buy_coins_screen.dart';
import 'package:church_on_app/features/finance/presentation/payout_request_screen.dart';
import 'package:church_on_app/features/auth/presentation/register_church_screen.dart';
import 'package:church_on_app/features/connect/presentation/communities_screen.dart';
import 'package:church_on_app/features/connect/presentation/kingdom_klips_screen.dart';
import 'package:church_on_app/features/connect/presentation/testimonies_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/post_product_screen.dart';
import 'package:church_on_app/features/bible_study/data/bible_study_service.dart' show BibleStudy;
import 'package:church_on_app/features/modules/games/data/game_service.dart' show KingdomGame;
import 'package:church_on_app/core/providers/profile_provider.dart';

class SplashCompletedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void setCompleted(bool val) => state = val;
}

final splashCompletedProvider = NotifierProvider<SplashCompletedNotifier, bool>(
  SplashCompletedNotifier.new,
);
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  final onboardingAsync = ref.watch(onboardingProvider);
  final tenant = ref.watch(currentTenantProvider);
  final tenantInit = ref.watch(tenantInitializerProvider);

  return GoRouter(
    navigatorKey: NavigationService.navigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      // Public church websites — no splash, login or tenant required.
      // Shared links `churchonapp.com/church/<churchId>` and
      // `churchonapp.com/site/<tenantId>` render a published website for
      // anyone (the RLS policy exposes `is_published = true` rows to anon).
      final publicPath = state.uri.path;
      if (publicPath.startsWith('/church/') ||
          publicPath.startsWith('/site/') ||
          publicPath.startsWith('/c/')) {
        return null;
      }
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
      if (seenOnboarding &&
          (state.uri.path == '/onboarding' || state.uri.path == '/splash')) {
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
      if (tenant == null &&
          !isSelectingChurch &&
          !isRegisteringChurch &&
          state.uri.path != '/onboarding' &&
          !isLoggingIn &&
          !isSignUp &&
          !isForgotPassword &&
           state.uri.path != '/join' &&
           state.uri.path != '/invite') {
        return '/select-church';
      }

      if (!loggedIn) {
        if (isLoggingIn ||
            isSelectingChurch ||
            isSignUp ||
            state.uri.path == '/onboarding' ||
            isRegisteringChurch ||
            isForgotPassword) {
          return null;
        }
        if (kIsWeb && isLanding) return null;
        if (kIsWeb) return '/landing';
        return '/login';
      }

      if (loggedIn &&
          (isLoggingIn ||
              isLanding ||
              state.uri.path == '/onboarding' ||
              isSelectingChurch)) {
        if (tenant != null) {
          return '/';
        } else {
          return '/select-church';
        }
      }

      // Subscription check for quiz + kids-zone routes
      if (tenant != null && tenant.isSubscriptionExpired) {
        final gatedPaths = ['/quiz', '/quiz/', '/kids-zone'];
        if (gatedPaths.any((p) => state.uri.path == p || state.uri.path.startsWith(p))) {
          return '/';
        }
      }

      // Role-based route guards
      final path = state.uri.path;
      final profile = ref.read(profileProvider).value;
      if (profile == null &&
          !['/login', '/signup', '/select-church', '/onboarding', '/splash', '/landing', '/register-church', '/forgot-password', '/join', '/invite'].contains(path)) {
        return null; // Profile loading or not required
      }

      bool hasAccess(String route, UserProfile user) {
        // Platform level admin (SuperAdmin / COA Employee only)
        if (route.startsWith('/superadmin') ||
            route == '/coa-employee-dashboard' ||
            route == '/system-docs' ||
            route == '/database-setup' ||
            route == '/emergency-shutdown' ||
            route == '/ads' ||
            route == '/platform-ads' ||
            route == '/expansion-leads' ||
            route == '/shutdown' ||
            route == '/writer-approvals' ||
            route == '/carpso-approval' ||
            route == '/manage-partners' ||
            route == '/news-management' ||
            route == '/church-directory-edit' ||
            route == '/feature-toggles' ||
            route == '/platform-analytics' ||
            route == '/admin/radio-mgmt' ||
            route == '/radio-stations' ||
            route == '/role-quick-actions') {
          return user.isEmployee;
        }

        // Executive level admin (Bishop / Apostle / SuperAdmin)
        if (route.startsWith('/bishop') || route.startsWith('/apostle')) {
          return user.isBishopOrHigher;
        }

        // Church level admin (Pastor / Admin / Leader)
        if (route.startsWith('/pastor-dashboard') ||
            route.startsWith('/service-report') ||
            route.startsWith('/streaming-config') ||
            route.startsWith('/crm-donors') ||
            route.startsWith('/stream-admin') ||
            route.startsWith('/volunteer-scheduling') ||
            route.startsWith('/role-approvals') ||
            route.startsWith('/custom-roles') ||
            route == '/admin-hub' ||
            route == '/ledger' ||
            route == '/financial-report' ||
            route == '/data-import' ||
            route == '/poll-creator' ||
            route == '/report-creator') {
          return user.isPastorOrHigher || user.role == 'general_treasurer';
        }

        // Live studio: pastors, bishops and assigned tenant leaders may stream
        if (route.startsWith('/live-studio') || route == '/admin/live-studio') {
          return user.isLeadershipTeam || user.role == 'general_treasurer';
        }

        // Admin hub registry tiles (member mgmt / event scheduler)
        if (route == '/admin/members' || route == '/admin/event-scheduler') {
          return user.isPastorOrHigher || user.isLeadershipTeam;
        }

        // Finance (Treasurer / Usher / Leadership)
        if (route == '/turnover-tax') {
          return user.isLedgerManager;
        }

        // Church staff scanning (Usher / Admin / Leader)
        if (route == '/attendance-scanner' ||
            route == '/ride-scanner' ||
            route.startsWith('/events/ticket-scanner')) {
          return user.isAdminOrHigher || user.role == 'usher';
        }

        // Logistics (Driver / Rider / Employee)
        if (route.startsWith('/driver-portal') ||
            route == '/driver-earnings' ||
            route == '/ride-portal') {
          return user.canWork || user.isEmployee;
        }

        // Marketplace (Vendor / Bookshop Staff / Employee)
        if (route == '/vendor-dashboard' || route == '/bookshop-dashboard') {
          return user.isBookshopStaff || user.isEmployee;
        }

        return true;
      }

      if (profile != null && !hasAccess(path, profile)) {
        debugPrint('Security Guard: Access denied for $path to role ${profile.role}');
        return '/';
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
        builder: (context, state) => const SelectTenantScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/register-church',
        builder: (context, state) => const RegisterChurchScreen(),
      ),

      GoRoute(
        path: '/landing',
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
       GoRoute(
         path: '/join',
         builder: (context, state) {
           final churchId = state.uri.queryParameters['church'];
           final churchSlug = state.uri.queryParameters['slug'];
           final inviteCode = state.uri.queryParameters['code'];
           final referralCode = state.uri.queryParameters['ref'];
           return JoinChurchScreen(
             churchId: churchId,
             churchSlug: churchSlug,
             inviteCode: inviteCode,
             referralCode: referralCode,
           );
         },
       ),
       GoRoute(
         path: '/invite',
         builder: (context, state) {
           return const ChurchInviteScreen();
         },
       ),
       GoRoute(
         path: '/invite-church/:code',
        builder: (context, state) {
          final code = state.pathParameters['code']!;
          return JoinChurchScreen(inviteCode: code);
        },
      ),
      GoRoute(
        path: '/invite/church/:code',
        redirect: (context, state) {
          final code = state.pathParameters['code']!;
          return '/invite-church/$code';
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
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
      GoRoute(
        path: '/support',
        builder: (context, state) => const SupportHubScreen(),
      ),
      GoRoute(
        path: '/security',
        builder: (context, state) => const SecurityScreen(),
      ),
      GoRoute(
        path: '/active-sessions',
        builder: (context, state) => const ActiveSessionsScreen(),
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
        path: '/coa-employee-dashboard',
        builder: (context, state) => const CoaEmployeeDashboard(),
      ),
      GoRoute(
        path: '/data-import',
        builder: (context, state) => const DataImportScreen(),
      ),
      GoRoute(
        path: '/feature-toggles',
        builder: (context, state) => const FeatureTogglesScreen(),
      ),
      GoRoute(
        path: '/platform-analytics',
        builder: (context, state) => const PlatformAnalyticsScreen(),
      ),
      GoRoute(
        path: '/kids-zone',
        builder: (context, state) => const KidsZoneScreen(),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
      GoRoute(
        path: '/vendor-dashboard',
        builder: (context, state) => const VendorDashboardScreen(),
      ),
      GoRoute(
        path: '/bookshop-dashboard',
        builder: (context, state) => const BookshopDashboardScreen(),
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
        path: '/events',
        builder: (context, state) => const EventsScreen(),
      ),
      GoRoute(
        path: '/event/:id',
        redirect: (context, state) {
          final id = state.pathParameters['id']!;
          final qs = state.uri.queryParameters;
          final qString = qs.isNotEmpty ? '?${state.uri.query}' : '';
          return '/events/$id$qString';
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
                  body: Center(
                    child: CircularProgressIndicator(color: Colors.amber),
                  ),
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
          GoRoute(
            path: 'post',
            builder: (context, state) => const PostJobScreen(),
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
      GoRoute(
        path: '/two-factor-setup',
        builder: (context, state) => const TwoFactorSetupScreen(),
      ),
      GoRoute(
        path: '/discipleship',
        builder: (context, state) => const DiscipleshipScreen(),
      ),
      GoRoute(
        path: '/notebook',
        builder: (context, state) => const NotebookScreen(),
      ),
      GoRoute(
        path: '/rider-onboarding',
        builder: (context, state) => const RiderOnboardingScreen(),
      ),
      GoRoute(
        path: '/driver-portal',
        builder: (context, state) => const DriverPortalScreen(),
      ),
      GoRoute(
        path: '/church-commute',
        builder: (context, state) => const ChurchCommuteScreen(),
      ),
      GoRoute(
        path: '/marketplace',
        builder: (context, state) => const MarketplaceScreen(),
      ),
      GoRoute(
        path: '/prayer-wall',
        builder: (context, state) => const PrayerWallScreen(),
      ),
      GoRoute(
        path: '/partner-redemption',
        builder: (context, state) => const PartnerRedemptionScreen(),
      ),
      GoRoute(
        path: '/manage-partners',
        builder: (context, state) => const ManagePartnersScreen(),
      ),
      GoRoute(
        path: '/church-directory-edit',
        builder: (context, state) => const ChurchDirectoryEditScreen(),
      ),
      // === ORPHAN SCREENS ===
      GoRoute(
        path: '/financial-report',
        builder: (context, state) => const FinancialReportScreen(),
      ),
      GoRoute(
        path: '/go-live',
        builder: (context, state) => const GoLiveScreen(),
      ),
      GoRoute(
        path: '/member-directory',
        builder: (context, state) => const MemberDirectoryScreen(),
      ),
      GoRoute(
        path: '/platform-ads',
        builder: (context, state) => const PlatformAdScreen(),
      ),
      GoRoute(
        path: '/radio-stations',
        builder: (context, state) => const RadioStationManagementScreen(),
      ),
      GoRoute(
        path: '/admin/radio-mgmt',
        builder: (context, state) => const RadioStationManagementScreen(),
      ),
      GoRoute(
        path: '/role-quick-actions',
        builder: (context, state) {
          final profile = state.extra as UserProfile;
          return RoleQuickActions(profile: profile);
        },
      ),
      GoRoute(
        path: '/expansion-leads',
        builder: (context, state) => const ExpansionLeadsScreen(),
      ),
      GoRoute(
        path: '/carpso-approval',
        builder: (context, state) => const CarpsoDriverApprovalScreen(),
      ),
      GoRoute(
        path: '/service-report',
        builder: (context, state) => const ServiceReportFormScreen(),
      ),
      GoRoute(
        path: '/sos-alerts',
        builder: (context, state) => const SosAlertsManagementScreen(),
      ),
      GoRoute(
        path: '/year-planner',
        builder: (context, state) => const YearPlannerScreen(),
      ),
      GoRoute(
        path: '/pastor-bishop-report',
        builder: (context, state) => const PastorBishopReportScreen(),
      ),
      GoRoute(
        path: '/attendance-scanner',
        builder: (context, state) => const AttendanceScannerScreen(),
      ),
      GoRoute(
        path: '/admin-hub',
        builder: (context, state) => const AdminHubScreen(),
      ),
      GoRoute(
        path: '/church-schedule',
        builder: (context, state) => const ChurchScheduleScreen(),
      ),
      GoRoute(
        path: '/ledger',
        builder: (context, state) => const LedgerScreen(),
      ),
      GoRoute(
        path: '/streaming-config/:tenantId',
        builder: (context, state) {
          final tenantId = state.pathParameters['tenantId']!;
          return StreamingConfigScreen(tenantId: tenantId);
        },
      ),
      GoRoute(
        path: '/turnover-tax',
        builder: (context, state) => const TurnoverTaxLedgerScreen(),
      ),
      GoRoute(
        path: '/volunteer-schedule',
        builder: (context, state) => const VolunteerScheduleScreen(),
      ),
      GoRoute(
        path: '/two-factor-verify',
        builder: (context, state) => const TwoFactorVerifyScreen(),
      ),
      GoRoute(
        path: '/bible-books-audit',
        builder: (context, state) => const BibleBooksAuditScreen(),
      ),
      // === NEW ROUTES FOR ORPHANED SCREENS ===
      GoRoute(
        path: '/bishop-hub',
        builder: (context, state) => const BishopHubScreen(),
      ),
      GoRoute(
        path: '/bishop-dashboard',
        builder: (context, state) => const BishopDashboardScreen(),
      ),
      GoRoute(
        path: '/superadmin-hub',
        builder: (context, state) => const SuperadminHubScreen(),
      ),
      GoRoute(
        path: '/buy-coins',
        builder: (context, state) => const BuyCoinsScreen(),
      ),
      GoRoute(
        path: '/payout-request',
        builder: (context, state) => const PayoutRequestScreen(),
      ),
      GoRoute(
        path: '/communities',
        builder: (context, state) => const CommunitiesScreen(),
      ),
      GoRoute(
        path: '/kingdom-klips',
        builder: (context, state) => const KingdomKlipsScreen(),
      ),
      GoRoute(
        path: '/testimonies',
        builder: (context, state) => const TestimoniesScreen(),
      ),
      GoRoute(
        path: '/post-product',
        builder: (context, state) {
          final category = state.uri.queryParameters['category'];
          return PostProductScreen(initialCategory: category);
        },
      ),
      GoRoute(
        path: '/bible',
        builder: (context, state) => const BibleScreen(),
      ),
      GoRoute(
        path: '/bible/:book/:chapter/:verse',
        builder: (context, state) {
          final book = state.pathParameters['book']!;
          final chapter = int.tryParse(state.pathParameters['chapter'] ?? '1') ?? 1;
          final verse = int.tryParse(state.pathParameters['verse'] ?? '1') ?? 1;
          return BibleScreen(initialBook: book, initialChapter: chapter, initialVerse: verse);
        },
      ),
      GoRoute(
        path: '/bible/:book/:chapter',
        builder: (context, state) {
          final book = state.pathParameters['book']!;
          final chapter = int.tryParse(state.pathParameters['chapter'] ?? '1') ?? 1;
          return BibleScreen(initialBook: book, initialChapter: chapter);
        },
      ),
      GoRoute(
        path: '/bible-study',
        builder: (context, state) => const BibleStudyListScreen(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (context, state) {
              final study = state.extra as BibleStudy?;
              return BibleStudyCreateScreen(study: study);
            },
          ),
          GoRoute(
            path: ':studyId',
            builder: (context, state) {
              final studyId = state.pathParameters['studyId']!;
              return BibleStudyDetailScreen(studyId: studyId);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final extraStudy = state.extra as BibleStudy?;
                  return BibleStudyCreateScreen(study: extraStudy);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/create-klip',
        builder: (context, state) => const CreateKlipScreen(),
      ),
      GoRoute(
        path: '/sovereign-matchmaking',
        builder: (context, state) => const SovereignMatchmakingScreen(),
      ),
      GoRoute(
        path: '/giving-history',
        builder: (context, state) => const GivingHistoryScreen(),
      ),
      GoRoute(
        path: '/my-pledges',
        builder: (context, state) => const MyPledgesScreen(),
      ),
      GoRoute(
        path: '/qr-payment',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return QrPaymentScreen(
            amount: (extra['amount'] as num).toDouble(),
            description: extra['description'] as String,
            recipient: extra['recipient'] as String,
          );
        },
      ),
      GoRoute(
        path: '/tithe-card',
        builder: (context, state) => const TitheCardScreen(),
      ),
      GoRoute(
        path: '/finance-wallet',
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: '/fundraising',
        builder: (context, state) => const FundraisingListScreen(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (context, state) => const CreateFundraisingScreen(),
          ),
          GoRoute(
            path: ':ventureId',
            builder: (context, state) {
              final ventureId = state.pathParameters['ventureId']!;
              return FundraisingDetailScreen(ventureId: ventureId);
            },
          ),
          GoRoute(
            path: 'contribute/:ventureId',
            builder: (context, state) {
              final ventureId = state.pathParameters['ventureId']!;
              return ContributeScreen(ventureId: ventureId);
            },
          ),
          GoRoute(
            path: 'groups',
            builder: (context, state) => const GroupContributionListScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (context, state) {
                  final tenantId = state.extra is String
                      ? state.extra as String
                      : ref.read(currentTenantProvider)?.id ?? '';
                  return CreateGroupContributionScreen(tenantId: tenantId);
                },
              ),
              GoRoute(
                path: ':groupId',
                builder: (context, state) {
                  final groupId = state.pathParameters['groupId']!;
                  return GroupContributionDetailScreen(groupId: groupId);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/branch-locator',
        builder: (context, state) => const BranchLocatorScreen(),
      ),
      GoRoute(
        path: '/news',
        builder: (context, state) => const NewsListScreen(),
      ),
      GoRoute(
        path: '/song-lyrics',
        builder: (context, state) => const SongLyricsScreen(),
      ),
      GoRoute(
        path: '/tech-fast-blocker',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return TechFastBlocker(
            categories: List<String>.from(extra['categories'] as List),
            child: extra['child'] as Widget,
          );
        },
      ),
      GoRoute(
        path: '/ai-sermon-notes/:sermonId',
        builder: (context, state) {
          final sermonId = state.pathParameters['sermonId']!;
          final extra = state.extra as Map<String, dynamic>?;
          return AISermonNotesScreen(
            sermonId: sermonId,
            sermonTitle: extra?['title'] as String? ?? 'Sermon Notes',
            sermonContent: extra?['content'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/quiz',
        builder: (context, state) => const BibleQuizHubScreen(),
        routes: [
          GoRoute(
            path: 'lobby',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return ChurchCompetitionLobbyScreen(
                competitionId: extra?['competitionId'] as String?,
                initialPin: extra?['pin'] as String?,
              );
            },
          ),
          GoRoute(
            path: 'arena',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final mode = extra?['mode'] as String? ?? 'Solo';
              final matchData = extra?['pvpMatch'];
              int qCount = 10;
              int tpq = 15;
              PvPMatch? pvpMatch;
              if (matchData is PvPMatch) {
                pvpMatch = matchData;
                qCount = pvpMatch.questionCount;
                tpq = pvpMatch.timePerQuestion;
              } else if (matchData is Map<String, dynamic>) {
                qCount = (matchData['questionCount'] as int?) ?? 10;
                tpq = (matchData['timePerQuestion'] as int?) ?? 15;
              }
              return BibleQuizArenaScreen(
                mode: mode,
                questionCount: qCount,
                timePerQuestionSec: tpq,
                initialPvPMatch: pvpMatch,
              );
            },
          ),
          GoRoute(
            path: 'invite/:matchId',
            builder: (context, state) {
              final matchId = state.pathParameters['matchId']!;
              return QuizInviteHandlerScreen(matchId: matchId);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/church-website/:tenantId',
        builder: (context, state) {
          final tenantId = state.pathParameters['tenantId']!;
          return ChurchWebsiteBuilderScreen(tenantId: tenantId);
        },
      ),
      GoRoute(
        path: '/church/:churchId',
        builder: (context, state) {
          final churchId = state.pathParameters['churchId']!;
          return PublicChurchWebsiteScreen(churchId: churchId);
        },
      ),
      GoRoute(
        path: '/c/:slug',
        builder: (context, state) {
          final slug = state.pathParameters['slug']!;
          return PublicChurchWebsiteScreen(churchId: slug, slug: slug);
        },
      ),
      GoRoute(
        path: '/site/:tenantId',
        builder: (context, state) {
          final tenantId = state.pathParameters['tenantId']!;
          return PublicChurchWebsiteScreen(churchId: tenantId);
        },
      ),
      GoRoute(
        path: '/crm-donors/:tenantId',
        builder: (context, state) {
          final tenantId = state.pathParameters['tenantId']!;
          return CRMDonorScreen(tenantId: tenantId);
        },
      ),
      GoRoute(
        path: '/events/ticket-scanner/:eventId',
        builder: (context, state) {
          final eventId = state.pathParameters['eventId']!;
          final eventTitle = state.uri.queryParameters['title'] ?? 'Event';
          return EventTicketScannerScreen(eventId: eventId, eventTitle: eventTitle);
        },
      ),
      GoRoute(
        path: '/ticket',
        builder: (context, state) {
          final event = state.extra as ChurchEvent;
          return TicketDetailScreen(event: event);
        },
      ),
      GoRoute(
        path: '/game-arena',
        builder: (context, state) {
          final game = state.extra as KingdomGame;
          return KingdomGameArenaScreen(game: game);
        },
      ),
      GoRoute(
        path: '/my-applications',
        builder: (context, state) => const MyApplicationsScreen(),
      ),
      GoRoute(
        path: '/my-jobs',
        builder: (context, state) => const MyJobsScreen(),
      ),
      GoRoute(
        path: '/live-streaming',
        builder: (context, state) => const LiveStreamingScreen(),
      ),
      GoRoute(
        path: '/stream-admin/:tenantId',
        builder: (context, state) {
          final tenantId = state.pathParameters['tenantId']!;
          return StreamAdminScreen(tenantId: tenantId);
        },
      ),
      GoRoute(
        path: '/live-studio',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final tenantId = extra?['tenantId'] as String?;
          return LiveStreamStudioScreen(tenantId: tenantId);
        },
      ),
      GoRoute(
        path: '/admin/live-studio',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final tenantId = extra?['tenantId'] as String?;
          return LiveStreamStudioScreen(tenantId: tenantId);
        },
      ),
      GoRoute(
        path: '/admin/members',
        builder: (context, state) => const MemberManagementScreen(),
      ),
      GoRoute(
        path: '/admin/event-scheduler',
        builder: (context, state) => const EventSchedulerScreen(),
      ),
      GoRoute(
        path: '/flyer-studio',
        builder: (context, state) => const FlyerStudioScreen(),
      ),
      GoRoute(
        path: '/kael-chat',
        builder: (context, state) => const KaelChatScreen(),
      ),
      GoRoute(
        path: '/worship-lyrics',
        builder: (context, state) => const WorshipLyricsScreen(),
      ),
      GoRoute(
        path: '/life-hub',
        builder: (context, state) => const LifeHubScreen(),
      ),
      GoRoute(
        path: '/more-hub',
        builder: (context, state) => const MoreHubScreen(),
      ),
      GoRoute(
        path: '/fasting',
        builder: (context, state) => const FastingTrackerScreen(),
      ),
      GoRoute(
        path: '/radio',
        builder: (context, state) => const RadioScreen(),
      ),
      GoRoute(
        path: '/ride-scanner',
        builder: (context, state) => const CarpsoRideScannerScreen(),
      ),
      GoRoute(
        path: '/account-settings',
        builder: (context, state) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: '/request-verification',
        builder: (context, state) => const VerificationRequestScreen(),
      ),
      GoRoute(
        path: '/referral-program',
        builder: (context, state) => const ReferralSystemScreen(),
      ),
      GoRoute(
        path: '/missions-donate',
        builder: (context, state) => const CoaMissionsDonateScreen(),
      ),
      GoRoute(
        path: '/volunteer-scheduling/:tenantId',
        builder: (context, state) {
          final tenantId = state.pathParameters['tenantId']!;
          return VolunteerSchedulingScreen(tenantId: tenantId);
        },
      ),
      GoRoute(
        path: '/certificates',
        builder: (context, state) => const CertificatesScreen(),
      ),
      GoRoute(
        path: '/membership-card',
        builder: (context, state) => const MembershipCardScreen(),
      ),
      GoRoute(
        path: '/kyc-verification',
        builder: (context, state) => const KycVerificationScreen(),
      ),
      GoRoute(
        path: '/notification-preferences',
        builder: (context, state) => const NotificationPreferencesScreen(),
      ),
      GoRoute(
        path: '/profile-by-id/:userId',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return ProfileDeepLinkHandlerScreen(userId: userId);
        },
      ),
      GoRoute(
        path: '/rewards',
        builder: (context, state) => const RewardsScreen(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const SubscriptionManagementScreen(),
      ),
      GoRoute(
        path: '/driver-earnings',
        builder: (context, state) => const DriverEarningsScreen(),
      ),
      GoRoute(
        path: '/ride-history',
        builder: (context, state) => const RideHistoryScreen(),
      ),
      GoRoute(
        path: '/sos-trigger',
        builder: (context, state) => const SosTriggerScreen(),
      ),
      GoRoute(
        path: '/ride',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map && extra['mode'] is String) {
            return RideRequestScreen(mode: extra['mode'] as String);
          }
          return const RideRequestScreen();
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainNavigationShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (context, state) => HomeScreen()),
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
                path: '/giving',
                builder: (context, state) => const GivingScreen(),
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
