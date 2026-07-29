#!/usr/bin/env dart
// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps, depend_on_referenced_packages
// Audio Bible Generator - Desktop Runner
// Run this on Windows/Mac/Linux to generate audio for all 66 Bible books
// Usage: dart run tools/generate_audio_bible.dart --supabase-url=... --supabase-key=...

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

/// Bible book metadata for all 66 books
class BibleBook {
  final String name;
  final String abbreviation;
  final String testament; // 'OT' or 'NT'
  final int chapters;
  final int bookOrder;

  const BibleBook({
    required this.name,
    required this.abbreviation,
    required this.testament,
    required this.chapters,
    required this.bookOrder,
  });

  static const List<BibleBook> allBooks = [
    // Old Testament (39 books)
    BibleBook(name: 'Genesis', abbreviation: 'Gen', testament: 'OT', chapters: 50, bookOrder: 1),
    BibleBook(name: 'Exodus', abbreviation: 'Exod', testament: 'OT', chapters: 40, bookOrder: 2),
    BibleBook(name: 'Leviticus', abbreviation: 'Lev', testament: 'OT', chapters: 27, bookOrder: 3),
    BibleBook(name: 'Numbers', abbreviation: 'Num', testament: 'OT', chapters: 36, bookOrder: 4),
    BibleBook(name: 'Deuteronomy', abbreviation: 'Deut', testament: 'OT', chapters: 34, bookOrder: 5),
    BibleBook(name: 'Joshua', abbreviation: 'Josh', testament: 'OT', chapters: 24, bookOrder: 6),
    BibleBook(name: 'Judges', abbreviation: 'Judg', testament: 'OT', chapters: 21, bookOrder: 7),
    BibleBook(name: 'Ruth', abbreviation: 'Ruth', testament: 'OT', chapters: 4, bookOrder: 8),
    BibleBook(name: '1 Samuel', abbreviation: '1 Sam', testament: 'OT', chapters: 31, bookOrder: 9),
    BibleBook(name: '2 Samuel', abbreviation: '2 Sam', testament: 'OT', chapters: 24, bookOrder: 10),
    BibleBook(name: '1 Kings', abbreviation: '1 Kgs', testament: 'OT', chapters: 22, bookOrder: 11),
    BibleBook(name: '2 Kings', abbreviation: '2 Kgs', testament: 'OT', chapters: 25, bookOrder: 12),
    BibleBook(name: '1 Chronicles', abbreviation: '1 Chron', testament: 'OT', chapters: 29, bookOrder: 13),
    BibleBook(name: '2 Chronicles', abbreviation: '2 Chron', testament: 'OT', chapters: 36, bookOrder: 14),
    BibleBook(name: 'Ezra', abbreviation: 'Ezra', testament: 'OT', chapters: 10, bookOrder: 15),
    BibleBook(name: 'Nehemiah', abbreviation: 'Neh', testament: 'OT', chapters: 13, bookOrder: 16),
    BibleBook(name: 'Esther', abbreviation: 'Esth', testament: 'OT', chapters: 10, bookOrder: 17),
    BibleBook(name: 'Job', abbreviation: 'Job', testament: 'OT', chapters: 42, bookOrder: 18),
    BibleBook(name: 'Psalms', abbreviation: 'Ps', testament: 'OT', chapters: 150, bookOrder: 19),
    BibleBook(name: 'Proverbs', abbreviation: 'Prov', testament: 'OT', chapters: 31, bookOrder: 20),
    BibleBook(name: 'Ecclesiastes', abbreviation: 'Eccl', testament: 'OT', chapters: 12, bookOrder: 21),
    BibleBook(name: 'Song of Solomon', abbreviation: 'Song', testament: 'OT', chapters: 8, bookOrder: 22),
    BibleBook(name: 'Isaiah', abbreviation: 'Isa', testament: 'OT', chapters: 66, bookOrder: 23),
    BibleBook(name: 'Jeremiah', abbreviation: 'Jer', testament: 'OT', chapters: 52, bookOrder: 24),
    BibleBook(name: 'Lamentations', abbreviation: 'Lam', testament: 'OT', chapters: 5, bookOrder: 25),
    BibleBook(name: 'Ezekiel', abbreviation: 'Ezek', testament: 'OT', chapters: 48, bookOrder: 26),
    BibleBook(name: 'Daniel', abbreviation: 'Dan', testament: 'OT', chapters: 12, bookOrder: 27),
    BibleBook(name: 'Hosea', abbreviation: 'Hos', testament: 'OT', chapters: 14, bookOrder: 28),
    BibleBook(name: 'Joel', abbreviation: 'Joel', testament: 'OT', chapters: 3, bookOrder: 29),
    BibleBook(name: 'Amos', abbreviation: 'Amos', testament: 'OT', chapters: 9, bookOrder: 30),
    BibleBook(name: 'Obadiah', abbreviation: 'Obad', testament: 'OT', chapters: 1, bookOrder: 31),
    BibleBook(name: 'Jonah', abbreviation: 'Jonah', testament: 'OT', chapters: 4, bookOrder: 32),
    BibleBook(name: 'Micah', abbreviation: 'Mic', testament: 'OT', chapters: 7, bookOrder: 33),
    BibleBook(name: 'Nahum', abbreviation: 'Nah', testament: 'OT', chapters: 3, bookOrder: 34),
    BibleBook(name: 'Habakkuk', abbreviation: 'Hab', testament: 'OT', chapters: 3, bookOrder: 35),
    BibleBook(name: 'Zephaniah', abbreviation: 'Zeph', testament: 'OT', chapters: 3, bookOrder: 36),
    BibleBook(name: 'Haggai', abbreviation: 'Hag', testament: 'OT', chapters: 2, bookOrder: 37),
    BibleBook(name: 'Zechariah', abbreviation: 'Zech', testament: 'OT', chapters: 14, bookOrder: 38),
    BibleBook(name: 'Malachi', abbreviation: 'Mal', testament: 'OT', chapters: 4, bookOrder: 39),

    // New Testament (27 books)
    BibleBook(name: 'Matthew', abbreviation: 'Matt', testament: 'NT', chapters: 28, bookOrder: 40),
    BibleBook(name: 'Mark', abbreviation: 'Mk', testament: 'NT', chapters: 16, bookOrder: 41),
    BibleBook(name: 'Luke', abbreviation: 'Lk', testament: 'NT', chapters: 24, bookOrder: 42),
    BibleBook(name: 'John', abbreviation: 'Jn', testament: 'NT', chapters: 21, bookOrder: 43),
    BibleBook(name: 'Acts', abbreviation: 'Acts', testament: 'NT', chapters: 28, bookOrder: 44),
    BibleBook(name: 'Romans', abbreviation: 'Rom', testament: 'NT', chapters: 16, bookOrder: 45),
    BibleBook(name: '1 Corinthians', abbreviation: '1 Cor', testament: 'NT', chapters: 16, bookOrder: 46),
    BibleBook(name: '2 Corinthians', abbreviation: '2 Cor', testament: 'NT', chapters: 13, bookOrder: 47),
    BibleBook(name: 'Galatians', abbreviation: 'Gal', testament: 'NT', chapters: 6, bookOrder: 48),
    BibleBook(name: 'Ephesians', abbreviation: 'Eph', testament: 'NT', chapters: 6, bookOrder: 49),
    BibleBook(name: 'Philippians', abbreviation: 'Phil', testament: 'NT', chapters: 4, bookOrder: 50),
    BibleBook(name: 'Colossians', abbreviation: 'Col', testament: 'NT', chapters: 4, bookOrder: 51),
    BibleBook(name: '1 Thessalonians', abbreviation: '1 Thess', testament: 'NT', chapters: 5, bookOrder: 52),
    BibleBook(name: '2 Thessalonians', abbreviation: '2 Thess', testament: 'NT', chapters: 3, bookOrder: 53),
    BibleBook(name: '1 Timothy', abbreviation: '1 Tim', testament: 'NT', chapters: 6, bookOrder: 54),
    BibleBook(name: '2 Timothy', abbreviation: '2 Tim', testament: 'NT', chapters: 4, bookOrder: 55),
    BibleBook(name: 'Titus', abbreviation: 'Titus', testament: 'NT', chapters: 3, bookOrder: 56),
    BibleBook(name: 'Philemon', abbreviation: 'Phlm', testament: 'NT', chapters: 1, bookOrder: 57),
    BibleBook(name: 'Hebrews', abbreviation: 'Heb', testament: 'NT', chapters: 13, bookOrder: 58),
    BibleBook(name: 'James', abbreviation: 'Jas', testament: 'NT', chapters: 5, bookOrder: 59),
    BibleBook(name: '1 Peter', abbreviation: '1 Pet', testament: 'NT', chapters: 5, bookOrder: 60),
    BibleBook(name: '2 Peter', abbreviation: '2 Pet', testament: 'NT', chapters: 3, bookOrder: 61),
    BibleBook(name: '1 John', abbreviation: '1 Jn', testament: 'NT', chapters: 5, bookOrder: 62),
    BibleBook(name: '2 John', abbreviation: '2 Jn', testament: 'NT', chapters: 1, bookOrder: 63),
    BibleBook(name: '3 John', abbreviation: '3 Jn', testament: 'NT', chapters: 1, bookOrder: 64),
    BibleBook(name: 'Jude', abbreviation: 'Jude', testament: 'NT', chapters: 1, bookOrder: 65),
    BibleBook(name: 'Revelation', abbreviation: 'Rev', testament: 'NT', chapters: 22, bookOrder: 66),
  ];

  static List<BibleBook> getOldTestament() => allBooks.where((b) => b.testament == 'OT').toList();
  static List<BibleBook> getNewTestament() => allBooks.where((b) => b.testament == 'NT').toList();
}

/// Verse data structure
class BibleVerse {
  final int chapter;
  final int verse;
  final String text;

  BibleVerse({required this.chapter, required this.verse, required this.text});

  factory BibleVerse.fromJson(Map<String, dynamic> json) {
    return BibleVerse(
      chapter: json['chapter'] as int,
      verse: json['verse'] as int,
      text: json['text'] as String,
    );
  }
}

/// Configuration
class Config {
  final String supabaseUrl;
  final String supabaseKey;
  final String translationCode;
  final String voiceName;
  final double speechRate;
  final String format;
  final String bucketName;
  final bool skipExisting;
  final String? onlyBook;
  final int? startChapter;
  final int? endChapter;
  
  // R2/S3 Configuration
  final String? r2Endpoint;
  final String? r2AccessKey;
  final String? r2SecretKey;
  final String? r2Bucket;
  final String? r2Region;
  final bool useR2Fallback;

  Config({
    required this.supabaseUrl,
    required this.supabaseKey,
    this.translationCode = 'web',
    this.voiceName = 'en-US-Standard-A',
    this.speechRate = 0.5,
    this.format = 'mp3',
    this.bucketName = 'bible-audio',
    this.skipExisting = true,
    this.onlyBook,
    this.startChapter,
    this.endChapter,
    this.r2Endpoint,
    this.r2AccessKey,
    this.r2SecretKey,
    this.r2Bucket,
    this.r2Region,
    this.useR2Fallback = false,
  });
}

/// Main generator class
class AudioBibleGenerator {
  final Config _config;
  late final SupabaseClient _supabase;
  late final FlutterTts _tts;
  String? _translationId;
  
  int _totalChapters = 0;
  int _completedChapters = 0;
  int _totalBooks = 0;
  int _completedBooks = 0;

  AudioBibleGenerator(this._config);

  Future<void> run() async {
    print('🎵 Audio Bible Generator');
    print('========================');
    print('Translation: ${_config.translationCode}');
    print('Voice: ${_config.voiceName}');
    print('Format: ${_config.format}');
    print('Bucket: ${_config.bucketName}');
    print('Skip existing: ${_config.skipExisting}');
    if (_config.onlyBook != null) print('Single book: ${_config.onlyBook}');
    print('');

    // Initialize Supabase
    _supabase = SupabaseClient(_config.supabaseUrl, _config.supabaseKey);
    
    // Initialize TTS
    _tts = FlutterTts();
    await _initializeTts();

    // Get translation ID
    _translationId = await _getOrCreateTranslation();
    if (_translationId == null) {
      print('❌ Failed to get translation ID');
      return;
    }

    // Determine which books to process
    final books = _getBooksToProcess();
    _totalBooks = books.length;
    
    // Count total chapters
    _totalChapters = books.fold(0, (sum, b) => sum + b.chapters);
    print('📚 Processing ${_totalBooks} books, ${_totalChapters} total chapters\n');

    // Process each book
    for (final book in books) {
      await _processBook(book);
    }

    print('\n✅ Generation complete!');
    print('   Books: $_completedBooks/$_totalBooks');
    print('   Chapters: $_completedChapters/$_totalChapters');
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_config.speechRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    
    // Try to set voice
    final voices = await _tts.getVoices;
    if (voices is List) {
      for (final voice in voices) {
        final voiceStr = voice.toString();
        if (voiceStr.contains(_config.voiceName.split('-').first)) {
          await _tts.setVoice({'name': voiceStr, 'locale': 'en-US'});
          print('🎤 Using voice: $voiceStr');
          break;
        }
      }
    }
  }

  Future<String?> _getOrCreateTranslation() async {
    // Try to get existing
    final existing = await _supabase
        .from('bible_translations')
        .select('id')
        .eq('code', _config.translationCode)
        .maybeSingle();
    
    if (existing != null) return existing['id'] as String;

    // Create new
    final result = await _supabase.from('bible_translations').insert({
      'code': _config.translationCode,
      'name': _config.translationCode.toUpperCase(),
      'language': 'en',
      'is_public_domain': true,
    }).select('id').single();
    
    return result['id'] as String;
  }

  List<BibleBook> _getBooksToProcess() {
    var books = BibleBook.allBooks;
    
    if (_config.onlyBook != null) {
      books = books.where((b) => b.name.toLowerCase() == _config.onlyBook!.toLowerCase()).toList();
    }
    
    return books;
  }

  Future<void> _processBook(BibleBook book) async {
    _completedBooks++;
    print('\n📖 [$_completedBooks/$_totalBooks] ${book.name} (${book.chapters} chapters)');
    
    // Ensure book exists in DB
    await _ensureBookExists(book);
    
    final startChapter = _config.startChapter ?? 1;
    final endChapter = _config.endChapter ?? book.chapters;
    
    for (int chapter = startChapter; chapter <= endChapter; chapter++) {
      _completedChapters++;
      
      // Check if exists
      if (_config.skipExisting) {
        final exists = await _chapterExists(book.name, chapter);
        if (exists) {
          print('  ⏭️  Chapter $chapter (exists)');
          continue;
        }
      }
      
      await _processChapter(book, chapter);
      
      // Progress update
      final pct = (_completedChapters / _totalChapters * 100).toStringAsFixed(1);
      print('  📊 Overall: $_completedChapters/$_totalChapters ($pct%)');
      
      // Small delay to avoid overwhelming TTS
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _ensureBookExists(BibleBook book) async {
    await _supabase.from('bible_books').upsert({
      'name': book.name,
      'abbreviation': book.abbreviation,
      'testament': book.testament,
      'book_order': book.bookOrder,
      'testament_order': book.testament,
      'chapters': book.chapters,
    }, onConflict: 'name');
  }

  Future<bool> _chapterExists(String bookName, int chapter) async {
    final path = 'audio/${_config.translationCode}/$bookName/${chapter.toString().padLeft(3, '0')}.${_config.format}';
    if (_config.r2Endpoint == null) return false;
    try {
      final uri = Uri.parse('${_config.r2Endpoint}/${_config.r2Bucket}/$path');
      final client = http.Client();
      final response = await client.head(uri);
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _processChapter(BibleBook book, int chapter) async {
    print('  🎙️  Generating chapter $chapter...');
    
    // Fetch verses
    final verses = await _fetchVerses(book.name, chapter);
    if (verses.isEmpty) {
      print('  ⚠️  No verses found, skipping');
      return;
    }
    
    // Format text
    final text = _formatChapterText(book.name, chapter, verses);
    
    // Generate audio file
    final tempDir = await getTemporaryDirectory();
    final fileName = '${book.name}_ch${chapter.toString().padLeft(3, '0')}.${_config.format}';
    final file = File('${tempDir.path}/$fileName');
    
    try {
      final success = await _tts.synthesizeToFile(text, file.path);
      if (!success || !await file.exists()) {
        print('  ❌ TTS synthesis failed');
        return;
      }
      
      // Upload to storage (Supabase or R2 fallback)
      final storageProvider = await _uploadAudio(file, book.name, chapter);
      
      // Record in database
      await _recordAudioFile(book.name, chapter, file, storageProvider);
      
      print('  ✅ Chapter $chapter uploaded');
      
    } catch (e) {
      print('  ❌ Error: $e');
    } finally {
      // Clean up temp file
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<List<BibleVerse>> _fetchVerses(String bookName, int chapter) async {
    // Try local Supabase first
    final result = await _supabase
        .from('bible_verses')
        .select('chapter, verse, text')
        .eq('translation_id', _translationId!)
        .eq('book_id', (await _getBookId(bookName))!)
        .eq('chapter', chapter)
        .order('verse');
    
    if (result.isNotEmpty) {
      return (result as List).map((v) => BibleVerse.fromJson(v)).toList();
    }
    
    // Fallback: fetch from public API
    return await _fetchVersesFromApi(bookName, chapter);
  }

  Future<String?> _getBookId(String bookName) async {
    final result = await _supabase
        .from('bible_books')
        .select('id')
        .eq('translation_id', _translationId!)
        .eq('name', bookName)
        .maybeSingle();
    return result?['id'] as String?;
  }

  Future<List<BibleVerse>> _fetchVersesFromApi(String bookName, int chapter) async {
    // Map book name to API format
    final apiBook = bookName.toLowerCase().replaceAll(' ', '_');
    final url = 'https://bible-api.com/$apiBook+$chapter?translation=${_config.translationCode}';
    
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body);
        final verses = data['verses'] as List?;
        
        if (verses != null) {
          return verses.map((v) => BibleVerse.fromJson(v)).toList();
        }
      }
    } catch (e) {
      print('  ⚠️  API fetch failed: $e');
    }
    
    return [];
  }

  String _formatChapterText(String bookName, int chapter, List<BibleVerse> verses) {
    final buffer = StringBuffer();
    buffer.write('$bookName, chapter $chapter. ');
    
    for (final verse in verses) {
      buffer.write('Verse ${verse.verse}. ${verse.text} ');
    }
    
    return buffer.toString().trim();
  }

  Future<String> _uploadAudio(File file, String bookName, int chapter) async {
    final path = 'audio/${_config.translationCode}/$bookName/${chapter.toString().padLeft(3, '0')}.${_config.format}';
    final bytes = await file.readAsBytes();
    
    // Upload to R2 only
    if (_config.r2Endpoint != null) {
      await _uploadToR2(bytes, path);
      print('  ☁️  Uploaded to R2');
      return 'r2';
    }
    
    throw Exception('R2 not configured');
  }

  Future<void> _uploadToR2(List<int> bytes, String path) async {
    if (_config.r2Endpoint == null || _config.r2AccessKey == null || _config.r2SecretKey == null || _config.r2Bucket == null) {
      throw Exception('R2 configuration incomplete');
    }
    
    final uri = Uri.parse('${_config.r2Endpoint}/${_config.r2Bucket}/$path');
    final now = DateTime.now().toUtc();
    final dateString = _formatDate(now);
    final dateTimeString = _formatDateTime(now);
    
    // AWS Signature Version 4
    final canonicalRequest = _buildCanonicalRequest('PUT', path, dateTimeString, bytes);
    final stringToSign = _buildStringToSign(dateTimeString, dateString, canonicalRequest);
    final signingKey = _getSigningKey(dateString);
    final signature = _hmacSha256(signingKey, stringToSign);
    
    final authorization = 'AWS4-HMAC-SHA256 Credential=${_config.r2AccessKey}/$dateString/${_config.r2Region ?? 'auto'}/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=$signature';
    
    final response = await http.put(
      uri,
      headers: {
        'Host': uri.host,
        'X-Amz-Content-Sha256': _sha256Hex(bytes),
        'X-Amz-Date': dateTimeString,
        'Authorization': authorization,
        'Content-Type': 'audio/${_config.format}',
      },
      body: bytes,
    );
    
    if (response.statusCode >= 400) {
      throw Exception('R2 upload failed: ${response.statusCode} ${response.body}');
    }
  }

  String _formatDate(DateTime dt) => 
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
  
  String _formatDateTime(DateTime dt) => 
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}T${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}Z';

  String _buildCanonicalRequest(String method, String path, String dateTimeString, List<int> bytes) {
    final payloadHash = _sha256Hex(bytes);
    return '$method\n/$path\n\nhost:${Uri.parse(_config.r2Endpoint!).host}\nx-amz-content-sha256:$payloadHash\nx-amz-date:$dateTimeString\n\nhost;x-amz-content-sha256;x-amz-date\n$payloadHash';
  }

  String _buildStringToSign(String dateTimeString, String dateString, String canonicalRequest) {
    final hashedRequest = _sha256Hex(utf8.encode(canonicalRequest));
    return 'AWS4-HMAC-SHA256\n$dateTimeString\n$dateString/${_config.r2Region ?? 'auto'}/s3/aws4_request\n$hashedRequest';
  }

  List<int> _getSigningKey(String dateString) {
    var kDate = _hmacSha256Bytes(utf8.encode('AWS4${_config.r2SecretKey}'), utf8.encode(dateString));
    var kRegion = _hmacSha256Bytes(kDate, utf8.encode(_config.r2Region ?? 'auto'));
    var kService = _hmacSha256Bytes(kRegion, utf8.encode('s3'));
    return _hmacSha256Bytes(kService, utf8.encode('aws4_request'));
  }

  String _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(data));
    return digest.toString();
  }

  List<int> _hmacSha256Bytes(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(data).bytes;
  }

  String _sha256Hex(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _recordAudioFile(String bookName, int chapter, File file, String storageProvider) async {
    final bookId = await _getBookId(bookName);
    if (bookId == null) return;
    
    final fileSize = await file.length();
    final duration = _estimateDuration(fileSize);
    
    final bucket = storageProvider == 'r2' ? _config.r2Bucket! : _config.bucketName;
    
    await _supabase.from('bible_audio_files').upsert({
      'translation_id': _translationId,
      'book_id': bookId,
      'chapter': chapter,
      'storage_provider': storageProvider,
      'storage_bucket': bucket,
      'storage_path': 'audio/${_config.translationCode}/$bookName/${chapter.toString().padLeft(3, '0')}.${_config.format}',
      'file_size_bytes': fileSize,
      'duration_seconds': duration,
      'format': _config.format,
      'sample_rate': 22050,
      'voice_name': _config.voiceName,
      'generation_status': 'completed',
      'generated_at': DateTime.now().toIso8601String(),
      'uploaded_at': DateTime.now().toIso8601String(),
    }, onConflict: 'translation_id,book_id,chapter,storage_provider');
  }

  double _estimateDuration(int fileSizeBytes) {
    // Rough estimate: 64kbps MP3 = 8KB/s
    return (fileSizeBytes / 8000).ceilToDouble();
  }
}

/// Main entry point
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('supabase-url', abbr: 'u', help: 'Supabase project URL', mandatory: true)
    ..addOption('supabase-key', abbr: 'k', help: 'Supabase service role key', mandatory: true)
    ..addOption('translation', abbr: 't', help: 'Translation code (web, kjv)', defaultsTo: 'web')
    ..addOption('voice', abbr: 'v', help: 'TTS voice name', defaultsTo: 'en-US-Standard-A')
    ..addOption('rate', abbr: 'r', help: 'Speech rate (0.0-1.0)', defaultsTo: '0.5')
    ..addOption('format', abbr: 'f', help: 'Audio format (mp3, wav)', defaultsTo: 'mp3')
    ..addOption('bucket', abbr: 'b', help: 'Storage bucket name', defaultsTo: 'bible-audio')
    ..addFlag('skip-existing', abbr: 's', help: 'Skip already generated chapters', defaultsTo: true)
    ..addOption('book', help: 'Process only specific book (e.g., "Genesis")')
    ..addOption('start-chapter', help: 'Start chapter (for single book)')
    ..addOption('end-chapter', help: 'End chapter (for single book)')
    // R2/S3 fallback options
    ..addOption('r2-endpoint', help: 'R2/S3 endpoint URL (e.g., https://<account>.r2.cloudflarestorage.com)')
    ..addOption('r2-access-key', help: 'R2/S3 access key ID')
    ..addOption('r2-secret-key', help: 'R2/S3 secret access key')
    ..addOption('r2-bucket', help: 'R2/S3 bucket name')
    ..addOption('r2-region', help: 'R2/S3 region (default: auto)', defaultsTo: 'auto')
    ..addFlag('use-r2-fallback', help: 'Enable R2 fallback when Supabase upload fails', defaultsTo: false)
    ..addFlag('help', abbr: 'h', help: 'Show usage');

  final results = parser.parse(args);
  
  if (results['help'] == true) {
    print(parser.usage);
    return;
  }

  final config = Config(
    supabaseUrl: results['supabase-url'] as String,
    supabaseKey: results['supabase-key'] as String,
    translationCode: results['translation'] as String,
    voiceName: results['voice'] as String,
    speechRate: double.parse(results['rate'] as String),
    format: results['format'] as String,
    bucketName: results['bucket'] as String,
    skipExisting: results['skip-existing'] as bool,
    onlyBook: results['book'] as String?,
    startChapter: results['start-chapter'] != null ? int.parse(results['start-chapter'] as String) : null,
    endChapter: results['end-chapter'] != null ? int.parse(results['end-chapter'] as String) : null,
    r2Endpoint: results['r2-endpoint'] as String?,
    r2AccessKey: results['r2-access-key'] as String?,
    r2SecretKey: results['r2-secret-key'] as String?,
    r2Bucket: results['r2-bucket'] as String?,
    r2Region: results['r2-region'] as String?,
    useR2Fallback: results['use-r2-fallback'] as bool,
  );

  final generator = AudioBibleGenerator(config);
  await generator.run();
}