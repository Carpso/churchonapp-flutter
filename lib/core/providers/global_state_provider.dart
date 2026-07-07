import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App Global State to manage top-level configuration
/// like Currency formats, localization, and theme overrides.

enum AppCurrency {
  zmw("K"),
  usd("\$");

  final String symbol;
  const AppCurrency(this.symbol);
}

class GlobalAppState {
  final AppCurrency currency;
  final String languageCode;
  final bool isEnterpriseLocked;

  GlobalAppState({
    this.currency = AppCurrency.zmw,
    this.languageCode = 'en',
    this.isEnterpriseLocked = false,
  });

  GlobalAppState copyWith({
    AppCurrency? currency,
    String? languageCode,
    bool? isEnterpriseLocked,
  }) {
    return GlobalAppState(
      currency: currency ?? this.currency,
      languageCode: languageCode ?? this.languageCode,
      isEnterpriseLocked: isEnterpriseLocked ?? this.isEnterpriseLocked,
    );
  }
}

class GlobalStateNotifier extends Notifier<GlobalAppState> {
  @override
  GlobalAppState build() {
    return GlobalAppState();
  }

  void toggleCurrency() {
    state = state.copyWith(
      currency: state.currency == AppCurrency.zmw ? AppCurrency.usd : AppCurrency.zmw,
    );
  }

  void setLanguage(String code) {
    state = state.copyWith(languageCode: code);
  }

  void unlockEnterprise(bool isUnlocked) {
    state = state.copyWith(isEnterpriseLocked: !isUnlocked);
  }
}

final globalStateProvider = NotifierProvider<GlobalStateNotifier, GlobalAppState>(() {
  return GlobalStateNotifier();
});

