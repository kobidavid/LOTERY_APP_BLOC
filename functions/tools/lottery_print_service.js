const fs = require("fs/promises");
const path = require("path");

const admin = require("firebase-admin");
const {PDFDocument, rgb, StandardFonts} = require("pdf-lib");

const CM_TO_PT = 28.3465;
const A4_WIDTH_PT = cmToPt(21.0);
const A4_HEIGHT_PT = cmToPt(29.7);

const REGULAR_GRID_START_X_CM = 0.50;
const REGULAR_COL_STEP_X_CM = 0.663;
const REGULAR_FIRST_ROW_Y_CM = 2.50;
const REGULAR_UNIFIED_STEP_Y_CM = 0.387;

const STRONG_RIGHT_X_CM = 7.6;
const STRONG_LEFT_X_CM = 7.0;

const LINE_WIDTH_CM = 0.35;
const LINE_HEIGHT_CM = 0.15;
const REGULAR_LINE_LENGTH_PT = cmToPt(LINE_WIDTH_CM);
const STRONG_LINE_LENGTH_PT = cmToPt(LINE_WIDTH_CM);

const DEBUG_ANCHOR_RADIUS = 2.2;
const STROKE_WIDTH = cmToPt(LINE_HEIGHT_CM) / 2;
const GLOBAL_SCALE_Y = 1.01;
const GLOBAL_OFFSET_Y_CM = 0;

const DEFAULT_PROJECT_ID = "lotogroup-1ea8a";
const DEFAULT_TEMPLATE_PDF_PATH = path.join(
    process.env.HOME || "",
    "Downloads",
    "Scanned Document.pdf",
);

function initializeFirebaseAdmin({serviceAccountPath, projectId} = {}) {
  if (admin.apps.length > 0) {
    return admin.app();
  }

  const resolvedProjectId = projectId || process.env.GCLOUD_PROJECT || DEFAULT_PROJECT_ID;
  if (serviceAccountPath) {
    // eslint-disable-next-line global-require, import/no-dynamic-require
    const serviceAccount = require(path.resolve(serviceAccountPath));
    return admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: resolvedProjectId,
    });
  }

  return admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: resolvedProjectId,
  });
}

function getRegularNumberPosition(tableIndex, number) {
  return getRegularNumberPositionCm(tableIndex, number);
}

function getRegularNumberPositionCm(tableIndex, number) {
  if (tableIndex < 0 || tableIndex > 13) {
    throw new Error(`Invalid tableIndex ${tableIndex}`);
  }
  if (number < 1 || number > 37) {
    throw new Error(`Invalid regular number ${number}`);
  }

  let rowIndex;
  let columnIndex;

  if (number >= 1 && number <= 7) {
    rowIndex = 0;
    columnIndex = (number - 1) + 3;
  } else if (number >= 8 && number <= 17) {
    rowIndex = 1;
    columnIndex = number - 8;
  } else if (number >= 18 && number <= 27) {
    rowIndex = 2;
    columnIndex = number - 18;
  } else {
    rowIndex = 3;
    columnIndex = number - 28;
  }

  return {
    x: REGULAR_GRID_START_X_CM + (columnIndex * REGULAR_COL_STEP_X_CM),
    y: REGULAR_FIRST_ROW_Y_CM +
      (((tableIndex * 4) + rowIndex) * REGULAR_UNIFIED_STEP_Y_CM),
  };
}

function getStrongNumberPosition(tableIndex, strongNumber) {
  return getStrongNumberPositionCm(tableIndex, strongNumber);
}

function getStrongNumberPositionCm(tableIndex, strongNumber) {
  if (tableIndex < 0 || tableIndex > 13) {
    throw new Error(`Invalid tableIndex ${tableIndex}`);
  }
  if (strongNumber < 1 || strongNumber > 7) {
    throw new Error(`Invalid strong number ${strongNumber}`);
  }

  const strongLayout = [
    null,
    {x: STRONG_RIGHT_X_CM, rowIndex: 0},
    {x: STRONG_LEFT_X_CM, rowIndex: 1},
    {x: STRONG_RIGHT_X_CM, rowIndex: 1},
    {x: STRONG_LEFT_X_CM, rowIndex: 2},
    {x: STRONG_RIGHT_X_CM, rowIndex: 2},
    {x: STRONG_LEFT_X_CM, rowIndex: 3},
    {x: STRONG_RIGHT_X_CM, rowIndex: 3},
  ];
  const mapped = strongLayout[strongNumber];
  const globalRowIndex = (tableIndex * 4) + mapped.rowIndex;

  return {
    x: mapped.x,
    y: REGULAR_FIRST_ROW_Y_CM + (globalRowIndex * REGULAR_UNIFIED_STEP_Y_CM),
  };
}

function calibratePoint(rawPoint) {
  return {
    x: cmToPt(rawPoint.x),
    y: cmToPt((rawPoint.y * GLOBAL_SCALE_Y) + GLOBAL_OFFSET_Y_CM),
  };
}

function getLineSegmentCm(xCenter, yCenter, lineWidthCm = LINE_WIDTH_CM) {
  const halfWidth = lineWidthCm / 2;
  return {
    startX: xCenter - halfWidth,
    endX: xCenter + halfWidth,
    y: yCenter,
  };
}

function cmToPt(cm) {
  return cm * CM_TO_PT;
}

async function loadFormFromFirestore({
  firestore,
  formId,
  userId,
  formPath,
}) {
  if (formPath) {
    const snapshot = await firestore.doc(formPath).get();
    if (!snapshot.exists) {
      throw new Error(`Form not found at path ${formPath}`);
    }
    return {ref: snapshot.ref, data: snapshot.data()};
  }

  if (userId && formId) {
    const snapshot = await firestore
        .collection("users")
        .doc(userId)
        .collection("forms")
        .doc(formId)
        .get();
    if (!snapshot.exists) {
      throw new Error(`Form ${formId} not found for user ${userId}`);
    }
    return {ref: snapshot.ref, data: snapshot.data()};
  }

  if (!formId) {
    throw new Error("Either formPath or formId must be provided.");
  }

  const snapshot = await firestore
      .collectionGroup("forms")
      .where("formId", "==", formId)
      .limit(2)
      .get();

  if (snapshot.empty) {
    throw new Error(`Form ${formId} was not found.`);
  }
  if (snapshot.docs.length > 1) {
    throw new Error(`Form ${formId} is ambiguous. Pass --userId or --path.`);
  }

  return {ref: snapshot.docs[0].ref, data: snapshot.docs[0].data()};
}

function validatePrintableForm(formData) {
  if (!formData || typeof formData !== "object") {
    throw new Error("Form payload is missing.");
  }

  if (!Array.isArray(formData.tables) || formData.tables.length === 0) {
    throw new Error("Form tables are missing.");
  }

  if (formData.status !== "submitted" && formData.status !== "saved") {
    throw new Error(`Form status ${formData.status} is not printable.`);
  }

  formData.tables.forEach((table, index) => {
    if (!table || typeof table !== "object") {
      throw new Error(`Table ${index + 1} is malformed.`);
    }

    if (!Array.isArray(table.regularNumbers)) {
      throw new Error(`Table ${index + 1} regularNumbers are malformed.`);
    }

    if (table.regularNumbers.some((number) => !Number.isInteger(number) || number < 1 || number > 37)) {
      throw new Error(`Table ${index + 1} contains invalid regular numbers.`);
    }

    if (table.regularNumbers.length > 6) {
      throw new Error(`Table ${index + 1} has too many regular numbers.`);
    }

    if (table.strongNumber != null &&
      (!Number.isInteger(table.strongNumber) || table.strongNumber < 1 || table.strongNumber > 7)) {
      throw new Error(`Table ${index + 1} has an invalid strong number.`);
    }
  });
}

async function renderFormToPdf({
  formData,
  templatePdfPath = DEFAULT_TEMPLATE_PDF_PATH,
  outPath,
  renderMode = "clean",
  calibrationMode = "none",
  debug = false,
  debugLabels = false,
}) {
  const pdfDocument = await createBasePdfDocument({
    renderMode,
    templatePdfPath,
  });
  const page = pdfDocument.getPage(0);
  const pageHeight = page.getHeight();
  const pageWidth = page.getWidth();

  const font = await pdfDocument.embedFont(StandardFonts.Helvetica);

  if (debug) {
    drawDebugGrid({page, pageWidth, pageHeight});
  }
  drawDebugTemplateBounds({page, pageHeight, debug});
  if (calibrationMode !== "none") {
    drawCalibrationSheet({page, pageHeight, font, calibrationMode});
  } else {
    drawFormMarks({page, pageHeight, formData, debug, debugLabels, font});
  }

  const outputBytes = await pdfDocument.save();
  if (outPath) {
    await savePdf(outputBytes, outPath);
  }

  return {
    pdfBytes: outputBytes,
    pageWidth,
    pageHeight,
    renderMode,
    calibrationMode,
    templatePdfPath,
    outPath,
  };
}

async function createBasePdfDocument({renderMode, templatePdfPath}) {
  if (renderMode === "template") {
    const pdfBytes = await fs.readFile(templatePdfPath);
    return PDFDocument.load(pdfBytes);
  }

  if (renderMode !== "clean") {
    throw new Error(`Unsupported renderMode: ${renderMode}`);
  }

  const pdfDocument = await PDFDocument.create();
  pdfDocument.addPage([A4_WIDTH_PT, A4_HEIGHT_PT]);
  return pdfDocument;
}

function drawFormMarks({
  page,
  pageHeight,
  formData,
  debug,
  debugLabels,
  font,
}) {
  const tables = formData.tables;
  tables.forEach((table, tableIndex) => {
    table.regularNumbers.forEach((number) => {
      const point = calibratePoint(getRegularNumberPosition(tableIndex, number));
      drawHorizontalMark(page, pageHeight, point, REGULAR_LINE_LENGTH_PT);
      if (debug) {
        drawAnchorDot(page, pageHeight, point, rgb(1, 0.4, 0));
      }
      if (debugLabels) {
        drawLabel(page, pageHeight, point, `${tableIndex + 1}:${number}`, font);
      }
    });

    if (table.strongNumber != null) {
      const point = calibratePoint(
          getStrongNumberPosition(tableIndex, table.strongNumber),
      );
      drawHorizontalMark(page, pageHeight, point, STRONG_LINE_LENGTH_PT);
      if (debug) {
        drawAnchorDot(page, pageHeight, point, rgb(0, 0.6, 0.2));
      }
      if (debugLabels) {
        drawLabel(page, pageHeight, point, `S${table.strongNumber}`, font);
      }
    }
  });

  if (debug) {
    buildDebugSampleRows().forEach((row, tableIndex) => {
      row.slice(0, 6).filter(Boolean).forEach((number) => {
        const point = calibratePoint(getRegularNumberPosition(tableIndex, number));
        drawHorizontalMark(page, pageHeight, point, REGULAR_LINE_LENGTH_PT, {
          color: rgb(0.1, 0.2, 0.9),
        });
      });

      if (row[6] != null) {
        const point = calibratePoint(getStrongNumberPosition(tableIndex, row[6]));
        drawHorizontalMark(page, pageHeight, point, STRONG_LINE_LENGTH_PT, {
          color: rgb(0.1, 0.2, 0.9),
        });
      }
    });
  }
}

function drawCalibrationSheet({page, pageHeight, font, calibrationMode}) {
  const anchors = buildCalibrationAnchors(calibrationMode);
  anchors.forEach((anchor) => {
    const rawPoint = anchor.type === "strong" ?
      getStrongNumberPosition(anchor.tableIndex, anchor.number) :
      getRegularNumberPosition(anchor.tableIndex, anchor.number);
    const point = calibratePoint(rawPoint);
    const lineLength = anchor.type === "strong" ? STRONG_LINE_LENGTH_PT : REGULAR_LINE_LENGTH_PT;
    drawHorizontalMark(page, pageHeight, point, lineLength);
    drawLabel(page, pageHeight, point, anchor.label, font, {
      xOffset: 8,
      yOffset: 2,
      color: rgb(0.1, 0.1, 0.1),
    });
  });
}

function drawHorizontalMark(page, pageHeight, point, lineLength, options = {}) {
  const halfLength = lineLength / 2;
  const pdfY = pageHeight - point.y;
  page.drawLine({
    start: {x: point.x - halfLength, y: pdfY},
    end: {x: point.x + halfLength, y: pdfY},
    thickness: STROKE_WIDTH,
    color: options.color || rgb(0, 0, 0),
  });
}

function drawAnchorDot(page, pageHeight, point, color) {
  page.drawCircle({
    x: point.x,
    y: pageHeight - point.y,
    size: DEBUG_ANCHOR_RADIUS,
    color,
  });
}

function drawLabel(page, pageHeight, point, text, font, options = {}) {
  page.drawText(text, {
    x: point.x + (options.xOffset ?? 3),
    y: pageHeight - point.y + (options.yOffset ?? 3),
    size: options.size ?? 6,
    font,
    color: options.color || rgb(0, 0, 1),
  });
}

function drawDebugTemplateBounds({page, pageHeight, debug}) {
  if (!debug) {
    return;
  }

  page.drawRectangle({
    x: 0,
    y: 0,
    width: page.getWidth(),
    height: pageHeight,
    borderColor: rgb(1, 0, 0),
    borderWidth: 0.8,
  });
}

function drawDebugGrid({page, pageWidth, pageHeight}) {
  const step = cmToPt(1);
  const color = rgb(0.85, 0.85, 0.85);

  for (let x = step; x < pageWidth; x += step) {
    page.drawLine({
      start: {x, y: 0},
      end: {x, y: pageHeight},
      thickness: 0.5,
      color,
      opacity: 0.7,
    });
  }

  for (let y = step; y < pageHeight; y += step) {
    page.drawLine({
      start: {x: 0, y},
      end: {x: pageWidth, y},
      thickness: 0.5,
      color,
      opacity: 0.7,
    });
  }
}

function buildDebugSampleRows() {
  const rows = Array.from({length: 14}, () => Array(7).fill(null));
  rows[0] = [1, 10, 11, 20, 21, 37, 7];
  rows[1] = [8, 13, 15, 27, 28, 31, 3];
  return rows;
}

function buildCalibrationAnchors(calibrationMode) {
  if (calibrationMode === "strong-only") {
    return [
      {type: "strong", tableIndex: 0, number: 1, label: "T1-S1"},
      {type: "strong", tableIndex: 0, number: 2, label: "T1-S2"},
      {type: "strong", tableIndex: 0, number: 3, label: "T1-S3"},
      {type: "strong", tableIndex: 0, number: 4, label: "T1-S4"},
      {type: "strong", tableIndex: 0, number: 5, label: "T1-S5"},
      {type: "strong", tableIndex: 0, number: 6, label: "T1-S6"},
      {type: "strong", tableIndex: 0, number: 7, label: "T1-S7"},
    ];
  }

  if (calibrationMode === "full-page") {
    const anchors = [];
    for (let tableIndex = 0; tableIndex < 14; tableIndex++) {
      const tableLabel = `T${tableIndex + 1}`;
      anchors.push(
          {type: "regular", tableIndex, number: 1, label: `${tableLabel}-1`},
          {type: "regular", tableIndex, number: 11, label: `${tableLabel}-11`},
          {type: "regular", tableIndex, number: 21, label: `${tableLabel}-21`},
          {type: "regular", tableIndex, number: 31, label: `${tableLabel}-31`},
          {type: "strong", tableIndex, number: 1, label: `${tableLabel}-S1`},
          {type: "strong", tableIndex, number: 2, label: `${tableLabel}-S2`},
          {type: "strong", tableIndex, number: 3, label: `${tableLabel}-S3`},
          {type: "strong", tableIndex, number: 4, label: `${tableLabel}-S4`},
      );
    }
    return anchors;
  }

  throw new Error(`Unsupported calibrationMode: ${calibrationMode}`);
}

async function savePdf(pdfBytes, outPath) {
  await fs.mkdir(path.dirname(outPath), {recursive: true});
  await fs.writeFile(outPath, pdfBytes);
}

module.exports = {
  A4_HEIGHT_PT,
  A4_WIDTH_PT,
  DEFAULT_TEMPLATE_PDF_PATH,
  calibratePoint,
  cmToPt,
  getLineSegmentCm,
  getRegularNumberPosition,
  getRegularNumberPositionCm,
  getStrongNumberPosition,
  getStrongNumberPositionCm,
  initializeFirebaseAdmin,
  loadFormFromFirestore,
  renderFormToPdf,
  savePdf,
  validatePrintableForm,
};
