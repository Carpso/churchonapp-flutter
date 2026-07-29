import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/finance/data/partner_tenant_service.dart';

void main() {
  group('PartnerTenant', () {
    test('creates from map correctly', () {
      final map = {
        'id': 'test-id',
        'name': 'Test Bookshop',
        'type': 'bookshop',
        'description': 'A test bookshop',
        'location': 'Lusaka',
        'logo_url': 'https://example.com/logo.jpg',
        'is_active': true,
        'created_at': '2026-01-01T00:00:00Z',
      };
      final partner = PartnerTenant.fromMap(map);
      expect(partner.id, 'test-id');
      expect(partner.name, 'Test Bookshop');
      expect(partner.type, 'bookshop');
      expect(partner.description, 'A test bookshop');
      expect(partner.location, 'Lusaka');
      expect(partner.logoUrl, 'https://example.com/logo.jpg');
      expect(partner.isActive, true);
    });

    test('handles missing optional fields', () {
      final map = <String, dynamic>{
        'id': 'test-id',
        'name': 'Test',
        'type': 'other',
      };
      final partner = PartnerTenant.fromMap(map);
      expect(partner.description, isNull);
      expect(partner.location, isNull);
      expect(partner.logoUrl, isNull);
      expect(partner.isActive, true);
    });

    test('defaults to inactive when is_active is false', () {
      final map = {
        'id': 'test-id',
        'name': 'Test',
        'type': 'bookshop',
        'is_active': false,
        'created_at': '2026-01-01T00:00:00Z',
      };
      final partner = PartnerTenant.fromMap(map);
      expect(partner.isActive, false);
    });
  });

  group('PartnerOffer', () {
    test('creates from map correctly', () {
      final map = {
        'id': 'offer-id',
        'partner_id': 'partner-id',
        'title': 'Free Coffee',
        'description': 'Get a free coffee',
        'coins_required': 100,
        'image_url': 'https://example.com/coffee.jpg',
        'is_active': true,
        'redeemed_count': 5,
      };
      final offer = PartnerOffer.fromMap(map);
      expect(offer.id, 'offer-id');
      expect(offer.partnerId, 'partner-id');
      expect(offer.title, 'Free Coffee');
      expect(offer.description, 'Get a free coffee');
      expect(offer.coinsRequired, 100);
      expect(offer.imageUrl, 'https://example.com/coffee.jpg');
      expect(offer.isActive, true);
      expect(offer.redeemedCount, 5);
    });

    test('handles missing optional fields', () {
      final map = <String, dynamic>{
        'id': 'offer-id',
        'partner_id': 'partner-id',
        'title': 'Test',
        'coins_required': 50,
      };
      final offer = PartnerOffer.fromMap(map);
      expect(offer.description, isNull);
      expect(offer.imageUrl, isNull);
      expect(offer.isActive, true);
      expect(offer.redeemedCount, 0);
    });

    test('coins required is correctly parsed', () {
      final map = {
        'id': 'offer-id',
        'partner_id': 'partner-id',
        'title': 'Premium Offer',
        'coins_required': 500,
      };
      final offer = PartnerOffer.fromMap(map);
      expect(offer.coinsRequired, 500);
    });
  });
}
