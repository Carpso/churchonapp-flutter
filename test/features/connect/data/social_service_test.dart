
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/connect/data/social_service.dart';
import '../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockMaybeSingleBuilder mockMaybeSingle;
  late SocialService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    service = SocialService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  group('createPost', () {
    test('creates post successfully', () async {
      when(() => mockClient.from('profiles')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('tenant_id')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = {'tenant_id': 'church_1'};

      when(() => mockClient.from('social_posts')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.createPost(content: 'Hello world');
      verify(() => mockQuery.insert(any(that: containsPair('content', 'Hello world')))).called(1);
    });

    test('throws when user is not authenticated', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      expect(
        () => service.createPost(content: 'test'),
        throwsException,
      );
    });
  });

  group('fetchPosts', () {
    test('returns list of posts', () async {
      when(() => mockClient.from('social_posts')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.range(any(), any())).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [
        {
          'id': 'p1',
          'user_id': 'u1',
          'content': 'Test post',
          'created_at': DateTime.now().toIso8601String(),
          'likes_count': 0,
          'comments_count': 0,
          'is_moderated': false,
          'prophetic_weight': 0.0,
          'category': 'general',
        },
      ];

      final posts = await service.fetchPosts();
      expect(posts.length, 1);
      expect(posts.first.content, 'Test post');
    });

    test('returns empty list on error', () async {
      when(() => mockClient.from('social_posts')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.range(any(), any())).thenThrow(Exception('error'));

      final posts = await service.fetchPosts();
      expect(posts, isEmpty);
    });

    test('filters by tenantId when provided', () async {
      when(() => mockClient.from('social_posts')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.filter('tenant_id::text', 'eq', 'church_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.range(any(), any())).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      final posts = await service.fetchPosts(tenantId: 'church_1');
      expect(posts, isEmpty);
      verify(() => mockFilter.filter('tenant_id::text', 'eq', 'church_1')).called(1);
    });
  });

  group('toggleLike', () {
    test('adds like when not already liked', () async {
      when(() => mockClient.from('social_likes')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('id')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('post_id', 'p1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = null;
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      final liked = await service.toggleLike('p1');
      expect(liked, true);
    });

    test('removes like when already liked', () async {
      when(() => mockClient.from('social_likes')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select('id')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('post_id', 'p1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = {'id': 'like_1'};

      when(() => mockQuery.delete()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('post_id', 'p1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);

      final liked = await service.toggleLike('p1');
      expect(liked, false);
    });
  });

  group('reportPost - addComment as proxy for report', () {
    test('adds comment successfully', () async {
      when(() => mockClient.from('social_comments')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.addComment('p1', 'Great post!');
      verify(() => mockQuery.insert(any(that: containsPair('content', 'Great post!')))).called(1);
    });
  });

  /* group('deleteComment', () {
    test('deletes own comment', () async {
      when(() => mockClient.from('social_comments')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.delete()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('id', 'c1')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('user_id', 'user_1')).thenAnswer((_) => mockFilter);

      await service.deleteComment('c1');
      verify(() => mockFilter.eq('id', 'c1')).called(1);
    });
  }); */
}
