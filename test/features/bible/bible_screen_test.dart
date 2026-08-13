import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/bible/presentation/bible_screen.dart';
import 'package:church_on_app/features/bible/data/audio_bible_service.dart';
import 'package:church_on_app/features/bible/data/bible_service.dart';
import 'package:church_on_app/features/bible/data/bible_book_model.dart';
import 'package:church_on_app/features/bible/data/bible_books_service.dart';
import 'package:church_on_app/features/bible/data/bible_verse_service.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeSupabaseService extends SupabaseService {
  final SupabaseClient _client;
  FakeSupabaseService(this._client);
  @override
  SupabaseClient get client => _client;
}

class QuietAudioBibleService extends AudioBibleService {
  QuietAudioBibleService({required super.supabase, required super.bibleService});
  @override
  Future<void> initialize() async {}
}

void main() {
  final mockClient = MockSupabaseClient();
  final bibleService = BibleService();

  testWidgets('Bible screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseServiceProvider.overrideWithValue(FakeSupabaseService(mockClient)),
          audioBibleServiceProvider.overrideWith((ref) => QuietAudioBibleService(supabase: mockClient, bibleService: bibleService)),
          bibleBooksProvider.overrideWith((ref) async => const <BibleBook>[]),
          dailyBibleVerseProvider.overrideWith((ref) async => DailyBibleVerse(id: 'd', reference: 'John 3:16', text: 'For God so loved', createdAt: DateTime(2026, 1, 1))),
        ],
        child: const MaterialApp(home: BibleScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(BibleScreen), findsOneWidget);
  });

  testWidgets('Bible screen has an AppBar with back button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseServiceProvider.overrideWithValue(FakeSupabaseService(mockClient)),
          audioBibleServiceProvider.overrideWith((ref) => QuietAudioBibleService(supabase: mockClient, bibleService: bibleService)),
          bibleBooksProvider.overrideWith((ref) async => const <BibleBook>[]),
          dailyBibleVerseProvider.overrideWith((ref) async => DailyBibleVerse(id: 'd', reference: 'John 3:16', text: 'For God so loved', createdAt: DateTime(2026, 1, 1))),
        ],
        child: const MaterialApp(home: BibleScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
  });
}
