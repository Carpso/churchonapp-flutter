import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists driver/rider/seller ratings after transactions.
class ServiceRatingService {
  final SupabaseClient _client;

  ServiceRatingService(this._client);

  /// Submit a rating for a completed transaction.
  /// [ratedId] - the user being rated (driver, rider, or seller)
  /// [rating] - 1-5 stars
  /// [review] - optional text review
  /// [context] - 'ride', 'delivery', or 'marketplace'
  /// [contextId] - the ride_request_id, delivery_request_id, or order_id
  Future<void> submitRating({
    required String ratedId,
    required int rating,
    String? review,
    required String context,
    String? contextId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    if (rating < 1 || rating > 5) throw Exception('Rating must be 1-5');

    await _client.from('service_ratings').insert({
      'rater_id': userId,
      'rated_id': ratedId,
      'rating': rating,
      'review': review?.trim().isEmpty == true ? null : review?.trim(),
      'context': context,
      'context_id': contextId,
    });
  }

  /// Get average rating for a user.
  Future<Map<String, dynamic>> getAverageRating(String userId) async {
    final result = await _client
        .rpc('get_user_avg_rating', params: {'target_user_id': userId});
    if (result != null && result is List && result.isNotEmpty) {
      return result.first as Map<String, dynamic>;
    }
    return {'avg_rating': 0, 'total_ratings': 0};
  }

  /// Check if a user has already rated a specific transaction.
  Future<bool> hasRated({
    required String context,
    required String contextId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final existing = await _client
        .from('service_ratings')
        .select('id')
        .eq('rater_id', userId)
        .eq('context', context)
        .eq('context_id', contextId)
        .maybeSingle();
    return existing != null;
  }
}

final serviceRatingServiceProvider = Provider((ref) => ServiceRatingService(Supabase.instance.client));

