// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('window.receiptOcr.extractText')
external JSPromise<JSString?> _extractReceiptText(
  JSString base64,
  JSString contentType,
  JSString fileName,
);

class ReceiptOcrService {
  const ReceiptOcrService();

  Future<String> extractText({
    required Uint8List bytes,
    required String contentType,
    required String fileName,
  }) async {
    final String encodedBytes = base64Encode(bytes);
    final JSString? rawResult = await _extractReceiptText(
      encodedBytes.toJS,
      contentType.toJS,
      fileName.toJS,
    ).toDart;

    if (rawResult == null) {
      return '';
    }

    return rawResult.toDart;
  }
}
