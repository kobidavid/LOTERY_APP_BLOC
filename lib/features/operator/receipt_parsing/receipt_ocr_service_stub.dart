import 'dart:typed_data';

class ReceiptOcrService {
  const ReceiptOcrService();

  Future<String> extractText({
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) async {
    return '';
  }
}
