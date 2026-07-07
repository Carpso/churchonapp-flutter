import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'marketplace_service.dart';

class CartItem {
  final MarketProduct product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});
}

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void addToCart(MarketProduct product) {
    final existingIndex = state.indexWhere((item) => item.product.id == product.id);
    if (existingIndex != -1) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == existingIndex)
            CartItem(product: state[i].product, quantity: state[i].quantity + 1)
          else
            state[i],
      ];
    } else {
      state = [...state, CartItem(product: product)];
    }
  }

  void removeFromCart(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(productId);
      return;
    }
    state = [
      for (final item in state)
        if (item.product.id == productId)
          CartItem(product: item.product, quantity: quantity)
        else
          item,
    ];
  }

  void clear() => state = [];

  double get total => state.fold(0, (sum, item) => sum + (item.product.price * item.quantity));
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(() => CartNotifier());
