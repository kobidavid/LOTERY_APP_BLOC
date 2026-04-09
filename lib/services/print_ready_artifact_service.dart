import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';

import '../features/lottery_form/lottery_ticket_preview.dart';
import '../features/lottery_form/lotto_form_anchor_layout.dart';
import '../models/lottery_form.dart';

class PrintReadyArtifactResult {
  const PrintReadyArtifactResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.generatedAt,
  });

  final String downloadUrl;
  final String storagePath;
  final DateTime generatedAt;
}

class PrintReadyArtifactService {
  PrintReadyArtifactService({
    FirebaseStorage? storage,
  }) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<PrintReadyArtifactResult> generateForSubmittedForm({
    required LotteryForm form,
  }) async {
    final String? formId = form.formId;
    if (formId == null || formId.isEmpty) {
      throw StateError('Submitted form is missing formId.');
    }

    final ByteData imageData =
        await rootBundle.load(LottoFormAnchorLayout.backgroundAssetPath);
    final ui.Image background = await _decodeImage(
      imageData.buffer.asUint8List(),
    );

    final int width = LottoFormAnchorLayout.templatePixelSize.width.toInt();
    final int height = LottoFormAnchorLayout.templatePixelSize.height.toInt();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final ui.Size size = ui.Size(width.toDouble(), height.toDouble());

    canvas.drawImageRect(
      background,
      ui.Rect.fromLTWH(
        0,
        0,
        background.width.toDouble(),
        background.height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, size.width, size.height),
      ui.Paint(),
    );

    LotteryTicketRenderer.paint(
      canvas: canvas,
      size: size,
      tables: form.tables,
      showDebug: false,
    );

    final ui.Image image = await recorder.endRecording().toImage(width, height);
    final ByteData? pngData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (pngData == null) {
      throw StateError('Failed to encode print-ready image.');
    }

    final DateTime generatedAt = DateTime.now();
    final String storagePath = 'print_ready/${form.userId}/$formId.png';
    final Reference ref = _storage.ref(storagePath);
    await ref.putData(
      pngData.buffer.asUint8List(),
      SettableMetadata(
        contentType: 'image/png',
        customMetadata: <String, String>{
          'formId': formId,
          'userId': form.userId,
          'source': 'submitted_form',
        },
      ),
    );
    final String downloadUrl = await ref.getDownloadURL();

    return PrintReadyArtifactResult(
      downloadUrl: downloadUrl,
      storagePath: storagePath,
      generatedAt: generatedAt,
    );
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    final ui.ImageDescriptor descriptor =
        await ui.ImageDescriptor.encoded(buffer);
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }
}
