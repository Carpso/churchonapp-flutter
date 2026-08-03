import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/admin/data/role_onboarding_service.dart';
import 'package:church_on_app/features/marketplace/presentation/bookshop_onboarding_screen.dart';
import 'package:church_on_app/features/marketplace/presentation/post_product_screen.dart';

class RoleOnboardingScreen extends ConsumerStatefulWidget {
  final String role;
  const RoleOnboardingScreen({super.key, required this.role});

  @override
  ConsumerState<RoleOnboardingScreen> createState() => _RoleOnboardingScreenState();
}

class _RoleOnboardingScreenState extends ConsumerState<RoleOnboardingScreen> {
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final status = await ref.read(roleOnboardingServiceProvider).getOnboardingStatus(widget.role);
    if (status != null && !status.isCompleted) {
      setState(() => _currentStep = status.step - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _getSteps();

    return Scaffold(
      appBar: AppBar(
        title: Text('${_roleLabel()} Onboarding'),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _currentStep < steps.length - 1
            ? () => _nextStep(steps.length)
            : null,
        onStepCancel: _currentStep > 0 ? () => setState(() => _currentStep--) : null,
        controlsBuilder: (context, details) {
          final isLastStep = _currentStep >= steps.length - 1;
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                if (!isLastStep)
                  ElevatedButton(
                    onPressed: details.onStepContinue,
                    child: const Text('Continue'),
                  ),
                if (isLastStep)
                  ElevatedButton(
                    onPressed: () => _nextStep(steps.length),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Complete Onboarding'),
                  ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  TextButton(onPressed: details.onStepCancel, child: const Text('Back')),
                ],
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          );
        },
        steps: steps.asMap().entries.map((entry) {
          return Step(
            title: Text(entry.value['title'] as String),
            content: entry.value['content'] as Widget,
            isActive: _currentStep >= entry.key,
            state: entry.key < _currentStep ? StepState.complete : StepState.indexed,
          );
        }).toList(),
      ),
    );
  }

  String _roleLabel() {
    return widget.role.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }

  void _nextStep(int totalSteps) async {
    if (_currentStep >= 2) {
      await ref.read(roleOnboardingServiceProvider).completeOnboarding(widget.role);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Onboarding complete!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
      return;
    }
    await ref.read(roleOnboardingServiceProvider).saveOrUpdate(
      role: widget.role,
      step: _currentStep + 2,
      totalSteps: totalSteps,
    );
    setState(() => _currentStep++);
  }

  List<Map<String, dynamic>> _getSteps() {
    final stepsMap = <String, List<Map<String, dynamic>>>{
      'driver': [
        {
          'title': 'Profile Setup',
          'content': _stepCard(
            icon: Icons.person,
            title: 'Complete Your Profile',
            desc: 'Add a profile photo, phone number, and bio so riders know who you are.',
            action: 'Upload Photo & Fill Bio',
          ),
        },
        {
          'title': 'Vehicle Info',
          'content': _stepCard(
            icon: Icons.directions_car,
            title: 'Add Your Vehicle',
            desc: 'Tell us about your vehicle: make, model, year, color, and license plate.',
            action: 'Add Vehicle Details',
          ),
        },
        {
          'title': 'License & Documents',
          'content': _stepCard(
            icon: Icons.verified,
            title: 'Upload Documents',
            desc: 'Upload your driver\'s license, vehicle registration, and insurance for verification.',
            action: 'Upload Documents',
          ),
        },
      ],
      'bookshop_owner': [
        {
          'title': 'Shop Setup',
          'content': _stepCard(
            icon: Icons.store,
            title: 'Create Your Bookshop',
            desc: 'Set up your bookshop name, description, logo, and contact info.',
            action: 'Set Up Shop',
            onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookshopOnboardingScreen())),
          ),
        },
        {
          'title': 'Add Inventory',
          'content': _stepCard(
            icon: Icons.inventory_2,
            title: 'Add Books & Items',
            desc: 'Upload your catalog with images, prices, and descriptions.',
            action: 'Add Items',
            onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PostProductScreen(initialCategory: 'bookshop'))),
          ),
        },
        {
          'title': 'Payment Setup',
          'content': _stepCard(
            icon: Icons.payment,
            title: 'Payment Details',
            desc: 'Connect your mobile money or bank account for payouts.',
            action: 'Add Payment Info',
          ),
        },
      ],
      'vendor': [
        {
          'title': 'Vendor Profile',
          'content': _stepCard(
            icon: Icons.storefront,
            title: 'Create Your Vendor Profile',
            desc: 'Set your business name, category, description, and location.',
            action: 'Set Up Profile',
          ),
        },
        {
          'title': 'Products & Services',
          'content': _stepCard(
            icon: Icons.sell,
            title: 'List Your Offerings',
            desc: 'Add products or services with images and pricing.',
            action: 'Add Listings',
          ),
        },
        {
          'title': 'Verification',
          'content': _stepCard(
            icon: Icons.verified_user,
            title: 'Get Verified',
            desc: 'Submit business documents for verification to build trust with customers.',
            action: 'Submit Documents',
          ),
        },
      ],
      'pastor': [
        {
          'title': 'Ministry Profile',
          'content': _stepCard(
            icon: Icons.church,
            title: 'Set Up Ministry Profile',
            desc: 'Add your bio, ministry focus, and contact information.',
            action: 'Create Profile',
          ),
        },
        {
          'title': 'Sermons & Content',
          'content': _stepCard(
            icon: Icons.mic,
            title: 'Upload Sermons',
            desc: 'Upload sermon recordings, notes, and schedule upcoming services.',
            action: 'Upload Content',
          ),
        },
        {
          'title': 'Connect With Church',
          'content': _stepCard(
            icon: Icons.people,
            title: 'Link to Your Church',
            desc: 'Connect your pastor profile to your church for seamless ministry management.',
            action: 'Link Church',
          ),
        },
      ],
      'bishop': [
        {
          'title': 'Episcopal Profile',
          'content': _stepCard(
            icon: Icons.account_balance,
            title: 'Bishop Profile Setup',
            desc: 'Set up your episcopal profile with diocese, jurisdiction, and credentials.',
            action: 'Create Profile',
          ),
        },
        {
          'title': 'Diocese Management',
          'content': _stepCard(
            icon: Icons.map,
            title: 'Manage Diocese',
            desc: 'Configure your diocese, oversee churches, and assign pastors.',
            action: 'Configure Diocese',
          ),
        },
        {
          'title': 'Oversight Tools',
          'content': _stepCard(
            icon: LucideIcons.shield,
            title: 'Setup Oversight',
            desc: 'Get access to diocese-wide analytics, reports, and church management tools.',
            action: 'Enable Tools',
          ),
        },
      ],
    };

    return stepsMap[widget.role] ?? [
      {
        'title': 'Welcome',
        'content': _stepCard(
          icon: Icons.waving_hand,
          title: 'Welcome to ${_roleLabel()}',
          desc: 'Complete the onboarding steps to get the most out of your ${_roleLabel()} experience.',
          action: 'Get Started',
        ),
      },
    ];
  }

  Widget _stepCard({required IconData icon, required String title, required String desc, required String action, VoidCallback? onAction}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(desc, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction ?? () {}, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
