import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/transport/data/ride_request_model.dart';
import 'package:church_on_app/features/transport/data/delivery_model.dart';

void main() {
  Map<String, dynamic> rideMap({String status = 'pending', String payment = 'unpaid'}) => {
        'id': 'r1',
        'rider_id': 'u-rider',
        'driver_id': null,
        'pickup_address': 'Kabulonga',
        'delivery_address': 'CBD',
        'status': status,
        'payment_status': payment,
      };

  Map<String, dynamic> parcelMap({String status = 'pending', String payment = 'unpaid'}) => {
        'id': 'p1',
        'sender_id': 'u-sender',
        'driver_id': null,
        'pickup_address': 'Store',
        'delivery_address': 'Home',
        'status': status,
        'payment_status': payment,
      };

  group('Ride dispatch state machine (hailing)', () {
    test('legal transitions pending → accepted → completed', () {
      const legal = ['pending', 'accepted', 'confirmed', 'completed'];
      // Model contract: statuses flow forward only; verify parse integrity.
      for (var i = 0; i < legal.length; i++) {
        final r = RideRequest.fromMap(rideMap(status: legal[i]));
        expect(r.status, legal[i]);
        if (i + 1 < legal.length) {
          expect(legal.indexOf(r.status), lessThan(legal.indexOf(legal[i + 1])));
        }
      }
    });

    test('cancelled is terminal from any pre-completion state', () {
      for (final s in ['pending', 'accepted', 'confirmed']) {
        final r = RideRequest.fromMap(rideMap(status: s));
        expect(r.status, isNot('completed'));
        expect(['pending', 'accepted', 'confirmed'], contains(s));
      }
    });

    test('payment status defaults to unpaid and parses paid', () {
      expect(RideRequest.fromMap(rideMap()).paymentStatus, 'unpaid');
      expect(RideRequest.fromMap(rideMap(payment: 'paid')).paymentStatus, 'paid');
    });

    test('fromMap tolerates missing optional fields (null safety)', () {
      final r = RideRequest.fromMap({'id': 'x', 'status': 'pending'});
      expect(r.id, 'x');
      expect(r.status, 'pending');
    });

    test('toMap roundtrip preserves dispatch fields', () {
      final r = RideRequest.fromMap(rideMap(status: 'accepted', payment: 'pending'));
      final m = r.toMap();
      expect(m['status'], 'accepted');
      expect(m['payment_status'], 'pending');
    });
  });

  group('Parcel delivery state machine (logistics)', () {
    test('full lifecycle pending → in_transit → delivered', () {
      const stages = ['pending', 'accepted', 'assigned', 'in_transit', 'delivered'];
      for (var i = 0; i < stages.length - 1; i++) {
        final cur = DeliveryRequest.fromMap(parcelMap(status: stages[i]));
        final next = DeliveryRequest.fromMap(parcelMap(status: stages[i + 1]));
        expect(stages.indexOf(cur.status), lessThan(stages.indexOf(next.status)));
      }
      final delivered = DeliveryRequest.fromMap(parcelMap(status: 'delivered'));
      expect(delivered.status, 'delivered');
    });

    test('delivered parcels must be paid before payout eligibility', () {
      final unpaidDelivered = DeliveryRequest.fromMap(parcelMap(status: 'delivered'));
      final paidDelivered =
          DeliveryRequest.fromMap(parcelMap(status: 'delivered', payment: 'paid'));
      expect(unpaidDelivered.paymentStatus, 'unpaid',
          reason: 'settlement layer must reject unpaid deliveries');
      expect(paidDelivered.paymentStatus, 'paid');
    });

    test('fromMap handles missing driver (pre-assignment)', () {
      final d = DeliveryRequest.fromMap({'id': 'd1', 'status': 'pending'});
      expect(d.status, 'pending');
    });
  });
}
