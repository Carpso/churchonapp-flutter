import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/r2_service.dart';

/// Resolves an R2 public-domain URL to its signed form, then hands it to
/// [builder]. Use for widgets that need the resolved URL directly (e.g.
/// `CachedNetworkImage` with `imageBuilder`, or `CachedNetworkImageProvider`).
/// While resolving, [builder] is first called with the original URL so callers
/// render their normal placeholder immediately; after resolution it rebuilds
/// with the signed URL. Non-R2 URLs are passed through untouched.
class ResolvedR2Image extends StatefulWidget {
  final String url;
  final Widget Function(BuildContext context, String resolvedUrl) builder;

  const ResolvedR2Image({super.key, required this.url, required this.builder});

  @override
  State<ResolvedR2Image> createState() => _ResolvedR2ImageState();
}

class _ResolvedR2ImageState extends State<ResolvedR2Image> {
  late String _resolved = widget.url.trim();
  String? _inFlight;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ResolvedR2Image oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url.trim() != oldWidget.url.trim()) {
      _resolved = widget.url.trim();
      _inFlight = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.url.trim();
    if (_inFlight == url) return;
    _inFlight = url;
    final resolved = await R2Service.resolveReadUrl(url);
    if (!mounted || _inFlight != url) return;
    _inFlight = null;
    if (resolved != _resolved) setState(() => _resolved = resolved);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _resolved);
}

/// App-wide network image. Automatically signs R2 public-domain URLs so
/// images load even though the R2 bucket is private; every call site benefits
/// without changes. Non-R2 URLs pass through unchanged.
class AppImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget Function(BuildContext, String)? errorWidget;
  final Color? color;
  final Alignment alignment;
  final BorderRadius? borderRadius;

  const AppImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.color,
    this.alignment = Alignment.center,
    this.borderRadius,
  });

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  late String _displayUrl = widget.url.trim();
  String? _resolvingUrl;
  int _retryCount = 0;
  static const int _maxRetries = 2;

  @override
  void initState() {
    super.initState();
    _maybeResolve();
  }

  @override
  void didUpdateWidget(covariant AppImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.url.trim();
    if (next != oldWidget.url.trim()) {
      _displayUrl = next;
      _resolvingUrl = null;
      _retryCount = 0;
      _maybeResolve();
    }
  }

  Future<void> _maybeResolve() async {
    if (_displayUrl.isEmpty) return;
    final url = _displayUrl;
    if (_resolvingUrl == url) return;
    _resolvingUrl = url;
    try {
      final resolved = await R2Service.resolveReadUrl(url);
      if (!mounted || _resolvingUrl != url) return;
      if (resolved != _displayUrl) {
        setState(() => _displayUrl = resolved);
      }
    } catch (e) {
      // R2-sign failed — keep original URL; CachedNetworkImage may still
      // serve it from its own disk cache even if the bucket is private.
      debugPrint('AppImage resolve failed (non-fatal): $e');
    }
  }

  /// Called by CachedNetworkImage errorWidget when the resolved URL 403s.
  /// On first failure, invalidate the R2 cache and re-resolve (the signed
  /// URL may have expired). On second failure, try the raw public URL
  /// directly — some images may be publicly accessible despite the bucket
  /// being private (e.g. profile pics uploaded via a different path).
  void _onImageError(String failedUrl) {
    if (_retryCount >= _maxRetries) return;
    _retryCount++;
    _resolvingUrl = null;
    // Clear the cached signed URL so we get a fresh one
    R2Service.invalidateReadCache(widget.url.trim());
    // On second try, skip resolve and use raw URL
    if (_retryCount >= _maxRetries && mounted) {
      setState(() => _displayUrl = widget.url.trim());
    } else {
      _maybeResolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: callers routinely pass `width: double.infinity` (e.g. banners and
    // grid tiles). `infinity * dpr` is `Infinity`, and `Infinity.round()`
    // THROWS "Unsupported operation: Infinity or NaN toInt" during build — which
    // killed the whole AppImage widget and left the image blank/broken.
    // Only derive a cache size when the dimension is finite and > 0.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (widget.width != null && widget.width!.isFinite && widget.width! > 0)
        ? (widget.width! * dpr).round()
        : null;
    final cacheHeight = (widget.height != null && widget.height!.isFinite && widget.height! > 0)
        ? (widget.height! * dpr).round()
        : null;

    final url = _displayUrl;
    if (url.isEmpty) {
      // Empty URL: render the placeholder / error fallback instead of a
      // broken-image icon.
      return widget.placeholder ??
          widget.errorWidget?.call(context, '') ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
    }

    Widget image = CachedNetworkImage(
      imageUrl: url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (context, url) => widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      errorWidget: (context, url, error) {
        // Retry: invalidate R2 cache and re-resolve (signed URL may have expired)
        _onImageError(url);
        if (widget.errorWidget != null) return widget.errorWidget!(context, url);
        return Container(
          width: widget.width,
          height: widget.height,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
        );
      },
    );

    if (widget.borderRadius != null) {
      image = ClipRRect(borderRadius: widget.borderRadius!, child: image);
    }

    if (widget.color != null) {
      image = ColorFiltered(
        colorFilter: ColorFilter.mode(widget.color!, BlendMode.multiply),
        child: image,
      );
    }

    return image;
  }
}