import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/features/bible/data/strongs_lexicon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StrongsLexicon', () {
    test('loads the full public-domain dictionaries', () async {
      final lexicon = StrongsLexicon();
      final h = await lexicon.hebrew;
      final g = await lexicon.greek;
      expect(h.length, 8674);
      expect(g.length, 5624);
    });

    test('looks up Strong\'s numbers in any format', () async {
      final lexicon = StrongsLexicon();
      final h3068 = await lexicon.byNumber('3068');
      expect(h3068, isNotNull);
      expect(h3068!.id, 'H3068');
      expect(h3068.word, 'יהוה');

      final g26 = await lexicon.byNumber('G0026');
      expect(g26, isNotNull);
      expect(g26!.id, 'G26');
      expect(g26.word, 'ἀγάπη');
    });

    test('diacritic-insensitive search finds agape/shálôm/ḥeseḏ', () async {
      final lexicon = StrongsLexicon();
      final agape = await lexicon.search('agape');
      expect(agape.map((e) => e.id), contains('G26'));

      final shalom = await lexicon.search('shalom');
      expect(shalom.map((e) => e.id), contains('H7965'));

      final chesed = await lexicon.search('chesed');
      expect(chesed.map((e) => e.id), contains('H2617'));

      final love = await lexicon.search('love');
      expect(love, isNotEmpty);
    });

    test('search by meaning matches definitions', () async {
      final lexicon = StrongsLexicon();
      final grace = await lexicon.search('grace');
      expect(grace.map((e) => e.id), contains('G5485')); // charis
    });

    test('popular list is curated and non-empty', () async {
      final lexicon = StrongsLexicon();
      final popular = await lexicon.popular();
      expect(popular.length, 12);
      expect(popular.map((e) => e.id), containsAll(['G26', 'H3068', 'H7965']));
    });

    test('Hebrew entries carry morphology labels', () async {
      final lexicon = StrongsLexicon();
      final h1 = await lexicon.byNumber('H1');
      expect(h1!.morphLabel, 'Noun (masculine)');
    });
  });
}