import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LencoPaymentGateway extends ConsumerStatefulWidget {
  final double amount;
  final String description;
  final String category; // 'tithe', 'giving', 'event', 'product'
  final String? recipientName;
  final String? recipientAccount;
  final String? paymentReason;
  final Function(bool success, String? transactionId) onComplete;

  const LencoPaymentGateway({
    super.key,
    required this.amount,
    required this.description,
    this.category = 'giving',
    this.recipientName,
    this.recipientAccount,
    this.paymentReason,
    required this.onComplete,
  });

  @override
  ConsumerState<LencoPaymentGateway> createState() => _LencoPaymentGatewayState();
}

class _LencoPaymentGatewayState extends ConsumerState<LencoPaymentGateway> {
  String _selectedMethod = "Mobile Money";
  String _selectedNetwork = "MTN";
  final _phoneCtrl = TextEditingController();
  bool _isProcessing = false;
  String? _errorMessage;
  String _statusMessage = "Initializing payload...";

  final List<Map<String, dynamic>> _networks = [
    {"name": "MTN", "color": Colors.yellow, "id": "mtn_zambia"},
    {"name": "Airtel", "color": Colors.red, "id": "airtel_zambia"},
    {"name": "Zamtel", "color": Colors.green, "id": "zamtel_zambia"},
  ];

  Future<void> _initiatePayment() async {
    if (_phoneCtrl.text.isEmpty) {
      setState(() => _errorMessage = "Phone number is required");
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _statusMessage = "Connecting to Lenco APIs...";
    });

    try {
      final String apiKey = dotenv.get('LENCO_API_KEY').trim();
      const String baseUrl = "https://api.lenco.co/access/v2";
      final tenant = ref.read(currentTenantProvider);
      
      // Format phone: ensure 260 prefix
      String phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (phone.startsWith('0')) phone = '260${phone.substring(1)}';
      if (phone.startsWith('9')) phone = '260$phone';

      final String reference = "TX-${DateTime.now().millisecondsSinceEpoch}";
      final String operatorId = _networks.firstWhere((n) => n['name'] == _selectedNetwork)['id'];

      // Step 1: Initiate Collection
      final response = await http.post(
        Uri.parse("$baseUrl/collections/mobile-money"),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "amount": widget.amount,
          "reference": reference,
          "phone": phone,
          "operator": operatorId,
          "country": "zm",
          "currency": "ZMW",
          "bearer": "merchant",
          "account_id": dotenv.get('LENCO_MAIN_ACCOUNT_ID'),
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? "Lenco API Error");
      }

      setState(() => _statusMessage = "Pushing PIN prompt to $_phoneCtrl.text...");

      // Step 2: Polling for Status
      bool confirmed = false;
      int attempts = 0;
      const int maxAttempts = 30; // 2 minutes approx

      while (!confirmed && attempts < maxAttempts) {
        await Future.delayed(const Duration(seconds: 4));
        attempts++;
        setState(() => _statusMessage = "Waiting for your PIN confirmation... (Attempt $attempts)");

        final statusResp = await http.get(
          Uri.parse("$baseUrl/collections/status/$reference"),
          headers: {"Authorization": "Bearer $apiKey"},
        );

        if (statusResp.statusCode == 200) {
          final statusData = jsonDecode(statusResp.body);
          final String status = (statusData['data']['status'] ?? '').toString().toLowerCase();
          
          if (status == 'successful' || status == 'paid' || status == 'settled') {
            confirmed = true;
          } else if (status == 'failed' || status == 'cancelled' || status == 'rejected') {
            throw Exception("Transaction was $status by user or provider.");
          }
        }
      }

      if (!confirmed) {
        throw Exception("Transaction timed out. Please try again.");
      }

      setState(() => _statusMessage = "PIN confirmed. Finishing settlement...");
      await Future.delayed(const Duration(seconds: 2));
      
      widget.onComplete(true, reference);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Settled to: ${widget.recipientName ?? tenant?.name ?? 'Church On App'}"), 
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final displayRecipient = widget.recipientName ?? tenant?.name ?? "Church On App";
    final displayAccount = widget.recipientAccount ?? tenant?.treasurerPhone ?? "Merchant ID: 097654321";

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(left: 25, right: 25, top: 30, bottom: MediaQuery.of(context).viewInsets.bottom + 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Secure Settlement", style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 20),
          
          // RECIPIENT CARD
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                _buildInfoRow("Paying To:", displayRecipient, isTitle: true),
                const SizedBox(height: 8),
                _buildInfoRow("Settlement A/C:", displayAccount),
                const SizedBox(height: 8),
                _buildInfoRow("Reference:", widget.paymentReason ?? widget.description),
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total (Inc. Fees)", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text("K${widget.amount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blue)),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          if (_isProcessing) 
             _buildProcessingState()
          else ...[
            const Text("Select Network", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _networks.map((n) {
                bool isSelected = _selectedNetwork == n['name'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedNetwork = n['name']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? n['color'].withOpacity(0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: isSelected ? n['color'] : const Color(0xFFF1F5F9), width: 2),
                    ),
                    child: Text(n['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? (n['color'] == Colors.yellow ? Colors.black : n['color']) : const Color(0xFF94A3B8))),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: "Enter Mobile number to pay from",
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                prefixIcon: const Icon(LucideIcons.phone, size: 20),
              ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _initiatePayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                minimumSize: const Size(double.infinity, 65),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text("PROCEED TO PIN PROMPT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
          
          const SizedBox(height: 20),
          const Center(child: Text("Regulated by Bank of Zambia via Lenco", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isTitle = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value, style: TextStyle(fontWeight: isTitle ? FontWeight.w900 : FontWeight.bold, fontSize: isTitle ? 14 : 12)),
      ],
    );
  }

  Widget _buildProcessingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          const CircularProgressIndicator(strokeWidth: 6, color: Colors.blue),
          const SizedBox(height: 30),
          Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          const SizedBox(height: 10),
          const Text("Please check your phone for the PIN request pop-up.", style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

