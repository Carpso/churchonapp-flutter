enum TenantPlan { silver, gold, platinum }

class PlanLimits {
  final TenantPlan plan;
  final String label;
  final double monthlyPriceKwacha;
  final int maxMembers;
  final int liveStreamMinutesPerMonth;
  final bool isSilverSharedPool;
  final int eventsPerMonth;
  final int mediaStorageGb;
  final int kaelAiQueriesPerMonth;
  final int marketplaceListingsPerMonth;
  final bool canHostQuizTournaments;
  final String supportLevel;

  const PlanLimits({
    required this.plan,
    required this.label,
    required this.monthlyPriceKwacha,
    required this.maxMembers,
    required this.liveStreamMinutesPerMonth,
    required this.isSilverSharedPool,
    required this.eventsPerMonth,
    required this.mediaStorageGb,
    required this.kaelAiQueriesPerMonth,
    required this.marketplaceListingsPerMonth,
    required this.canHostQuizTournaments,
    required this.supportLevel,
  });

  static const Map<TenantPlan, PlanLimits> all = {
    TenantPlan.silver: PlanLimits(
      plan: TenantPlan.silver,
      label: 'Silver',
      monthlyPriceKwacha: 0,
      maxMembers: 100,
      liveStreamMinutesPerMonth: 0,
      isSilverSharedPool: true,
      eventsPerMonth: 10,
      mediaStorageGb: 1,
      kaelAiQueriesPerMonth: 50,
      marketplaceListingsPerMonth: 5,
      canHostQuizTournaments: false,
      supportLevel: 'Email (48h)',
    ),
    TenantPlan.gold: PlanLimits(
      plan: TenantPlan.gold,
      label: 'Gold',
      monthlyPriceKwacha: 100,
      maxMembers: 500,
      liveStreamMinutesPerMonth: 3600,
      isSilverSharedPool: false,
      eventsPerMonth: 50,
      mediaStorageGb: 10,
      kaelAiQueriesPerMonth: 500,
      marketplaceListingsPerMonth: 50,
      canHostQuizTournaments: false,
      supportLevel: 'Email (24h)',
    ),
    TenantPlan.platinum: PlanLimits(
      plan: TenantPlan.platinum,
      label: 'Platinum',
      monthlyPriceKwacha: 500,
      maxMembers: -1,
      liveStreamMinutesPerMonth: 12000,
      isSilverSharedPool: false,
      eventsPerMonth: -1,
      mediaStorageGb: 50,
      kaelAiQueriesPerMonth: -1,
      marketplaceListingsPerMonth: -1,
      canHostQuizTournaments: true,
      supportLevel: 'Priority + Phone',
    ),
  };

  static PlanLimits forPlan(TenantPlan plan) => all[plan]!;

  static TenantPlan fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'gold':
        return TenantPlan.gold;
      case 'platinum':
        return TenantPlan.platinum;
      default:
        return TenantPlan.silver;
    }
  }

  bool get isUnlimited => maxMembers == -1;
  String get priceDisplay => monthlyPriceKwacha == 0 ? 'Free' : 'K$monthlyPriceKwacha/mo';

  static const double platformFeePercent = 0.01;
  static const double minPlatformFeeKwacha = 3.0;
  static const double quizLeaseFeeKwacha = 1500.0;
  static const double onboardingFeeKwacha = 500.0;

  /// SMS bundles (separate from plans)
  static const Map<int, int> smsBundles = {
    50: 100,
    100: 250,
    250: 600,
  };

  /// Sep 30, 2026 — promotion end date for free Platinum after onboarding
  static DateTime get promotionEndDate => DateTime(2026, 9, 30, 23, 59, 59);
}
