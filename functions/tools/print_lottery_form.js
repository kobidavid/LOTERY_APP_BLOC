#!/usr/bin/env node

const path = require("path");

const {
  DEFAULT_TEMPLATE_PDF_PATH,
  initializeFirebaseAdmin,
  loadFormFromFirestore,
  renderFormToPdf,
  validatePrintableForm,
} = require("./lottery_print_service");

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    printHelp();
    process.exit(0);
  }

  initializeFirebaseAdmin({
    serviceAccountPath: args.serviceAccount,
    projectId: args.projectId,
  });

  const firestore = require("firebase-admin").firestore();

  const {ref, data} = await loadFormFromFirestore({
    firestore,
    formId: args.formId,
    userId: args.userId,
    formPath: args.path,
  });

  validatePrintableForm(data);

  const outPath = path.resolve(args.out || defaultOutputPath(data, ref.id));
  const templatePath = path.resolve(args.template || DEFAULT_TEMPLATE_PDF_PATH);

  const result = await renderFormToPdf({
    formData: data,
    templatePdfPath: templatePath,
    outPath,
    renderMode: args.renderMode || "clean",
    calibrationMode: args.calibrationMode || (args.calibrationSheet ? "strong-only" : "none"),
    debug: Boolean(args.debug),
    debugLabels: Boolean(args.debugLabels),
  });

  // eslint-disable-next-line no-console
  console.log("Lottery form PDF generated successfully.");
  // eslint-disable-next-line no-console
  console.log(`Project ID: ${args.projectId || process.env.GCLOUD_PROJECT || "lotogroup-1ea8a"}`);
  // eslint-disable-next-line no-console
  console.log(`Firestore path: ${ref.path}`);
  // eslint-disable-next-line no-console
  console.log(`Template PDF: ${result.templatePdfPath}`);
  // eslint-disable-next-line no-console
  console.log(`Render mode: ${result.renderMode}`);
  // eslint-disable-next-line no-console
  console.log(`Calibration mode: ${result.calibrationMode}`);
  // eslint-disable-next-line no-console
  console.log(`Output PDF: ${outPath}`);
  // eslint-disable-next-line no-console
  console.log(`Debug mode: ${Boolean(args.debug)}`);
}

function parseArgs(argv) {
  const args = {};

  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    switch (arg) {
      case "--userId":
        args.userId = argv[++index];
        break;
      case "--formId":
        args.formId = argv[++index];
        break;
      case "--path":
        args.path = argv[++index];
        break;
      case "--out":
        args.out = argv[++index];
        break;
      case "--template":
        args.template = argv[++index];
        break;
      case "--renderMode":
        args.renderMode = argv[++index];
        break;
      case "--projectId":
        args.projectId = argv[++index];
        break;
      case "--calibration-sheet":
        args.calibrationSheet = true;
        break;
      case "--calibration-mode":
        args.calibrationMode = argv[++index];
        break;
      case "--serviceAccount":
        args.serviceAccount = argv[++index];
        break;
      case "--debug":
        args.debug = true;
        break;
      case "--debug-labels":
        args.debugLabels = true;
        break;
      case "--help":
      case "-h":
        args.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!args.help && !args.path && !args.formId) {
    throw new Error("Provide --formId or --path.");
  }

  return args;
}

function defaultOutputPath(formData, refId) {
  const baseName = `${formData.userId || "user"}_${formData.formId || refId}.pdf`;
  return path.join(process.cwd(), "output", baseName);
}

function printHelp() {
  // eslint-disable-next-line no-console
  console.log(`Usage:
  node tools/print_lottery_form.js --userId <USER_ID> --formId <FORM_ID> --out output/form.pdf
  node tools/print_lottery_form.js --path users/<USER_ID>/forms/<FORM_ID> --out output/form.pdf

Options:
  --userId <USER_ID>          Firestore user ID
  --formId <FORM_ID>          Firestore form ID
  --path <DOC_PATH>           Direct Firestore document path
  --out <FILE_PATH>           Output PDF path
  --template <PDF_PATH>       Source template PDF path
  --renderMode <MODE>         clean | template (default: clean)
  --calibration-sheet         Legacy alias for --calibration-mode strong-only
  --calibration-mode <MODE>   none | strong-only | full-page
  --projectId <PROJECT_ID>    Firebase project ID (default: lotogroup-1ea8a)
  --serviceAccount <JSON>     Service account JSON path
  --debug                     Draw anchor dots and sample marks
  --debug-labels              Draw coordinate labels in debug mode
  --help                      Show this help
`);
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error("Failed to generate lottery print PDF.");
  // eslint-disable-next-line no-console
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
