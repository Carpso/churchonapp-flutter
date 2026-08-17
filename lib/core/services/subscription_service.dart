import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Subscription tier
enum SubscriptionTier { free, silver, gold }

/// User subscription model
class UserSubscription {
  final String? id;
  final String userId;
  final SubscriptionTier tier;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionStartedAt;
  final DateTime? subscriptionEndsAt;
  final double? paymentAmount;
  final String? paymentReference;
  final String paymentStatus;
  final bool autoRenew;

  UserSubscription({
    this.id,
    required this.userId,
    this.tier = SubscriptionTier.free,
    this.trialStartedAt,
    this.trialEndsAt,
    this.subscriptionStartedAt,
    this.subscriptionEndsAt,
    this.paymentAmount,
    this.paymentReference,
    this.paymentStatus = 'none',
    this.autoRenew = false,
  });

  bool get isTrialActive {
    if (trialEndsAt == null) return false;
    return DateTime.now().isBefore(trialEndsAt!);
  }

  bool get isSubscriptionActive {
    if (subscriptionEndsAt == null) return false;
    return DateTime.now().isBefore(subscriptionEndsAt!);
  }

  bool get isPremium => tier != SubscriptionTier.free && (isTrialActive || isSubscriptionActive);

  bool get isGold => tier == SubscriptionTier.gold;

  int get trialDaysRemaining {
    if (trialEndsAt == null) return 0;
    final diff = trialEndsAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  int get subscriptionDaysRemaining {
    if (subscriptionEndsAt == null) return 0;
    final diff = subscriptionEndsAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory UserSubscription.fromMap(Map<String, dynamic> map) {
    return UserSubscription(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      tier: SubscriptionTier.values.firstWhere(
        (t) => t.name == (map['tier'] ?? 'free'),
        orElse: () => SubscriptionTier.free,
      ),
      trialStartedAt: map['trial_started_at'] != null ? DateTime.parse(map['trial_started_at']) : null,
      trialEndsAt: map['trial_ends_at'] != null ? DateTime.parse(map['trial_ends_at']) : null,
      subscriptionStartedAt: map['subscription_started_at'] != null ? DateTime.parse(map['subscription_started_at']) : null,
      subscriptionEndsAt: map['subscription_ends_at'] != null ? DateTime.parse(map['subscription_ends_at']) : null,
      paymentAmount: (map['payment_amount'] as num?)?.toDouble(),
      paymentReference: map['payment_reference']?.toString(),
      paymentStatus: map['payment_status']?.toString() ?? 'none',
      autoRenew: map['auto_renew'] ?? false,
    );
  }
}

/// Feature tier model
class FeatureTier {
  final String id;
  final String featureName;
  final String featureKey;
  final String requiredTier;
  final String? description;
  final bool isActive;

  FeatureTier({
    required this.id,
    required this.featureName,
    required this.featureKey,
    required this.requiredTier,
    this.description,
    this.isActive = true,
  });

  factory FeatureTier.fromMap(Map<String, dynamic> map) {
    return FeatureTier(
      id: map['id']?.toString() ?? '',
      featureName: map['feature_name']?.toString() ?? '',
      featureKey: map['feature_key']?.toString() ?? '',
      requiredTier: map['required_tier']?.toString() ?? 'free',
      description: map['description']?.toString(),
      isActive: map['is_active'] ?? true,
    );
  }
}

class SubscriptionService {
  final SupabaseClient _client;
  SubscriptionService(this._client);

  /// Get current user's subscription
  Future<UserSubscription?> getSubscription() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final result = await _client
          .from('user_subscriptions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (result == null) return await _createDefaultSubscription(userId);
      return UserSubscription.fromMap(result);
    } catch (e) {
      return _createDefaultSubscription(userId);
    }
  }

  /// Stream subscription changes
  Stream<UserSubscription?> subscriptionStream() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Stream.value(null);
    return _client
        .from('user_subscriptions')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((data) {
          if (data.isEmpty) return null;
          return UserSubscription.fromMap(data.first);
        });
  }

  /// Check feature access
  Future<bool> hasFeatureAccess(String featureKey) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final result = await _client.rpc('user_has_feature_access', params: {
        'feature_key': featureKey,
      });
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Subscribe to a tier
  Future<bool> subscribeToTier(String tier, {double? amountZmw, String? paymentRef}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      await _client.rpc('subscribe_user_to_tier', params: {
        'p_user_id': userId,
        'p_tier': tier,
        'p_payment_ref': paymentRef,
        'p_amount': amountZmw,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Approve subscription payment (superadmin only)
  Future<void> approvePayment(String paymentId) async {
    await _client.rpc('approve_user_subscription_payment', params: {
      'payment_id': paymentId,
    });
  }

  /// Reject subscription payment (superadmin only)
  Future<void> rejectPayment(String paymentId, {String? reason}) async {
    await _client.rpc('reject_user_subscription_payment', params: {
      'payment_id': paymentId,
      'p_reason': reason,
    });
  }

  /// Get streaming usage for a church
  Future<StreamingUsage> getStreamingUsage(String tenantId) async {
    try {
      final result = await _client.rpc('get_streaming_usage', params: {
        'p_church_id': tenantId,
      });

      if (result != null && result is List && result.isNotEmpty) {
        final data = result.first;
        return StreamingUsage(
          minutesUsed: (data['minutes_used'] as num?)?.toDouble() ?? 0,
          minutesLimit: (data['minutes_limit'] as num?)?.toDouble() ?? 10,
          minutesRemaining: (data['minutes_remaining'] as num?)?.toDouble() ?? 0,
          canStream: data['can_stream'] ?? false,
          weekStart: data['week_start'] != null ? DateTime.parse(data['week_start']) : null,
        );
      }
    } catch (e) {
      debugPrint('Error fetching streaming usage: $e');
    }
    return StreamingUsage.defaultUsage();
  }

  /// Record streaming minutes
  Future<void> recordStreamingMinutes({
    required String tenantId,
    required double minutes,
    int peakViewers = 0,
  }) async {
    try {
      await _client.rpc('record_streaming_minutes', params: {
        'p_church_id': tenantId,
        'p_minutes': minutes,
        'p_peak_viewers': peakViewers,
      });
    } catch (e) {
      debugPrint('Error recording streaming minutes: $e');
    }
  }

  /// Check if church can stream
  Future<bool> canChurchStream(String tenantId) async {
    final usage = await getStreamingUsage(tenantId);
    return usage.canStream;
  }

  /// Get streaming limits based on subscription status
  StreamingLimits getStreamingLimits(bool isTrial) {
    if (isTrial) {
      return StreamingLimits(
        maxMinutesPerWeek: 10,
        maxViewers: 25,
        recordingRetentionDays: 7,
        canMultiCamera: false,
        canCustomBranding: false,
      );
    } else {
      return StreamingLimits(
        maxMinutesPerWeek: -1,
        maxViewers: -1,
        recordingRetentionDays: -1,
        canMultiCamera: true,
        canCustomBranding: true,
      );
    }
  }

  /// Get all feature tiers
  Future<List<FeatureTier>> getFeatureTiers() async {
    try {
      final result = await _client
          .from('feature_tiers')
          .select()
          .eq('is_active', true)
          .order('feature_name');
      return (result as List).map((m) => FeatureTier.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get pending payments (superadmin)
  Future<List<Map<String, dynamic>>> getPendingPayments() async {
    try {
      final result = await _client
          .from('user_subscription_payments')
          .select('*, profiles!user_id(full_name, email)')
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(result);
    } catch (_) {
      return [];
    }
  }

  /// Create default free subscription — users are free forever, no trial
  Future<UserSubscription> _createDefaultSubscription(String userId) async {
    try {
      final result = await _client
          .from('user_subscriptions')
          .insert({
            'user_id': userId,
            'tier': 'free',
            // No trial — users are free forever, only churches get trials
          })
          .select()
          .single();
      return UserSubscription.fromMap(result);
    } catch (e) {
      return UserSubscription(userId: userId, tier: SubscriptionTier.free);
    }
  }
}

/// Provider
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService(Supabase.instance.client);
});

/// Current user subscription provider
final userSubscriptionProvider =
    FutureProvider<UserSubscription?>((ref) async {
  final service = ref.watch(subscriptionServiceProvider);
  return service.getSubscription();
});

/// Subscription stream provider
final subscriptionStreamProvider =
    StreamProvider<UserSubscription?>((ref) {
  final service = ref.watch(subscriptionServiceProvider);
  return service.subscriptionStream();
});

/// Feature access provider
final featureAccessProvider =
    FutureProvider.family<bool, String>((ref, featureKey) async {
  final service = ref.watch(subscriptionServiceProvider);
  return service.hasFeatureAccess(featureKey);
});

/// Streaming usage model
class StreamingUsage {
  final double minutesUsed;
  final double minutesLimit;
  final double minutesRemaining;
  final bool canStream;
  final DateTime? weekStart;

  StreamingUsage({
    required this.minutesUsed,
    required this.minutesLimit,
    required this.minutesRemaining,
    required this.canStream,
    this.weekStart,
  });

  factory StreamingUsage.defaultUsage() {
    return StreamingUsage(
      minutesUsed: 0,
      minutesLimit: 10,
      minutesRemaining: 10,
      canStream: true,
    );
  }

  double get usagePercentage {
    if (minutesLimit == -1) return 0;
    if (minutesLimit == 0) return 100;
    return (minutesUsed / minutesLimit * 100).clamp(0, 100);
  }

  bool get isUnlimited => minutesLimit == -1;
  bool get isTrial => minutesLimit == 10;
}

/// Streaming limits model
class StreamingLimits {
  final int maxMinutesPerWeek;
  final int maxViewers;
  final int recordingRetentionDays;
  final bool canMultiCamera;
  final bool canCustomBranding;

  StreamingLimits({
    required this.maxMinutesPerWeek,
    required this.maxViewers,
    required this.recordingRetentionDays,
    required this.canMultiCamera,
    required this.canCustomBranding,
  });

  bool get isUnlimited => maxMinutesPerWeek == -1;
}
