import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// A small, BOUNDED fallback for a SINGLE failed widget.
///
/// This is what `ErrorWidget.builder` must return. `ErrorWidget.builder` is
/// invoked in place of an arbitrary failing widget — very often a small child
/// inside a `ListView`/`Sliver` (e.g. one home-feed section). It MUST therefore
/// be a self-sizing widget, never a `Scaffold`/`MaterialApp`: laying a full
/// screen out inside a sliver child breaks the whole viewport and paints a
/// blank white block under the first section that fails.
class InlineErrorTile extends StatelessWidget {
  final FlutterErrorDetails details;

  const InlineErrorTile({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.55)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(LucideIcons.alertTriangle, color: Colors.orange, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "This section couldn't load",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 4),
                    Text(
                      details.exceptionAsString(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// App Global Error Boundary
/// Traps any unhandled exception in the widget tree
/// and presents a Premium "Oops" screen instead of the 
/// red screen of death.
class CustomErrorBoundary extends StatelessWidget {
  final FlutterErrorDetails errorDetails;

  const CustomErrorBoundary({super.key, required this.errorDetails});

  @override
  Widget build(BuildContext context) {
    final body = Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: const SizedBox.shrink(),
        title: Text("App Recovered", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.alertTriangle, color: Colors.red, size: 60),
              ),
              const SizedBox(height: 25),
              Text(
                "An unexpected error occurred.",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              Text(
                "Our engineers have been notified. Please return to the Home Hub or restart the app.",
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(15)),
                width: double.infinity,
                child: SelectableText(
                  errorDetails.exceptionAsString(),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontFamily: "monospace"),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(15)),
                width: double.infinity,
                child: SelectableText(
                  errorDetails.stack.toString(),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3), fontFamily: "monospace"),
                  maxLines: 8,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                   try {
                     Navigator.of(context).popUntil((route) => route.isFirst);
                   } catch (_) {
                     // If we are at root, we can't pop
                   }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: Icon(LucideIcons.home, color: Theme.of(context).colorScheme.onPrimary),
                label: Text("RETURN TO HOME", style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );

    // If we are the root error widget, we need a MaterialApp
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: body,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },
    );
  }

}

