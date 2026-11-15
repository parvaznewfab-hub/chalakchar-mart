/// True for electronics / parts categories (Mobile Parts, Motherboard,
/// Computer Accessories, Storage Devices, ...). Their products have no use
/// for the medicine-era fields Generic, Strength and Type (admin E4).
bool isElectronicsCategory(String? categoryName) {
  final name = (categoryName ?? '').toLowerCase();
  if (name.isEmpty) return false;
  return RegExp(
    r'mobile|phone|computer|laptop|motherboard|storage|electronic|gadget|parts|accessor|display|charger|cable|watch',
  ).hasMatch(name);
}
