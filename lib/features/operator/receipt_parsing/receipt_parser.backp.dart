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

  final ReceiptOcrService _ocrService;

  Future<ReceiptParseResult> parse({
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final String extractedText = _extractText(bytes);
    final ReceiptParseResult primaryResult = _parseNormalizedText(
      _normalizeExtractedText(extractedText),
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
    ReceiptParseResult primaryResult,
    ReceiptParseResult fallbackResult,
  ) {
    final int primaryScore = _resultQualityScore(primaryResult);
    final int fallbackScore = _resultQualityScore(fallbackResult);
    if (fallbackScore > primaryScore) {
      return fallbackResult;
    }
    return primaryResult;
  }

  int _resultQualityScore(ReceiptParseResult result) {
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

    final ReceiptParsingStatus status;
    if (tableExtraction.tables.isEmpty) {
      status = hasUsefulHints
          ? ReceiptParsingStatus.partial
          : ReceiptParsingStatus.failed;
    } else if (rowCountMismatch || tableExtraction.partialRowsFound) {
      status = ReceiptParsingStatus.partial;
    } else {
      status = ReceiptParsingStatus.parsed;
    }

    final List<String> notes = <String>[
      if (tableExtraction.tables.isNotEmpty)
        'Extracted ${tableExtraction.tables.length} valid ticket row${tableExtraction.tables.length == 1 ? '' : 's'}.',
      if (tableExtraction.expectedRowCount != null)
        'Structured row block suggests ${tableExtraction.expectedRowCount} row${tableExtraction.expectedRowCount == 1 ? '' : 's'}.',
      if (rowCountMismatch)
        'Structured row extraction is incomplete, so the result remains partial.',
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
      ticketTypeHint: ticketTypeHint,
      fingerprintSource: fingerprintSource,
      fingerprint: fingerprint,
      sourceTextLength: normalizedText.length,
    );
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
    final List<ReceiptParsedTable> tables = <ReceiptParsedTable>[];
    final Set<String> seenRows = <String>{};
    bool partialRowsFound = false;
    bool numberHintsFound = false;
    final List<String> allLines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final _TicketBlock ticketBlock = _extractTicketBlock(allLines);
    final List<String> lines =
        ticketBlock.lines.isNotEmpty ? ticketBlock.lines : allLines;

    for (var index = 0; index < lines.length; index += 1) {
      final List<String> candidateLines = <String>[
        lines[index],
        if (index + 1 < lines.length && _looksLikeTicketRowStart(lines[index]))
          '${lines[index]} ${lines[index + 1]}',
      ];

      for (final String candidateLine in candidateLines) {
        final _CandidateTableRow? candidate =
            _parseCandidateLine(candidateLine);
        if (candidate == null) {
          continue;
        }

        numberHintsFound = numberHintsFound || candidate.numberHintsFound;
        if (candidate.table == null) {
          partialRowsFound = true;
          continue;
        }

        if (seenRows.add(candidate.table!.canonicalRow)) {
          tables.add(
            ReceiptParsedTable(
              tableIndex: tables.length + 1,
              regularNumbers: candidate.table!.regularNumbers,
              strongNumber: candidate.table!.strongNumber,
            ),
          );
        }
      }
    }

    return _TableExtractionResult(
      tables: List<ReceiptParsedTable>.unmodifiable(tables),
      partialRowsFound: partialRowsFound,
      numberHintsFound: numberHintsFound,
      expectedRowCount: ticketBlock.expectedRowCount,
    );
  }

  _CandidateTableRow? _parseCandidateLine(String line) {
    final String sanitizedLine = _sanitizeCandidateLine(line);
    final int? explicitRowIndex = _extractExplicitRowIndex(sanitizedLine);
    final bool rowLabeled =
        _looksLikeTicketRowStart(line) || explicitRowIndex != null;
    final List<int> values = RegExp(r'\b\d{1,2}\b')
        .allMatches(sanitizedLine)
        .map((match) => int.parse(match.group(0)!))
        .toList();

    if (values.isEmpty) {
      return null;
    }

    if (!rowLabeled && _isStructuredHeaderOnlyLine(line, values)) {
      return null;
    }

    final bool hasNumberHints = values.length >= 4;
    if (!rowLabeled && values.length != 7) {
      return hasNumberHints
          ? _CandidateTableRow(table: null, numberHintsFound: true)
          : null;
    }

    final List<List<int>> candidateWindows = <List<int>>[];
    if (rowLabeled) {
      final List<int> withoutLeadingIndex = _dropExplicitRowIndex(
        values,
        explicitRowIndex,
      );
      if (withoutLeadingIndex.length >= 7) {
        for (var start = 0;
            start <= withoutLeadingIndex.length - 7;
            start += 1) {
          candidateWindows.add(withoutLeadingIndex.sublist(start, start + 7));
        }
      }
    } else if (values.length == 7) {
      candidateWindows.add(values);
    }

    for (final List<int> window in candidateWindows) {
      final ReceiptParsedTable? table = _buildTable(window);
      if (table != null) {
        return _CandidateTableRow(
          table: table,
          numberHintsFound: true,
        );
      }
    }

    return _CandidateTableRow(
      table: null,
      numberHintsFound: hasNumberHints || rowLabeled,
    );
  }

  String _sanitizeCandidateLine(String line) {
    return line
        .replaceAll(RegExp(r'6\s*/\s*37'), ' ')
        .replaceAll(RegExp(r'1\s*/\s*7'), ' ')
        .replaceAll('טבלה', ' ')
        .replaceAll('חזק', ' ')
        .replaceAll(RegExp(r'[A-Za-z]'), ' ')
        .replaceAll(RegExp(r'[^\d() ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<int> _dropExplicitRowIndex(List<int> values, int? explicitRowIndex) {
    if (explicitRowIndex == null || values.length < 8) {
      return values;
    }

    if (values.first == explicitRowIndex) {
      return values.sublist(1);
    }
    if (values.last == explicitRowIndex) {
      return values.sublist(0, values.length - 1);
    }

    final List<int> withoutIndex = List<int>.from(values);
    withoutIndex.remove(explicitRowIndex);
    return withoutIndex;
  }

  int? _extractExplicitRowIndex(String line) {
    final List<RegExp> patterns = <RegExp>[
      RegExp(r'\((\d{1,2})\)'),
      RegExp(r'(?:^|\s)(\d{1,2})\)'),
      RegExp(r'^\s*(\d{1,2})(?:\s|$)'),
    ];

    for (final RegExp pattern in patterns) {
      final RegExpMatch? match = pattern.firstMatch(line);
      final int? value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value >= 1 && value <= 20) {
        return value;
      }
    }

    return null;
  }

  bool _looksLikeTicketRowStart(String line) {
    return line.contains('טבלה') ||
        line.contains('חזק') ||
        RegExp(r'^\s*(?:טבלה\s*)?(?:\(\d{1,2}\)|\d{1,2}[.)])').hasMatch(line);
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
      RegExp(
        r"(?:(?:הגרלה)|(?:משתתף\s+בהגרלה))\s*מס['׳]?[^\d]{0,12}(\d{4})(?:\(\d{1,2}\))?",
      ),
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
    if (text.contains('דאבל לוטו')) {
      return ticketTypeDouble;
    }
    if (text.contains('לוטו') || text.toLowerCase().contains('lotto')) {
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

  _TicketBlock _extractTicketBlock(List<String> lines) {
    if (lines.isEmpty) {
      return const _TicketBlock(lines: <String>[]);
    }

    int? startIndex;
    for (var index = 0; index < lines.length; index += 1) {
      final String line = lines[index];
      if (line.contains('6/37') ||
          line.contains('1/7') ||
          line.contains('6 / 37')) {
        startIndex = index;
        break;
      }
    }

    if (startIndex == null) {
      for (var index = 0; index < lines.length; index += 1) {
        final int? rowIndex = _extractExplicitRowIndex(lines[index]);
        final int numberCount =
            RegExp(r'\b\d{1,2}\b').allMatches(lines[index]).length;
        if (rowIndex != null && numberCount >= 7) {
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

      if (!_isLikelyTicketBlockLine(line)) {
        if (blockLines.isNotEmpty) {
          final int numberCount =
              RegExp(r'\b\d{1,2}\b').allMatches(line).length;
          if (numberCount > 0) {
            break;
          }
        }
        continue;
      }

      blockLines.add(line);
      final int? rowIndex = _extractExplicitRowIndex(line);
      if (rowIndex != null) {
        rowIndexes.add(rowIndex);
      }
    }

    return _TicketBlock(
      lines: List<String>.unmodifiable(blockLines),
      expectedRowCount: rowIndexes.isEmpty ? null : rowIndexes.length,
    );
  }

  bool _isLikelyTicketBlockLine(String line) {
    if (line.contains('6/37') ||
        line.contains('1/7') ||
        line.contains('6 / 37')) {
      return true;
    }

    final int? rowIndex = _extractExplicitRowIndex(line);
    final int numberCount = RegExp(r'\b\d{1,2}\b').allMatches(line).length;
    if (rowIndex != null && numberCount >= 7) {
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

  bool _isStructuredHeaderOnlyLine(String line, List<int> values) {
    if (!(line.contains('6/37') ||
        line.contains('1/7') ||
        line.contains('6 / 37'))) {
      return false;
    }
    final Set<int> normalizedValues = values.toSet();
    return normalizedValues.contains(1) &&
        normalizedValues.contains(6) &&
        normalizedValues.contains(7) &&
        normalizedValues.contains(37) &&
        values.length <= 4;
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

class _CandidateTableRow {
  const _CandidateTableRow({
    required this.table,
    required this.numberHintsFound,
  });

  final ReceiptParsedTable? table;
  final bool numberHintsFound;
}

class _TicketBlock {
  const _TicketBlock({
    required this.lines,
    this.expectedRowCount,
  });

  final List<String> lines;
  final int? expectedRowCount;
}
