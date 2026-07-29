import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/gemini_service.dart';

class MockGeminiService extends Mock implements GeminiService {}

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockAuth extends Mock implements GoTrueClient {}
class MockUser extends Mock implements User {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ignore: must_be_immutable
class MockFilterBuilder extends Mock
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  List<Map<String, dynamic>> mockResult = [];

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>>) onValue,
      {Function? onError}) {
    return Future.value(mockResult).then(onValue, onError: onError);
  }
}

// ignore: must_be_immutable
class MockSingleBuilder extends Mock
    implements PostgrestTransformBuilder<Map<String, dynamic>> {
  Map<String, dynamic> result = const {};

  @override
  Future<R> then<R>(FutureOr<R> Function(Map<String, dynamic>) onValue,
      {Function? onError}) {
    return Future.value(result).then(onValue, onError: onError);
  }
}

// ignore: must_be_immutable
class MockMaybeSingleBuilder extends Mock
    implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  Map<String, dynamic>? result;

  @override
  Future<R> then<R>(FutureOr<R> Function(Map<String, dynamic>?) onValue,
      {Function? onError}) {
    return Future.value(result).then(onValue, onError: onError);
  }
}

class MockSupabaseStreamBuilder extends Mock
    implements SupabaseStreamFilterBuilder {
  Stream<List<Map<String, dynamic>>> streamResult = const Stream.empty();

  @override
  Stream<E> map<E>(E Function(List<Map<String, dynamic>>) convert) {
    return streamResult.map(convert);
  }

  @override
  StreamSubscription<List<Map<String, dynamic>>> listen(
    void Function(List<Map<String, dynamic>> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return streamResult.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
