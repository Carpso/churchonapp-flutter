import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bible_book_model.dart';

class BibleBooksService {
  static const String _cacheKey = 'bible_books_cache';
  static const String _timestampKey = 'bible_books_cache_timestamp';
  static const Duration _cacheExpiry = Duration(days: 30);

  // Primary public APIs for Bible books metadata
  static const List<String> _apiEndpoints = [
    'https://bible-api.com/books',
    'https://bible-api.com/books?translation=web',
    'https://cdn.jsdelivr.net/gh/wldeh/bible-api/bibles/en-web/books.json',
    'https://bibleapi.co/api/books',
    'https://api.scripture.api.bible/v1/bibles/eng-web/books',
  ];

  final http.Client _client;

  BibleBooksService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() {
    _client.close();
  }

  /// Fetch Bible books from public APIs with fallback chain
Future<List<BibleBook>> fetchAllBooks({bool forceRefresh = false}) async {
    // Try cache first unless forced refresh
    if (!forceRefresh) {
      final cached = await _getFromCache();
      if (cached != null && cached.isNotEmpty) {
        debugPrint('BibleBooksService: Returning ${cached.length} books from cache');
        return cached;
      }
    }

    // Try each API endpoint in order
    for (final endpoint in _apiEndpoints) {
      try {
        debugPrint('BibleBooksService: Trying endpoint: $endpoint');
        final books = await _fetchFromEndpoint(endpoint);
        if (books != null && books.isNotEmpty) {
          await _saveToCache(books);
          debugPrint('BibleBooksService: Successfully fetched ${books.length} books from $endpoint');
          return books;
        }
      } catch (e) {
        debugPrint('BibleBooksService: Endpoint $endpoint failed: $e');
        continue;
      }
    }

    // All APIs failed, return built-in defaults
    debugPrint('BibleBooksService: All APIs failed, using built-in defaults');
    return _getBuiltInDefaults();
  }

  Future<List<BibleBook>?> _fetchFromEndpoint(String endpoint) async {
    try {
      final response = await _client
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        return _parseBooksResponse(data);
      }
    } catch (e) {
      debugPrint('BibleBooksService: Failed to fetch from $endpoint: $e');
    }
    return null;
  }

  List<BibleBook> _parseBooksResponse(dynamic data) {
    final List<BibleBook> books = [];

    // Handle different API response formats
    if (data is List) {
      // Direct array of books
      for (var item in data) {
        if (item is Map<String, dynamic>) {
          final book = _parseBookItem(item);
          if (book != null) books.add(book);
        }
      }
    } else if (data is Map<String, dynamic>) {
      // Object with books array
      final booksData = data['books'] ?? data['data'] ?? data['booksList'] ?? data['booklist'];
      if (booksData is List) {
        for (var item in booksData) {
          if (item is Map<String, dynamic>) {
            final book = _parseBookItem(item);
            if (book != null) books.add(book);
          }
        }
      }
    }

    // Sort by book order
    books.sort((a, b) => a.bookOrder.compareTo(b.bookOrder));
    return books;
  }

  BibleBook? _parseBookItem(Map<String, dynamic> item) {
    try {
      // Try standard fields first
      final name = (item['name'] ?? item['book'] ?? item['bookName'] ?? item['title'] ?? '').toString().trim();
      if (name.isEmpty) return null;

      // Extract abbreviation
      String abbreviation = (item['abbreviation'] ?? item['abbrev'] ?? item['abbr'] ?? '').toString().trim();
      if (abbreviation.isEmpty) {
        abbreviation = _generateAbbreviation(name);
      }

      // Determine testament
      Testament testament;
      final testamentStr = (item['testament'] ?? item['testamentName'] ?? '').toString().toLowerCase();
      if (testamentStr == 'ot' || testamentStr == 'old' || testamentStr == 'old testament') {
        testament = Testament.old;
      } else if (testamentStr == 'nt' || testamentStr == 'new' || testamentStr == 'new testament') {
        testament = Testament.nt;
      } else {
        // Infer from name
        final otBooks = [
          'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy',
          'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel',
          '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles',
          'Ezra', 'Nehemiah', 'Esther', 'Job', 'Psalms',
          'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah',
          'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel',
          'Hosea', 'Joel', 'Amos', 'Obadiah', 'Jonah',
          'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai',
          'Zechariah', 'Malachi'
        ];
        testament = otBooks.contains(name) ? Testament.old : Testament.nt;
      }

      // Extract chapters
      int chapters = (item['chapters'] ?? item['chapterCount'] ?? item['numChapters'] ?? 0);
      if (chapters == 0) {
        chapters = _getDefaultChapterCount(name);
      }

      // Description/summary
      String description = (item['description'] ?? item['summary'] ?? item['overview'] ?? '').toString();
      if (description.isEmpty) {
        description = _generateDescription(name, testament);
      }

      // Order
      int bookOrder = (item['order'] ?? item['bookOrder'] ?? item['book_order'] ?? item['index'] ?? 0);
      if (bookOrder == 0) {
        bookOrder = _getDefaultBookOrder(name);
      }

      // Testament order
      String testamentOrder = (item['testamentOrder'] ?? item['testament_order'] ?? '').toString();
      if (testamentOrder.isEmpty) {
        testamentOrder = testament == Testament.old ? 'OT' : 'NT';
      }

      // Alternate names
      List<String> alternateNames = [];
      if (item['alternateNames'] is List) {
        alternateNames = List<String>.from(item['alternateNames']);
      } else if (item['alternate_names'] is List) {
        alternateNames = List<String>.from(item['alternate_names']);
      } else if (item['synonyms'] is List) {
        alternateNames = List<String>.from(item['synonyms']);
      }

      return BibleBook(
        name: name,
        abbreviation: abbreviation,
        testament: testament,
        chapters: chapters,
        description: description,
        testamentOrder: testamentOrder,
        bookOrder: bookOrder,
        alternateNames: alternateNames,
      );
    } catch (e) {
      debugPrint('BibleBooksService: Failed to parse book item: $e');
      return null;
    }
  }

  String _generateAbbreviation(String name) {
    // Common abbreviations
    final abbrevMap = {
      'Genesis': 'Gen', 'Exodus': 'Exod', 'Leviticus': 'Lev', 'Numbers': 'Num', 'Deuteronomy': 'Deut',
      'Joshua': 'Josh', 'Judges': 'Judg', 'Ruth': 'Ruth', '1 Samuel': '1 Sam', '2 Samuel': '2 Sam',
      '1 Kings': '1 Kgs', '2 Kings': '2 Kgs', '1 Chronicles': '1 Chron', '2 Chronicles': '2 Chron',
      'Ezra': 'Ezra', 'Nehemiah': 'Neh', 'Esther': 'Esth', 'Job': 'Job', 'Psalms': 'Ps',
      'Proverbs': 'Prov', 'Ecclesiastes': 'Eccl', 'Song of Solomon': 'Song', 'Isaiah': 'Isa',
      'Jeremiah': 'Jer', 'Lamentations': 'Lam', 'Ezekiel': 'Ezek', 'Daniel': 'Dan',
      'Hosea': 'Hos', 'Joel': 'Joel', 'Amos': 'Amos', 'Obadiah': 'Obad', 'Jonah': 'Jonah',
      'Micah': 'Mic', 'Nahum': 'Nah', 'Habakkuk': 'Hab', 'Zephaniah': 'Zeph', 'Haggai': 'Hag',
      'Zechariah': 'Zech', 'Malachi': 'Mal', 'Matthew': 'Matt', 'Mark': 'Mk', 'Luke': 'Lk',
      'John': 'Jn', 'Acts': 'Acts', 'Romans': 'Rom', '1 Corinthians': '1 Cor', '2 Corinthians': '2 Cor',
      'Galatians': 'Gal', 'Ephesians': 'Eph', 'Philippians': 'Phil', 'Colossians': 'Col',
      '1 Thessalonians': '1 Thess', '2 Thessalonians': '2 Thess', '1 Timothy': '1 Tim', '2 Timothy': '2 Tim',
      'Titus': 'Titus', 'Philemon': 'Phlm', 'Hebrews': 'Heb', 'James': 'Jas', '1 Peter': '1 Pet',
      '2 Peter': '2 Pet', '1 John': '1 Jn', '2 John': '2 Jn', '3 John': '3 Jn', 'Jude': 'Jude',
      'Revelation': 'Rev',
    };
    return abbrevMap[name] ?? name.substring(0, name.length.clamp(0, 4)).toUpperCase();
  }

  int _getDefaultChapterCount(String name) {
    const chapterCounts = {
      'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36, 'Deuteronomy': 34,
      'Joshua': 24, 'Judges': 21, 'Ruth': 4, '1 Samuel': 31, '2 Samuel': 24,
      '1 Kings': 22, '2 Kings': 25, '1 Chronicles': 29, '2 Chronicles': 36,
      'Ezra': 10, 'Nehemiah': 13, 'Esther': 10, 'Job': 42, 'Psalms': 150,
      'Proverbs': 31, 'Ecclesiastes': 12, 'Song of Solomon': 8, 'Isaiah': 66,
      'Jeremiah': 52, 'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12,
      'Hosea': 14, 'Joel': 3, 'Amos': 9, 'Obadiah': 1, 'Jonah': 4,
      'Micah': 7, 'Nahum': 3, 'Habakkuk': 3, 'Zephaniah': 3, 'Haggai': 2,
      'Zechariah': 14, 'Malachi': 4, 'Matthew': 28, 'Mark': 16, 'Luke': 24,
      'John': 21, 'Acts': 28, 'Romans': 16, '1 Corinthians': 16, '2 Corinthians': 13,
      'Galatians': 6, 'Ephesians': 6, 'Philippians': 4, 'Colossians': 4,
      '1 Thessalonians': 5, '2 Thessalonians': 3, '1 Timothy': 6, '2 Timothy': 4,
      'Titus': 3, 'Philemon': 1, 'Hebrews': 13, 'James': 5, '1 Peter': 5,
      '2 Peter': 3, '1 John': 5, '2 John': 1, '3 John': 1, 'Jude': 1,
      'Revelation': 22,
    };
    return chapterCounts[name] ?? 0;
  }

  int _getDefaultBookOrder(String name) {
    const order = {
      'Genesis': 1, 'Exodus': 2, 'Leviticus': 3, 'Numbers': 4, 'Deuteronomy': 5,
      'Joshua': 6, 'Judges': 7, 'Ruth': 8, '1 Samuel': 9, '2 Samuel': 10,
      '1 Kings': 11, '2 Kings': 12, '1 Chronicles': 13, '2 Chronicles': 14,
      'Ezra': 15, 'Nehemiah': 16, 'Esther': 17, 'Job': 18, 'Psalms': 19,
      'Proverbs': 20, 'Ecclesiastes': 21, 'Song of Solomon': 22, 'Isaiah': 23,
      'Jeremiah': 24, 'Lamentations': 25, 'Ezekiel': 25, 'Daniel': 27,
      'Hosea': 28, 'Joel': 29, 'Amos': 30, 'Obadiah': 31, 'Jonah': 32,
      'Micah': 33, 'Nahum': 34, 'Habakkuk': 35, 'Zephaniah': 36, 'Haggai': 37,
      'Zechariah': 38, 'Malachi': 39, 'Matthew': 40, 'Mark': 41, 'Luke': 42,
      'John': 43, 'Acts': 44, 'Romans': 45, '1 Corinthians': 46, '2 Corinthians': 47,
      'Galatians': 48, 'Ephesians': 49, 'Philippians': 50, 'Colossians': 51,
      '1 Thessalonians': 52, '2 Thessalonians': 53, '1 Timothy': 54, '2 Timothy': 55,
      'Titus': 56, 'Philemon': 57, 'Hebrews': 58, 'James': 59, '1 Peter': 60,
      '2 Peter': 61, '1 John': 62, '2 John': 63, '3 John': 64, 'Jude': 65,
      'Revelation': 66,
    };
    return order[name] ?? 0;
  }

  String _generateDescription(String name, Testament testament) {
    const descriptions = {
      'Genesis': 'The book of beginnings - creation, the fall, and the patriarchs.',
      'Exodus': 'Israel\'s deliverance from Egypt and the giving of the Law at Sinai.',
      'Leviticus': 'Laws for worship, sacrifice, and holy living for Israel.',
      'Numbers': 'Israel\'s wilderness wanderings and census records.',
      'Deuteronomy': 'Moses\' final speeches - restating the Law before entering Canaan.',
      'Joshua': 'Conquest and settlement of the Promised Land.',
      'Judges': 'Cycles of apostasy, oppression, and deliverance by judges.',
      'Ruth': 'A Moabite woman\'s loyalty and inclusion in David\'s lineage.',
      '1 Samuel': 'Samuel\'s ministry, Saul\'s kingship, and David\'s rise.',
      '2 Samuel': 'David\'s reign as king over Israel.',
      '1 Kings': 'Solomon\'s reign, the divided kingdom, and Elijah\'s ministry.',
      '2 Kings': 'The fall of both Israel and Judah into exile.',
      '1 Chronicles': 'Genealogies and David\'s preparations for the temple.',
      '2 Chronicles': 'Solomon\'s temple, the divided kingdom, and Judah\'s history.',
      'Ezra': 'Return from exile and rebuilding the temple.',
      'Nehemiah': 'Rebuilding Jerusalem\'s walls and spiritual renewal.',
      'Esther': 'God\'s providence saving Jews in Persia.',
      'Job': 'Suffering, sovereignty, and the nature of God\'s justice.',
      'Psalms': 'Israel\'s prayer and worship book - 150 songs and poems.',
      'Proverbs': 'Wisdom sayings for skillful, God-fearing living.',
      'Ecclesiastes': 'The search for meaning "under the sun."',
      'Song of Solomon': 'Celebration of marital love and intimacy.',
      'Isaiah': 'Judgment and hope - the suffering servant and future glory.',
      'Jeremiah': 'Judgment on Judah and the promise of a new covenant.',
      'Lamentations': 'Five laments over Jerusalem\'s destruction.',
      'Ezekiel': 'Visions of judgment and restoration for Israel.',
      'Daniel': 'Faith in exile and visions of future kingdoms.',
      'Hosea': 'God\'s faithful love for unfaithful Israel.',
      'Joel': 'The day of the Lord and the pouring out of the Spirit.',
      'Amos': 'Justice and righteousness for Israel and nations.',
      'Obadiah': 'Judgment on Edom for pride and violence.',
      'Jonah': 'God\'s mercy extends to repentant Nineveh.',
      'Micah': 'Justice, mercy, and the coming ruler from Bethlehem.',
      'Nahum': 'Nineveh\'s inevitable fall and God\'s justice.',
      'Habakkuk': 'Faith in God\'s mysterious ways among nations.',
      'Zephaniah': 'The day of the Lord - judgment and remnant hope.',
      'Haggai': 'Call to rebuild the temple - God\'s presence returns.',
      'Zechariah': 'Visions of restoration and the coming King.',
      'Malachi': 'Covenant faithfulness and the messenger of the covenant.',
      'Matthew': 'Jesus as the fulfillment of OT promises - King and Teacher.',
      'Mark': 'Jesus as the suffering Servant and powerful Son of God.',
      'Luke': 'Jesus as Savior of all people - detailed, orderly account.',
      'John': 'Jesus as the eternal Word - believing for eternal life.',
      'Acts': 'The Spirit-empowered spread of the gospel to the world.',
      'Romans': 'The gospel of righteousness by faith for Jew and Gentile.',
      '1 Corinthians': 'Church unity, purity, and resurrection hope.',
      '2 Corinthians': 'Ministry of reconciliation and apostolic authority.',
      'Galatians': 'Freedom in Christ vs. legalism - justification by faith.',
      'Ephesians': 'The church as Christ\'s body - unity and spiritual warfare.',
      'Philippians': 'Joy in Christ, humility, and heavenly citizenship.',
      'Colossians': 'Christ\'s supremacy and fullness over all things.',
      '1 Thessalonians': 'Hope in Christ\'s return and holy living.',
      '2 Thessalonians': 'Correction on the day of the Lord and idleness.',
      '1 Timothy': 'Church leadership, doctrine, and godly conduct.',
      '2 Timothy': 'Endurance in ministry and guarding the gospel.',
      'Titus': 'Qualified elders and sound doctrine for Cretan churches.',
      'Philemon': 'Christian brotherhood transforming slave-master relations.',
      'Hebrews': 'Christ\'s supremacy - better covenant, sacrifice, priesthood.',
      'James': 'Faith that works - practical wisdom for trials.',
      '1 Peter': 'Hope and holiness amid suffering as exiles.',
      '2 Peter': 'Growth in grace and warning against false teachers.',
      '1 John': 'Assurance of eternal life - love, obedience, truth.',
      '2 John': 'Walking in truth and love - avoiding deceivers.',
      '3 John': 'Supporting missionaries vs. Diotrephes\' pride.',
      'Jude': 'Contending for the faith against ungodly infiltrators.',
      'Revelation': 'Christ\'s victory, judgment, and the new creation.',
    };
    return descriptions[name] ?? 'A book of the ${testament == Testament.old ? 'Old' : 'New'} Testament.';
  }

  Future<void> _saveToCache(List<BibleBook> books) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(books.map((b) => b.toJson()).toList());
      await prefs.setString(_cacheKey, jsonData);
      await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);
      debugPrint('BibleBooksService: Cached ${books.length} books');
    } catch (e) {
      debugPrint('BibleBooksService: Cache save failed: $e');
    }
  }

  Future<List<BibleBook>?> _getFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_timestampKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - timestamp > _cacheExpiry.inMilliseconds) {
        debugPrint('BibleBooksService: Cache expired');
        return null;
      }

      final cachedData = prefs.getString(_cacheKey);
      if (cachedData != null) {
        final List<dynamic> jsonList = json.decode(cachedData);
        return jsonList.map((e) => BibleBook.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('BibleBooksService: Cache read failed: $e');
    }
    return null;
  }

  /// Built-in default Bible books as ultimate fallback
  List<BibleBook> _getBuiltInDefaults() {
    return [
      // Old Testament
      BibleBook(name: 'Genesis', abbreviation: 'Gen', testament: Testament.old, chapters: 50, description: 'The book of beginnings - creation, the fall, and the patriarchs.', testamentOrder: 'OT', bookOrder: 1, alternateNames: ['Gen']),
      BibleBook(name: 'Exodus', abbreviation: 'Exod', testament: Testament.old, chapters: 40, description: 'Israel\'s deliverance from Egypt and the giving of the Law at Sinai.', testamentOrder: 'OT', bookOrder: 2, alternateNames: ['Exod']),
      BibleBook(name: 'Leviticus', abbreviation: 'Lev', testament: Testament.old, chapters: 27, description: 'Laws for worship, sacrifice, and holy living for Israel.', testamentOrder: 'OT', bookOrder: 3, alternateNames: ['Lev']),
      BibleBook(name: 'Numbers', abbreviation: 'Num', testament: Testament.old, chapters: 36, description: 'Israel\'s wilderness wanderings and census records.', testamentOrder: 'OT', bookOrder: 4, alternateNames: ['Num']),
      BibleBook(name: 'Deuteronomy', abbreviation: 'Deut', testament: Testament.old, chapters: 34, description: 'Moses\' final speeches - restating the Law before entering Canaan.', testamentOrder: 'OT', bookOrder: 5, alternateNames: ['Deut']),
      BibleBook(name: 'Joshua', abbreviation: 'Josh', testament: Testament.old, chapters: 24, description: 'Conquest and settlement of the Promised Land.', testamentOrder: 'OT', bookOrder: 6, alternateNames: ['Josh']),
      BibleBook(name: 'Judges', abbreviation: 'Judg', testament: Testament.old, chapters: 21, description: 'Cycles of apostasy, oppression, and deliverance by judges.', testamentOrder: 'OT', bookOrder: 7, alternateNames: ['Judg']),
      BibleBook(name: 'Ruth', abbreviation: 'Ruth', testament: Testament.old, chapters: 4, description: 'A Moabite woman\'s loyalty and inclusion in David\'s lineage.', testamentOrder: 'OT', bookOrder: 8, alternateNames: []),
      BibleBook(name: '1 Samuel', abbreviation: '1 Sam', testament: Testament.old, chapters: 31, description: 'Samuel\'s ministry, Saul\'s kingship, and David\'s rise.', testamentOrder: 'OT', bookOrder: 9, alternateNames: ['1 Sam', '1Sam']),
      BibleBook(name: '2 Samuel', abbreviation: '2 Sam', testament: Testament.old, chapters: 24, description: 'David\'s reign as king over Israel.', testamentOrder: 'OT', bookOrder: 10, alternateNames: ['2 Sam', '2Sam']),
      BibleBook(name: '1 Kings', abbreviation: '1 Kgs', testament: Testament.old, chapters: 22, description: 'Solomon\'s reign, the divided kingdom, and Elijah\'s ministry.', testamentOrder: 'OT', bookOrder: 11, alternateNames: ['1 Kgs', '1Kgs']),
      BibleBook(name: '2 Kings', abbreviation: '2 Kgs', testament: Testament.old, chapters: 25, description: 'The fall of both Israel and Judah into exile.', testamentOrder: 'OT', bookOrder: 12, alternateNames: ['2 Kgs', '2Kgs']),
      BibleBook(name: '1 Chronicles', abbreviation: '1 Chron', testament: Testament.old, chapters: 29, description: 'Genealogies and David\'s preparations for the temple.', testamentOrder: 'OT', bookOrder: 13, alternateNames: ['1 Chron', '1Chron']),
      BibleBook(name: '2 Chronicles', abbreviation: '2 Chron', testament: Testament.old, chapters: 36, description: 'Solomon\'s temple, the divided kingdom, and Judah\'s history.', testamentOrder: 'OT', bookOrder: 14, alternateNames: ['2 Chron', '2Chron']),
      BibleBook(name: 'Ezra', abbreviation: 'Ezra', testament: Testament.old, chapters: 10, description: 'Return from exile and rebuilding the temple.', testamentOrder: 'OT', bookOrder: 15, alternateNames: []),
      BibleBook(name: 'Nehemiah', abbreviation: 'Neh', testament: Testament.old, chapters: 13, description: 'Rebuilding Jerusalem\'s walls and spiritual renewal.', testamentOrder: 'OT', bookOrder: 16, alternateNames: ['Neh']),
      BibleBook(name: 'Esther', abbreviation: 'Esth', testament: Testament.old, chapters: 10, description: 'God\'s providence saving Jews in Persia.', testamentOrder: 'OT', bookOrder: 17, alternateNames: ['Esth']),
      BibleBook(name: 'Job', abbreviation: 'Job', testament: Testament.old, chapters: 42, description: 'Suffering, sovereignty, and the nature of God\'s justice.', testamentOrder: 'OT', bookOrder: 18, alternateNames: []),
      BibleBook(name: 'Psalms', abbreviation: 'Ps', testament: Testament.old, chapters: 150, description: 'Israel\'s prayer and worship book - 150 songs and poems.', testamentOrder: 'OT', bookOrder: 19, alternateNames: ['Psalm', 'Ps']),
      BibleBook(name: 'Proverbs', abbreviation: 'Prov', testament: Testament.old, chapters: 31, description: 'Wisdom sayings for skillful, God-fearing living.', testamentOrder: 'OT', bookOrder: 20, alternateNames: ['Prov']),
      BibleBook(name: 'Ecclesiastes', abbreviation: 'Eccl', testament: Testament.old, chapters: 12, description: 'The search for meaning "under the sun."', testamentOrder: 'OT', bookOrder: 21, alternateNames: ['Eccl', 'Ecc']),
      BibleBook(name: 'Song of Solomon', abbreviation: 'Song', testament: Testament.old, chapters: 8, description: 'Celebration of marital love and intimacy.', testamentOrder: 'OT', bookOrder: 22, alternateNames: ['Song', 'Songs', 'Canticles']),
      BibleBook(name: 'Isaiah', abbreviation: 'Isa', testament: Testament.old, chapters: 66, description: 'Judgment and hope - the suffering servant and future glory.', testamentOrder: 'OT', bookOrder: 23, alternateNames: ['Isa']),
      BibleBook(name: 'Jeremiah', abbreviation: 'Jer', testament: Testament.old, chapters: 52, description: 'Judgment on Judah and the promise of a new covenant.', testamentOrder: 'OT', bookOrder: 24, alternateNames: ['Jer']),
      BibleBook(name: 'Lamentations', abbreviation: 'Lam', testament: Testament.old, chapters: 5, description: 'Five laments over Jerusalem\'s destruction.', testamentOrder: 'OT', bookOrder: 25, alternateNames: ['Lam']),
      BibleBook(name: 'Ezekiel', abbreviation: 'Ezek', testament: Testament.old, chapters: 48, description: 'Visions of judgment and restoration for Israel.', testamentOrder: 'OT', bookOrder: 26, alternateNames: ['Ezek']),
      BibleBook(name: 'Daniel', abbreviation: 'Dan', testament: Testament.old, chapters: 12, description: 'Faith in exile and visions of future kingdoms.', testamentOrder: 'OT', bookOrder: 27, alternateNames: ['Dan']),
      BibleBook(name: 'Hosea', abbreviation: 'Hos', testament: Testament.old, chapters: 14, description: 'God\'s faithful love for unfaithful Israel.', testamentOrder: 'OT', bookOrder: 28, alternateNames: ['Hos']),
      BibleBook(name: 'Joel', abbreviation: 'Joel', testament: Testament.old, chapters: 3, description: 'The day of the Lord and the pouring out of the Spirit.', testamentOrder: 'OT', bookOrder: 29, alternateNames: []),
      BibleBook(name: 'Amos', abbreviation: 'Amos', testament: Testament.old, chapters: 9, description: 'Justice and righteousness for Israel and nations.', testamentOrder: 'OT', bookOrder: 30, alternateNames: []),
      BibleBook(name: 'Obadiah', abbreviation: 'Obad', testament: Testament.old, chapters: 1, description: 'Judgment on Edom for pride and violence.', testamentOrder: 'OT', bookOrder: 31, alternateNames: ['Obad']),
      BibleBook(name: 'Jonah', abbreviation: 'Jonah', testament: Testament.old, chapters: 4, description: 'God\'s mercy extends to repentant Nineveh.', testamentOrder: 'OT', bookOrder: 32, alternateNames: []),
      BibleBook(name: 'Micah', abbreviation: 'Mic', testament: Testament.old, chapters: 7, description: 'Justice, mercy, and the coming ruler from Bethlehem.', testamentOrder: 'OT', bookOrder: 33, alternateNames: ['Mic']),
      BibleBook(name: 'Nahum', abbreviation: 'Nah', testament: Testament.old, chapters: 3, description: 'Nineveh\'s inevitable fall and God\'s justice.', testamentOrder: 'OT', bookOrder: 34, alternateNames: ['Nah']),
      BibleBook(name: 'Habakkuk', abbreviation: 'Hab', testament: Testament.old, chapters: 3, description: 'Faith in God\'s mysterious ways among nations.', testamentOrder: 'OT', bookOrder: 35, alternateNames: ['Hab']),
      BibleBook(name: 'Zephaniah', abbreviation: 'Zeph', testament: Testament.old, chapters: 3, description: 'The day of the Lord - judgment and remnant hope.', testamentOrder: 'OT', bookOrder: 36, alternateNames: ['Zeph']),
      BibleBook(name: 'Haggai', abbreviation: 'Hag', testament: Testament.old, chapters: 2, description: 'Call to rebuild the temple - God\'s presence returns.', testamentOrder: 'OT', bookOrder: 37, alternateNames: ['Hag']),
      BibleBook(name: 'Zechariah', abbreviation: 'Zech', testament: Testament.old, chapters: 14, description: 'Visions of restoration and the coming King.', testamentOrder: 'OT', bookOrder: 38, alternateNames: ['Zech']),
      BibleBook(name: 'Malachi', abbreviation: 'Mal', testament: Testament.old, chapters: 4, description: 'Covenant faithfulness and the messenger of the covenant.', testamentOrder: 'OT', bookOrder: 39, alternateNames: ['Mal']),

      // New Testament
      BibleBook(name: 'Matthew', abbreviation: 'Matt', testament: Testament.nt, chapters: 28, description: 'Jesus as the fulfillment of OT promises - King and Teacher.', testamentOrder: 'NT', bookOrder: 40, alternateNames: ['Matt']),
      BibleBook(name: 'Mark', abbreviation: 'Mk', testament: Testament.nt, chapters: 16, description: 'Jesus as the suffering Servant and powerful Son of God.', testamentOrder: 'NT', bookOrder: 41, alternateNames: ['Mk']),
      BibleBook(name: 'Luke', abbreviation: 'Lk', testament: Testament.nt, chapters: 24, description: 'Jesus as Savior of all people - detailed, orderly account.', testamentOrder: 'NT', bookOrder: 42, alternateNames: ['Lk']),
      BibleBook(name: 'John', abbreviation: 'Jn', testament: Testament.nt, chapters: 21, description: 'Jesus as the eternal Word - believing for eternal life.', testamentOrder: 'NT', bookOrder: 43, alternateNames: ['Jn']),
      BibleBook(name: 'Acts', abbreviation: 'Acts', testament: Testament.nt, chapters: 28, description: 'The Spirit-empowered spread of the gospel to the world.', testamentOrder: 'NT', bookOrder: 44, alternateNames: []),
      BibleBook(name: 'Romans', abbreviation: 'Rom', testament: Testament.nt, chapters: 16, description: 'The gospel of righteousness by faith for Jew and Gentile.', testamentOrder: 'NT', bookOrder: 45, alternateNames: ['Rom']),
      BibleBook(name: '1 Corinthians', abbreviation: '1 Cor', testament: Testament.nt, chapters: 16, description: 'Church unity, purity, and resurrection hope.', testamentOrder: 'NT', bookOrder: 46, alternateNames: ['1 Cor', '1Cor']),
      BibleBook(name: '2 Corinthians', abbreviation: '2 Cor', testament: Testament.nt, chapters: 13, description: 'Ministry of reconciliation and apostolic authority.', testamentOrder: 'NT', bookOrder: 46, alternateNames: ['2 Cor', '2Cor']),
      BibleBook(name: 'Galatians', abbreviation: 'Gal', testament: Testament.nt, chapters: 6, description: 'Freedom in Christ vs. legalism - justification by faith.', testamentOrder: 'NT', bookOrder: 48, alternateNames: ['Gal']),
      BibleBook(name: 'Ephesians', abbreviation: 'Eph', testament: Testament.nt, chapters: 6, description: 'The church as Christ\'s body - unity and spiritual warfare.', testamentOrder: 'NT', bookOrder: 49, alternateNames: ['Eph']),
      BibleBook(name: 'Philippians', abbreviation: 'Phil', testament: Testament.nt, chapters: 4, description: 'Joy in Christ, humility, and heavenly citizenship.', testamentOrder: 'NT', bookOrder: 50, alternateNames: ['Phil']),
      BibleBook(name: 'Colossians', abbreviation: 'Col', testament: Testament.nt, chapters: 4, description: 'Christ\'s supremacy and fullness over all things.', testamentOrder: 'NT', bookOrder: 51, alternateNames: ['Col']),
      BibleBook(name: '1 Thessalonians', abbreviation: '1 Thess', testament: Testament.nt, chapters: 5, description: 'Hope in Christ\'s return and holy living.', testamentOrder: 'NT', bookOrder: 52, alternateNames: ['1 Thess', '1Thess']),
      BibleBook(name: '2 Thessalonians', abbreviation: '2 Thess', testament: Testament.nt, chapters: 3, description: 'Correction on the day of the Lord and idleness.', testamentOrder: 'NT', bookOrder: 53, alternateNames: ['2 Thess', '2Thess']),
      BibleBook(name: '1 Timothy', abbreviation: '1 Tim', testament: Testament.nt, chapters: 6, description: 'Church leadership, doctrine, and godly conduct.', testamentOrder: 'NT', bookOrder: 54, alternateNames: ['1 Tim', '1Tim']),
      BibleBook(name: '2 Timothy', abbreviation: '2 Tim', testament: Testament.nt, chapters: 4, description: 'Endurance in ministry and guarding the gospel.', testamentOrder: 'NT', bookOrder: 55, alternateNames: ['2 Tim', '2Tim']),
      BibleBook(name: 'Titus', abbreviation: 'Titus', testament: Testament.nt, chapters: 3, description: 'Qualified elders and sound doctrine for Cretan churches.', testamentOrder: 'NT', bookOrder: 56, alternateNames: []),
      BibleBook(name: 'Philemon', abbreviation: 'Phlm', testament: Testament.nt, chapters: 1, description: 'Christian brotherhood transforming slave-master relations.', testamentOrder: 'NT', bookOrder: 57, alternateNames: ['Phlm', 'Philem']),
      BibleBook(name: 'Hebrews', abbreviation: 'Heb', testament: Testament.nt, chapters: 13, description: 'Christ\'s supremacy - better covenant, sacrifice, priesthood.', testamentOrder: 'NT', bookOrder: 58, alternateNames: ['Heb']),
      BibleBook(name: 'James', abbreviation: 'Jas', testament: Testament.nt, chapters: 5, description: 'Faith that works - practical wisdom for trials.', testamentOrder: 'NT', bookOrder: 59, alternateNames: ['Jas']),
      BibleBook(name: '1 Peter', abbreviation: '1 Pet', testament: Testament.nt, chapters: 5, description: 'Hope and holiness amid suffering as exiles.', testamentOrder: 'NT', bookOrder: 60, alternateNames: ['1 Pet', '1Pet']),
      BibleBook(name: '2 Peter', abbreviation: '2 Pet', testament: Testament.nt, chapters: 3, description: 'Growth in grace and warning against false teachers.', testamentOrder: 'NT', bookOrder: 61, alternateNames: ['2 Pet', '2Pet']),
      BibleBook(name: '1 John', abbreviation: '1 Jn', testament: Testament.nt, chapters: 5, description: 'Assurance of eternal life - love, obedience, truth.', testamentOrder: 'NT', bookOrder: 62, alternateNames: ['1 Jn', '1Jn']),
      BibleBook(name: '2 John', abbreviation: '2 Jn', testament: Testament.nt, chapters: 1, description: 'Walking in truth and love - avoiding deceivers.', testamentOrder: 'NT', bookOrder: 63, alternateNames: ['2 Jn', '2Jn']),
      BibleBook(name: '3 John', abbreviation: '3 Jn', testament: Testament.nt, chapters: 1, description: 'Supporting missionaries vs. Diotrephes\' pride.', testamentOrder: 'NT', bookOrder: 64, alternateNames: ['3 Jn', '3Jn']),
      BibleBook(name: 'Jude', abbreviation: 'Jude', testament: Testament.nt, chapters: 1, description: 'Contending for the faith against ungodly infiltrators.', testamentOrder: 'NT', bookOrder: 65, alternateNames: []),
      BibleBook(name: 'Revelation', abbreviation: 'Rev', testament: Testament.nt, chapters: 22, description: 'Christ\'s victory, judgment, and the new creation.', testamentOrder: 'NT', bookOrder: 66, alternateNames: ['Rev', 'Apoc']),
    ];
  }

  /// Audit current Bible books against standard 66-book canon
  Future<BibleBookAuditResult> auditBibleBooks() async {
    final books = await fetchAllBooks();

    // Standard 66-book canon
    final standardBooks = _getBuiltInDefaults();
    final standardNames = standardBooks.map((b) => b.name).toSet();

    final fetchedNames = books.map((b) => b.name).toSet();
    final missingBooks = standardNames.difference(fetchedNames).toList();
    missingBooks.sort();

    // Check for duplicates
    final nameCounts = <String, int>{};
    for (final book in books) {
      nameCounts[book.name] = (nameCounts[book.name] ?? 0) + 1;
    }
    final duplicateBooks = nameCounts.entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toList();

    // Statistics
    final otCount = books.where((b) => b.testament == Testament.old).length;
    final ntCount = books.where((b) => b.testament == Testament.nt).length;
    final totalChapters = books.fold(0, (sum, b) => sum + b.chapters);
    final booksWithDescriptions = books.where((b) => b.description.isNotEmpty).length;

    return BibleBookAuditResult(
      books: books,
      missingBooks: missingBooks,
      duplicateBooks: duplicateBooks,
      statistics: {
        'totalBooks': books.length,
        'oldTestamentBooks': otCount,
        'newTestamentBooks': ntCount,
        'totalChapters': totalChapters,
        'booksWithDescriptions': booksWithDescriptions,
        'standardCanonMatch': missingBooks.isEmpty && duplicateBooks.isEmpty,
      },
      auditedAt: DateTime.now(),
    );
  }
}

final bibleBooksServiceProvider = Provider<BibleBooksService>((ref) {
  return BibleBooksService();
});

final bibleBooksProvider = FutureProvider<List<BibleBook>>((ref) async {
  return ref.watch(bibleBooksServiceProvider).fetchAllBooks();
});

final bibleBooksAuditProvider = FutureProvider<BibleBookAuditResult>((ref) async {
  return ref.watch(bibleBooksServiceProvider).auditBibleBooks();
});

final bibleBooksRefreshProvider = FutureProvider.family<List<BibleBook>, bool>((ref, forceRefresh) async {
  return ref.watch(bibleBooksServiceProvider).fetchAllBooks(forceRefresh: forceRefresh);
});