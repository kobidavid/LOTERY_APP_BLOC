import 'dart:ui';

class LotteryPrintLayout {
  const LotteryPrintLayout._();

  static const String templatePreviewAssetPath =
      'assets/images/lottery_form_template.png';

  static const double formLeft = 378;
  static const double formTop = 64;
  static const double formWidth = 469;
  static const double formHeight = 1455;

  static const double tableStepY = 88.37;
  static const double colStepX = 33.72;

  static const Size pageSize = Size(
    formLeft + formWidth + formLeft,
    formTop + formHeight + formTop,
  );

  static const Rect formBounds = Rect.fromLTWH(
    formLeft,
    formTop,
    formWidth,
    formHeight,
  );

  static const List<double> regularRowStartX = <double>[
    512.88,
    546.59,
    548.13,
    592.57,
  ];

  static const List<double> regularRowY = <double>[
    207.21,
    231.59,
    252.92,
    274.25,
  ];

  static const double strongX = 799.49;
  static const double strongY1 = 207.21;
  static const double strongStepY = 11.17;

  static const double regularLineLength = 18;
  static const double strongLineLength = 14;
  static const double strokeWidth = 1.5;
  static const double debugAnchorRadius = 2.2;
  static const double globalOffsetX = -4;
  static const double globalOffsetY = -8;
  static const double globalScaleX = 1.02;
  static const double globalScaleY = 1.01;

  static Offset getRegularNumberPosition(int tableIndex, int number) {
    assert(tableIndex >= 0 && tableIndex < 14);
    assert(number >= 1 && number <= 37);

    final _RegularCell cell = _mapRegularCell(number);
    return Offset(
      regularRowStartX[cell.rowIndex] + (cell.columnIndex * colStepX),
      regularRowY[cell.rowIndex] + (tableIndex * tableStepY),
    );
  }

  static Offset getStrongNumberPosition(int tableIndex, int strongNumber) {
    assert(tableIndex >= 0 && tableIndex < 14);
    assert(strongNumber >= 1 && strongNumber <= 7);

    return Offset(
      strongX,
      strongY1 + (tableIndex * tableStepY) + ((strongNumber - 1) * strongStepY),
    );
  }

  static Offset calibratePoint(Offset rawPoint) {
    return Offset(
      (rawPoint.dx * globalScaleX) + globalOffsetX,
      (rawPoint.dy * globalScaleY) + globalOffsetY,
    );
  }

  static Iterable<Offset> getAllRegularAnchorPositions(int tableIndex) sync* {
    for (int number = 1; number <= 37; number++) {
      yield getRegularNumberPosition(tableIndex, number);
    }
  }

  static Iterable<Offset> getAllStrongAnchorPositions(int tableIndex) sync* {
    for (int number = 1; number <= 7; number++) {
      yield getStrongNumberPosition(tableIndex, number);
    }
  }

  static List<List<int?>> buildDebugSampleRows() {
    final List<List<int?>> rows =
        List<List<int?>>.generate(14, (_) => List<int?>.filled(7, null));

    rows[0] = <int?>[1, 10, 11, 20, 21, 37, 7];
    rows[1] = <int?>[8, 13, 15, 27, 28, 31, 3];

    return rows;
  }

  static _RegularCell _mapRegularCell(int number) {
    if (number <= 10) {
      return _RegularCell(rowIndex: 0, columnIndex: number - 1);
    }
    if (number <= 20) {
      return _RegularCell(rowIndex: 1, columnIndex: number - 11);
    }
    if (number <= 30) {
      return _RegularCell(rowIndex: 2, columnIndex: number - 21);
    }
    return _RegularCell(rowIndex: 3, columnIndex: number - 31);
  }
}

class _RegularCell {
  const _RegularCell({
    required this.rowIndex,
    required this.columnIndex,
  });

  final int rowIndex;
  final int columnIndex;
}
