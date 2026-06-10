import 'dart:io';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/image_upload_service.dart';
import '../../../services/firebase_service.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final db = FirebaseFirestore.instance;

  final nameController = TextEditingController();
  final priceController = TextEditingController();
  final oldPriceController = TextEditingController();

  String category = "Product";
  File? _imageFile;
  Uint8List? _webImage; // For web support
  bool _isUploading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() => _webImage = bytes);
      } else {
        setState(() => _imageFile = File(pickedFile.path));
      }
    }
  }

  Future<void> addProduct() async {
    if (nameController.text.isEmpty || priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill name and price")),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      String imageUrl = "";

      if (_imageFile != null || _webImage != null) {
        imageUrl = await ImageUploadService.upload(_imageFile, webImage: _webImage);
      }

      await db.collection('products').add({
        'name': nameController.text,
        'price': double.parse(priceController.text),
        'oldPrice': double.parse(oldPriceController.text.isEmpty ? "0" : oldPriceController.text),
        'image': imageUrl,
        'category': category,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      nameController.clear();
      priceController.clear();
      oldPriceController.clear();
      setState(() {
        _imageFile = null;
        _webImage = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Product Added Successfully!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // IMAGE PICKER
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey),
                ),
                child: _imageFile != null
                    ? Image.file(_imageFile!, fit: BoxFit.cover)
                    : (kIsWeb && _webImage != null
                        ? Image.memory(_webImage!, fit: BoxFit.cover)
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, size: 50, color: Colors.grey),
                              Text("Tap to pick image"),
                            ],
                          )),
              ),
            ),
            const SizedBox(height: 16),

            TextField(controller: nameController, decoration: const InputDecoration(labelText: "Product Name")),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: "Price"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: oldPriceController,
              decoration: const InputDecoration(labelText: "Old Price (Optional)"),
              keyboardType: TextInputType.number,
            ),

            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getCategories(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                var cats = snapshot.data!.docs.map((d) => d['name'].toString()).toList();
                if (cats.isEmpty) return const Text("No categories found");
                if (!cats.contains(category)) category = cats[0];

                return DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: "Category"),
                  items: cats.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => category = v!),
                );
              },
            ),

            const SizedBox(height: 24),
            _isUploading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: addProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF32A8C7),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("Add Product", style: TextStyle(color: Colors.white)),
                  ),

            const Divider(height: 40),

            const Text("All Products", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            StreamBuilder(
              stream: db.collection('products').orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snap.hasData) return const Text("No products");

                var docs = snap.data!.docs;

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    var p = docs[i];
                    bool isActive = p['isActive'] ?? true;

                    return Card(
                      child: ListTile(
                        leading: (p['image'] != null && p['image'] != "")
                            ? Image.network(p['image'], width: 50, height: 50, fit: BoxFit.cover)
                            : const Icon(Icons.image),
                        title: Text(p['name'], style: TextStyle(color: isActive ? Colors.black : Colors.grey)),
                        subtitle: Text("৳${p['price']} - ${p['category']} • ${isActive ? 'Active' : 'Inactive'}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isActive,
                              onChanged: (v) => FirebaseService.toggleProductStatus(p.id, v),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => db.collection('products').doc(p.id).delete(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            )
          ],
        ),
      ),
    );
  }
}



