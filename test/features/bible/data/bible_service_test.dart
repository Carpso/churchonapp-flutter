import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ignore: unused_local_variable
  late MockConnectivity mockConnectivity;

  setUp(() {
    mockConnectivity = MockConnectivity();
    SharedPreferences.setMockInitialValues({});

    const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'check') {
        return ['none'];
      }
      return null;
    });
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

    test('returns fallback verses from local map for known books', () async {
      SharedPreferences.setMockInitialValues({});
      final service = BibleService();
      final verses = await service.getChapter('web', 'Psalms', 23);
      expect(verses.length, 6);
      expect(verses.first.text, contains('Yahweh is my shepherd'));
    });

    test('throws exception when offline and no cache', () async {
      SharedPreferences.setMockInitialValues({});
      final service = BibleService();
      expect(() => service.getChapter('web', 'UnknownBook', 99), throwsException);
    });

    test('returns cached fallback after error fallback lookup', () async {
      SharedPreferences.setMockInitialValues({});
      final service = BibleService();
      final verses = await service.getChapter('web', 'Genesis', 1);
      expect(verses.length, 3);
      expect(verses.first.text, contains('In the beginning'));
    });
  });

  /* group('BibleService - getShareText', () {
    test('returns formatted share text with verses', () async {
      SharedPreferences.setMockInitialValues({
        'bible_web_John_3': '[{"chapter":3,"verse":16,"text":"For God so loved the world"}]',
      });
      final service = BibleService();
      final text = await service.getShareText('web', 'John', 3);
      expect(text, contains('John 3 (World English Bible (WEB))'));
      expect(text, contains('For God so loved the world'));
    });

    test('returns book and chapter when no verses available', () async {
      SharedPreferences.setMockInitialValues({});
      final service = BibleService();
      final text = await service.getShareText('web', 'FakeBook', 99);
      expect(text, 'FakeBook 99 (World English Bible (WEB))');
    });
  }); */
}
