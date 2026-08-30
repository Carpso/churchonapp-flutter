import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Instagram-style image carousel for church social posts.
///
/// • Snapping PageView (one swipe = one image), page dots + "n/N" pill.
/// • Images render with BoxFit.contain inside a 16:9 letterboxed stage so
///   NOTHING is cropped or zoomed — the full frame always fits.
/// • Tapping any image opens a full-screen black viewer with pinch-zoom
///   (InteractiveViewer) and horizontal swiping between all post images;
///   tap anywhere to dismiss.
class PostImageCarousel extends StatefulWidget {
  const PostImageCarousel({super.key, required this.images});

  final List<String> images;

  @override
  State<PostImageCarousel> createState() => _PostImageCarouselState();
}

class _PostImageCarouselState extends State<PostImageCarousel> {
  final PageController _pageController = PageController();
  int _page = 0;
  final Map<int, double> _aspects = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.images.length; i++) {
      _resolveAspect(widget.images[i], i);
    }
  }

  void _resolveAspect(String url, int index) {
    final provider = CachedNetworkImageProvider(url);
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (w > 0 && h > 0) {
        final aspect = w / h;
        // Clamp to reasonable feed bounds: 0.8 (tall) .. 2.2 (wide) so a single tall panorama doesn't dominate.
        final clamped = aspect.clamp(0.8, 2.0);
        if (mounted && _aspects[index] != clamped) {
          setState(() => _aspects[index] = clamped);
        }
      }
      stream.removeListener(listener);
    }, onError: (_, __) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openViewer(int initialIndex) {
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _FullScreenGallery(
        images: widget.images,
        initialIndex: initialIndex,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageAspect = _aspects[_page] ?? 16 / 12;
        final isSingle = widget.images.length == 1;
        final content = isSingle
            ? GestureDetector(
                onTap: () => _openViewer(0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: widget.images.first,
                    fit: BoxFit.cover,
                    width: constraints.maxWidth,
                    memCacheWidth: 900,
                    placeholder: (_, __) => AspectRatio(
                      aspectRatio: pageAspect,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
                    ),
                    errorWidget: (_, __, ___) => AspectRatio(
                      aspectRatio: pageAspect,
                      child: Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.broken_image, color: scheme.onSurface.withValues(alpha: 0.35)),
                      ),
                    ),
                  ),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: pageAspect,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.images.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => _openViewer(i),
                      child: CachedNetworkImage(
                        imageUrl: widget.images[i],
                        fit: BoxFit.cover,
                        width: constraints.maxWidth,
                        memCacheWidth: 900,
                        placeholder: (_, __) => Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.broken_image, color: scheme.onSurface.withValues(alpha: 0.35)),
                        ),
                      ),
                    ),
                  ),
                ),
              );
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: content,
            ),
            if (widget.images.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.images.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? Theme.of(context).primaryColor
                              : scheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Full-screen pinch-zoom gallery. Swipe left/right through images, tap to
/// close, double-tap toggles 2x zoom on the tapped point.
class _FullScreenGallery extends StatefulWidget {
  const _FullScreenGallery({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: widget.images[i],
                  fit: BoxFit.contain,
                  memCacheWidth: 1200,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image,
                      color: Colors.white24, size: 48),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.images.length > 1)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${_page + 1} / ${widget.images.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                            color: Colors.white24, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
