import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart';
import 'package:church_on_app/core/services/r2_service.dart';

class OfflineQueueItem {
  final String table;
  final Map<String, dynamic> data;
  final String operation;
  final DateTime queuedAt;

  OfflineQueueItem({
    required this.table,
    required this.data,
    required this.operation,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'table': table,
    'data': data,
    'operation': operation,
    'queuedAt': queuedAt.toIso8601String(),
  };

  factory OfflineQueueItem.fromJson(Map<String, dynamic> json) => OfflineQueueItem(
    table: json['table'] as String,
    data: Map<String, dynamic>.from(json['data'] as Map),
    operation: json['operation'] as String,
    queuedAt: DateTime.parse(json['queuedAt'] as String),
  );
}

class OfflineService {
  static const String _queueKey = 'offline_sync_queue';
  static const int _maxRetries = 3;
  
  final R2Service? _r2service;
  OfflineService([this._r2service]);

  final StreamController<int> _queueLengthController = StreamController<int>.broadcast();
  final StreamController<bool> _offlineController = StreamController<bool>.broadcast();
  StreamSubscription? _connectivitySub;
  bool _isOffline = false;

  Stream<int> get queueLengthStream => _queueLengthController.stream;
  Stream<bool> get offlineStream => _offlineController.stream;
  bool get isOffline => _isOffline;
  int _currentLength = 0;

  /// Start auto-sync AND process any pending queue on startup.
  void startAutoSync() {
    // P1 FIX: Process queue immediately on startup if we have connectivity
    _checkAndProcessOnStartup();

    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((result) async {
      final wasOffline = _isOffline;
      _isOffline = result.every((r) => r == ConnectivityResult.none);
      _offlineController.add(_isOffline);

      if (!_isOffline) {
        // Transitioned from offline to online — process queue
        final processed = await processQueue();
        if (processed > 0) {
          debugPrint("OfflineService: Auto-synced $processed items");
        }
      } else if (!wasOffline) {
        debugPrint("OfflineService: Device went offline — queueing changes");
      }
    });

    // Also check initial connectivity state
    Connectivity().checkConnectivity().then((result) {
      _isOffline = result.every((r) => r == ConnectivityResult.none);
      _offlineController.add(_isOffline);
    });
  }

  /// P1 FIX: Process pending queue on app startup if connected
  Future<void> _checkAndProcessOnStartup() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final isConnected = result.any((r) => r != ConnectivityResult.none);
      if (isConnected) {
        // Delay slightly to let Supabase initialize
        await Future.delayed(const Duration(seconds: 2));
        final processed = await processQueue();
        if (processed > 0) {
          debugPrint("OfflineService: Startup sync processed $processed items");
        }
      }
    } catch (e) {
      debugPrint("OfflineService: Startup check failed: $e");
    }
  }

  void stopAutoSync() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<List<OfflineQueueItem>> _getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null) return [];
    try {
      final List items = jsonDecode(raw);
      return items.map((e) => OfflineQueueItem.fromJson(e)).toList();
    } catch (e) {
      debugPrint("OfflineService: Error decoding queue: $e");
      return [];
    }
  }

  Future<void> _saveQueue(List<OfflineQueueItem> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(queue.map((e) => e.toJson()).toList()));
    _currentLength = queue.length;
    _queueLengthController.add(_currentLength);
  }

  Future<void> enqueue(String table, Map<String, dynamic> data, String operation) async {
    final queue = await _getQueue();
    queue.add(OfflineQueueItem(table: table, data: data, operation: operation));
    await _saveQueue(queue);
    debugPrint("OfflineService: Enqueued $operation on $table (queue: ${queue.length})");
  }

  bool _isProcessing = false;

  Future<Map<String, dynamic>> _processLocalMediaFields(Map<String, dynamic> data) async {
    final updatedData = Map<String, dynamic>.from(data);
    for (final entry in updatedData.entries) {
      final value = entry.value;
      if (value is String && value.startsWith('local://')) {
        try {
          final uri = Uri.parse(value);
          final remotePath = uri.host + uri.path;
          final localPath = uri.queryParameters['localPath'];
          if (localPath != null) {
            final file = File(localPath);
            if (await file.exists()) {
              debugPrint("OfflineService: Uploading queued file $localPath to R2: $remotePath");
              final publicUrl = await _r2service?.uploadFile(file, remotePath);
              if (publicUrl != null && !publicUrl.startsWith('local://')) {
                updatedData[entry.key] = publicUrl;
                // Delete local file after successful upload
                await file.delete();
                debugPrint("OfflineService: Uploaded successfully, URL: $publicUrl");
              } else {
                throw Exception("Failed to upload queued file to R2");
              }
            } else {
              debugPrint("OfflineService: Queued local file not found at $localPath, setting to null");
              updatedData[entry.key] = null;
            }
          }
        } catch (e) {
          debugPrint("OfflineService: Error uploading offline media field: $e");
          rethrow;
        }
      } else if (value is Map) {
        updatedData[entry.key] = await _processLocalMediaFields(Map<String, dynamic>.from(value));
      }
    }
    return updatedData;
  }

  Future<int> processQueue() async {
    if (_isProcessing) return 0;
    _isProcessing = true;
    try {
      final queue = await _getQueue();
      if (queue.isEmpty) return 0;

      final supabase = Supabase.instance.client;
      int processed = 0;
      final remaining = <OfflineQueueItem>[];

      for (final item in queue) {
        int retries = 0;
        bool success = false;
        while (!success && retries <= _maxRetries) {
          try {
            // Preprocess local media fields to upload them to R2 first
            final syncData = await _processLocalMediaFields(item.data);

            switch (item.operation) {
              case 'insert':
                await supabase.from(item.table).insert(syncData);
                break;
              case 'update':
                final id = syncData['id'];
                if (id != null) {
                  await supabase.from(item.table).update(syncData).eq('id', id);
                }
                break;
              case 'delete':
                final id = syncData['id'];
                if (id != null) {
                  await supabase.from(item.table).delete().eq('id', id);
                }
                break;
            }
            success = true;
            processed++;
          } catch (e) {
            retries++;
            if (retries > _maxRetries) {
              remaining.add(item);
            } else {
              await Future.delayed(Duration(seconds: retries * 2));
            }
          }
        }
      }

      await _saveQueue(remaining);
      debugPrint("OfflineService: Processed $processed items, ${remaining.length} remaining");
      return processed;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> clearQueue() async {
    await _saveQueue([]);
  }

  Future<int> getQueueLength() async {
    final queue = await _getQueue();
    return queue.length;
  }

  void dispose() {
    stopAutoSync();
    _queueLengthController.close();
    _offlineController.close();
  }
}

final offlineServiceProvider = Provider<OfflineService>((ref) {
  final r2 = ref.watch(r2ServiceProvider);
  final service = OfflineService(r2);
  ref.onDispose(() => service.dispose());
  return service;
});
