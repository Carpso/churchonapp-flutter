import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/admin/data/pastoral_followup_service.dart';

void main() {
  group('PastoralFollowup.fromMap', () {
    test('parses a full row', () {
      final f = PastoralFollowup.fromMap({
        'id': 'fu-1',
        'tenant_id': 'ten-1',
        'member_id': 'mem-1',
        'followup_type': 'whatsapp',
        'notes': 'Prayed with family, needs job advice',
        'status': 'open',
        'follow_up_at': '2026-08-20T10:00:00.000Z',
        'completed_at': null,
        'created_by': 'leader-1',
        'created_at': '2026-08-17T09:00:00.000Z',
      });

      expect(f.id, 'fu-1');
      expect(f.tenantId, 'ten-1');
      expect(f.memberId, 'mem-1');
      expect(f.followupType, 'whatsapp');
      expect(f.notes, 'Prayed with family, needs job advice');
      expect(f.status, 'open');
      expect(f.isOpen, isTrue);
      expect(f.followUpAt, DateTime.utc(2026, 8, 20, 10));
      expect(f.completedAt, isNull);
      expect(f.createdBy, 'leader-1');
      expect(f.createdAt, DateTime.utc(2026, 8, 17, 9));
    });

    test('applies defaults for missing optional fields', () {
      final f = PastoralFollowup.fromMap({
        'id': 'fu-2',
        'tenant_id': 'ten-1',
        'member_id': 'mem-2',
        'created_at': '2026-08-17T09:00:00.000Z',
      });

      expect(f.followupType, 'visit');
      expect(f.notes, '');
      expect(f.status, 'open');
      expect(f.isOpen, isTrue);
      expect(f.followUpAt, isNull);
      expect(f.completedAt, isNull);
      expect(f.createdBy, isNull);
    });

    test('completed rows are not open', () {
      final f = PastoralFollowup.fromMap({
        'id': 'fu-3',
        'tenant_id': 'ten-1',
        'member_id': 'mem-3',
        'status': 'done',
        'completed_at': '2026-08-18T10:00:00.000Z',
        'created_at': '2026-08-17T09:00:00.000Z',
      });

      expect(f.isOpen, isFalse);
      expect(f.completedAt, DateTime.utc(2026, 8, 18, 10));
    });

    test('cancelled rows are not open', () {
      final f = PastoralFollowup.fromMap({
        'id': 'fu-4',
        'tenant_id': 'ten-1',
        'member_id': 'mem-4',
        'status': 'cancelled',
        'created_at': '2026-08-17T09:00:00.000Z',
      });

      expect(f.isOpen, isFalse);
    });

    test('handles every follow-up type label mapping', () {
      for (final type in ['visit', 'phone', 'whatsapp', 'sms', 'email', 'in_church']) {
        final f = PastoralFollowup.fromMap({
          'id': 'fu-$type',
          'tenant_id': 'ten-1',
          'member_id': 'mem-1',
          'followup_type': type,
          'created_at': '2026-08-17T09:00:00.000Z',
        });
        expect(f.followupType, type);
      }
    });

    test('tolerates a bad created_at date', () {
      final f = PastoralFollowup.fromMap({
        'id': 'fu-5',
        'tenant_id': 'ten-1',
        'member_id': 'mem-5',
        'created_at': 'not-a-date',
      });
      expect(f.createdAt.isAfter(DateTime(2020)), isTrue);
    });
  });
}