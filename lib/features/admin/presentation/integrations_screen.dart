import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> integrations = [
      {"title": "API & Developers", "desc": "Integrate your services with our platform.", "icon": LucideIcons.code, "comingSoon": false, "color": Colors.blue},
      {"title": "Banks Integration", "desc": "Sync financial data securely with banking institutions.", "icon": LucideIcons.landmark, "comingSoon": true, "color": Colors.green},
      {"title": "Utility Management", "desc": "Manage and pay for church utilities directly.", "icon": LucideIcons.lightbulb, "comingSoon": true, "color": Colors.amber},
      {"title": "Accounting Management", "desc": "Integrate with platforms like QuickBooks.", "icon": LucideIcons.calculator, "comingSoon": true, "color": Colors.indigo},
      {"title": "Car Parking Management", "desc": "Manage church parking and reservations.", "icon": LucideIcons.car, "comingSoon": true, "color": Colors.blueGrey},
      {"title": "Attendance Management", "desc": "Track service and event attendance seamlessly.", "icon": LucideIcons.users, "comingSoon": true, "color": Colors.teal},
      {"title": "Visitors Management", "desc": "Streamline the process for welcoming and following up with visitors.", "icon": LucideIcons.userPlus, "comingSoon": true, "color": Colors.pink},
      {"title": "Digital Evangelism", "desc": "Tools for online outreach and tracking engagement.", "icon": LucideIcons.globe, "comingSoon": true, "color": Colors.cyan},
      {"title": "Bible College Management", "desc": "Manage students, courses, and resources for your Bible college.", "icon": LucideIcons.bookOpen, "comingSoon": true, "color": Colors.purple},
      {"title": "Interpreters Management", "desc": "Schedule and manage language interpreters for services.", "icon": LucideIcons.languages, "comingSoon": true, "color": Colors.deepOrange},
      {"title": "Library Management", "desc": "Catalog and manage your church's physical library.", "icon": LucideIcons.library, "comingSoon": true, "color": Colors.brown},
      {"title": "Business Meeting Management", "desc": "Tools for organizing agendas, minutes, and voting.", "icon": LucideIcons.briefcase, "comingSoon": true, "color": Colors.grey.shade700},
      {"title": "Tithe Management", "desc": "Advanced tools for tracking and reporting on tithes.", "icon": LucideIcons.fileText, "comingSoon": true, "color": Colors.teal},
      {"title": "Whitelisting Management", "desc": "Control access and features for specific user groups.", "icon": LucideIcons.shield, "comingSoon": true, "color": Colors.red},
      {"title": "Media & Music Management", "desc": "Organize and schedule your worship and media teams.", "icon": LucideIcons.music, "comingSoon": true, "color": Colors.deepPurple},
      {"title": "Presentation Management", "desc": "Integrate with presentation software for services.", "icon": LucideIcons.monitor, "comingSoon": true, "color": Colors.purpleAccent},
      {"title": "Branding Management", "desc": "Centrally control branding across all app modules.", "icon": LucideIcons.palette, "comingSoon": true, "color": Colors.pinkAccent},
    ];

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
        itemCount: integrations.length,
        itemBuilder: (context, index) {
          final item = integrations[index];
          return _buildIntegrationCard(context, item);
        },
      ),
    );
  }

  Widget _buildIntegrationCard(BuildContext context, Map<String, dynamic> item) {
    bool comingSoon = item['comingSoon'];
    Color color = item['color'];

    return GestureDetector(
      onTap: () {
         if (comingSoon) {
            _showIntegrationDetails(context, item);
         } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Opening ${item['title']} configuration...")));
         }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
              child: Icon(item['icon'], color: color, size: 28),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      if (comingSoon) Icon(LucideIcons.lock, size: 14, color: Colors.grey.shade400)
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(item['desc'], style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.3)),
                  const SizedBox(height: 12),
                  if (comingSoon)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.sparkles, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 5),
                          Text("ENTERPRISE", style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Text("Configure Now", style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(width: 5),
                        Icon(LucideIcons.arrowRight, size: 14, color: Colors.blue.shade700),
                      ],
                    )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showIntegrationDetails(BuildContext context, Map<String, dynamic> item) {
    Color color = item['color'];
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              Container(
                 padding: const EdgeInsets.all(20),
                 decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                 child: Icon(item['icon'], size: 40, color: color),
              ),
              const SizedBox(height: 20),
              Text(item['title'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(item['desc'], style: TextStyle(color: Colors.grey.shade600, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 25),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.amber.shade100)),
                child: Row(
                  children: [
                    Icon(LucideIcons.sparkles, color: Colors.amber.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text("This Enterprise feature is currently in development.", style: TextStyle(color: Colors.amber.shade800, fontSize: 12, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: () {
                   Navigator.pop(context);
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You will be notified!")));
                },
                style: ElevatedButton.styleFrom(
                   backgroundColor: Colors.black,
                   foregroundColor: Colors.white,
                   minimumSize: const Size(double.infinity, 55),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text("Notify Me When Ready", style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }
}

