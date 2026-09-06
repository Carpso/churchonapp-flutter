class LinkedScripture {
  final String aBook;
  final int aChapter;
  final int aVerse;
  final String bBook;
  final int bChapter;
  final int bVerse;
  final String type;

  const LinkedScripture({
    required this.aBook,
    required this.aChapter,
    required this.aVerse,
    required this.bBook,
    required this.bChapter,
    required this.bVerse,
    required this.type,
  });
}

const List<LinkedScripture> kLinkedScripture = [
  LinkedScripture(aBook: 'Matthew', aChapter: 5, aVerse: 3, bBook: 'Luke', bChapter: 6, bVerse: 20, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 5, aVerse: 11, bBook: 'Luke', bChapter: 6, bVerse: 22, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 6, aVerse: 9, bBook: 'Luke', bChapter: 11, bVerse: 2, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 7, aVerse: 7, bBook: 'Luke', bChapter: 11, bVerse: 9, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 3, aVerse: 13, bBook: 'Mark', bChapter: 1, bVerse: 9, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 3, aVerse: 13, bBook: 'Luke', bChapter: 3, bVerse: 21, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 13, aVerse: 31, bBook: 'Mark', bChapter: 4, bVerse: 30, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 13, aVerse: 31, bBook: 'Luke', bChapter: 13, bVerse: 18, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 16, aVerse: 15, bBook: 'Mark', bChapter: 8, bVerse: 29, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 16, aVerse: 15, bBook: 'Luke', bChapter: 9, bVerse: 20, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 16, aVerse: 24, bBook: 'Mark', bChapter: 8, bVerse: 34, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 16, aVerse: 24, bBook: 'Luke', bChapter: 9, bVerse: 23, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 17, aVerse: 1, bBook: 'Mark', bChapter: 9, bVerse: 2, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 17, aVerse: 1, bBook: 'Luke', bChapter: 9, bVerse: 28, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 19, aVerse: 13, bBook: 'Mark', bChapter: 10, bVerse: 13, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 19, aVerse: 13, bBook: 'Luke', bChapter: 18, bVerse: 15, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 21, aVerse: 12, bBook: 'Mark', bChapter: 11, bVerse: 15, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 21, aVerse: 12, bBook: 'Luke', bChapter: 19, bVerse: 45, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 26, aVerse: 26, bBook: 'Mark', bChapter: 14, bVerse: 22, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 26, aVerse: 26, bBook: 'Luke', bChapter: 22, bVerse: 19, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 26, aVerse: 39, bBook: 'Mark', bChapter: 14, bVerse: 36, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 26, aVerse: 39, bBook: 'Luke', bChapter: 22, bVerse: 42, type: 'harmony'),
  LinkedScripture(aBook: 'Matthew', aChapter: 27, aVerse: 46, bBook: 'Mark', bChapter: 15, bVerse: 34, type: 'harmony'),

  LinkedScripture(aBook: 'Isaiah', aChapter: 7, aVerse: 14, bBook: 'Matthew', bChapter: 1, bVerse: 22, type: 'fulfillment'),
  LinkedScripture(aBook: 'Micah', aChapter: 5, aVerse: 2, bBook: 'Matthew', bChapter: 2, bVerse: 5, type: 'fulfillment'),
  LinkedScripture(aBook: 'Hosea', aChapter: 11, aVerse: 1, bBook: 'Matthew', bChapter: 2, bVerse: 15, type: 'fulfillment'),
  LinkedScripture(aBook: 'Jeremiah', aChapter: 31, aVerse: 15, bBook: 'Matthew', bChapter: 2, bVerse: 17, type: 'fulfillment'),
  LinkedScripture(aBook: 'Isaiah', aChapter: 40, aVerse: 3, bBook: 'Matthew', bChapter: 3, bVerse: 3, type: 'fulfillment'),
  LinkedScripture(aBook: 'Isaiah', aChapter: 9, aVerse: 1, bBook: 'Matthew', bChapter: 4, bVerse: 14, type: 'fulfillment'),
  LinkedScripture(aBook: 'Isaiah', aChapter: 53, aVerse: 4, bBook: 'Matthew', bChapter: 8, bVerse: 16, type: 'fulfillment'),
  LinkedScripture(aBook: 'Malachi', aChapter: 3, aVerse: 1, bBook: 'Matthew', bChapter: 11, bVerse: 10, type: 'fulfillment'),
  LinkedScripture(aBook: 'Jonah', aChapter: 1, aVerse: 17, bBook: 'Matthew', bChapter: 12, bVerse: 40, type: 'fulfillment'),
  LinkedScripture(aBook: 'Isaiah', aChapter: 6, aVerse: 9, bBook: 'Matthew', bChapter: 13, bVerse: 14, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 78, aVerse: 2, bBook: 'Matthew', bChapter: 13, bVerse: 35, type: 'fulfillment'),
  LinkedScripture(aBook: 'Isaiah', aChapter: 53, aVerse: 12, bBook: 'Luke', bChapter: 22, bVerse: 37, type: 'fulfillment'),
  LinkedScripture(aBook: 'Isaiah', aChapter: 61, aVerse: 1, bBook: 'Luke', bChapter: 4, bVerse: 18, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 118, aVerse: 26, bBook: 'Matthew', bChapter: 21, bVerse: 9, type: 'fulfillment'),
  LinkedScripture(aBook: 'Zechariah', aChapter: 9, aVerse: 9, bBook: 'Matthew', bChapter: 21, bVerse: 4, type: 'fulfillment'),
  LinkedScripture(aBook: 'Zechariah', aChapter: 9, aVerse: 9, bBook: 'John', bChapter: 12, bVerse: 14, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 22, aVerse: 18, bBook: 'Matthew', bChapter: 27, bVerse: 35, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 22, aVerse: 1, bBook: 'Matthew', bChapter: 27, bVerse: 46, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 69, aVerse: 21, bBook: 'John', bChapter: 19, bVerse: 28, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 34, aVerse: 20, bBook: 'John', bChapter: 19, bVerse: 36, type: 'fulfillment'),
  LinkedScripture(aBook: 'Zechariah', aChapter: 12, aVerse: 10, bBook: 'John', bChapter: 19, bVerse: 37, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 41, aVerse: 9, bBook: 'John', bChapter: 13, bVerse: 18, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 69, aVerse: 9, bBook: 'John', bChapter: 2, bVerse: 17, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 69, aVerse: 4, bBook: 'John', bChapter: 15, bVerse: 25, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 110, aVerse: 1, bBook: 'Matthew', bChapter: 22, bVerse: 44, type: 'fulfillment'),
  LinkedScripture(aBook: 'Psalm', aChapter: 16, aVerse: 10, bBook: 'Acts', bChapter: 2, bVerse: 27, type: 'fulfillment'),
  LinkedScripture(aBook: 'Isaiah', aChapter: 53, aVerse: 7, bBook: 'Acts', bChapter: 8, bVerse: 32, type: 'fulfillment'),
];

class RelatedLink {
  final String label;
  final String bookmark;
  final int chapter;
  final int verse;
  final String type;

  const RelatedLink({
    required this.label,
    required this.bookmark,
    required this.chapter,
    required this.verse,
    required this.type,
  });
}

List<RelatedLink> builtInRelatedLinks(String book, int chapter, int verse) {
  final out = <RelatedLink>[];
  for (final link in kLinkedScripture) {
    if (link.aBook == book &&
        link.aChapter == chapter &&
        link.aVerse == verse) {
      out.add(RelatedLink(
        label: '${link.bBook} ${link.bChapter}:${link.bVerse}',
        bookmark: link.bBook,
        chapter: link.bChapter,
        verse: link.bVerse,
        type: link.type,
      ));
    } else if (link.bBook == book &&
        link.bChapter == chapter &&
        link.bVerse == verse) {
      out.add(RelatedLink(
        label: '${link.aBook} ${link.aChapter}:${link.aVerse}',
        bookmark: link.aBook,
        chapter: link.aChapter,
        verse: link.aVerse,
        type: link.type,
      ));
    }
  }
  return out;
}