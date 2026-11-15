import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Storage image names are unique (timestamped) and never overwritten, so
/// browsers and CDNs may keep them for a year instead of re-downloading them
/// on every visit (the Storage default is "private, max-age=0").
const String kImageCacheControl = 'public, max-age=31536000, immutable';

class ImageUploadService {
  static Future<String> upload(
      File? file, {
        Uint8List? webImage,
        String folder = 'products',
        String? fileName,
      }) async {
    final safeFileName = fileName ?? '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref = FirebaseStorage.instance.ref().child('$folder/$safeFileName');

    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: kImageCacheControl,
    );

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