(function() {
  const pdfScriptVersion = "3.11.174";
  const pdfWorkerSrc =
      `https://cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfScriptVersion}/pdf.worker.min.js`;

  async function recognizeImage(imageSource) {
    const result = await window.Tesseract.recognize(
        imageSource,
        "heb+eng",
        {
          logger: () => {},
        },
    );
    return (result && result.data && result.data.text) ?
      String(result.data.text).trim() :
      "";
  }

  function decodeBase64(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  }

  async function extractPdfText(bytes) {
    if (!window.pdfjsLib) {
      throw new Error("PDF.js is not available.");
    }

    window.pdfjsLib.GlobalWorkerOptions.workerSrc = pdfWorkerSrc;
    const loadingTask = window.pdfjsLib.getDocument({data: bytes});
    const pdfDocument = await loadingTask.promise;
    const textParts = [];

    for (let pageNumber = 1; pageNumber <= pdfDocument.numPages; pageNumber += 1) {
      const page = await pdfDocument.getPage(pageNumber);
      const viewport = page.getViewport({scale: 2});
      const canvas = document.createElement("canvas");
      const context = canvas.getContext("2d");
      canvas.width = Math.ceil(viewport.width);
      canvas.height = Math.ceil(viewport.height);
      await page.render({
        canvasContext: context,
        viewport,
      }).promise;
      const pageText = await recognizeImage(canvas.toDataURL("image/png"));
      if (pageText) {
        textParts.push(pageText);
      }
    }

    return textParts.join("\n").trim();
  }

  async function extractImageText(bytes, contentType) {
    const mimeType = contentType && contentType.startsWith("image/") ?
      contentType :
      "image/png";
    const blob = new Blob([bytes], {type: mimeType});
    const objectUrl = URL.createObjectURL(blob);
    try {
      return await recognizeImage(objectUrl);
    } finally {
      URL.revokeObjectURL(objectUrl);
    }
  }

  window.receiptOcr = {
    extractText: async function(base64, contentType, fileName) {
      if (!window.Tesseract) {
        throw new Error("Tesseract.js is not available.");
      }

      const normalizedType = String(contentType || "").toLowerCase();
      const normalizedFileName = String(fileName || "").toLowerCase();
      const bytes = decodeBase64(String(base64 || ""));

      if (normalizedType === "application/pdf" || normalizedFileName.endsWith(".pdf")) {
        return extractPdfText(bytes);
      }

      return extractImageText(bytes, normalizedType);
    },
  };
})();
