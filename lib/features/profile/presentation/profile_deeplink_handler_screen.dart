import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'profile_screen.dart';

class ProfileDeepLinkHandlerScreen extends ConsumerWidget {
  final String userId;
  const ProfileDeepLinkHandlerScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProfileScreen(userId: userId);
  }
}
