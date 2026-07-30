import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/providers/profile_provider.dart';
import '../../../../core/services/tenant_service.dart';
import '../../../../core/widgets/premium_toast.dart';
import '../../../finance/presentation/lipila_payment_gateway.dart';
import '../data/bible_quiz_service.dart';

class ChurchCompetitionScreen extends ConsumerStatefulWidget {
  const ChurchCompetitionScreen({super.key});

  @override
  ConsumerState<ChurchCompetitionScreen> createState() => _ChurchCompetitionScreenState();
}

class _ChurchCompetitionScreenState extends ConsumerState<ChurchCompetitionScreen> {
  final _titleCtrl = TextEditingController();
  final _feeCtrl = TextEditingController(text: "0");
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 14, minute: 0);
  int _questionCount = 10;
  String _difficulty = 'Mixed';
  bool _isPaid = false;
  bool _isCreating = false;
  bool _isLiveChampionship = false;
  String? _createdPin;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _createCompetition() async {
    if (_titleCtrl.text.trim().isEmpty) {
      PremiumToast.showWarning(context, "Please enter a competition title");
      return;
    }

    if (_isLiveChampionship) {
      final profile = ref.read(profileProvider).value;
      if (profile == null || !profile.isEmployee) {
        PremiumToast.showError(context, "Only the COA Team can host Live Championship Seasons");
        return;
      }
    }

    setState(() => _isCreating = true);

    final profile = ref.read(profileProvider).value;
    final activeTenant = ref.read(currentTenantProvider);
    final tenantId = profile?.tenantId ?? activeTenant?.id;
    if (tenantId == null || activeTenant == null) {
      PremiumToast.showError(context, "You must belong to a church to host competitions");
      setState(() => _isCreating = false);
      return;
    }

    final combinedDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final result = await ref.read(bibleQuizServiceProvider).createChurchCompetition(
      tenantId: tenantId,
      title: _titleCtrl.text.trim(),
      date: combinedDate,
      questionCount: _questionCount,
      difficulty: _difficulty == 'Mixed' ? null : _difficulty,
      entryFee: _isPaid ? (double.tryParse(_feeCtrl.text) ?? 0) : 0,
    );

    setState(() => _isCreating = false);

    if (result != null && result.containsKey('id')) {
      _createdPin = result['pin_code'];

      if (mounted) {
        PremiumToast.showSuccess(context, "Competition created! Share the PIN with participants.", title: "Success");
        setState(() {});
      }
    } else {
      if (mounted) {
        PremiumToast.showError(context, "Failed to create competition. Please ensure you have a church selected.");
      }
    }
  }

  void _shareCompetition() {
    if (_createdPin == null) return;
    SharePlus.instance.share(ShareParams(
      text: "Join my Church Bible Quiz Competition!\n\nTitle: ${_titleCtrl.text}\nDate: ${DateFormat.yMMMd().add_jm().format(_selectedDate)}\nPIN: $_createdPin\n\nDownload Church On App to participate!",
      subject: "Bible Quiz Competition Invitation",
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text("Host Competition", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.trophy, color: Colors.white, size: 32),
                  const SizedBox(height: 10),
                  const Text("Church Bible Quizzing", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const Text("Set up a competition for your church members", style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // Live Championship toggle
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.crown, color: Colors.amber, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Live Championship Season", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("COA Team only • Hard & Very Hard", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isLiveChampionship,
                    onChanged: (v) => setState(() {
                      _isLiveChampionship = v;
                      if (v) {
                        _difficulty = 'Hard';
                      } else {
                        _difficulty = 'Mixed';
                      }
                    }),
                    activeThumbColor: Colors.amber,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Title
            _buildLabel("Competition Title"),
            const SizedBox(height: 8),
            _buildField(_titleCtrl, "e.g. Book of Acts Challenge", LucideIcons.type),
            const SizedBox(height: 20),

            // Date & Time
            _buildLabel("Date & Time"),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.calendar, color: Colors.white54, size: 16),
                          const SizedBox(width: 8),
                          Text(DateFormat.yMMMd().format(_selectedDate), style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null) setState(() => _selectedTime = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.clock, color: Colors.white54, size: 16),
                          const SizedBox(width: 8),
                          Text(_selectedTime.format(context), style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Question Count
            _buildLabel("Number of Questions"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _questionCount,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2D2D3F),
                  items: [5, 10, 15, 20, 25, 30].map((c) => DropdownMenuItem(value: c, child: Text("$c questions", style: const TextStyle(color: Colors.white)))).toList(),
                  onChanged: (v) => setState(() => _questionCount = v ?? 10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Difficulty
            _buildLabel("Difficulty"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _difficulty,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2D2D3F),
                  items: (_isLiveChampionship
                      ? ["Hard", "Very Hard"]
                      : ["Mixed", "Easy", "Medium", "Hard"]
                  ).map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(color: Colors.white)))).toList(),
                  onChanged: (v) => setState(() => _difficulty = v ?? "Mixed"),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Entry Fee
            _buildLabel("Entry Fee"),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: Text("Free", style: TextStyle(color: !_isPaid ? Colors.greenAccent : Colors.white70, fontWeight: FontWeight.bold)),
                  selected: !_isPaid,
                  selectedColor: Colors.greenAccent.withAlpha(45),
                  backgroundColor: Colors.white.withAlpha(10),
                  checkmarkColor: Colors.greenAccent,
                  side: BorderSide(color: !_isPaid ? Colors.greenAccent : Colors.white10),
                  onSelected: (v) => setState(() => _isPaid = false),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: Text("Paid", style: TextStyle(color: _isPaid ? Colors.orangeAccent : Colors.white70, fontWeight: FontWeight.bold)),
                  selected: _isPaid,
                  selectedColor: Colors.orangeAccent.withAlpha(45),
                  backgroundColor: Colors.white.withAlpha(10),
                  checkmarkColor: Colors.orangeAccent,
                  side: BorderSide(color: _isPaid ? Colors.orangeAccent : Colors.white10),
                  onSelected: (v) => setState(() => _isPaid = true),
                ),
                if (_isPaid) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _feeCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        prefixText: "K ",
                        prefixStyle: const TextStyle(color: Colors.white54),
                        hintText: "0.00",
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: Colors.white.withAlpha(10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 35),

            // Create Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCreating ? null : _createCompetition,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                icon: _isCreating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.sparkles),
                label: Text(_isCreating ? "CREATING..." : "CREATE COMPETITION", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ),

            // Created Competition Details
            if (_createdPin != null) ...[
              const SizedBox(height: 30),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withAlpha(15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withAlpha(50)),
                ),
                child: Column(
                  children: [
                    const Icon(LucideIcons.checkCircle, color: Colors.greenAccent, size: 40),
                    const SizedBox(height: 10),
                    const Text("Competition Created!", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(_titleCtrl.text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 20),

                    // PIN Display
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text("Share this PIN with participants", style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(height: 6),
                          Text(_createdPin!, style: const TextStyle(color: Colors.greenAccent, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 8)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: _createdPin!,
                        version: QrVersions.auto,
                        size: 160,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Share Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _shareCompetition,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(LucideIcons.share2, size: 18),
                        label: const Text("SHARE COMPETITION", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Entry Fee Payment via Lipila
                    if (_isPaid && (double.tryParse(_feeCtrl.text) ?? 0) > 0) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => LipilaPaymentGateway(
                                amount: double.tryParse(_feeCtrl.text) ?? 0.0,
                                description: "Entry Fee: ${_titleCtrl.text}",
                                category: "event",
                                onComplete: (success, txId) {
                                  Navigator.pop(context);
                                  if (success) {
                                    PremiumToast.showSuccess(context, "Payment of K${_feeCtrl.text} received!", title: "Entry Fee Paid");
                                  }
                                },
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(color: Colors.orangeAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(LucideIcons.banknote, size: 18),
                          label: Text("COLLECT ENTRY FEES (K${_feeCtrl.text}) VIA LIPILA", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5));
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled: true,
        fillColor: Colors.white.withAlpha(10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
