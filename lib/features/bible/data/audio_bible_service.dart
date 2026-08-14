import 'dart:async';
import 'package:universal_io/io.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/features/bible/data/bible_book_model.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';
import 'package:http/http.dart' as http;

/// Configuration for audio generation
class AudioBibleConfig {
  final String translationCode; // 'kjv', 'web'
  final String voiceName; // e.g., 'en-US-Standard-A', 'en-GB-Wavenet-B'
  final double speechRate; // 0.0 - 1.0
  final double pitch; // 0.5 - 2.0
  final double volume; // 0.0 - 1.0
  final String format; // 'mp3', 'wav', 'opus'
  final int sampleRate; // 8000, 16000, 22050, 44100
  final String storageProvider; // 'supabase', 'r2'
  final String bucketName;

  const AudioBibleConfig({
    this.translationCode = 'kjv',
    this.voiceName = 'en-US-Standard-A',
    this.speechRate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.format = 'mp3',
    this.sampleRate = 22050,
    this.storageProvider = 'r2',
    this.bucketName = 'choa-sermons-vault',
  });
}

/// Represents a generated audio file for a Bible chapter
class BibleAudioFile {
  final String translationCode;
  final String bookName;
  final int chapter;
  final File file;
  final Duration duration;
  final int fileSizeBytes;
  final String voiceName;
  final String format;

  BibleAudioFile({
    required this.translationCode,
    required this.bookName,
    required this.chapter,
    required this.file,
    required this.duration,
    required this.fileSizeBytes,
    required this.voiceName,
    required this.format,
  });

  String get storagePath => 'audio/$translationCode/$bookName/${chapter.toString().padLeft(3, '0')}.$format';
}

/// Progress callback for generation
typedef GenerationProgressCallback = void Function(
  String bookName,
  int chapter,
  int totalChapters,
  GenerationStatus status,
  String? error,
);

enum GenerationStatus {
  pending,
  fetchingText,
  generatingAudio,
  savingFile,
  uploading,
  completed,
  failed,
}

/// Service for generating and managing audio Bible files
class AudioBibleService {
  final SupabaseClient _supabase;
  final BibleService _bibleService;
  final FlutterTts _flutterTts;
  final AudioBibleConfig _config;
  
  bool _isGenerating = false;
  GenerationProgressCallback? _onProgress;

  AudioBibleService({
    required SupabaseClient supabase,
    required BibleService bibleService,
    AudioBibleConfig? config,
  })  : _supabase = supabase,
        _bibleService = bibleService,
        _config = config ?? const AudioBibleConfig(),
        _flutterTts = FlutterTts();

  bool _isPlayingSpeech = false;
  bool _isPausedSpeech = false;
  String _currentSpeakingBook = '';
  int _currentSpeakingChapter = 0;
  int _currentSpeakingVerse = 0;
  double _currentSpeechRate = 0.5;
  void Function(int verseNum)? _onVerseChangeCallback;
  final RegExp _versePattern = RegExp(r'(?:Verse )?(\d+)\.');
  final StreamController<int> _verseChangeController = StreamController<int>.broadcast();

  Stream<int> get verseChangeStream => _verseChangeController.stream;

  bool get isPlayingSpeech => _isPlayingSpeech;
  bool get isPausedSpeech => _isPausedSpeech;
  String get currentSpeakingBook => _currentSpeakingBook;
  int get currentSpeakingChapter => _currentSpeakingChapter;
  int get currentSpeakingVerse => _currentSpeakingVerse;
  double get currentSpeechRate => _currentSpeechRate;

  /// Initialize TTS engine
  Future<void> initialize() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(_currentSpeechRate);
    await _flutterTts.setPitch(_config.pitch);
    await _flutterTts.setVolume(_config.volume);

    _flutterTts.setCompletionHandler(() {
      _isPlayingSpeech = false;
      _isPausedSpeech = false;
    });

    _flutterTts.setErrorHandler((msg) {
      _isPlayingSpeech = false;
      _isPausedSpeech = false;
    });
    
    // Try to set voice (platform-dependent)
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is List) {
        final matchingVoice = voices.firstWhere(
          (v) => v.toString().contains(_config.voiceName.split('-').first),
          orElse: () => null,
        );
        if (matchingVoice != null) {
          await _flutterTts.setVoice({'name': matchingVoice.toString(), 'locale': 'en-US'});
        }
      }
    } catch (e) {
      debugPrint('Error setting TTS voice: $e');
    }
  }

  /// Speak a Bible chapter aloud using TTS
  Future<void> speakChapterText(String bookName, int chapter, List<BibleVerse> verses, {void Function(int verseNum)? onVerseChange}) async {
    await stopSpeech();
    if (verses.isEmpty) return;

    _currentSpeakingBook = bookName;
    _currentSpeakingChapter = chapter;
    _currentSpeakingVerse = 1;
    _isPlayingSpeech = true;
    _isPausedSpeech = false;
    _onVerseChangeCallback = onVerseChange;

    _flutterTts.setProgressHandler((String text, int startOffset, int endOffset, String word) {
      // Parse verse number from the spoken text chunk
      final match = _versePattern.firstMatch(text);
      if (match != null) {
        final verseNum = int.tryParse(match.group(1) ?? '');
        if (verseNum != null && verseNum != _currentSpeakingVerse) {
          _currentSpeakingVerse = verseNum;
          _onVerseChangeCallback?.call(verseNum);
          if (!_verseChangeController.isClosed) {
            _verseChangeController.add(verseNum);
          }
        }
      }
    });

    final spokenText = _formatChapterText(bookName, chapter, verses);
    await _flutterTts.setSpeechRate(_currentSpeechRate);
    await _flutterTts.speak(spokenText);
  }

  Future<void> pauseSpeech() async {
    await _flutterTts.pause();
    _isPlayingSpeech = false;
    _isPausedSpeech = true;
  }

  Future<void> resumeSpeech() async {
    _isPlayingSpeech = true;
    _isPausedSpeech = false;
    await _flutterTts.speak('');
  }

  Future<void> stopSpeech() async {
    await _flutterTts.stop();
    _isPlayingSpeech = false;
    _isPausedSpeech = false;
  }

  Future<void> setSpeechRate(double rate) async {
    _currentSpeechRate = rate;
    await _flutterTts.setSpeechRate(rate);
  }

  /// Set progress callback
  void setProgressCallback(GenerationProgressCallback callback) {
    _onProgress = callback;
  }

  /// Generate audio for a single chapter
  Future<BibleAudioFile?> generateChapterAudio({
    required String bookName,
    required int chapter,
    required int totalChapters,
  }) async {
    _reportProgress(bookName, chapter, totalChapters, GenerationStatus.fetchingText, null);
    
    // Fetch chapter text
    final verses = await _bibleService.getChapter(
      _config.translationCode,
      bookName,
      chapter,
    );
    
    if (verses.isEmpty) {
      _reportProgress(bookName, chapter, totalChapters, GenerationStatus.failed, 'No verses found');
      return null;
    }
    
    // Combine verses into readable text
    final chapterText = _formatChapterText(bookName, chapter, verses);
    
    _reportProgress(bookName, chapter, totalChapters, GenerationStatus.generatingAudio, null);
    
    // Generate audio file
    final audioFile = await _synthesizeToFile(bookName, chapter, chapterText);
    if (audioFile == null) {
      _reportProgress(bookName, chapter, totalChapters, GenerationStatus.failed, 'TTS synthesis failed');
      return null;
    }
    
    _reportProgress(bookName, chapter, totalChapters, GenerationStatus.savingFile, null);
    
    // Get file info
    final fileSize = await audioFile.length();
    final duration = await _estimateDuration(chapterText.length);
    
    _reportProgress(bookName, chapter, totalChapters, GenerationStatus.uploading, null);
    
    // Upload to storage
    final uploaded = await _uploadToStorage(audioFile, bookName, chapter);
    if (!uploaded) {
      _reportProgress(bookName, chapter, totalChapters, GenerationStatus.failed, 'Upload failed');
      return null;
    }
    
    // Record in database
    await _recordAudioFile(
      bookName: bookName,
      chapter: chapter,
      fileSizeBytes: fileSize,
      durationSeconds: duration.inSeconds.toDouble(),
    );
    
    _reportProgress(bookName, chapter, totalChapters, GenerationStatus.completed, null);
    
    return BibleAudioFile(
      translationCode: _config.translationCode,
      bookName: bookName,
      chapter: chapter,
      file: audioFile,
      duration: duration,
      fileSizeBytes: fileSize,
      voiceName: _config.voiceName,
      format: _config.format,
    );
  }

  /// Generate audio for an entire book (all chapters)
  Future<List<BibleAudioFile>> generateBookAudio({
    required BibleBook book,
    bool skipExisting = true,
  }) async {
    if (_isGenerating) {
      throw StateError('Generation already in progress');
    }
    
    _isGenerating = true;
    final results = <BibleAudioFile>[];
    
    try {
      for (int chapter = 1; chapter <= book.chapters; chapter++) {
        // Check if already exists
        if (skipExisting) {
          final exists = await _chapterAudioExists(book.name, chapter);
          if (exists) {
            debugPrint('AudioBibleService: Skipping ${book.name} ch $chapter (already exists)');
            continue;
          }
        }
        
        final audioFile = await generateChapterAudio(
          bookName: book.name,
          chapter: chapter,
          totalChapters: book.chapters,
        );
        
        if (audioFile != null) {
          results.add(audioFile);
        }
        
        // Small delay between chapters to avoid TTS engine overload
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      _isGenerating = false;
    }
    
    return results;
  }

  /// Generate audio for all books in a testament
  Future<Map<String, List<BibleAudioFile>>> generateTestamentAudio({
    required Testament testament,
    bool skipExisting = true,
  }) async {
    final books = await _getBooksForTestament(testament);
    final results = <String, List<BibleAudioFile>>{};
    
    for (final book in books) {
      debugPrint('AudioBibleService: Generating audio for ${book.name}...');
      final bookAudio = await generateBookAudio(book: book, skipExisting: skipExisting);
      results[book.name] = bookAudio;
    }
    
    return results;
  }

  /// Generate audio for all 66 books
  Future<Map<String, List<BibleAudioFile>>> generateFullBibleAudio({
    bool skipExisting = true,
  }) async {
    final otResults = await generateTestamentAudio(
      testament: Testament.old,
      skipExisting: skipExisting,
    );
    final ntResults = await generateTestamentAudio(
      testament: Testament.nt,
      skipExisting: skipExisting,
    );
    
    return {...otResults, ...ntResults};
  }

  /// Check if chapter audio already exists in database
  Future<bool> _chapterAudioExists(String bookName, int chapter) async {
    final path = 'audio/${_config.translationCode}/$bookName/${chapter.toString().padLeft(3, '0')}.${_config.format}';
    
    try {
      final result = await _supabase
          .from('bible_audio_files')
          .select('id')
          .eq('storage_path', path)
          .eq('generation_status', 'completed')
          .maybeSingle();
      return result != null;
    } catch (_) {
      return false;
    }
  }

  /// Synthesize text to audio file using flutter_tts
  Future<File?> _synthesizeToFile(String bookName, int chapter, String text) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = '${bookName}_ch${chapter.toString().padLeft(3, '0')}.${_config.format}';
      final file = File('${tempDir.path}/$fileName');
      
      // On desktop, flutter_tts supports synthesizeToFile
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        final success = await _flutterTts.synthesizeToFile(text, file.path);
        if (success && await file.exists()) {
          return file;
        }
      }
      
      // On mobile, we can't easily save to file with flutter_tts
      // This would need a platform-specific implementation or different TTS approach
      debugPrint('AudioBibleService: File synthesis not supported on this platform');
      return null;
    } catch (e) {
      debugPrint('AudioBibleService: Synthesis error: $e');
      return null;
    }
  }

  /// Upload audio file to R2
  Future<bool> _uploadToStorage(File file, String bookName, int chapter) async {
    return await _uploadToR2(file, bookName, chapter);
  }

  /// Upload to Cloudflare R2 via the r2-sign edge function
  Future<bool> _uploadToR2(File file, String bookName, int chapter) async {
    try {
      final path = 'audio/${_config.translationCode}/$bookName/${chapter.toString().padLeft(3, '0')}.${_config.format}';
      final filename = path.split('/').last;
      final folder = 'audio/${_config.translationCode}/$bookName';

      final response = await _supabase.functions.invoke('r2-sign', body: {
        'filename': filename,
        'contentType': 'audio/${_config.format}',
        'folder': folder,
      });

      if (response.status != 200) {
        debugPrint('AudioBibleService: R2 sign failed with status ${response.status}');
        return false;
      }

      final signedUrl = response.data['signedUrl'] as String?;
      if (signedUrl == null) {
        debugPrint('AudioBibleService: No signedUrl returned from r2-sign');
        return false;
      }

      final bytes = await file.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(signedUrl),
        headers: {'Content-Type': 'audio/${_config.format}'},
        body: bytes,
      ).timeout(const Duration(minutes: 5));

      if (uploadResponse.statusCode == 200) {
        debugPrint('AudioBibleService: R2 upload successful for $path');
        return true;
      }

      debugPrint('AudioBibleService: R2 PUT returned status ${uploadResponse.statusCode}');
      return false;
    } catch (e) {
      debugPrint('AudioBibleService: R2 upload error: $e');
      return false;
    }
  }

  /// Record audio file metadata in database
  Future<void> _recordAudioFile({
    required String bookName,
    required int chapter,
    required int fileSizeBytes,
    required double durationSeconds,
  }) async {
    // Get translation ID
    final translationId = await _getTranslationId();
    if (translationId.isEmpty) {
      debugPrint('AudioBibleService: No translation found for ${_config.translationCode}');
      return;
    }

    // Get book ID
    final bookResult = await _supabase
        .from('bible_books')
        .select('id')
        .eq('name', bookName)
        .maybeSingle();
    
    if (bookResult == null) {
      debugPrint('AudioBibleService: No book found for $bookName');
      return;
    }

    final storagePath = 'audio/${_config.translationCode}/$bookName/${chapter.toString().padLeft(3, '0')}.${_config.format}';
    
    await _supabase.from('bible_audio_files').upsert({
      'translation_id': translationId,
      'book_id': bookResult['id'],
      'chapter': chapter,
      'storage_provider': _config.storageProvider,
      'storage_bucket': _config.bucketName,
      'storage_path': storagePath,
      'file_size_bytes': fileSizeBytes,
      'duration_seconds': durationSeconds,
      'format': _config.format,
      'sample_rate': _config.sampleRate,
      'voice_name': _config.voiceName,
      'generation_status': 'completed',
      'generated_at': DateTime.now().toIso8601String(),
      'uploaded_at': DateTime.now().toIso8601String(),
    }, onConflict: 'translation_id,book_id,chapter,storage_provider');
  }

  Future<String> _getTranslationId() async {
    final result = await _supabase
        .from('bible_translations')
        .select('id')
        .eq('code', _config.translationCode)
        .maybeSingle();
    return result?['id'] as String? ?? '';
  }

  /// Format chapter text for natural TTS reading
  String _formatChapterText(String bookName, int chapter, List<BibleVerse> verses) {
    final buffer = StringBuffer();
    buffer.write('$bookName, chapter $chapter. ');
    
    for (final verse in verses) {
      // Add verse number for navigation, but speak naturally
      if (verse.verse == 1) {
        buffer.write('Verse 1. ${verse.text} ');
      } else {
        buffer.write('${verse.verse}. ${verse.text} ');
      }
    }
    
    return buffer.toString().trim();
  }

  /// Estimate audio duration from text length (rough approximation)
  Future<Duration> _estimateDuration(int charCount) async {
    // Average speaking rate: ~150 words/min, ~5 chars/word = ~750 chars/min
    // So ~12.5 chars/second
    final seconds = (charCount / 12.5).ceil();
    return Duration(seconds: seconds);
  }

  Future<List<BibleBook>> _getBooksForTestament(Testament testament) async {
    final testamentStr = testament == Testament.old ? 'OT' : 'NT';
    final result = await _supabase
        .from('bible_books')
        .select('name, abbreviation, testament, chapters, book_order, description')
        .eq('testament', testamentStr)
        .order('book_order');
    
    return (result as List).map((json) => BibleBook.fromJson(json)).toList();
  }

  void _reportProgress(
    String bookName,
    int chapter,
    int totalChapters,
    GenerationStatus status,
    String? error,
  ) {
    _onProgress?.call(bookName, chapter, totalChapters, status, error);
  }

  void dispose() {
    _flutterTts.stop();
    _verseChangeController.close();
  }
}

/// Riverpod provider for AudioBibleService
final audioBibleServiceProvider = Provider<AudioBibleService>((ref) {
  final supabase = ref.watch(supabaseServiceProvider).client;
  final bibleService = ref.watch(bibleServiceProvider);
  
  return AudioBibleService(
    supabase: supabase,
    bibleService: bibleService,
    config: const AudioBibleConfig(),
  );
});

/// Provider for generation progress state (Riverpod v3 compatible)
class GenerationProgress {
  final String bookName;
  final int currentChapter;
  final int totalChapters;
  final GenerationStatus status;
  final String? error;
  final int completedBooks;
  final int totalBooks;

  GenerationProgress({
    required this.bookName,
    required this.currentChapter,
    required this.totalChapters,
    required this.status,
    this.error,
    this.completedBooks = 0,
    this.totalBooks = 66,
  });

  double get chapterProgress => totalChapters > 0 ? currentChapter / totalChapters : 0.0;
  double get overallProgress => totalBooks > 0 ? completedBooks / totalBooks : 0.0;
}

class AudioGenerationProgressNotifier extends Notifier<GenerationProgress?> {
  @override
  GenerationProgress? build() => null;

  void update(GenerationProgress progress) => state = progress;
  void clear() => state = null;
}

final audioGenerationProgressProvider = NotifierProvider<AudioGenerationProgressNotifier, GenerationProgress?>(
  AudioGenerationProgressNotifier.new,
);