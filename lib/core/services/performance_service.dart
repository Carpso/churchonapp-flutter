import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Performance optimization service for Church On App
/// Optimized for low-end Android devices common in Zambia
class PerformanceService {
  static PerformanceService? _instance;
  static PerformanceService get instance => _instance ??= PerformanceService._();
  PerformanceService._();

  bool _isLowEndDevice = false;
  bool _isInitialized = false;

  bool get isLowEndDevice => _isLowEndDevice;

  /// Initialize performance service with real device detection
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final ramMb = _getTotalRamMb(androidInfo);
        final sdkInt = androidInfo.version.sdkInt;

        // Heuristic: low-end if < 3GB RAM or Android < 10
        _isLowEndDevice = ramMb < 3072 || sdkInt < 29;
        debugPrint('Android device: RAM=${ramMb}MB, SDK=$sdkInt, lowEnd=$_isLowEndDevice');
      } else if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        // iPhones with limited RAM are older models
        _isLowEndDevice = false; // iOS devices are generally well-optimized
        debugPrint('iOS device: ${iosInfo.name}, assuming standard performance');
      }
    } catch (e) {
      debugPrint('Failed to detect device capabilities: $e');
      // Assume low-end for safety on error
      _isLowEndDevice = true;
    }

    _isInitialized = true;
  }

  int _getTotalRamMb(AndroidDeviceInfo info) {
    // Heuristic: low-end Zambian devices often have 2GB RAM
    // Use supportedAbis to detect 32-bit-only (low-end) vs 64-bit
    try {
      final abis = info.supportedAbis;
      if (abis.isNotEmpty && !abis.any((a) => a.contains('arm64'))) {
        return 2048; // 32-bit-only = likely low-end
      }
      return 4096;
    } catch (_) {
      return 4096;
    }
  }

  /// Get image quality based on device capability
  int get imageQuality => _isLowEndDevice ? 60 : 85;

  /// Get image cache size based on device capability
  int get imageCacheSize => _isLowEndDevice ? 50 : 200;

  /// Get animation duration multiplier
  double get animationMultiplier => _isLowEndDevice ? 0.5 : 1.0;

  /// Should we use reduced animations?
  bool get reduceAnimations => _isLowEndDevice;

  /// Get list page limit based on device
  int get pageLimit => _isLowEndDevice ? 10 : 25;

  /// Should we lazy load images?
  bool get lazyLoadImages => _isLowEndDevice;

  /// Get preload count for lists
  int get preloadCount => _isLowEndDevice ? 3 : 10;

  /// Get estimated item height for list optimization
  double get estimatedItemHeight => _isLowEndDevice ? 72.0 : 80.0;
}

/// Performance-optimized list view with proper itemExtent
class OptimizedListView extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final double? itemExtent;

  const OptimizedListView({
    super.key,
    required this.children,
    this.controller,
    this.padding,
    this.shrinkWrap = false,
    this.itemExtent,
  });

  @override
  Widget build(BuildContext context) {
    final performance = PerformanceService.instance;

    return ListView.builder(
      controller: controller,
      padding: padding,
      shrinkWrap: shrinkWrap,
      // P2 FIX: Wire itemExtent to actual estimated height for scroll optimization
      itemExtent: itemExtent ?? performance.estimatedItemHeight,
      addAutomaticKeepAlives: !performance.isLowEndDevice,
      addRepaintBoundaries: true,
      itemCount: children.length,
      itemBuilder: (context, index) {
        if (index < children.length) {
          return children[index];
        }
        return null;
      },
    );
  }
}

/// Performance-optimized image widget with bitmap downsampling via CachedNetworkImage
class OptimizedImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedImage({
    super.key,
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final performance = PerformanceService.instance;

    if (url == null || url!.isEmpty) {
      return placeholder ?? Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.image, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
      );
    }

    final cacheWidth = width != null ? (width! * MediaQuery.devicePixelRatioOf(context)).round() : null;
    final cacheHeight = height != null ? (height! * MediaQuery.devicePixelRatioOf(context)).round() : null;

    return CachedNetworkImage(
      imageUrl: url!,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      filterQuality: performance.isLowEndDevice ? FilterQuality.low : FilterQuality.medium,
      placeholder: (context, url) => placeholder ?? Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (context, url, error) => errorWidget ?? Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
      ),
    );
  }
}

/// Performance-optimized animation wrapper
class OptimizedAnimation extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final bool enabled;

  const OptimizedAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final performance = PerformanceService.instance;

    if (!enabled || performance.reduceAnimations) {
      return child;
    }

    return AnimatedContainer(
      duration: Duration(
        milliseconds: (duration.inMilliseconds * performance.animationMultiplier).round(),
      ),
      child: child,
    );
  }
}

/// Performance monitor for debugging
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._();
  static PerformanceMonitor get instance => _instance;
  PerformanceMonitor._();

  final List<double> _frameTimes = [];
  Timer? _timer;

  void startMonitoring() {
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      _checkFrameRate();
    });
  }

  void _checkFrameRate() {
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
      _frameTimes.add(timeStamp.inMilliseconds.toDouble());
      if (_frameTimes.length > 60) {
        _frameTimes.removeAt(0);
      }

      if (_frameTimes.length > 10) {
        final avgFrameTime = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
        if (avgFrameTime > 16.67) {
          debugPrint('Performance warning: Average frame time ${avgFrameTime.toStringAsFixed(1)}ms');
        }
      }
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
  }
}
