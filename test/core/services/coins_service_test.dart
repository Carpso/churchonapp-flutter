import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/coins_service.dart';
import '../../test_mocks.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockUser extends Mock implements User {}

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockGoTrue;
  late CoinsService coinsService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockClient = MockSupabaseClient();
    mockGoTrue = MockGoTrueClient();
    coinsService = CoinsService(mockClient);
    when(() => mockClient.auth).thenReturn(mockGoTrue);
  });

  group('CoinsService', () {
    test('Constructor takes SupabaseClient', () {
      expect(coinsService, isA<CoinsService>());
    });

    group('getCoins', () {
      test('returns 0 when no user is authenticated', () async {
        when(() => mockGoTrue.currentUser).thenReturn(null);
        final coins = await coinsService.getCoins();
        expect(coins, 0);
      });
    });

    group('canCollectDaily', () {
      test('returns true when no previous collect time', () async {
        final result = await coinsService.canCollectDaily();
        expect(result, true);
      });

      test('returns false when collected less than 20 hours ago', () async {
        final prefs = await SharedPreferences.getInstance();
        final recentTime = DateTime.now().subtract(const Duration(hours: 10));
        await prefs.setString('last_daily_coin_collect', recentTime.toIso8601String());
        
        final result = await coinsService.canCollectDaily();
        expect(result, false);
      });

      test('returns true when collected more than 20 hours ago', () async {
        final prefs = await SharedPreferences.getInstance();
        final oldTime = DateTime.now().subtract(const Duration(hours: 21));
        await prefs.setString('last_daily_coin_collect', oldTime.toIso8601String());
        
        final result = await coinsService.canCollectDaily();
        expect(result, true);
      });
    });

    group('hasCollectedToday', () {
      test('returns false when can collect', () async {
        final result = await coinsService.hasCollectedToday();
        expect(result, false);
      });

      test('returns true when cannot collect', () async {
        final prefs = await SharedPreferences.getInstance();
        final recentTime = DateTime.now().subtract(const Duration(hours: 5));
        await prefs.setString('last_daily_coin_collect', recentTime.toIso8601String());
        
        final result = await coinsService.hasCollectedToday();
        expect(result, true);
      });
    });

    group('collectDailyCoins', () {
      test('throws when not authenticated', () async {
        when(() => mockGoTrue.currentUser).thenReturn(null);
        expect(() => coinsService.collectDailyCoins(), throwsA(isA<Exception>()));
      });

      test('returns 0 when cannot collect', () async {
        final mockUser = MockUser();
        when(() => mockGoTrue.currentUser).thenReturn(mockUser);
        
        final prefs = await SharedPreferences.getInstance();
        final recentTime = DateTime.now().subtract(const Duration(hours: 5));
        await prefs.setString('last_daily_coin_collect', recentTime.toIso8601String());
        
        final result = await coinsService.collectDailyCoins();
        expect(result, 0);
      });
    });

    group('addStreakBonus', () {
      test('throws when not authenticated', () async {
        when(() => mockGoTrue.currentUser).thenReturn(null);
        expect(() => coinsService.addStreakBonus(1), throwsA(isA<Exception>()));
      });

      test('returns 0 for streak count 0', () async {
        final mockUser = MockUser();
        when(() => mockGoTrue.currentUser).thenReturn(mockUser);
        final result = await coinsService.addStreakBonus(0);
        expect(result, 0);
      });

      test('returns 0 for negative streak count', () async {
        final mockUser = MockUser();
        when(() => mockGoTrue.currentUser).thenReturn(mockUser);
        final result = await coinsService.addStreakBonus(-1);
        expect(result, 0);
      });
    });

    group('addAppOpenStreakCoins', () {
      test('throws when not authenticated', () async {
        when(() => mockGoTrue.currentUser).thenReturn(null);
        expect(() => coinsService.addAppOpenStreakCoins(1), throwsA(isA<Exception>()));
      });

      test('returns 0 for day 0', () async {
        final mockUser = MockUser();
        when(() => mockGoTrue.currentUser).thenReturn(mockUser);
        final result = await coinsService.addAppOpenStreakCoins(0);
        expect(result, 0);
      });

      test('returns 5 coins for day 1', () async {
        final mockUser = MockUser();
        when(() => mockUser.id).thenReturn('test-user');
        when(() => mockGoTrue.currentUser).thenReturn(mockUser);
        when(() => mockClient.rpc(any(), params: any(named: 'params'))).thenReturn(MockFilterBuilder());
        final result = await coinsService.addAppOpenStreakCoins(1);
        expect(result, 5);
      });

      test('returns 10 coins for day 3', () async {
        final mockUser = MockUser();
        when(() => mockUser.id).thenReturn('test-user');
        when(() => mockGoTrue.currentUser).thenReturn(mockUser);
        when(() => mockClient.rpc(any(), params: any(named: 'params'))).thenReturn(MockFilterBuilder());
        final result = await coinsService.addAppOpenStreakCoins(3);
        expect(result, 10);
      });

      test('returns 20 coins for day 7', () async {
        final mockUser = MockUser();
        when(() => mockUser.id).thenReturn('test-user');
        when(() => mockGoTrue.currentUser).thenReturn(mockUser);
        when(() => mockClient.rpc(any(), params: any(named: 'params'))).thenReturn(MockFilterBuilder());
        final result = await coinsService.addAppOpenStreakCoins(7);
        expect(result, 20);
      });

      test('returns 30 coins for day 14', () async {
        final mockUser = MockUser();
        when(() => mockUser.id).thenReturn('test-user');
        when(() => mockGoTrue.currentUser).thenReturn(mockUser);
        when(() => mockClient.rpc(any(), params: any(named: 'params'))).thenReturn(MockFilterBuilder());
        final result = await coinsService.addAppOpenStreakCoins(14);
        expect(result, 30);
      });
    });

    group('redeemAtBookshop', () {
      test('throws when not authenticated', () async {
        when(() => mockGoTrue.currentUser).thenReturn(null);
        expect(
          () => coinsService.redeemAtBookshop(
            coinAmount: 100,
            bookshopId: 'bookshop-id',
            description: 'Test redemption',
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('redeemAtMerchStore', () {
      test('throws when not authenticated', () async {
        when(() => mockGoTrue.currentUser).thenReturn(null);
        expect(
          () => coinsService.redeemAtMerchStore(
            coinAmount: 100,
            itemId: 'item-id',
            description: 'Test redemption',
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('addAttendanceCoins', () {
      test('throws when not authenticated', () async {
        when(() => mockGoTrue.currentUser).thenReturn(null);
        expect(() => coinsService.addAttendanceCoins(), throwsA(isA<Exception>()));
      });
    });

    group('addReferralCoins', () {
      test('throws when not authenticated', () async {
        when(() => mockGoTrue.currentUser).thenReturn(null);
        expect(() => coinsService.addReferralCoins(), throwsA(isA<Exception>()));
      });
    });
  });
}
