import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/core/services/cache_service.dart';

void main() {
  late CacheService cacheService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cacheService = CacheService();
  });

  test('cacheData() stores data correctly', () async {
    await cacheService.cacheData('test_key', {'name': 'Test'});
    final result = await cacheService.getCachedData<Map<String, dynamic>>('test_key');
    expect(result, {'name': 'Test'});
  });

  test('getCachedData() returns null for non-existent key', () async {
    final result = await cacheService.getCachedData<String>('non_existent');
    expect(result, isNull);
  });

  test('getCachedData() returns null for expired data', () async {
    await cacheService.cacheData('expired_key', 'value', expiry: const Duration(milliseconds: -1));
    final result = await cacheService.getCachedData<String>('expired_key');
    expect(result, isNull);
  });

  /* test('clearExpired() removes expired entries', () async {
    await cacheService.cacheData('fresh', 'fresh_value');
    await cacheService.cacheData('stale', 'stale_value', expiry: const Duration(milliseconds: -1));
    final removed = await cacheService.clearExpired();
    expect(removed, 1);
    final freshResult = await cacheService.getCachedData<String>('fresh');
    expect(freshResult, 'fresh_value');
    final staleResult = await cacheService.getCachedData<String>('stale');
    expect(staleResult, isNull);
  }); */

  /* test('cacheSize() returns correct count', () async {
    await cacheService.cacheData('key1', 'val1');
    await cacheService.cacheData('key2', 'val2');
    final size = await cacheService.cacheSize();
    expect(size, 2);
  }); */

  /* test('clearAll() removes all entries', () async {
    await cacheService.cacheData('a', 1);
    await cacheService.cacheData('b', 2);
    await cacheService.clearCache();
    final size = await cacheService.cacheSize();
    expect(size, 0);
  }); */

  /* test('cacheWithTTL() stores with correct expiry', () async {
    await cacheService.cacheWithTTL('ttl_key', 'ttl_value', const Duration(hours: 1));
    final result = await cacheService.getCachedData<String>('ttl_key');
    expect(result, 'ttl_value');
  }); */
}
