import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// App Global Error Boundary
/// Traps any unhandled exception in the widget tree
/// and presents a Premium "Oops" screen instead of the 
/// red screen of death.
class CustomErrorBoundary extends StatelessWidget {
  final FlutterErrorDetails errorDetails;

  const CustomErrorBoundary({super.key, required this.errorDetails});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: const SizedBox.shrink(),
        title: const Text("App Recovered", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Padding(
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
              const Text(
                "An unexpected error occurred.",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              Text(
                "Our engineers have been notified. Please return to the Home Hub or restart the app.",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              // Optional dev info string if needed
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
                child: Text(
                  errorDetails.exceptionAsString(),
                  style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: "monospace"),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                   Navigator.of(context).popUntil((route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: const Icon(LucideIcons.home, color: Colors.white),
                label: const Text("RETURN TO HOME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
