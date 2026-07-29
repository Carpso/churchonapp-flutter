import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/job_model.dart';
import '../data/jobs_service.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';

class PostJobScreen extends ConsumerStatefulWidget {
  final Job? editJob;
  const PostJobScreen({super.key, this.editJob});

  @override
  ConsumerState<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends ConsumerState<PostJobScreen> {
  final _titleCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  String _jobType = "Full-Time";

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty || _companyCtrl.text.isEmpty) return;

    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    final job = Job(
      id: '', // Supabase generates this
      title: _titleCtrl.text,
      company: _companyCtrl.text,
      location: _locationCtrl.text,
      type: _jobType,
      description: _descCtrl.text,
      salary: _salaryCtrl.text,
      contact: _contactCtrl.text,
      employerId: userId,
      createdAt: DateTime.now(),
    );

    await ref.read(jobsServiceProvider).postJob(job);
    if (mounted) context.pop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Job Opportunity Published!"), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Post Opportunity", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _buildTextField("Job Title", _titleCtrl, LucideIcons.type),
            const SizedBox(height: 15),
            _buildTextField("Company / Ministry Name", _companyCtrl, LucideIcons.building),
            const SizedBox(height: 15),
            _buildTextField("Location (City, Area)", _locationCtrl, LucideIcons.mapPin),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _jobType,
                  isExpanded: true,
                  items: ["Full-Time", "Part-Time", "Contract", "Volunteer"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => _jobType = v!),
                ),
              ),
            ),
            const SizedBox(height: 15),
            _buildTextField("Remuneration / Salary (Optional)", _salaryCtrl, LucideIcons.banknote),
            const SizedBox(height: 15),
            _buildTextField("Contact Email / Phone", _contactCtrl, LucideIcons.mail),
            const SizedBox(height: 15),
            TextField(
              controller: _descCtrl,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: "Full Job Description",
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: Text("POST OPPORTUNITY", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String hint, TextEditingController controller, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}

