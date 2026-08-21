import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

enum ZambianNetwork { mtn, airtel, zamtel }

class MomoPhoneInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final String selectedNetwork;
  final ValueChanged<String> onNetworkChanged;
  final String? error;

  const MomoPhoneInputWidget({
    super.key,
    required this.controller,
    required this.selectedNetwork,
    required this.onNetworkChanged,
    this.error,
  });

  static const _networks = [
    {
      "name": "MTN",
      "color": Color(0xFFFFCC00),
      "id": "mtn",
      "prefixes": ["096", "076"],
      "logo": "assets/logo_mtn.png",
    },
    {
      "name": "Airtel",
      "color": Color(0xFFE31937),
      "id": "airtel",
      "prefixes": ["097", "077"],
      "logo": "assets/logo_airtel.png",
    },
    {
      "name": "Zamtel",
      "color": Color(0xFF4CAF50),
      "id": "zamtel",
      "prefixes": ["095", "075"],
      "logo": "assets/logo_zamtel.png",
    },
  ];

  /// Current Zambian mobile prefixes (ZICTA 2024/2025):
  /// MTN  -> 096, 076
  /// Airtel -> 097, 077
  /// Zamtel -> 095, 075
  /// Handles local `0` prefix, international `260`, `+260`, and bare 9-digit input.
  static String detectNetwork(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return "MTN";
    String localNumber = clean;
    if (clean.startsWith('260') && clean.length >= 12) {
      localNumber = '0${clean.substring(3)}';
    } else if (clean.startsWith('260') && clean.length >= 11) {
      // Handles pasted `2609...` without leading 0
      localNumber = '0${clean.substring(3)}';
    } else if (!clean.startsWith('0') && clean.length == 9) {
      localNumber = '0$clean';
    } else if (!clean.startsWith('0') && clean.length == 10 && clean.startsWith('9')) {
      localNumber = '0$clean';
    }

    if (localNumber.startsWith('096') || localNumber.startsWith('076')) {
      return "MTN";
    } else if (localNumber.startsWith('097') || localNumber.startsWith('077')) {
      return "Airtel";
    } else if (localNumber.startsWith('095') || localNumber.startsWith('075')) {
      return "Zamtel";
    }
    // Unknown/incomplete prefix — keep current selection; fallback to MTN for fresh installs
    return "MTN";
  }

  /// Lowercase id variant for forms that store `mtn`/`airtel`/`zamtel`.
  static String detectNetworkId(String phone) => detectNetwork(phone).toLowerCase();

  /// Returns the network id only when a valid Zambian prefix is confidently detected (≥3 digits).
  /// Returns null for empty/incomplete/unknown prefixes so callers can decide not to auto-switch.
  static String? detectNetworkIdIfKnown(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 3) return null;
    String local = clean;
    if (clean.startsWith('260') && clean.length >= 11) {
      local = '0${clean.substring(3)}';
    } else if (!clean.startsWith('0') && clean.length >= 9) {
      local = '0${clean.substring(clean.length - 9)}';
    }
    if (local.startsWith('096') || local.startsWith('076')) return "mtn";
    if (local.startsWith('097') || local.startsWith('077')) return "airtel";
    if (local.startsWith('095') || local.startsWith('075')) return "zamtel";
    return null;
  }

  static String formatPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'\D'), '');
    if (cleaned.startsWith('0')) cleaned = '260${cleaned.substring(1)}';
    if (cleaned.startsWith('9') && cleaned.length == 9) cleaned = '260$cleaned';
    if (cleaned.length == 9) cleaned = '260$cleaned';
    return cleaned;
  }

  static String? validateZambianPhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Phone number is required";
    }
    final clean = value.replaceAll(RegExp(r'\D'), '');
    String local = clean;
    if (clean.startsWith('260') && clean.length >= 12) {
      local = clean.substring(3);
    }
    if (!local.startsWith('0') && local.length == 9) {
      local = '0$local';
    }
    if (!RegExp(r'^0(9[5-7]|7[5-7])\d{7}$').hasMatch(local)) {
      return "Enter a valid Zambian mobile number";
    }
    return null;
  }

  @override
  State<MomoPhoneInputWidget> createState() => _MomoPhoneInputWidgetState();
}

class _MomoPhoneInputWidgetState extends State<MomoPhoneInputWidget> {
  String? _validationError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPhoneChanged);
  }

  @override
  void didUpdateWidget(covariant MomoPhoneInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPhoneChanged);
      widget.controller.addListener(_onPhoneChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPhoneChanged);
    super.dispose();
  }

  void _onPhoneChanged() {
    final text = widget.controller.text;
    // Auto-detect only when a known Zambian prefix is present — avoids flicking to MTN while user types "09"
    final detectedId = MomoPhoneInputWidget.detectNetworkIdIfKnown(text);
    if (detectedId != null) {
      final detectedName = detectedId == 'mtn' ? 'MTN' : detectedId == 'airtel' ? 'Airtel' : 'Zamtel';
      if (detectedName != widget.selectedNetwork) {
        widget.onNetworkChanged(detectedName);
      }
    }
    final err = MomoPhoneInputWidget.validateZambianPhone(text);
    if (mounted) {
      setState(() => _validationError = text.isEmpty ? null : err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayError = widget.error ?? _validationError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select Network",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: MomoPhoneInputWidget._networks.map((n) {
            final isSelected = widget.selectedNetwork == n['name'];
            final networkColor = n['color'] as Color;
            return GestureDetector(
              onTap: () => widget.onNetworkChanged(n['name'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? networkColor.withValues(alpha: 0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSelected ? networkColor : const Color(0xFFF1F5F9),
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      n['logo'] as String,
                      height: 20,
                      width: 20,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        LucideIcons.signal,
                        color: networkColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      n['name'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? (networkColor == const Color(0xFFFFCC00)
                                ? Colors.black
                                : networkColor)
                            : const Color(0xFF94A3B8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: InputDecoration(
            hintText: "097 123 4567",
            hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Colors.red, width: 1.5),
            ),
            prefixIcon: const Icon(LucideIcons.phone, size: 20),
            prefixText: "+260 ",
            prefixStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        if (displayError != null && displayError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const Icon(LucideIcons.alertCircle, color: Colors.red, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    displayError,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
