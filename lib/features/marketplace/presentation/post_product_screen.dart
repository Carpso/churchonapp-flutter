import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/marketplace_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/profile_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/r2_service.dart';
import 'package:universal_io/io.dart';

class PostProductScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  const PostProductScreen({super.key, this.initialCategory});

  @override
  ConsumerState<PostProductScreen> createState() => _PostProductScreenState();
}

class _PostProductScreenState extends ConsumerState<PostProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  String _selectedCategory = "apparel";
  String _selectedType = "general";
  bool _isSubmitting = false;
  File? _imageFile;
  // ignore: unused_field
  String? _uploadedImageUrl;

  final List<String> _categories = ["bookshop", "apparel", "worship", "tickets", "media", "electronics", "home"];

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null && _categories.contains(widget.initialCategory)) {
      _selectedCategory = widget.initialCategory!;
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080, maxHeight: 1080);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;
    final r2Service = ref.read(r2ServiceProvider);
    final fileName = "product_${DateTime.now().millisecondsSinceEpoch}.jpg";
    return await r2Service.uploadFile(_imageFile!, "products/$fileName");
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    
    final user = ref.read(authProvider).user;
    final profile = ref.read(profileProvider).value;

    if (user == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please login to post")));
       setState(() => _isSubmitting = false);
       return;
    }

    try {
      String? imageUrl = _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim();
      
      if (_imageFile != null) {
        imageUrl = await _uploadImage();
        if (imageUrl == null) {
          throw Exception("Failed to upload image to R2");
        }
      }

      final productData = {
        'name': _nameCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
        'description': _descCtrl.text.trim(),
        'image': imageUrl,
        'category': _selectedCategory,
        'market_type': _selectedType,
        'vendor_id': user.id,
        'vendor_name': profile?.name ?? "Citizen",
      };

      await ref.read(marketplaceServiceProvider).postProduct(productData);
      ref.invalidate(productsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Item posted successfully! It's now live."), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("List an Item", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("Product Details", LucideIcons.package),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _nameCtrl,
                label: "Item Name",
                hint: "e.g. Vintage Study Bible",
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim().length < 2) return 'Min 2 characters';
                  return null;
                },
              ),
              const SizedBox(height: 15),
              _buildPriceField(),
              const SizedBox(height: 15),
              _buildDropdownField(
                label: "Category",
                value: _selectedCategory,
                items: _categories,
                onChanged: (v) => setState(() => _selectedCategory = v!),
              ),
              const SizedBox(height: 25),
              _buildSectionHeader("Market Settings", LucideIcons.settings),
              const SizedBox(height: 15),
              _buildTypeSelector(),
              const SizedBox(height: 25),
              _buildSectionHeader("Description & Media", LucideIcons.image),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _descCtrl,
                label: "Description",
                hint: "Tell us more about this item...",
                maxLines: 4,
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 15),
              const Text("Product Photo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                  ),
                  child: _imageFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          // Downsample at decode time — camera photos are 12MP+;
                          // decoding full size is what Google Play flags as
                          // "improve your app's performance with bitmap downsampling".
                          child: Image.file(
                            _imageFile!,
                            fit: BoxFit.cover,
                            cacheWidth: (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.camera, color: Theme.of(context).primaryColor, size: 30),
                            const SizedBox(height: 10),
                            const Text("Tap to select photo", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 15),
              _buildTextField(
                controller: _imageCtrl,
                label: "OR Image URL",
                hint: "https://...",
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  minimumSize: const Size(double.infinity, 65),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: _isSubmitting 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("PUBLISH LISTING", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 20),
              const Center(child: Text("All listings undergo automated safety checks.", style: TextStyle(color: Colors.grey, fontSize: 10))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).primaryColor),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Price (Church Coins)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _priceCtrl,
          keyboardType: TextInputType.number,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            final amount = double.tryParse(v.trim());
            if (amount == null || amount <= 0) return 'Enter a valid positive price';
            return null;
          },
          decoration: InputDecoration(
            hintText: "0.00",
            prefixText: "K ",
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: [
        _buildTypeCard("general", "Store", LucideIcons.shoppingBag),
        const SizedBox(width: 15),
        _buildTypeCard("tuesday", "Tue Mkt", LucideIcons.calendar),
        const SizedBox(width: 15),
        _buildTypeCard("saturday", "Sat Mkt", LucideIcons.calendarRange),
      ],
    );
  }

  Widget _buildTypeCard(String id, String label, IconData icon) {
    bool isSelected = _selectedType == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: isSelected ? Theme.of(context).primaryColor : Colors.white),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 20),
              const SizedBox(height: 5),
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

