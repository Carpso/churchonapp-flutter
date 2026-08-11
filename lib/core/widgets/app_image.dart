import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AppImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cacheWidth = width != null ? (width! * MediaQuery.devicePixelRatioOf(context)).round() : null;
    final cacheHeight = height != null ? (height! * MediaQuery.devicePixelRatioOf(context)).round() : null;

    final url = this.url.trim();
    if (url.isEmpty) {
      // Empty URL: render the placeholder / error fallback instead of a
      // broken-image icon.
      return placeholder ??
          errorWidget?.call(context, '') ??
          Container(
            width: width,
            height: height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
    }

    Widget image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (context, url) => placeholder ?? Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (context, url, error) {
        if (errorWidget != null) return errorWidget!(context, url);
        return Container(
          width: width,
          height: height,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
        );
      },
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    if (color != null) {
      image = ColorFiltered(
        colorFilter: ColorFilter.mode(color!, BlendMode.multiply),
        child: image,
      );
    }

    return image;
  }
}
