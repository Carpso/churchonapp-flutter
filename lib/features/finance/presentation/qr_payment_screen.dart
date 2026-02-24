import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class QrPaymentScreen extends StatelessWidget {
  final double amount;
  final String description;
  final String recipient;

  const QrPaymentScreen({
    super.key,
    required this.amount,
    required this.description,
    required this.recipient,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("KINGDOM PAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildQrCard(context),
              const SizedBox(height: 40),
              _buildPaymentDetails(),
              const SizedBox(height: 50),
              _buildActionButtons(context),
              const SizedBox(height: 20),
              const Text(
                "Scan this QR at any Kingdom Hub or with your Banking App to settle the transaction via our sovereign ledger.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), blurRadius: 40, spreadRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.landmark, color: Theme.of(context).primaryColor, size: 20),
              const SizedBox(width: 10),
              Text(
                "VERIFIED HUB PAYMENT",
                style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 30),
          // In a real app, we'd use qr_flutter to generate a real dynamic QR
          const Icon(LucideIcons.qrCode, color: Colors.black, size: 220),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
            child: Text(
              "REF: COA-TX-${DateTime.now().millisecond}-ZAM",
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetails() {
    return Column(
      children: [
        Text(
          "K ${amount.toStringAsFixed(2)}",
          style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          description.toUpperCase(),
          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
        ),
        const SizedBox(height: 20),
        Text(
          "Recipient: $recipient",
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transaction proof requested from VPS...")));
             Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text("I HAVE PAID", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 15),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL TRANSACTION", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
