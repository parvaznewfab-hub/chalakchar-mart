import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ImageUploadService {
  static Future<String> upload(
      File? file, {
        Uint8List? webImage,
        String folder = 'products',
        String? fileName,
      }) async {
    final safeFileName = fileName ?? '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref = FirebaseStorage.instance.ref().child('$folder/$safeFileName');

    final metadata = SettableMetadata(contentType: 'image/jpeg');

    if (kIsWeb && webImage != null) {
      await ref.putData(webImage, metadata);
    } else if (file != null) {
      await ref.putFile(file, metadata);
    } else {
      return '';
    }

    return ref.getDownloadURL();
  }
}