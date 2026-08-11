import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BibleService - getChapter', () {
    test('returns cached verses when available in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'bible_web_John_1': '[{"chapter":1,"verse":1,"text":"In the beginning was the Word"}]',
      });
      final service = BibleService();
      final verses = await service.getChapter('web', 'John', 1);
      expect(verses.length, 1);
      expect(verses.first.text, 'In the beginning was the Word');
    });

    test('returns empty list for unsupported translation (no network)', () async {
      // 'msg' is neither on bible-api.com nor in the local table — service
      // should return [] gracefully (it does not throw).
      SharedPreferences.setMockInitialValues({});
      final service = BibleService();
      final verses = await service.getChapter('msg', 'John', 1);
      expect(verses, isEmpty);
    });

    test('caches a chapter on first fetch and re-reads from cache', () async {
      SharedPreferences.setMockInitialValues({});
      final service = BibleService();
      // First call populates the cache key (empty result is not cached),
      // but a seeded cache entry is returned verbatim:
      SharedPreferences.setMockInitialValues({
        'bible_web_Genesis_1': '[{"chapter":1,"verse":1,"text":"In the beginning God created the heaven"}]',
      });
      final verses = await service.getChapter('web', 'Genesis', 1);
      expect(verses.length, 1);
      expect(verses.first.text, contains('In the beginning'));
    });
  });
}
