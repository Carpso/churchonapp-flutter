import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum WagerTier { free, ten, fifty }

extension WagerTierX on WagerTier {
  int get coins {
    switch (this) {
      case WagerTier.free:
        return 0;
      case WagerTier.ten:
        return 10;
      case WagerTier.fifty:
        return 50;
    }
  }

  String get label {
    switch (this) {
      case WagerTier.free:
        return 'Free';
      case WagerTier.ten:
        return '10 CC';
      case WagerTier.fifty:
        return '50 CC';
    }
  }
}

class PvPMatch {
  final String id;
  final String player1Id;
  final String? player2Id;
  final String status;
  final String channelName;
  final int questionCount;
  final int timePerQuestion;
  int player1Score;
  int player2Score;
  int player1Correct;
  int player2Correct;
  String? winnerId;
  final DateTime createdAt;
  DateTime? completedAt;
  final int wagerAmount;
  final int player1EloAtMatch;
  int? player2EloAtMatch;
  int? player1EloChange;
  int? player2EloChange;

  PvPMatch({
    required this.id,
    required this.player1Id,
    this.player2Id,
    required this.status,
    required this.channelName,
    this.questionCount = 10,
    this.timePerQuestion = 15,
    this.player1Score = 0,
    this.player2Score = 0,
    this.player1Correct = 0,
    this.player2Correct = 0,
    this.winnerId,
    DateTime? createdAt,
    this.completedAt,
    this.wagerAmount = 0,
    this.player1EloAtMatch = 1200,
    this.player2EloAtMatch,
    this.player1EloChange,
    this.player2EloChange,
  }) : createdAt = createdAt ?? DateTime.now();

  factory PvPMatch.fromMap(Map<String, dynamic> m) => PvPMatch(
    id: m['id']?.toString() ?? '',
    player1Id: m['player1_id']?.toString() ?? '',
    player2Id: m['player2_id']?.toString(),
    status: m['status'] ?? 'pending',
    channelName: m['channel_name'] ?? '',
    questionCount: m['question_count'] ?? 10,
    timePerQuestion: m['time_per_question'] ?? 15,
    player1Score: m['player1_score'] ?? 0,
    player2Score: m['player2_score'] ?? 0,
    player1Correct: m['player1_correct'] ?? 0,
    player2Correct: m['player2_correct'] ?? 0,
    winnerId: m['winner_id']?.toString(),
    createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
    completedAt: m['completed_at'] != null ? DateTime.tryParse(m['completed_at'].toString()) : null,
    wagerAmount: m['wager_amount'] ?? 0,
    player1EloAtMatch: m['player1_elo_at_match'] ?? 1200,
    player2EloAtMatch: m['player2_elo_at_match'],
    player1EloChange: m['player1_elo_change'],
    player2EloChange: m['player2_elo_change'],
  );

  bool get isPlayer1Win => winnerId == player1Id;
  bool get isPlayer2Win => player2Id != null && winnerId == player2Id;
  bool get isDraw => player1Score == player2Score;
}

class PvPService {
  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _channel;
  RealtimeChannel? get activeChannel => _channel;

  /// Callback for opponent answer events — set by the consuming widget.
  void Function(Map<String, dynamic> payload)? onOpponentAnswered;

  /// Callback for connection state changes.
  void Function(bool isConnected)? onConnectionStateChanged;

  /// Callback for channel errors.
  void Function(String error)? onChannelError;

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  String? _lastMatchId;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<String?> _resolveTenantId() async {
    try {
      final profile = await _client
          .from('profiles')
          .select('tenant_id')
          .eq('id', currentUserId ?? '')
          .maybeSingle();
      return profile?['tenant_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<int> _getUserElo() async {
    final uid = currentUserId;
    if (uid == null) return 1200;
    try {
      final res = await _client
          .from('profiles')
          .select('elo_rating')
          .eq('id', uid)
          .maybeSingle();
      return (res?['elo_rating'] as num?)?.toInt() ?? 1200;
    } catch (_) {
      return 1200;
    }
  }

  /// Deduct coins for wager entry. Returns true on success.
  Future<bool> _deductWager(int amount) async {
    if (amount <= 0) return true;
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final res = await _client.rpc('deduct_wager_coins', params: {
        'p_user_id': uid,
        'p_amount': amount,
      });
      final data = res as Map<String, dynamic>?;
      return data?['success'] == true;
    } catch (e) {
      debugPrint('[PvP] Wager deduction failed: $e');
      return false;
    }
  }

  /// Refund coins on queue timeout.
  Future<void> _refundWager(int amount) async {
    if (amount <= 0) return;
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await _client.rpc('refund_wager_coins', params: {
        'p_user_id': uid,
        'p_amount': amount,
      });
    } catch (e) {
      debugPrint('[PvP] Wager refund failed: $e');
    }
  }

  /// ELO-based matchmaking with expanding range.
  ///
  /// 1. Deduct wager coins (if > 0).
  /// 2. Fetch user's ELO.
  /// 3. Search for pending matches within range [elo ± currentRange].
  /// 4. Expand range every 5 seconds: 100 → 200 → 400 → Global.
  /// 5. If no match found after 30s, refund wager and create a new match.
  Future<PvPMatch?> findOrCreateMatch({
    int questionCount = 10,
    int timePerQuestion = 15,
    WagerTier wagerTier = WagerTier.free,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;

    final wagerAmount = wagerTier.coins;

    // Deduct wager coins before queueing
    if (wagerAmount > 0) {
      final deducted = await _deductWager(wagerAmount);
      if (!deducted) {
        debugPrint('[PvP] Insufficient coins for wager');
        return null;
      }
    }

    try {
      final tid = await _resolveTenantId();
      final userElo = await _getUserElo();

      // ELO matchmaking with expanding range
      const ranges = [100, 200, 400, 9999]; // 9999 = global
      const rangeExpandInterval = Duration(seconds: 5);
      final searchTimeout = Duration(seconds: 30);
      final searchStart = DateTime.now();

      for (final range in ranges) {
        if (DateTime.now().difference(searchStart) >= searchTimeout) break;

        final freshSince = DateTime.now()
            .subtract(const Duration(minutes: 10))
            .toIso8601String();

        // Within-tenant first
        if (tid != null) {
          final within = await _client
              .from('pvp_matches')
              .select()
              .eq('status', 'pending')
              .eq('tenant_id', tid)
              .eq('wager_amount', wagerAmount)
              .neq('player1_id', uid)
              .gte('created_at', freshSince)
              .gte('player1_elo_at_match', userElo - range)
              .lte('player1_elo_at_match', userElo + range)
              .limit(1)
              .maybeSingle();

          if (within != null) {
            return _joinMatch(PvPMatch.fromMap(within), uid);
          }
        }

        // Cross-tenant
        final cross = await _client
            .from('pvp_matches')
            .select()
            .eq('status', 'pending')
            .eq('wager_amount', wagerAmount)
            .neq('player1_id', uid)
            .gte('created_at', freshSince)
            .gte('player1_elo_at_match', userElo - range)
            .lte('player1_elo_at_match', userElo + range)
            .limit(1)
            .maybeSingle();

        if (cross != null) {
          return _joinMatch(PvPMatch.fromMap(cross), uid, crossTenant: true);
        }

        // Wait before expanding range (except on last iteration)
        if (range != ranges.last) {
          await Future.delayed(rangeExpandInterval);
        }
      }

      // No match found within timeout — refund wager and create new match
      if (wagerAmount > 0) {
        await _refundWager(wagerAmount);
      }
      return _createMatch(uid, tid, questionCount, timePerQuestion, wagerAmount, userElo);
    } catch (e) {
      debugPrint('PvP findOrCreateMatch error: $e');
      // Refund on error
      if (wagerAmount > 0) await _refundWager(wagerAmount);
      return null;
    }
  }

  Future<PvPMatch?> joinByInvite(String matchId) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final res = await _client
          .from('pvp_matches')
          .select()
          .eq('id', matchId)
          .eq('status', 'pending')
          .maybeSingle();
      if (res == null) return null;
      return _joinMatch(PvPMatch.fromMap(res), uid);
    } catch (e) {
      debugPrint('joinByInvite error: $e');
      return null;
    }
  }

  Future<PvPMatch?> _joinMatch(PvPMatch match, String uid, {bool crossTenant = false}) async {
    // Server-side join: verifies availability, charges the joiner's wager,
    // fills the player2 slot atomically (join_pvp_match RPC).
    try {
      final res = await _client.rpc('join_pvp_match', params: {
        'p_match_id': match.id,
      });
      final data = res as Map<String, dynamic>?;
      if (data?['success'] != true) {
        debugPrint('[PvP] Join failed: $data');
        return null;
      }
    } catch (e) {
      debugPrint('[PvP] Join failed: $e');
      return null;
    }

    try {
      final joinerProfile = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', uid)
          .maybeSingle();
      final joinerName = joinerProfile?['full_name'] ?? 'An opponent';
      await _client.functions.invoke('push-notifications', body: {
        'userId': match.player1Id,
        'title': crossTenant ? 'Cross-Tenant Opponent Found!' : 'Opponent Found!',
        'body': '$joinerName has accepted your challenge. Get ready!',
        'data': {
          'type': 'pvp_match',
          'reference_id': match.id,
          'channel_id': 'coa_events',
        },
      });
    } catch (e) {
      debugPrint('[PvP] Opponent found notification failed: $e');
    }

    return PvPMatch(
      id: match.id,
      player1Id: match.player1Id,
      player2Id: uid,
      status: 'accepted',
      channelName: 'pvp_${match.id}',
      questionCount: match.questionCount,
      timePerQuestion: match.timePerQuestion,
      wagerAmount: match.wagerAmount,
      player1EloAtMatch: match.player1EloAtMatch,
      player2EloChange: 0,
    );
  }

  Future<PvPMatch> _createMatch(
    String uid,
    String? tid,
    int questionCount,
    int timePerQuestion,
    int wagerAmount,
    int userElo,
  ) async {
    final matchId = const Uuid().v4();
    final channelName = 'pvp_$matchId';
    await _client.from('pvp_matches').insert({
      'id': matchId,
      'player1_id': uid,
      'tenant_id': tid,
      'status': 'pending',
      'channel_name': channelName,
      'question_count': questionCount,
      'time_per_question': timePerQuestion,
      'wager_amount': wagerAmount,
      'player1_elo_at_match': userElo,
    });
    return PvPMatch(
      id: matchId,
      player1Id: uid,
      status: 'pending',
      channelName: channelName,
      questionCount: questionCount,
      timePerQuestion: timePerQuestion,
      wagerAmount: wagerAmount,
      player1EloAtMatch: userElo,
    );
  }

  Stream<Map<String, dynamic>?> watchMatchScores(String matchId) {
    return _client
        .from('pvp_matches')
        .stream(primaryKey: ['id'])
        .eq('id', matchId)
        .map((list) {
      if (list.isEmpty) return null;
      return list.first;
    });
  }

  Future<PvPMatch?> waitForMatch(String matchId, {Duration timeout = const Duration(seconds: 30)}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      try {
        final res = await _client
            .from('pvp_matches')
            .select()
            .eq('id', matchId)
            .maybeSingle();
        if (res != null) {
          final match = PvPMatch.fromMap(res);
          if (match.status == 'accepted' || match.status == 'playing') return match;
        }
      } catch (e) {
        debugPrint('Error polling PvP match status: $e');
      }
    }
    return null;
  }

  /// Connect to Supabase Realtime broadcast channel with auto-reconnect.
  ///
  /// Broadcasts on channel `pvp_room_{match_id}`:
  ///   - `opponent_answered`: { player_id, question_index, score, correct_count }
  ///   - `live_score`: { player_id, score, correct_count }
  ///   - `match_complete`: { winner_id, player1_score, player2_score }
  ///   - `rematch_invite`: { from_player_id, match_id }
  RealtimeChannel connectToChannel(PvPMatch match) {
    _lastMatchId = match.id;
    _reconnectAttempts = 0;
    _channel = _client.channel('pvp_room_${match.id}');

    _channel!.onBroadcast(event: 'opponent_answered', callback: (payload) {
      _onOpponentAnswer(payload, match);
    });

    _channel!.onBroadcast(event: 'live_score', callback: (payload) {
      debugPrint('[PvP] Live score update: $payload');
    });

    _channel!.onBroadcast(event: 'match_complete', callback: (payload) {
      _onMatchComplete(payload, match);
    });

    _channel!.onBroadcast(event: 'rematch_invite', callback: (payload) {
      debugPrint('[PvP] Rematch invite from: ${payload['from_player_id']}');
    });

    _channel!.subscribe((status, [error]) {
      final statusStr = status.toString().split('.').last;
      if (statusStr == 'subscribed') {
        _isConnected = true;
        _reconnectAttempts = 0;
        onConnectionStateChanged?.call(true);
        debugPrint('[PvP] Channel subscribed: pvp_room_${match.id}');
      } else if (statusStr == 'channelError' || statusStr == 'timedOut') {
        _isConnected = false;
        onConnectionStateChanged?.call(false);
        onChannelError?.call('${error ?? statusStr}');
        debugPrint('[PvP] Channel error: $statusStr — attempting reconnect');
        _scheduleReconnect(match);
      } else if (statusStr == 'closed') {
        _isConnected = false;
        onConnectionStateChanged?.call(false);
        debugPrint('[PvP] Channel closed — attempting reconnect');
        _scheduleReconnect(match);
      }
    });

    return _channel!;
  }

  void _scheduleReconnect(PvPMatch match) {
    _reconnectTimer?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[PvP] Max reconnect attempts reached — match may be lost');
      onChannelError?.call('Connection lost. Please check your network.');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts); // 2s, 4s, 6s, 8s, 10s
    debugPrint('[PvP] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(delay, () {
      if (_lastMatchId == null) return; // disconnected intentionally
      debugPrint('[PvP] Attempting reconnect...');
      disconnect();
      connectToChannel(match);
    });
  }

  void _onOpponentAnswer(Map<String, dynamic> payload, PvPMatch match) {
    debugPrint('[PvP] Opponent answered Q${payload['question_index']} — score: ${payload['score']}');
    onOpponentAnswered?.call(payload);
  }

  void _onMatchComplete(Map<String, dynamic> payload, PvPMatch match) {
    debugPrint('[PvP] Match complete — winner: ${payload['winner_id']}');
  }

  /// Send answer via broadcast + persist to DB.
  Future<void> sendAnswer({
    required PvPMatch match,
    required int questionIndex,
    required String questionId,
    required int selectedAnswer,
    required int responseTimeMs,
    required bool isCorrect,
    required int score,
    required int correctCount,
  }) async {
    try {
      await _client.from('pvp_answers').insert({
        'match_id': match.id,
        'player_id': currentUserId,
        'question_id': questionId,
        'question_index': questionIndex,
        'selected_answer': selectedAnswer,
        'response_time_ms': responseTimeMs,
        'is_correct': isCorrect,
      });

      // Broadcast answer to opponent
      await _channel?.sendBroadcastMessage(event: 'opponent_answered', payload: {
        'player_id': currentUserId,
        'question_index': questionIndex,
        'selected_answer': selectedAnswer,
        'score': score,
        'correct_count': correctCount,
        'response_time_ms': responseTimeMs,
      });

      // Broadcast live score update
      await _channel?.sendBroadcastMessage(event: 'live_score', payload: {
        'player_id': currentUserId,
        'score': score,
        'correct_count': correctCount,
      });
    } catch (e) {
      debugPrint('PvP sendAnswer error: $e');
    }
  }

  /// Complete the match — server-side settlement (verified scores + ELO +
  /// wager). Winner is derived from pvp_answers against the question bank.
  Future<void> completeMatch(PvPMatch match) async {
    final uid = currentUserId;
    if (uid == null) return;

    Map<String, dynamic>? result;
    try {
      final res = await _client.rpc('complete_pvp_match', params: {
        'p_match_id': match.id,
      });
      result = res as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[PvP] Match completion failed: $e');
    }

    // Server-derived winner (fall back to local scores only for the broadcast).
    final serverWinner = result?['winner_id']?.toString();
    final winnerId = (serverWinner != null && serverWinner.isNotEmpty)
        ? serverWinner
        : (match.player1Score > match.player2Score
            ? match.player1Id
            : (match.player2Score > match.player1Score
                ? match.player2Id
                : null));

    // Broadcast match complete
    await _channel?.sendBroadcastMessage(event: 'match_complete', payload: {
      'winner_id': winnerId,
      'player1_score': match.player1Score,
      'player2_score': match.player2Score,
      'player1_elo_change': result?['player1_elo_change'] ?? 0,
      'player2_elo_change': result?['player2_elo_change'] ?? 0,
    });

    // Notify loser
    try {
      final loserId = winnerId == match.player1Id ? match.player2Id : match.player1Id;
      if (loserId == null) return;
      final winnerProfile = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', winnerId ?? '')
          .maybeSingle();
      final winnerName = winnerProfile?['full_name'] ?? 'Your opponent';
      final resultText = winnerId == uid
          ? 'Congratulations! You won ${match.player1Score > match.player2Score ? match.player1Score : match.player2Score} to ${match.player1Score > match.player2Score ? match.player2Score : match.player1Score}!'
          : '$winnerName won. Better luck next time!';
      await _client.functions.invoke('push-notifications', body: {
        'userId': loserId,
        'title': 'Match Complete',
        'body': resultText,
        'data': {
          'type': 'pvp_result',
          'reference_id': match.id,
          'channel_id': 'coa_events',
        },
      });
    } catch (e) {
      debugPrint('[PvP] Match completion notification failed: $e');
    }

    disconnect();
  }

  /// Send a rematch invite to the opponent.
  Future<void> sendRematchInvite(PvPMatch match) async {
    final uid = currentUserId;
    if (uid == null) return;
    final opponentId = uid == match.player1Id ? match.player2Id : match.player1Id;
    if (opponentId == null) return;

    await _channel?.sendBroadcastMessage(event: 'rematch_invite', payload: {
      'from_player_id': uid,
      'match_id': match.id,
    });

    try {
      await _client.functions.invoke('push-notifications', body: {
        'userId': opponentId,
        'title': 'Rematch?',
        'body': 'Your opponent wants a rematch! Tap to accept.',
        'data': {
          'type': 'pvp_rematch',
          'reference_id': match.id,
          'channel_id': 'coa_events',
        },
      });
    } catch (e) {
      debugPrint('[PvP] Rematch notification failed: $e');
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _lastMatchId = null;
    _channel?.unsubscribe();
    _channel = null;
    _isConnected = false;
    onConnectionStateChanged?.call(false);
  }
}

final pvpServiceProvider = Provider((ref) => PvPService());
