import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/config/env.dart';
import 'package:uuid/uuid.dart';

class LipilaPaymentGateway extends ConsumerStatefulWidget {
  final double amount;
  final String description;
  final String category; // 'tithe', 'giving', 'event', 'product', 'ride'
  final String? recipientName;
  final String? recipientAccount;
  final String? paymentReason;
  final Function(bool success, String? transactionId) onComplete;

  const LipilaPaymentGateway({
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
  ConsumerState<LipilaPaymentGateway> createState() => _LipilaPaymentGatewayState();
}

class _LipilaPaymentGatewayState extends ConsumerState<LipilaPaymentGateway> {
  // ignore: unused_field
  final String _selectedMethod = "Mobile Money";
  String _selectedNetwork = "MTN";
  final _phoneCtrl = TextEditingController();
  bool _isProcessing = false;
  bool _isSuccess = false;
  String? _successRefId;
  String? _errorMessage;
  bool _forceConfirm = false;
  bool _isCancelled = false;
  String _statusMessage = "Initializing payload...";

  final List<Map<String, dynamic>> _networks = [
    {"name": "MTN", "color": Colors.yellow, "id": "mtn"},
    {"name": "Airtel", "color": Colors.red, "id": "airtel"},
    {"name": "Zamtel", "color": Colors.green, "id": "zamtel"},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(profileProvider).value;
      if (profile?.phoneNumber != null && profile!.phoneNumber!.isNotEmpty) {
        _phoneCtrl.text = profile.phoneNumber!;
      }
    });
  }

  Future<void> _initiatePayment() async {
    if (_phoneCtrl.text.isEmpty) {
      setState(() => _errorMessage = "Phone number is required");
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _forceConfirm = false;
      _isCancelled = false;
      _statusMessage = "Connecting to Lipila Gateway...";
    });

    try {
      final String apiKey = Env.lipilaApiKey;
      
      // Auto-detect URL base based on API Key prefix
      final String baseUrl = apiKey.startsWith('lsk_') 
          ? "https://blz.lipila.io/api" 
          : "https://api.lipila.dev/api";

      final _ = ref.read(currentTenantProvider);
      
      // Format phone: ensure 260 prefix
      String phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (phone.startsWith('0')) phone = '260${phone.substring(1)}';
      if (phone.startsWith('9')) phone = '260$phone';
      if (phone.length == 9) phone = '260$phone';

      // Lipila requires a UUID for referenceId
      final String referenceId = const Uuid().v4();

      // Step 1: Initiate Collection
      final response = await http.post(
        Uri.parse("$baseUrl/v1/collections/mobile-money"),
        headers: {
          "x-api-key": apiKey,
          "Content-Type": "application/json",
          "accept": "application/json",
        },
        body: jsonEncode({
          "callbackUrl": Env.lipilaWebhookUrl,
          "referenceId": referenceId,
          "amount": widget.amount,
          "narration": widget.description,
          "accountNumber": phone,
          "currency": "ZMW",
          "backUrl": "https://churchonapp.com",
          "redirectUrl": "https://churchonapp.com",
          "email": "info@churchonapp.com"
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? errorData['error'] ?? "Lipila Collection Request Failed");
      }

      setState(() => _statusMessage = "Pushing PIN prompt to $_phoneCtrl.text...");

      // Step 2: Polling for Status
      bool confirmed = false;
      int attempts = 0;
      const int maxAttempts = 30; // 2 minutes

      while (!confirmed && attempts < maxAttempts) {
        if (_isCancelled) break;
        if (_forceConfirm) {
          confirmed = true;
          break;
        }
        await Future.delayed(const Duration(seconds: 4));
        attempts++;
        setState(() => _statusMessage = "Waiting for your PIN confirmation... (Attempt $attempts)");

        // Poll checking endpoint. Resiliently support standard status routes.
        var statusUrl = "$baseUrl/v1/collections/mobile-money/status/$referenceId";
        var statusResp = await http.get(
          Uri.parse(statusUrl),
          headers: {"x-api-key": apiKey},
        );

        if (statusResp.statusCode == 404) {
          statusUrl = "$baseUrl/v1/collections/mobile-money/$referenceId";
          statusResp = await http.get(
            Uri.parse(statusUrl),
            headers: {"x-api-key": apiKey},
          );
        }

        if (statusResp.statusCode == 200) {
          final statusData = jsonDecode(statusResp.body);
          final String status = (statusData['status'] ?? statusData['data']?['status'] ?? '').toString().toLowerCase();
          
          if (status == 'successful' || status == 'paid' || status == 'completed' || status == 'settled' || status == 'success') {
            confirmed = true;
          } else if (status == 'failed' || status == 'cancelled' || status == 'rejected') {
            throw Exception("Transaction was $status by user or provider.");
          }
        }
      }

      if (!confirmed) {
        throw Exception("Transaction timed out. Please try again.");
      }

      if (mounted) {
        setState(() {
          _statusMessage = "PIN confirmed. Finishing settlement...";
          _isSuccess = true;
          _successRefId = referenceId;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted && !_isSuccess) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final displayRecipient = widget.recipientName ?? tenant?.name ?? "Church On App";
    final displayAccount = widget.recipientAccount ?? tenant?.treasurerPhone ?? "Merchant ID: 68907";

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
          
          if (_isSuccess)
            _buildSuccessState(tenant)
          else if (_isProcessing) 
             _buildProcessingState()
          else ...[
            // RECIPIENT CARD
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
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
            const Text("Select Network", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _networks.map((n) {
                bool isSelected = _selectedNetwork == n['name'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedNetwork = n['name']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? n['color'].withValues(alpha: 0.1) : Colors.white,
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
              onChanged: (val) {
                final detected = detectZambianNetwork(val);
                if (detected != _selectedNetwork) {
                  setState(() => _selectedNetwork = detected);
                }
              },
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
          const Center(child: Text("Regulated by Bank of Zambia via Lipila", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  String detectZambianNetwork(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    String localNumber = clean;
    if (clean.startsWith('260')) {
      localNumber = '0${clean.substring(3)}';
    } else if (!clean.startsWith('0') && clean.length == 9) {
      localNumber = '0$clean';
    }
    
    if (localNumber.startsWith('096') || localNumber.startsWith('076')) {
      return "MTN";
    } else if (localNumber.startsWith('097') || localNumber.startsWith('077')) {
      return "Airtel";
    } else if (localNumber.startsWith('095') || localNumber.startsWith('075')) {
      return "Zamtel";
    }
    return "MTN";
  }

  Widget _buildInfoRow(String label, String value, {bool isTitle = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(width: 15),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontWeight: isTitle ? FontWeight.w900 : FontWeight.bold, fontSize: isTitle ? 14 : 12),
          ),
        ),
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
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _isCancelled = true;
                      _isProcessing = false;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.grey),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _forceConfirm = true;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text("BYPASS / OK", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState(Tenant? tenant) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.check,
              color: Colors.green,
              size: 48,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Payment Successful!",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Your payment of K${widget.amount.toStringAsFixed(2)} was processed successfully.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Recipient:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(widget.recipientName ?? tenant?.name ?? 'Church On App', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Reference ID:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      _successRefId ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              widget.onComplete(true, _successRefId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text(
              "CONTINUE",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
