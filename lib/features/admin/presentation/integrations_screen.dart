import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class Integration {
  final String id;
  final String title;
  final String desc;
  final IconData icon;
  final Color color;
  bool enabled;
  String apiKey;
  String webhookUrl;

  Integration({
    required this.id,
    required this.title,
    required this.desc,
    required this.icon,
    required this.color,
    this.enabled = false,
    this.apiKey = '',
    this.webhookUrl = '',
  });
}

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final List<Integration> _integrations = [
    Integration(
      id: "api", 
      title: "API & Developers", 
      desc: "Integrate custom microservices and database webhooks with Church On App.", 
      icon: LucideIcons.code, 
      color: Colors.blue,
      enabled: true,
      webhookUrl: "https://churchonapp.com/api/webhooks/stewardship",
    ),
    Integration(
      id: "banks", 
      title: "Banks Integration", 
      desc: "Sync transaction statement logs directly with Absa/Barclays and Standard Chartered.", 
      icon: LucideIcons.landmark, 
      color: Colors.green
    ),
    Integration(
      id: "utility", 
      title: "Utility Management", 
      desc: "Pay electric, water, and broadband services automatically from the treasury wallet.", 
      icon: LucideIcons.lightbulb, 
      color: Colors.amber
    ),
    Integration(
      id: "accounting", 
      title: "Accounting Sync", 
      desc: "Integrate real-time cash flow and tithe ledger logs directly with QuickBooks and Xero.", 
      icon: LucideIcons.calculator, 
      color: Colors.indigo
    ),
    Integration(
      id: "parking", 
      title: "Car Parking Sensors", 
      desc: "Sync entry/exit camera feeds to count available slots and reserve VIP worker spots.", 
      icon: LucideIcons.car, 
      color: Colors.blueGrey
    ),
    Integration(
      id: "attendance", 
      title: "RFID Attendance", 
      desc: "Connect physical lobby scanners and NFC tag readers to log service attendance.", 
      icon: LucideIcons.users, 
      color: Colors.teal
    ),
    Integration(
      id: "tithe", 
      title: "Tithe Management APIs", 
      desc: "Direct integration with regional Airtel and MTN Mobile Money merchant wallets.", 
      icon: LucideIcons.fileText, 
      color: Colors.red,
      enabled: true,

    ),
  ];

  void _configureIntegration(Integration item) {
    final keyCtrl = TextEditingController(text: item.apiKey);
    final webhookCtrl = TextEditingController(text: item.webhookUrl);
    bool status = item.enabled;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                        child: Icon(item.icon, color: item.color, size: 30),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const Text("ENTERPRISE MODULE", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(item.desc, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
                  const Divider(height: 40),
                  SwitchListTile(
                    title: const Text("Connection Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: Text(status ? "Active & Syncing" : "Inactive / Suspended", style: TextStyle(color: status ? Colors.green : Colors.grey, fontSize: 12)),
                    value: status,
                    activeThumbColor: item.color,
                    onChanged: (val) {
                      setModalState(() => status = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text("API SECRET KEY / CLIENT ID", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: keyCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: "Enter integration key...",
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      prefixIcon: const Icon(LucideIcons.lock, size: 18),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("WEBHOOK CALLBACK URL", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: webhookCtrl,
                    decoration: InputDecoration(
                      hintText: "https://yourdomain.com/webhooks...",
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      prefixIcon: const Icon(LucideIcons.link, size: 18),
                    ),
                  ),
                  const SizedBox(height: 35),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        item.enabled = status;
                        item.apiKey = keyCtrl.text.trim();
                        item.webhookUrl = webhookCtrl.text.trim();
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("${item.title} configuration updated successfully!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 8,
                    ),
                    child: const Text("SAVE CONFIGURATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(height: 25),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enterprise Integrations", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text("Connect external services & extend capabilities", style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _integrations.length,
        itemBuilder: (context, index) {
          final item = _integrations[index];
          return GestureDetector(
            onTap: () => _configureIntegration(item),
            child: Container(
              margin: const EdgeInsets.only(bottom: 15),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.grey.shade100),
                boxShadow: [BoxShadow(color: item.color.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: item.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Icon(item.icon, color: item.color, size: 28),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.enabled ? Colors.green.withValues(alpha: 0.1) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: item.enabled ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    item.enabled ? "ACTIVE" : "INACTIVE",
                                    style: TextStyle(
                                      color: item.enabled ? Colors.green : Colors.grey,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(item.desc, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.3)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
