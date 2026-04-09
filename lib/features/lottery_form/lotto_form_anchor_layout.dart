import 'dart:ui';

class LottoFormAnchorLayout {
  const LottoFormAnchorLayout._();

  static const String backgroundAssetPath = 'assets/images/form-lotto.png';
  static const Size templatePixelSize = Size(500, 1516);

  static const Offset t1N1 = Offset(155, 151);
  static const Offset t1N2 = Offset(193, 150);
  static const Offset t1N7 = Offset(387, 150);
  static const Offset t1N8 = Offset(38, 173);
  static const Offset t1N11 = Offset(155, 172);
  static const Offset t1N17 = Offset(387, 173);
  static const Offset t1N18 = Offset(38, 196);
  static const Offset t1N21 = Offset(155, 197);
  static const Offset t1N27 = Offset(386, 195);
  static const Offset t1N28 = Offset(38, 218);
  static const Offset t1N31 = Offset(155, 219);
  static const Offset t1N37 = Offset(387, 218);
  static const Offset t1S1 = Offset(463, 151);
  static const Offset t1S2 = Offset(426, 172);
  static const Offset t1S3 = Offset(462, 173);
  static const Offset t1S4 = Offset(425, 196);
  static const Offset t1S7 = Offset(462, 218);

  static const Offset t2N1 = Offset(155, 238);
  static const Offset t2N2 = Offset(192, 238);
  static const Offset t2N13 = Offset(232, 262);
  static const Offset t2N24 = Offset(271, 283);
  static const Offset t2N35 = Offset(309, 306);

  static const Offset t3N2 = Offset(192, 332);
  static const Offset t3N13 = Offset(232, 354);
  static const Offset t3N24 = Offset(270, 376);
  static const Offset t3N35 = Offset(308, 399);

  static const Offset t4N2 = Offset(193, 421);
  static const Offset t4N13 = Offset(232, 443);
  static const Offset t4N24 = Offset(270, 466);
  static const Offset t4N35 = Offset(309, 488);

  static const Offset t5N2 = Offset(193, 511);
  static const Offset t5N13 = Offset(232, 534);
  static const Offset t5N24 = Offset(271, 556);
  static const Offset t5N35 = Offset(309, 579);

  static const Offset t7N2 = Offset(192, 691);
  static const Offset t7N7 = Offset(387, 692);
  static const Offset t7N8 = Offset(38, 714);
  static const Offset t7N13 = Offset(231, 714);
  static const Offset t7N17 = Offset(387, 714);
  static const Offset t7N18 = Offset(38, 736);
  static const Offset t7N24 = Offset(270, 737);
  static const Offset t7N27 = Offset(387, 737);
  static const Offset t7N28 = Offset(38, 760);
  static const Offset t7N35 = Offset(309, 759);
  static const Offset t7N37 = Offset(387, 760);
  static const Offset t7S3 = Offset(462, 714);
  static const Offset t7S4 = Offset(425, 737);
  static const Offset t7S7 = Offset(462, 760);

  static const Offset t8N2 = Offset(192, 796);
  static const Offset t8N7 = Offset(387, 798);
  static const Offset t8N8 = Offset(38, 820);
  static const Offset t8N17 = Offset(387, 820);
  static const Offset t8N18 = Offset(38, 841);
  static const Offset t8N27 = Offset(387, 842);
  static const Offset t8N28 = Offset(39, 865);
  static const Offset t8N37 = Offset(386, 865);
  static const Offset t8S3 = Offset(462, 820);
  static const Offset t8S4 = Offset(425, 843);
  static const Offset t8S7 = Offset(462, 865);

  static const Offset t9N2 = Offset(193, 884);
  static const Offset t9N13 = Offset(232, 909);
  static const Offset t9N24 = Offset(270, 930);
  static const Offset t9N35 = Offset(310, 954);

  static const Offset t10N2 = Offset(192, 976);
  static const Offset t10N13 = Offset(232, 1000);
  static const Offset t10N24 = Offset(270, 1022);
  static const Offset t10N35 = Offset(309, 1044);

  static const Offset t11N2 = Offset(193, 1065);
  static const Offset t11N13 = Offset(232, 1089);
  static const Offset t11N24 = Offset(271, 1111);
  static const Offset t11N35 = Offset(309, 1132);

  static const Offset t12N2 = Offset(193, 1157);
  static const Offset t12N13 = Offset(231, 1179);
  static const Offset t12N24 = Offset(270, 1202);
  static const Offset t12N35 = Offset(308, 1224);

  static const Offset t13N2 = Offset(192, 1245);
  static const Offset t13N13 = Offset(231, 1269);
  static const Offset t13N24 = Offset(270, 1291);
  static const Offset t13N35 = Offset(309, 1314);

  static const Offset t14N1 = Offset(155, 1335);
  static const Offset t14N2 = Offset(193, 1336);
  static const Offset t14N7 = Offset(387, 1336);
  static const Offset t14N8 = Offset(39, 1359);
  static const Offset t14N17 = Offset(386, 1359);
  static const Offset t14N18 = Offset(39, 1381);
  static const Offset t14N27 = Offset(386, 1382);
  static const Offset t14N28 = Offset(38, 1405);
  static const Offset t14N31 = Offset(155, 1404);
  static const Offset t14N37 = Offset(386, 1403);
  static const Offset t14S3 = Offset(462, 1359);
  static const Offset t14S4 = Offset(424, 1381);
  static const Offset t14S7 = Offset(463, 1404);

  static final double templateAspectRatio =
      templatePixelSize.width / templatePixelSize.height;

  static const List<Offset> anchorPoints = <Offset>[
    t1N1,
    t1N2,
    t1N7,
    t1N8,
    t1N11,
    t1N17,
    t1N18,
    t1N21,
    t1N27,
    t1N28,
    t1N31,
    t1N37,
    t1S1,
    t1S2,
    t1S3,
    t1S4,
    t1S7,
    t2N1,
    t2N2,
    t2N13,
    t2N24,
    t2N35,
    t3N2,
    t3N13,
    t3N24,
    t3N35,
    t4N2,
    t4N13,
    t4N24,
    t4N35,
    t5N2,
    t5N13,
    t5N24,
    t5N35,
    t7N2,
    t7N7,
    t7N8,
    t7N13,
    t7N17,
    t7N18,
    t7N24,
    t7N27,
    t7N28,
    t7N35,
    t7N37,
    t7S3,
    t7S4,
    t7S7,
    t8N2,
    t8N7,
    t8N8,
    t8N17,
    t8N18,
    t8N27,
    t8N28,
    t8N37,
    t8S3,
    t8S4,
    t8S7,
    t9N2,
    t9N13,
    t9N24,
    t9N35,
    t10N2,
    t10N13,
    t10N24,
    t10N35,
    t11N2,
    t11N13,
    t11N24,
    t11N35,
    t12N2,
    t12N13,
    t12N24,
    t12N35,
    t13N2,
    t13N13,
    t13N24,
    t13N35,
    t14N1,
    t14N2,
    t14N7,
    t14N8,
    t14N17,
    t14N18,
    t14N27,
    t14N28,
    t14N31,
    t14N37,
    t14S3,
    t14S4,
    t14S7,
  ];

  static final _LinearFit _row1XFit = _LinearFit.fromPoints(<_Point>[
    _Point(3, t1N1.dx),
    _Point(4, t1N2.dx),
    _Point(9, t1N7.dx),
  ]);
  static final _LinearFit _row2XFit = _LinearFit.fromPoints(<_Point>[
    _Point(0, t1N8.dx),
    _Point(3, t1N11.dx),
    _Point(9, t1N17.dx),
  ]);
  static final _LinearFit _row3XFit = _LinearFit.fromPoints(<_Point>[
    _Point(0, t1N18.dx),
    _Point(3, t1N21.dx),
    _Point(9, t1N27.dx),
  ]);
  static final _LinearFit _row4XFit = _LinearFit.fromPoints(<_Point>[
    _Point(0, t1N28.dx),
    _Point(3, t1N31.dx),
    _Point(9, t1N37.dx),
  ]);

  static final Map<int, double> _row1YAnchors = <int, double>{
    0: t1N2.dy,
    1: t2N2.dy,
    2: t3N2.dy,
    3: t4N2.dy,
    4: t5N2.dy,
    6: t7N2.dy,
    7: _average(<double>[t8N2.dy, t8N7.dy]),
    8: t9N2.dy,
    9: t10N2.dy,
    10: t11N2.dy,
    11: t12N2.dy,
    12: t13N2.dy,
    13: t14N2.dy,
  };

  static final Map<int, double> _row2YAnchors = <int, double>{
    0: _average(<double>[t1N8.dy, t1N11.dy, t1N17.dy, t1S2.dy, t1S3.dy]),
    1: t2N13.dy,
    2: t3N13.dy,
    3: t4N13.dy,
    4: t5N13.dy,
    6: _average(<double>[t7N8.dy, t7N13.dy, t7N17.dy, t7S3.dy]),
    7: _average(<double>[t8N8.dy, t8N17.dy, t8S3.dy]),
    8: t9N13.dy,
    9: t10N13.dy,
    10: t11N13.dy,
    11: t12N13.dy,
    12: t13N13.dy,
    13: _average(<double>[t14N8.dy, t14N17.dy, t14S3.dy]),
  };

  static final Map<int, double> _row3YAnchors = <int, double>{
    0: _average(<double>[t1N18.dy, t1N21.dy, t1N27.dy, t1S4.dy]),
    1: t2N24.dy,
    2: t3N24.dy,
    3: t4N24.dy,
    4: t5N24.dy,
    6: _average(<double>[t7N18.dy, t7N24.dy, t7N27.dy, t7S4.dy]),
    7: _average(<double>[t8N18.dy, t8N27.dy, t8S4.dy]),
    8: t9N24.dy,
    9: t10N24.dy,
    10: t11N24.dy,
    11: t12N24.dy,
    12: t13N24.dy,
    13: _average(<double>[t14N18.dy, t14N27.dy, t14S4.dy]),
  };

  static final Map<int, double> _row4YAnchors = <int, double>{
    0: _average(<double>[t1N28.dy, t1N31.dy, t1N37.dy, t1S7.dy]),
    1: t2N35.dy,
    2: t3N35.dy,
    3: t4N35.dy,
    4: t5N35.dy,
    6: _average(<double>[t7N28.dy, t7N35.dy, t7N37.dy, t7S7.dy]),
    7: _average(<double>[t8N28.dy, t8N37.dy, t8S7.dy]),
    8: t9N35.dy,
    9: t10N35.dy,
    10: t11N35.dy,
    11: t12N35.dy,
    12: t13N35.dy,
    13: _average(<double>[t14N28.dy, t14N31.dy, t14N37.dy, t14S7.dy]),
  };

  static final double _strongLeftX = _average(<double>[t1S2.dx, t1S4.dx]);
  static final double _strongRightX = _average(<double>[
    t1S1.dx,
    t1S3.dx,
    t1S7.dx,
  ]);

  static const double _strokeLogicalWidthPx = 22;
  static const double _strokeInsetXPx = 3;
  static const double _strokeWidthPx = 3.4;
  static const double _boxVerticalOffsetPx = 0;

  static Offset getNumberPosition(int tableIndex, int number) {
    if (tableIndex < 0 || tableIndex > 13) {
      throw ArgumentError.value(tableIndex, 'tableIndex', 'Must be 0..13');
    }
    if (number < 1 || number > 37) {
      throw ArgumentError.value(number, 'number', 'Must be 1..37');
    }
    final _RegularCell cell = _regularCellForNumber(number);
    return Offset(
      _regularXFor(rowIndex: cell.rowIndex, columnIndex: cell.columnIndex),
      _regularYFor(tableIndex: tableIndex, rowIndex: cell.rowIndex),
    );
  }

  static Offset getStrongNumberPosition(int tableIndex, int strongNumber) {
    if (tableIndex < 0 || tableIndex > 13) {
      throw ArgumentError.value(tableIndex, 'tableIndex', 'Must be 0..13');
    }
    if (strongNumber < 1 || strongNumber > 7) {
      throw ArgumentError.value(strongNumber, 'strongNumber', 'Must be 1..7');
    }
    final _StrongCell cell = _strongCellForNumber(strongNumber);
    return Offset(
      cell.isRightColumn ? _strongRightX : _strongLeftX,
      _regularYFor(tableIndex: tableIndex, rowIndex: cell.rowIndex),
    );
  }

  static Offset mapToCanvas(Offset templatePoint, Size canvasSize) {
    return Offset(
      (templatePoint.dx / templatePixelSize.width) * canvasSize.width,
      (templatePoint.dy / templatePixelSize.height) * canvasSize.height,
    );
  }

  static double scaleX(Size canvasSize) =>
      canvasSize.width / templatePixelSize.width;
  static double scaleY(Size canvasSize) =>
      canvasSize.height / templatePixelSize.height;

  static double get strokeLogicalWidthPx => _strokeLogicalWidthPx;
  static double get strokeInsetXPx => _strokeInsetXPx;
  static double get strokeWidthPx => _strokeWidthPx;
  static double get boxVerticalOffsetPx => _boxVerticalOffsetPx;

  static Iterable<Offset> getAllRegularPositions() sync* {
    for (int tableIndex = 0; tableIndex < 14; tableIndex++) {
      for (int number = 1; number <= 37; number++) {
        yield getNumberPosition(tableIndex, number);
      }
    }
  }

  static Iterable<Offset> getAllStrongPositions() sync* {
    for (int tableIndex = 0; tableIndex < 14; tableIndex++) {
      for (int strongNumber = 1; strongNumber <= 7; strongNumber++) {
        yield getStrongNumberPosition(tableIndex, strongNumber);
      }
    }
  }

  static List<String> debugSamples() {
    final Offset t1n2 = getNumberPosition(0, 2);
    final Offset t7n2 = getNumberPosition(6, 2);
    final Offset t14n2 = getNumberPosition(13, 2);
    final Offset t1n17 = getNumberPosition(0, 17);
    final Offset t14n37 = getNumberPosition(13, 37);
    return <String>[
      'Table 1, number 2 => (${t1n2.dx.toStringAsFixed(2)}, ${t1n2.dy.toStringAsFixed(2)})',
      'Table 7, number 2 => (${t7n2.dx.toStringAsFixed(2)}, ${t7n2.dy.toStringAsFixed(2)})',
      'Table 14, number 2 => (${t14n2.dx.toStringAsFixed(2)}, ${t14n2.dy.toStringAsFixed(2)})',
      'Table 1, number 17 => (${t1n17.dx.toStringAsFixed(2)}, ${t1n17.dy.toStringAsFixed(2)})',
      'Table 14, number 37 => (${t14n37.dx.toStringAsFixed(2)}, ${t14n37.dy.toStringAsFixed(2)})',
    ];
  }

  static double _regularXFor({
    required int rowIndex,
    required int columnIndex,
  }) {
    switch (rowIndex) {
      case 0:
        return _row1XFit.valueAt(columnIndex.toDouble());
      case 1:
        return _row2XFit.valueAt(columnIndex.toDouble());
      case 2:
        return _row3XFit.valueAt(columnIndex.toDouble());
      case 3:
        return _row4XFit.valueAt(columnIndex.toDouble());
      default:
        throw ArgumentError.value(rowIndex, 'rowIndex', 'Must be 0..3');
    }
  }

  static double _regularYFor({
    required int tableIndex,
    required int rowIndex,
  }) {
    switch (rowIndex) {
      case 0:
        return _interpolateAnchoredY(tableIndex, _row1YAnchors);
      case 1:
        return _interpolateAnchoredY(tableIndex, _row2YAnchors);
      case 2:
        return _interpolateAnchoredY(tableIndex, _row3YAnchors);
      case 3:
        return _interpolateAnchoredY(tableIndex, _row4YAnchors);
      default:
        throw ArgumentError.value(rowIndex, 'rowIndex', 'Must be 0..3');
    }
  }

  static double _interpolateAnchoredY(
    int tableIndex,
    Map<int, double> anchors,
  ) {
    final double? exact = anchors[tableIndex];
    if (exact != null) {
      return exact;
    }

    final List<int> ordered = anchors.keys.toList()..sort();
    int? lower;
    int? upper;
    for (final int key in ordered) {
      if (key < tableIndex) {
        lower = key;
      } else if (key > tableIndex) {
        upper = key;
        break;
      }
    }

    if (lower == null || upper == null) {
      throw StateError('Missing anchor segment for tableIndex=$tableIndex');
    }

    final double startY = anchors[lower]!;
    final double endY = anchors[upper]!;
    final double t = (tableIndex - lower) / (upper - lower);
    return startY + ((endY - startY) * t);
  }

  static _RegularCell _regularCellForNumber(int number) {
    if (number >= 1 && number <= 7) {
      return _RegularCell(rowIndex: 0, columnIndex: (number - 1) + 3);
    }
    if (number >= 8 && number <= 17) {
      return _RegularCell(rowIndex: 1, columnIndex: number - 8);
    }
    if (number >= 18 && number <= 27) {
      return _RegularCell(rowIndex: 2, columnIndex: number - 18);
    }
    return _RegularCell(rowIndex: 3, columnIndex: number - 28);
  }

  static _StrongCell _strongCellForNumber(int strongNumber) {
    switch (strongNumber) {
      case 1:
        return const _StrongCell(rowIndex: 0, isRightColumn: true);
      case 2:
        return const _StrongCell(rowIndex: 1, isRightColumn: false);
      case 3:
        return const _StrongCell(rowIndex: 1, isRightColumn: true);
      case 4:
        return const _StrongCell(rowIndex: 2, isRightColumn: false);
      case 5:
        return const _StrongCell(rowIndex: 2, isRightColumn: true);
      case 6:
        return const _StrongCell(rowIndex: 3, isRightColumn: false);
      case 7:
        return const _StrongCell(rowIndex: 3, isRightColumn: true);
      default:
        throw ArgumentError.value(strongNumber, 'strongNumber', 'Must be 1..7');
    }
  }

  static double _average(List<double> values) =>
      values.reduce((left, right) => left + right) / values.length;
}

class _RegularCell {
  const _RegularCell({required this.rowIndex, required this.columnIndex});
  final int rowIndex;
  final int columnIndex;
}

class _StrongCell {
  const _StrongCell({required this.rowIndex, required this.isRightColumn});
  final int rowIndex;
  final bool isRightColumn;
}

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;
}

class _LinearFit {
  const _LinearFit({required this.slope, required this.intercept});

  factory _LinearFit.fromPoints(List<_Point> points) {
    final double n = points.length.toDouble();
    final double sumX = points.fold(0, (sum, point) => sum + point.x);
    final double sumY = points.fold(0, (sum, point) => sum + point.y);
    final double sumXY =
        points.fold(0, (sum, point) => sum + (point.x * point.y));
    final double sumXX =
        points.fold(0, (sum, point) => sum + (point.x * point.x));
    final double slope =
        ((n * sumXY) - (sumX * sumY)) / ((n * sumXX) - (sumX * sumX));
    final double intercept = (sumY - (slope * sumX)) / n;
    return _LinearFit(slope: slope, intercept: intercept);
  }

  final double slope;
  final double intercept;

  double valueAt(double x) => intercept + (slope * x);
}
