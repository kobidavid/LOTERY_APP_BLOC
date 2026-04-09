import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../models/receipt_parsed_table.dart';
import 'receipt_ocr_service.dart';

class ReceiptParseResult {
  const ReceiptParseResult({
    required this.status,
    required this.message,
    required this.parsedTables,
    required this.lotteryIdHint,
    required this.tableCountHint,
    required this.expectedRowCount,
    required this.ticketTypeHint,
    required this.fingerprintSource,
    required this.fingerprint,
    required this.sourceTextLength,
  });

  final ReceiptParsingStatus status;
  final String message;
  final List<ReceiptParsedTable> parsedTables;
  final int? lotteryIdHint;
  final int? tableCountHint;
  final int? expectedRowCount;
  final String? ticketTypeHint;
  final String? fingerprintSource;
  final String? fingerprint;
  final int sourceTextLength;
}

enum ReceiptParsingStatus {
  pending('pending'),
  parsed('parsed'),
  partial('partial'),
  failed('failed');

  const ReceiptParsingStatus(this.value);

  final String value;
}

class ReceiptParser {
  const ReceiptParser({
    ReceiptOcrService? ocrService,
  }) : _ocrService = ocrService ?? const ReceiptOcrService();

  static const String ticketTypeRegular = 'regular';
  static const String ticketTypeDouble = 'double';
  static const String ticketTypeUnknown = 'unknown';
  static const int maxPlausibleParsedRows = 20;

  final ReceiptOcrService _ocrService;

  Future<ReceiptParseResult> parse({
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final bool isPdf = _isPdfContentType(contentType, fileName);
    final String extractedText = _extractText(bytes);
    final String normalizedEmbeddedText =
        _normalizeExtractedText(extractedText);

    if (isPdf) {
      final String ocrText = _normalizeExtractedText(
        await _ocrService.extractText(
          bytes: bytes,
          contentType: contentType,
          fileName: fileName,
        ),
      );
      final ReceiptParseResult ocrResult = _parseNormalizedText(
        ocrText,
        messagePrefix: 'Parsed OCR receipt text.',
      );

      if (!_looksLikeReadableEmbeddedPdfText(normalizedEmbeddedText)) {
        return ocrResult.sourceTextLength == 0
            ? const ReceiptParseResult(
                status: ReceiptParsingStatus.failed,
                message:
                    'No readable OCR text could be extracted from the scanned PDF.',
                parsedTables: <ReceiptParsedTable>[],
                lotteryIdHint: null,
                tableCountHint: null,
                expectedRowCount: null,
                ticketTypeHint: null,
                fingerprintSource: null,
                fingerprint: null,
                sourceTextLength: 0,
              )
            : ocrResult;
      }

      final ReceiptParseResult embeddedResult = _parseNormalizedText(
        normalizedEmbeddedText,
        messagePrefix: 'Parsed embedded receipt text.',
      );
      return _pickBetterResult(
        embeddedResult,
        ocrResult,
        preferFallback: true,
      );
    }

    final ReceiptParseResult primaryResult = _parseNormalizedText(
      normalizedEmbeddedText,
      messagePrefix: 'Parsed embedded receipt text.',
    );

    final bool shouldFallbackToOcr = primaryResult.sourceTextLength == 0 ||
        primaryResult.status != ReceiptParsingStatus.parsed;
    if (!shouldFallbackToOcr) {
      return primaryResult;
    }

    final String ocrText = _normalizeExtractedText(
      await _ocrService.extractText(
        bytes: bytes,
        contentType: contentType,
        fileName: fileName,
      ),
    );

    if (ocrText.isEmpty) {
      if (primaryResult.sourceTextLength == 0) {
        return const ReceiptParseResult(
          status: ReceiptParsingStatus.failed,
          message:
              'No readable text could be extracted from the receipt, including OCR fallback.',
          parsedTables: <ReceiptParsedTable>[],
          lotteryIdHint: null,
          tableCountHint: null,
          expectedRowCount: null,
          ticketTypeHint: null,
          fingerprintSource: null,
          fingerprint: null,
          sourceTextLength: 0,
        );
      }
      return primaryResult;
    }

    final ReceiptParseResult ocrResult = _parseNormalizedText(
      ocrText,
      messagePrefix: 'Parsed OCR receipt text.',
    );

    return _pickBetterResult(primaryResult, ocrResult);
  }

  static String? buildReceiptFingerprintSource({
    required int? lotteryId,
    required List<ReceiptParsedTable> tables,
  }) {
    if (lotteryId == null ||
        tables.isEmpty ||
        tables.any((table) => !table.isComplete)) {
      return null;
    }

    final String normalizedLotteryId = lotteryId.toString().padLeft(4, '0');
    final String tableCount = tables.length.toString().padLeft(2, '0');
    final String tableRows =
        tables.map((table) => table.canonicalRow).join('-');
    return '$normalizedLotteryId-$tableCount-$tableRows';
  }

  ReceiptParseResult _pickBetterResult(
      ReceiptParseResult primaryResult, ReceiptParseResult fallbackResult,
      {bool preferFallback = false}) {
    final int primaryScore = _resultQualityScore(primaryResult);
    final int fallbackScore = _resultQualityScore(fallbackResult);
    if (preferFallback) {
      if (!_isClearlyNoisyParse(fallbackResult) &&
          (fallbackScore >= primaryScore - 40 ||
              _isClearlyNoisyParse(primaryResult))) {
        return fallbackResult;
      }
    }
    if (fallbackScore > primaryScore) {
      return fallbackResult;
    }
    return primaryResult;
  }

  int _resultQualityScore(ReceiptParseResult result) {
    if (_isClearlyNoisyParse(result)) {
      return -1000;
    }

    int score = 0;
    switch (result.status) {
      case ReceiptParsingStatus.parsed:
        score += 300;
        break;
      case ReceiptParsingStatus.partial:
        score += 150;
        break;
      case ReceiptParsingStatus.failed:
      case ReceiptParsingStatus.pending:
        break;
    }

    score += result.parsedTables.length * 20;
    if (result.lotteryIdHint != null) {
      score += 25;
    }
    if (result.fingerprint != null) {
      score += 40;
    }
    if (result.expectedRowCount != null &&
        result.parsedTables.length == result.expectedRowCount) {
      score += 50;
    }
    score += result.sourceTextLength > 0 ? 5 : 0;
    return score;
  }

  ReceiptParseResult _parseNormalizedText(
    String normalizedText, {
    required String messagePrefix,
  }) {
    if (normalizedText.isEmpty) {
      return const ReceiptParseResult(
        status: ReceiptParsingStatus.failed,
        message: 'No readable text could be extracted from the receipt.',
        parsedTables: <ReceiptParsedTable>[],
        lotteryIdHint: null,
        tableCountHint: null,
        expectedRowCount: null,
        ticketTypeHint: null,
        fingerprintSource: null,
        fingerprint: null,
        sourceTextLength: 0,
      );
    }

    final _TableExtractionResult tableExtraction =
        _extractTables(normalizedText);
    final int? lotteryIdHint = _extractLotteryId(normalizedText);
    final String ticketTypeHint = _extractTicketType(normalizedText);
    final int? tableCountHint = tableExtraction.tables.isNotEmpty
        ? tableExtraction.tables.length
        : null;
    final String? fingerprintSource = buildReceiptFingerprintSource(
      lotteryId: lotteryIdHint,
      tables: tableExtraction.tables,
    );
    final String? fingerprint = fingerprintSource == null
        ? null
        : sha256.convert(utf8.encode(fingerprintSource)).toString();

    final bool hasUsefulHints = lotteryIdHint != null ||
        tableExtraction.partialRowsFound ||
        tableExtraction.numberHintsFound;
    final bool rowCountMismatch = tableExtraction.expectedRowCount != null &&
        tableExtraction.tables.length != tableExtraction.expectedRowCount;
    final bool rowCountOverflow = tableExtraction.expectedRowCount != null &&
        tableExtraction.tables.length > tableExtraction.expectedRowCount!;
    final bool missingFingerprintForStructuredParse =
        tableExtraction.tables.isNotEmpty && fingerprint == null;

    final ReceiptParsingStatus status;
    if (tableExtraction.tables.isEmpty) {
      status = hasUsefulHints
          ? ReceiptParsingStatus.partial
          : ReceiptParsingStatus.failed;
    } else if (rowCountMismatch ||
        rowCountOverflow ||
        tableExtraction.partialRowsFound ||
        missingFingerprintForStructuredParse) {
      status = ReceiptParsingStatus.partial;
    } else {
      status = ReceiptParsingStatus.parsed;
    }

    final List<String> notes = <String>[
      if (tableExtraction.tables.isNotEmpty)
        'Extracted ${tableExtraction.tables.length} valid ticket row${tableExtraction.tables.length == 1 ? '' : 's'}.',
      if (tableExtraction.expectedRowCount != null)
        'Structured row block suggests ${tableExtraction.expectedRowCount} row${tableExtraction.expectedRowCount == 1 ? '' : 's'}.',
      if (rowCountOverflow)
        'Parsed row count exceeded the marker count, so the result remains partial.',
      if (rowCountMismatch)
        'Structured row extraction is incomplete, so the result remains partial.',
      if (missingFingerprintForStructuredParse)
        'Fingerprint could not be built, so the result remains partial.',
      if (lotteryIdHint == null)
        'Lottery ID was not found using the allowed draw patterns.',
      if (fingerprint == null && tableExtraction.tables.isNotEmpty)
        'Fingerprint was not built because the lottery ID is missing.',
      if (tableExtraction.tables.isEmpty && tableExtraction.partialRowsFound)
        'Ticket-like rows were detected, but none contained a full 6+1 row.',
      if (tableExtraction.tables.isEmpty && !tableExtraction.partialRowsFound)
        'No complete lotto rows were extracted from the station receipt.',
    ];

    return ReceiptParseResult(
      status: status,
      message: '$messagePrefix ${notes.join(' ')}'.trim(),
      parsedTables: tableExtraction.tables,
      lotteryIdHint: lotteryIdHint,
      tableCountHint: tableCountHint,
      expectedRowCount: tableExtraction.expectedRowCount,
      ticketTypeHint: ticketTypeHint,
      fingerprintSource: fingerprintSource,
      fingerprint: fingerprint,
      sourceTextLength: normalizedText.length,
    );
  }

  bool _isPdfContentType(String contentType, String fileName) {
    return contentType == 'application/pdf' ||
        fileName.toLowerCase().endsWith('.pdf');
  }

  bool _looksLikeReadableEmbeddedPdfText(String text) {
    if (text.isEmpty || text.length < 40) {
      return false;
    }
    final int hebrewLetters =
        RegExp(r'[\u0590-\u05FF]').allMatches(text).length;
    final int lineBreaks = '\n'.allMatches(text).length;
    final bool hasReceiptKeywords = text.contains('הגרלה') ||
        text.contains('משתתף') ||
        text.contains('לוטו') ||
        text.contains('טבלה');
    return hebrewLetters >= 12 && lineBreaks >= 2 && hasReceiptKeywords;
  }

  bool _isClearlyNoisyParse(ReceiptParseResult result) {
    if (result.parsedTables.length > maxPlausibleParsedRows) {
      return true;
    }
    if (result.expectedRowCount != null &&
        result.parsedTables.length > result.expectedRowCount!) {
      return true;
    }
    if (result.lotteryIdHint == null &&
        result.parsedTables.length > maxPlausibleParsedRows ~/ 2) {
      return true;
    }
    return false;
  }

  String _extractText(Uint8List bytes) {
    final List<String> candidates = <String>[
      _normalizeExtractedText(utf8.decode(bytes, allowMalformed: true)),
      _normalizeExtractedText(latin1.decode(bytes, allowInvalid: true)),
      _normalizeExtractedText(_extractPrintableRuns(bytes)),
    ];

    candidates.sort((left, right) => right.length.compareTo(left.length));
    return candidates.firstWhere(
      (candidate) => candidate.isNotEmpty,
      orElse: () => '',
    );
  }

  String _normalizeExtractedText(String value) {
    return value
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[^\x09\x0A\x20-\x7E\u0590-\u05FF]'), ' ')
        .replaceAll(RegExp(r'[|,:;]+'), ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .trim();
  }

  String _extractPrintableRuns(Uint8List bytes) {
    final StringBuffer buffer = StringBuffer();
    StringBuffer currentRun = StringBuffer();

    for (final int byte in bytes) {
      final bool isPrintableAscii =
          byte == 10 || byte == 13 || (byte >= 32 && byte <= 126);
      if (isPrintableAscii) {
        currentRun.writeCharCode(byte);
        continue;
      }
      if (currentRun.length >= 4) {
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }
        buffer.write(currentRun.toString());
      }
      currentRun = StringBuffer();
    }

    if (currentRun.length >= 4) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(currentRun.toString());
    }

    return buffer.toString();
  }

  _TableExtractionResult _extractTables(String text) {
    final List<String> allLines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final _TicketBlock ticketBlock = _extractTicketBlock(allLines);
    final List<String> blockLines =
        ticketBlock.lines.isNotEmpty ? ticketBlock.lines : <String>[];

    if (blockLines.isEmpty) {
      return _parseLooseRows(allLines);
    }

    final _BlockParseResult blockParseResult = _parseStructuredTicketBlock(
      blockLines.join('\n'),
      expectedRowCount: ticketBlock.expectedRowCount,
    );

    return _TableExtractionResult(
      tables: blockParseResult.tables,
      partialRowsFound: blockParseResult.partialRowsFound,
      numberHintsFound: blockParseResult.numberHintsFound,
      expectedRowCount: blockParseResult.expectedRowCount,
    );
  }

  _TableExtractionResult _parseLooseRows(List<String> lines) {
    final List<ReceiptParsedTable> tables = <ReceiptParsedTable>[];
    final Set<String> seenRows = <String>{};
    bool partialRowsFound = false;
    bool numberHintsFound = false;

    for (final String line in lines) {
      final List<int> values = RegExp(r'\b\d{1,2}\b')
          .allMatches(line)
          .map((match) => int.parse(match.group(0)!))
          .toList();
      if (values.isEmpty) {
        continue;
      }

      final bool hasIndexedPrefix =
          RegExp(r'^\s*(?:טבלה\s*)?\d{1,2}[.)]?\s').hasMatch(line);
      final bool hasIndexedSuffix = RegExp(r'\(\d{1,2}\)\s*$').hasMatch(line);
      final bool rowLike =
          hasIndexedPrefix || hasIndexedSuffix || values.length == 7;

      if (!rowLike) {
        numberHintsFound = numberHintsFound || values.length >= 4;
        continue;
      }

      numberHintsFound = true;
      final int? suffixIndex = _extractTrailingRowIndex(line);
      List<int> normalizedValues = List<int>.from(values);
      if (suffixIndex != null && normalizedValues.isNotEmpty) {
        normalizedValues.removeLast();
      } else if (hasIndexedPrefix && normalizedValues.length >= 8) {
        normalizedValues = normalizedValues.sublist(1);
      }

      if (normalizedValues.length < 7) {
        partialRowsFound = true;
        continue;
      }

      final List<int> candidateValues = normalizedValues.sublist(0, 7);
      final ReceiptParsedTable? table = _buildTable(candidateValues);
      if (table == null) {
        partialRowsFound = true;
        continue;
      }

      if (seenRows.add(table.canonicalRow)) {
        tables.add(
          ReceiptParsedTable(
            tableIndex: tables.length + 1,
            regularNumbers: table.regularNumbers,
            strongNumber: table.strongNumber,
          ),
        );
      }
    }

    if (tables.isNotEmpty) {
      partialRowsFound = false;
    }

    return _TableExtractionResult(
      tables: List<ReceiptParsedTable>.unmodifiable(tables),
      partialRowsFound: partialRowsFound,
      numberHintsFound: numberHintsFound,
      expectedRowCount: null,
    );
  }

  bool _looksLikeHeaderSequence(List<int> values) {
    if (values.length != 7) {
      return false;
    }
    final Set<int> set = values.toSet();
    return set.contains(1) &&
        set.contains(6) &&
        set.contains(7) &&
        set.contains(37) &&
        values.where((value) => value == 1).isNotEmpty;
  }

  ReceiptParsedTable? _buildTable(List<int> values) {
    if (values.length != 7) {
      return null;
    }

    final List<int> regularNumbers = values.sublist(0, 6);
    final int strongNumber = values[6];
    if (strongNumber < 1 || strongNumber > 7) {
      return null;
    }

    final Set<int> uniqueRegulars = regularNumbers.toSet();
    final bool regularsValid = regularNumbers.length == 6 &&
        uniqueRegulars.length == 6 &&
        regularNumbers.every((value) => value >= 1 && value <= 37);
    if (!regularsValid) {
      return null;
    }

    return ReceiptParsedTable(
      tableIndex: 1,
      regularNumbers: List<int>.from(regularNumbers)..sort(),
      strongNumber: strongNumber,
    );
  }

  int? _extractLotteryId(String text) {
    final List<RegExp> patterns = <RegExp>[
      RegExp(r"משתתף\s+בהגרלה\s+מס['׳:]?\s*(\d{4})(?:\(\d{1,2}\))?"),
      RegExp(r"הגרלה\s+מס['׳:]?\s*(\d{4})(?:\(\d{1,2}\))?"),
    ];

    for (final RegExp pattern in patterns) {
      final RegExpMatch? match = pattern.firstMatch(text);
      final int? value = _parseFourDigit(match?.group(1));
      if (value != null) {
        return value;
      }
    }

    return null;
  }

  String _extractTicketType(String text) {
    final String normalized = text
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    if (normalized.contains('דאבל לוטו') ||
        normalized.contains('דאבללוטו') ||
        normalized.contains('double lotto')) {
      return ticketTypeDouble;
    }

    if (normalized.contains('לוטו') || normalized.contains('lotto')) {
      return ticketTypeRegular;
    }

    return ticketTypeUnknown;
  }

  int? _parseFourDigit(String? raw) {
    final int? value = int.tryParse(raw ?? '');
    if (value == null || value < 1000 || value > 9999) {
      return null;
    }
    return value;
  }

  int? _extractTrailingRowIndex(String line) {
    final RegExpMatch? match = RegExp(r'\((\d{1,2})\)\s*$').firstMatch(line);
    final int? value = int.tryParse(match?.group(1) ?? '');
    if (value == null || value < 1 || value > 20) {
      return null;
    }
    return value;
  }

  _BlockParseResult _parseStructuredTicketBlock(
    String blockText, {
    required int? expectedRowCount,
  }) {
    final String flattened = blockText
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'6\s*/\s*37'), ' ')
        .replaceAll(RegExp(r'1\s*/\s*7'), ' ')
        .replaceAll(RegExp(r'[^\d() ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final List<_IndexedTable> indexedTables = <_IndexedTable>[];
    final Set<String> seenRows = <String>{};
    final Set<int> seenRowIndexes = <int>{};
    int previousEnd = 0;
    final bool markersExist = expectedRowCount != null && expectedRowCount > 0;

    for (final RegExpMatch marker
        in RegExp(r'\((\d{1,2})\)').allMatches(flattened)) {
      final int? rowIndex = int.tryParse(marker.group(1) ?? '');
      if (rowIndex == null || rowIndex < 1 || rowIndex > 20) {
        previousEnd = marker.end;
        continue;
      }

      final String segment = flattened.substring(previousEnd, marker.start);
      final List<int> numbers = RegExp(r'\b\d{1,2}\b')
          .allMatches(segment)
          .map((match) => int.parse(match.group(0)!))
          .toList();
      previousEnd = marker.end;

      if (numbers.length < 7) {
        continue;
      }

      final List<int> trailingSeven = numbers.sublist(numbers.length - 7);
      if (_looksLikeHeaderSequence(trailingSeven)) {
        continue;
      }

      final ReceiptParsedTable? table = _buildTable(trailingSeven);
      if (table == null ||
          !seenRows.add(table.canonicalRow) ||
          !seenRowIndexes.add(rowIndex)) {
        continue;
      }

      indexedTables.add(
        _IndexedTable(
          rowIndex: rowIndex,
          table: ReceiptParsedTable(
            tableIndex: rowIndex,
            regularNumbers: table.regularNumbers,
            strongNumber: table.strongNumber,
          ),
        ),
      );
    }

    if (markersExist) {
      indexedTables.sort((a, b) => a.rowIndex.compareTo(b.rowIndex));
      final List<ReceiptParsedTable> tables = indexedTables
          .map(
            (indexed) => ReceiptParsedTable(
              tableIndex: indexed.rowIndex,
              regularNumbers: indexed.table.regularNumbers,
              strongNumber: indexed.table.strongNumber,
            ),
          )
          .toList(growable: false);
      final int indexedRowCount =
          indexedTables.map((row) => row.rowIndex).toSet().length;
      final int resolvedExpectedRowCount = expectedRowCount > indexedRowCount
          ? expectedRowCount
          : indexedRowCount;
      final bool partialRowsFound = tables.length != resolvedExpectedRowCount;
      return _BlockParseResult(
        tables: List<ReceiptParsedTable>.unmodifiable(tables),
        partialRowsFound: partialRowsFound,
        numberHintsFound: true,
        expectedRowCount: resolvedExpectedRowCount,
      );
    }

    // When no row markers exist, fall back to block-level numeric grouping.
    final List<int> allNumbers = RegExp(r'\b\d{1,2}\b')
        .allMatches(flattened)
        .map((match) => int.parse(match.group(0)!))
        .toList();

    if (allNumbers.length >= 7) {
      final List<ReceiptParsedTable> fallbackTables = <ReceiptParsedTable>[];
      final Set<String> fallbackSeenRows = <String>{};

      for (var start = 0; start <= allNumbers.length - 7; start += 7) {
        final List<int> window = allNumbers.sublist(start, start + 7);
        if (_looksLikeHeaderSequence(window)) {
          continue;
        }
        final ReceiptParsedTable? table = _buildTable(window);
        if (table == null || !fallbackSeenRows.add(table.canonicalRow)) {
          continue;
        }
        fallbackTables.add(
          ReceiptParsedTable(
            tableIndex: fallbackTables.length + 1,
            regularNumbers: table.regularNumbers,
            strongNumber: table.strongNumber,
          ),
        );
      }

      return _BlockParseResult(
        tables: List<ReceiptParsedTable>.unmodifiable(fallbackTables),
        partialRowsFound: allNumbers.length >= 4,
        numberHintsFound: allNumbers.isNotEmpty,
        expectedRowCount: expectedRowCount,
      );
    }

    return _BlockParseResult(
      tables: const <ReceiptParsedTable>[],
      partialRowsFound: allNumbers.length >= 4,
      numberHintsFound: allNumbers.isNotEmpty,
      expectedRowCount: expectedRowCount,
    );
  }

  _TicketBlock _extractTicketBlock(List<String> lines) {
    if (lines.isEmpty) {
      return const _TicketBlock(lines: <String>[]);
    }

    int? startIndex;
    for (var index = 0; index < lines.length; index += 1) {
      final String compact = lines[index].replaceAll(RegExp(r'\s+'), '');
      if (compact.contains('6/37') || compact.contains('1/7')) {
        startIndex = index;
        break;
      }
    }

    if (startIndex == null) {
      for (var index = 0; index < lines.length; index += 1) {
        final bool hasRowMarker = RegExp(r'\(\d{1,2}\)').hasMatch(lines[index]);
        final int numbers =
            RegExp(r'\b\d{1,2}\b').allMatches(lines[index]).length;
        if (hasRowMarker && numbers >= 7) {
          startIndex = index;
          break;
        }
      }
    }

    if (startIndex == null) {
      return const _TicketBlock(lines: <String>[]);
    }

    final List<String> blockLines = <String>[];
    final Set<int> rowIndexes = <int>{};

    for (var index = startIndex; index < lines.length; index += 1) {
      final String line = lines[index];
      if (blockLines.isNotEmpty && _looksLikeBlockFooter(line)) {
        break;
      }

      if (!_isLikelyTicketBlockLine(line) && blockLines.isNotEmpty) {
        final int numberCount = RegExp(r'\b\d{1,2}\b').allMatches(line).length;
        if (numberCount >= 3) {
          blockLines.add(line);
        }
        continue;
      }

      if (_isLikelyTicketBlockLine(line)) {
        blockLines.add(line);
      }

      for (final RegExpMatch match
          in RegExp(r'\((\d{1,2})\)').allMatches(line)) {
        final int idx = int.parse(match.group(1)!);
        rowIndexes.add(idx);
      }
    }

    return _TicketBlock(
      lines: List<String>.unmodifiable(blockLines),
      expectedRowCount: rowIndexes.isEmpty ? null : rowIndexes.length,
    );
  }

  bool _isLikelyTicketBlockLine(String line) {
    final String compact = line.replaceAll(RegExp(r'\s+'), '');
    if (compact.contains('6/37') ||
        compact.contains('1/7') ||
        compact.contains('6/37|1/7')) {
      return true;
    }

    final bool hasTrailingRowMarker = RegExp(r'\(\d{1,2}\)\s*$').hasMatch(line);
    final int numberCount = RegExp(r'\b\d{1,2}\b').allMatches(line).length;

    if (hasTrailingRowMarker && numberCount >= 7) {
      return true;
    }

    return numberCount == 7 && !_looksLikeBlockFooter(line);
  }

  bool _looksLikeBlockFooter(String line) {
    final String normalized = line.toLowerCase();
    return normalized.contains('extra') ||
        normalized.contains('לא משתתף') ||
        normalized.contains('הגרלה') ||
        normalized.contains('סכום') ||
        normalized.contains('שעה') ||
        normalized.contains('מחיר') ||
        normalized.contains('קבלה') ||
        RegExp(r'\b\d{4}\(\d{1,2}\)').hasMatch(line);
  }
}

class _TableExtractionResult {
  const _TableExtractionResult({
    required this.tables,
    required this.partialRowsFound,
    required this.numberHintsFound,
    required this.expectedRowCount,
  });

  final List<ReceiptParsedTable> tables;
  final bool partialRowsFound;
  final bool numberHintsFound;
  final int? expectedRowCount;
}

class _TicketBlock {
  const _TicketBlock({
    required this.lines,
    this.expectedRowCount,
  });

  final List<String> lines;
  final int? expectedRowCount;
}

class _IndexedTable {
  const _IndexedTable({
    required this.rowIndex,
    required this.table,
  });

  final int rowIndex;
  final ReceiptParsedTable table;
}

class _BlockParseResult {
  const _BlockParseResult({
    required this.tables,
    required this.partialRowsFound,
    required this.numberHintsFound,
    required this.expectedRowCount,
  });

  final List<ReceiptParsedTable> tables;
  final bool partialRowsFound;
  final bool numberHintsFound;
  final int? expectedRowCount;
}
