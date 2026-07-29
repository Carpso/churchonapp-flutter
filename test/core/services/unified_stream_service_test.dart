import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/services/unified_stream_service.dart';

void main() {
  group('StreamingConfig Cost Controls & Tier Specs', () {
    test('defaultConfig produces correct trial tier specifications', () {
      final config = StreamingConfig.defaultConfig('tenant_trial_1');

      expect(config.tenantId, 'tenant_trial_1');
      expect(config.isPaid, false);
      expect(config.maxMinutesPerWeek, 10);
      expect(config.maxViewers, 25);
      expect(config.retentionDays, 7);
      expect(config.maxStorageGb, 1.0);
      expect(config.maxQuality, 720);
    });

    test('fromMap parses custom tenant configuration correctly', () {
      final map = {
        'church_id': 'tenant_pro_1',
        'is_paid': true,
        'max_minutes_per_week': 480,
        'max_viewers': 200,
        'retention_days': 90,
        'max_storage_gb': 10.0,
        'max_quality': 720,
        'max_concurrent_streams': 2,
      };

      final config = StreamingConfig.fromMap(map);

      expect(config.tenantId, 'tenant_pro_1');
      expect(config.isPaid, true);
      expect(config.maxMinutesPerWeek, 480);
      expect(config.maxViewers, 200);
      expect(config.retentionDays, 90);
      expect(config.maxStorageGb, 10.0);
      expect(config.maxConcurrentStreams, 2);
    });
  });

  group('StreamGateResult Enforcement', () {
    test('allows stream when limits are within quota', () {
      final gate = StreamGateResult(allowed: true);
      expect(gate.allowed, true);
      expect(gate.reason, isNull);
      expect(gate.upgradeRequired, false);
      expect(gate.storageExceeded, false);
    });

    test('blocks stream when weekly limit is reached and requires upgrade', () {
      final gate = StreamGateResult(
        allowed: false,
        reason: 'Weekly streaming limit reached (10 min)',
        upgradeRequired: true,
      );

      expect(gate.allowed, false);
      expect(gate.reason, contains('Weekly streaming limit reached'));
      expect(gate.upgradeRequired, true);
    });

    test('blocks stream when storage quota is exceeded', () {
      final gate = StreamGateResult(
        allowed: false,
        reason: 'Storage limit reached (1.0GB)',
        upgradeRequired: true,
        storageExceeded: true,
      );

      expect(gate.allowed, false);
      expect(gate.storageExceeded, true);
    });
  });

  group('StreamingUsage Byte and Duration Parsing', () {
    test('default StreamingUsage initializes with zero usage', () {
      final usage = StreamingUsage(tenantId: 'tenant_1');

      expect(usage.tenantId, 'tenant_1');
      expect(usage.minutesUsed, 0);
      expect(usage.peakViewers, 0);
      expect(usage.storageUsedGb, 0.0);
    });

    test('fromMap calculates storage in GB accurately', () {
      final map = {
        'church_id': 'tenant_1',
        'minutes_used': 45,
        'peak_viewers': 88,
        'storage_used_gb': 2.0,
      };

      final usage = StreamingUsage.fromMap(map);

      expect(usage.minutesUsed, 45);
      expect(usage.peakViewers, 88);
      expect(usage.storageUsedGb, 2.0);
    });
  });
}
