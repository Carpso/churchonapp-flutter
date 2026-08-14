import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';

void main() {
  group('parseScriptureReference', () {
    test('parses single verse', () {
      final r = parseScriptureReference('John 3:16');
      expect(r, isNotNull);
      expect(r!.book, 'John');
      expect(r.chapter, 3);
      expect(r.verseStart, 16);
      expect(r.verseEnd, 16);
    });

    test('parses verse ranges', () {
      final r = parseScriptureReference('1 Corinthians 13:4-5');
      expect(r!.book, '1 Corinthians');
      expect(r.chapter, 13);
      expect(r.verseStart, 4);
      expect(r.verseEnd, 5);
    });

    test('parses whole chapter', () {
      final r = parseScriptureReference('Exodus 20');
      expect(r!.book, 'Exodus');
      expect(r.chapter, 20);
      expect(r.hasVerses, isFalse);
    });

    test('chapter range falls back to first chapter', () {
      final r = parseScriptureReference('Exodus 7-12');
      expect(r!.book, 'Exodus');
      expect(r.chapter, 7);
    });

    test('normalizes book aliases', () {
      expect(parseScriptureReference('Psalm 23:1')!.book, 'Psalms');
      expect(parseScriptureReference('Song of Songs 2:1')!.book, 'Song of Solomon');
      expect(parseScriptureReference('Revelations 22:8')!.book, 'Revelation');
    });

    test('rejects garbage', () {
      expect(parseScriptureReference(''), isNull);
      expect(parseScriptureReference('John'), isNull);
      expect(parseScriptureReference('123'), isNull);
    });
  });
}