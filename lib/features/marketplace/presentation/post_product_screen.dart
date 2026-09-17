import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/marketplace_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/tenant_service.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/r2_service.dart';
import '../../../core/widgets/kael_explain_sheet.dart';
import '../../../core/config/fee_config.dart';
import '../../admin/data/writer_approval_service.dart';
import 'package:universal_io/io.dart';

class PostProductScreen extends ConsumerStatefulWidget {
final String? initialCategory;

/// When set, the screen edits this existing listing instead of creating one.
final Map<String, dynamic>? product;

const PostProductScreen({super.key, this.initialCategory, this.product});

  @override
  ConsumerState<PostProductScreen> createState() => _PostProductScreenState();
}

class _PostProductScreenState extends ConsumerState<PostProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _imageCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _downloadUrlCtrl = TextEditingController();
  final _isbnCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _pagesCtrl = TextEditingController();
  String _selectedCategory = "apparel";
  String _selectedType = "general";
  bool _isSubmitting = false;
  // Book format (only meaningful when category == 'book'). Digital books carry
  // a download_url; physical books carry stock. No extra column is invented.
  bool _isDigitalBook = false;
  File? _imageFile;
  // ignore: unused_field
  String? _uploadedImageUrl;

  final List<String> _categories = ["book", "bookshop", "apparel", "worship", "tickets", "media", "electronics", "home"];

  bool get _isBook => _selectedCategory == "book";

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null && _categories.contains(widget.initialCategory)) {
      _selectedCategory = widget.initialCategory!;
    }
    final p = widget.product;
    if (p != null) {
      _nameCtrl.text = p['name']?.toString() ?? '';
      final price = (p['price'] as num?);
      _priceCtrl.text = price == null ? '' : price.toStringAsFixed(price is int ? 0 : 2);
      _descCtrl.text = p['description']?.toString() ?? '';
      _imageCtrl.text = p['image']?.toString() ?? '';
      final cat = p['category']?.toString();
      if (cat != null && _categories.contains(cat)) _selectedCategory = cat;
      final type = p['market_type']?.toString();
      if (type != null && type.isNotEmpty) _selectedType = type;
      _stockCtrl.text = p['stock']?.toString() ?? '';
      _downloadUrlCtrl.text = p['download_url']?.toString() ?? '';
      _isbnCtrl.text = p['isbn']?.toString() ?? '';
      _authorCtrl.text = p['author']?.toString() ?? '';
      _pagesCtrl.text = p['pages']?.toString() ?? '';
      _isDigitalBook = cat == 'book' && _downloadUrlCtrl.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _imageCtrl.dispose();
    _stockCtrl.dispose();
    _downloadUrlCtrl.dispose();
    _isbnCtrl.dispose();
    _authorCtrl.dispose();
    _pagesCtrl.dispose();
    super.dispose();
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

      final rawStock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
      // A digital/eBook has no stock; a physical book is stock-counted.
      final stock = _isBook && _isDigitalBook ? 0 : rawStock;
      final productData = {
        'name': _nameCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
        'description': _descCtrl.text.trim(),
        'image': imageUrl,
        'category': _selectedCategory,
        'market_type': _selectedType,
        'vendor_id': user.id,
        'vendor_name': profile?.name ?? "Citizen",
        'stock': stock < 0 ? 0 : stock,
        'download_url': _downloadUrlCtrl.text.trim().isEmpty ? null : _downloadUrlCtrl.text.trim(),
        'condition': 'new',
        'is_curated': false,
        if (_isBook) ...{
          'author': _authorCtrl.text.trim().isEmpty ? null : _authorCtrl.text.trim(),
          'isbn': _isbnCtrl.text.trim().isEmpty ? null : _isbnCtrl.text.trim(),
          'pages': int.tryParse(_pagesCtrl.text.trim()),
        },
      };

      if (_isEditing) {
        await ref.read(marketplaceServiceProvider).updateProduct(
          widget.product!['id'].toString(),
          productData,
        );
      } else {
        await ref.read(marketplaceServiceProvider).postProduct(
          productData,
          tenantId: ref.read(currentTenantProvider)?.id,
        );
      }
      ref.invalidate(productsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? "Item updated successfully!"
                : "Item posted successfully! It's now live."),
            backgroundColor: Colors.green,
          ),
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
    final isVerifiedWriter = ref.watch(isVerifiedWriterProvider).value ?? false;
    final bookFeePercent =
        (ref.watch(feeConfigProvider).value ?? FeeConfig.defaults)
            .marketplaceBookFeePercent;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _isBook ? (_isEditing ? "Edit Book" : "List a Book") : (_isEditing ? "Edit Item" : "List an Item"),
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isVerifiedWriter) ...[
                _buildVerifiedWriterBadge(),
                const SizedBox(height: 20),
              ],
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
              if (_isBook) ...[
                const SizedBox(height: 25),
                _buildSectionHeader("Book Details", LucideIcons.bookOpen),
                const SizedBox(height: 15),
                _buildBookFormatSelector(),
                const SizedBox(height: 15),
                _buildTextField(
                  controller: _authorCtrl,
                  label: "Author (optional)",
                  hint: "e.g. David K. Bernard",
                ),
                const SizedBox(height: 15),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _isbnCtrl,
                        label: "ISBN (optional)",
                        hint: "978-...",
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildTextField(
                        controller: _pagesCtrl,
                        label: "Pages (optional)",
                        hint: "e.g. 240",
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = int.tryParse(v.trim());
                          if (n == null || n <= 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.info, size: 18, color: Colors.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "COA marketplace fee: ${(bookFeePercent * 100).toStringAsFixed(1)}% per sale — applied through the same marketplace checkout as every other item.",
                          style: TextStyle(color: Colors.orange.shade900, fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 15),
              _buildSectionHeader("Inventory", LucideIcons.package),
              const SizedBox(height: 15),
              if (!(_isBook && _isDigitalBook))
                _buildTextField(
                  controller: _stockCtrl,
                  label: "Stock Quantity",
                  hint: "e.g. 10 (0 = out of stock)",
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 0) return 'Enter a valid number';
                    return null;
                  },
                ),
              if (!(_isBook && _isDigitalBook)) const SizedBox(height: 15),
              _buildTextField(
                controller: _downloadUrlCtrl,
                label: _isBook && _isDigitalBook
                    ? "eBook Download URL"
                    : "Digital Download URL (optional)",
                hint: _isBook && _isDigitalBook
                    ? "https://... link buyers receive"
                    : "https://... for e-books",
                validator: (_isBook && _isDigitalBook)
                    ? (v) => (v == null || v.trim().isEmpty)
                        ? 'A download link is required for an eBook'
                        : null
                    : null,
              ),
              const SizedBox(height: 25),
              _buildSectionHeader("Market Settings", LucideIcons.settings),
              const SizedBox(height: 15),
              _buildTypeSelector(),
              const SizedBox(height: 25),
              _buildSectionHeader("Description & Media", LucideIcons.image),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    final name = _nameCtrl.text.trim().isEmpty
                        ? 'this item'
                        : '"${_nameCtrl.text.trim()}"';
                    showKaelExplainSheet(
                      context,
                      action: 'summary',
                      title: 'Kael suggests a description',
                      prompt:
                          'Write a short, warm, persuasive marketplace listing description (3-4 sentences) for a church marketplace item named $name in the $_selectedCategory category. '
                          'Keep it honest, friendly and clear, and end with a one-line call to action.',
                    );
                  },
                  icon: const Icon(LucideIcons.sparkles, size: 16, color: Colors.amber),
                  label: const Text('Ask Kael to write it', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
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
              const Center(child: Text("All listings undergo automated safety checks.", style: TextStyle(color: Colors.grey, fontSize: 11))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerifiedWriterBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF9333EA)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.badgeCheck, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text(
            "VERIFIED WRITER",
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildBookFormatSelector() {
    return Row(
      children: [
        _buildBookFormatCard(false, "Physical Book", LucideIcons.book),
        const SizedBox(width: 15),
        _buildBookFormatCard(true, "Digital / eBook", LucideIcons.bookOpen),
      ],
    );
  }

  Widget _buildBookFormatCard(bool digital, String label, IconData icon) {
    final isSelected = _isDigitalBook == digital;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isDigitalBook = digital),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: isSelected ? Theme.of(context).primaryColor : Colors.white),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 20),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
              ),
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
        const Text("Price (Kwacha)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
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
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

