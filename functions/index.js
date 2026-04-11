const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const cheerio = require("cheerio");
const crypto = require("crypto");
const fetch = require("node-fetch");

admin.initializeApp();

const firestore = admin.firestore();

const PAIS_NEXT_LOTTERY_URL =
  "https://www.pais.co.il/include/getNextLotteryDate.ashx?type=1";
const PAIS_CURRENT_LOTTO_URL =
  "https://www.pais.co.il/Lotto/CurrentLotto.aspx?lotteryId=";
const HTTP_TIMEOUT_MS = 5000;
const HTTP_RETRY_ATTEMPTS = 3;
const ADMIN_SECRET_HEADER = "x-admin-secret";
const EXPECTED_TABLE_COUNT = 14;
const MAX_TABLES_JSON_LENGTH = 12000;
const RESULT_STATUS = {
  waiting: "waiting_for_results",
  checked: "checked",
  winner: "winner",
  loser: "loser",
};
const TICKET_TYPES = {
  regularLotto: "regular_lotto",
  doubleLotto: "double_lotto",
};
const PRIZE_TABLE_KEYS = {
  regularLotto: "regularLottoPrizeTable",
  doubleLotto: "doubleLottoPrizeTable",
};
const PRIZE_CATEGORIES = [
  "6 + חזק",
  "5 + חזק",
  "4 + חזק",
  "3 + חזק",
  "6",
  "5",
  "4",
  "3",
];

exports.sendMail = functions.https.onCall((data) => {
  const {to, subject, text, html} = data;

  if (!to || !subject) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required parameters.",
    );
  }

  const mailRef = firestore.collection("mail");

  if (text || html) {
    mailRef.add({
      to,
      message: {
        subject,
        text,
        html,
      },
    });
  }

  return {success: true};
});

exports.sendVerificationCode = functions.https.onCall((data) => {
  const {to, subject, text} = data;

  if (!to || !subject || !text) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required parameters.",
    );
  }

  const verificationCode = Math.floor(Math.random() * 9000) + 1000;

  const mailRef = firestore.collection("mail");

  mailRef.add({
    to,
    message: {
      subject,
      text: `${text} ${verificationCode}`,
    },
  });

  return {success: true, verificationCode};
});

exports.submitLotteryForm = functions.https.onCall(async (data, context) => {
  try {
    const authenticatedUserId = await resolveAuthenticatedUserId(data, context);
    if (!authenticatedUserId) {
      throw new functions.https.HttpsError(
          "unauthenticated",
          "Authentication is required.",
      );
    }

    validateSubmitPayload(data);
    const tables = normalizeTables(data.tables);
    if (!isSubmittedFormValid(tables)) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "Submitted lottery form is invalid.",
      );
    }

    const nextLottery = await fetchNextLotteryMetadata();
    const ticketFingerprintSource = buildTicketFingerprintSource({
      lotteryId: nextLottery.lotteryId,
      tables,
    });
    const ticketFingerprint = crypto
        .createHash("sha256")
        .update(ticketFingerprintSource, "utf8")
        .digest("hex");
    console.log("Fingerprint source:", ticketFingerprintSource);
    console.log("Fingerprint hash:", ticketFingerprint);
    console.log(
        "submitLotteryForm assigned lotteryId",
        nextLottery.lotteryId,
        "to user",
        authenticatedUserId,
    );

    const formRef = firestore
        .collection("users")
        .doc(authenticatedUserId)
        .collection("forms")
        .doc();

    const now = admin.firestore.FieldValue.serverTimestamp();
    await formRef.set({
      formId: formRef.id,
      userId: authenticatedUserId,
      status: "submitted",
      createdAt: now,
      updatedAt: now,
      submittedAt: now,
      savedAt: null,
      tables,
      isComplete: true,
      source: typeof data.source === "string" ? data.source : "manual",
      version: typeof data.version === "number" ? data.version : 1,
      lotteryId: nextLottery.lotteryId,
      salesCloseAt: nextLottery.salesCloseAt,
      resultStatus: RESULT_STATUS.waiting,
      resultPublishedAt: null,
      winAmount: 0,
      checkedAt: null,
      balanceApplied: false,
      ticketFingerprintSource,
      ticketFingerprint,
      fingerprintVersion: 1,
    });

    return {formId: formRef.id};
  } catch (error) {
    console.error("submitLotteryForm failed", error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
        "internal",
        "Lottery form submission failed.",
    );
  }
});

async function resolveAuthenticatedUserId(data, context) {
  if (context.auth && context.auth.uid) {
    console.log("submitLotteryForm authenticated via callable context", context.auth.uid);
    return context.auth.uid;
  }

  const idToken = data && typeof data === "object" ? data.idToken : null;
  if (typeof idToken === "string" && idToken.trim().length > 0) {
    try {
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      console.log(
          "submitLotteryForm authenticated via explicit idToken",
          decodedToken.uid,
      );
      return decodedToken.uid;
    } catch (error) {
      console.error("submitLotteryForm idToken verification failed", error);
    }
  }

  console.error("submitLotteryForm authentication missing", {
    hasContextAuth: Boolean(context.auth),
    hasIdToken: typeof idToken === "string" && idToken.trim().length > 0,
  });
  return null;
}

exports.checkLotteryResults = functions.pubsub
    .schedule("every 1 hours")
    .timeZone("Asia/Jerusalem")
    .onRun(async () => {
      try {
        await processWaitingLotteryResults();
      } catch (error) {
        console.error("checkLotteryResults scheduler failed", error);
      }
      return null;
    });

exports.checkLotteryResultsNow = functions.https.onCall(async (_, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError(
          "unauthenticated",
          "Authentication is required.",
      );
    }

    await processWaitingLotteryResults();
    return {success: true};
  } catch (error) {
    console.error("checkLotteryResultsNow failed", error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
        "internal",
        "Manual lottery result check failed.",
    );
  }
});

exports.checkLotteryResultsAdmin = functions
    .runWith({secrets: ["LOTTO_ADMIN_SECRET"]})
    .https.onRequest(async (req, res) => {
      let failureStage = "admin-trigger-start";
      try {
        console.log("checkLotteryResultsAdmin start", {
          method: req.method,
          hasSecretHeader: Boolean(req.get(ADMIN_SECRET_HEADER)),
          userAgent: req.get("user-agent") || null,
        });
        const configuredSecret = getAdminCheckSecret();
        const providedSecret = req.get(ADMIN_SECRET_HEADER);

        if (!configuredSecret) {
          console.error("checkLotteryResultsAdmin missing configured admin secret");
          return res.status(500).json({
            success: false,
            error: "admin-secret-not-configured",
          });
        }

        if (!providedSecret) {
          console.error("checkLotteryResultsAdmin missing admin secret header");
          return res.status(401).json({
            success: false,
            error: "missing-admin-secret",
          });
        }

        if (providedSecret !== configuredSecret) {
          console.error("checkLotteryResultsAdmin invalid admin secret");
          return res.status(403).json({
            success: false,
            error: "invalid-admin-secret",
          });
        }

        failureStage = "process-waiting-results";
        await processWaitingLotteryResults();
        return res.status(200).json({
          success: true,
          message: "Lottery results processed.",
        });
      } catch (error) {
        console.error("checkLotteryResultsAdmin failed", {
          stage: failureStage,
          message: error && error.message ? error.message : String(error),
          stack: error && error.stack ? error.stack : null,
        });
        return res.status(500).json({
          success: false,
          error: "lottery-result-check-failed",
          stage: failureStage,
          message: error && error.message ? error.message : String(error),
          stack: error && error.stack ? error.stack : null,
        });
      }
    });

async function processWaitingLotteryResults() {
  try {
    const snapshot = await firestore
        .collectionGroup("forms")
        .where("status", "==", "submitted")
        .where("resultStatus", "==", RESULT_STATUS.waiting)
        .get();

    console.log("processWaitingLotteryResults found forms", snapshot.size);

    if (snapshot.empty) {
      return;
    }

    const formsByLotteryId = new Map();
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const lotteryId = Number(data.lotteryId);
      if (!Number.isFinite(lotteryId)) {
        console.error("Skipping form with invalid lotteryId", doc.id, data.lotteryId);
        continue;
      }

      if (!formsByLotteryId.has(lotteryId)) {
        formsByLotteryId.set(lotteryId, []);
      }

      formsByLotteryId.get(lotteryId).push(doc);
    }

    console.log(
        "processWaitingLotteryResults lotteryIds",
        Array.from(formsByLotteryId.keys()).join(","),
    );

    for (const [lotteryId, docs] of formsByLotteryId.entries()) {
      try {
        console.log(
            "processWaitingLotteryResults fetching lottery result",
            lotteryId,
            "forms=",
            docs.length,
        );
        const result = await fetchLotteryResult(lotteryId);
        if (!result) {
          console.log("No published results yet for lotteryId", lotteryId);
          continue;
        }

        for (const doc of docs) {
          try {
            console.log(
                "processWaitingLotteryResults processing form",
                doc.id,
                "lotteryId=",
                lotteryId,
            );
            await applyLotteryResultToForm(doc.ref, doc.data(), result);
          } catch (error) {
            console.error("applyLotteryResultToForm failed", {
              formId: doc.id,
              lotteryId,
              message: error && error.message ? error.message : String(error),
              stack: error && error.stack ? error.stack : null,
            });
          }
        }
      } catch (error) {
        console.error("fetchLotteryResult group failed", {
          lotteryId,
          message: error && error.message ? error.message : String(error),
          stack: error && error.stack ? error.stack : null,
        });
      }
    }
  } catch (error) {
    console.error("processWaitingLotteryResults failed", {
      message: error && error.message ? error.message : String(error),
      stack: error && error.stack ? error.stack : null,
    });
    throw error;
  }
}

// Splits winAmount across paidParticipants by costShare (proportional).
// When all costShare values are equal, divides exactly to avoid float drift.
// The last participant absorbs any rounding remainder so the total is exact.
function computeWinAllocations(winAmount, paidParticipants) {
  const n = paidParticipants.length;
  const costShares = paidParticipants.map((p) => Number(p.costShare) || 0);
  const totalCost = costShares.reduce((s, c) => s + c, 0);
  const allEqual = costShares.every((s) => s === costShares[0]);

  const allocations = [];
  let distributed = 0;

  for (let i = 0; i < n; i++) {
    let amount;
    if (i === n - 1) {
      // Last participant absorbs any rounding remainder.
      amount = Math.round((winAmount - distributed) * 100) / 100;
    } else if (allEqual || totalCost === 0) {
      // Equal split — floor to agora to never exceed winAmount.
      amount = Math.floor((winAmount / n) * 100) / 100;
    } else {
      // Proportional split — floor to agora.
      amount = Math.floor((winAmount * (costShares[i] / totalCost)) * 100) / 100;
    }
    distributed += amount;
    allocations.push({userId: paidParticipants[i].userId, amount});
  }

  return allocations;
}

async function applyLotteryResultToForm(formRef, formData, result) {
  try {
    const tables = normalizeTables(formData.tables);
    const ticketType = getTicketTypeForForm(formData);
    const winAmount = tables.reduce(
        (sum, table) => sum + calculateTablePrize(table, result, ticketType),
        0,
    );
    console.log("applyLotteryResultToForm winAmount", formRef.id, winAmount);
    const resultStatus =
      winAmount > 0 ? RESULT_STATUS.winner : RESULT_STATUS.loser;
    const checkedAt = admin.firestore.Timestamp.now();

    await firestore.runTransaction(async (transaction) => {
      const freshSnapshot = await transaction.get(formRef);
      if (!freshSnapshot.exists) {
        return;
      }

      const freshData = freshSnapshot.data() || {};
      const alreadyApplied = freshData.balanceApplied === true;
      const updates = {
        resultStatus,
        winAmount,
        checkedAt,
        resultPublishedAt: result.resultPublishedAt,
        updatedAt: checkedAt,
      };

      if (winAmount > 0 && !alreadyApplied) {
        const isGroupForm = freshData.submissionType === "group";
        const paidParticipants = Array.isArray(freshData.paidParticipants)
            ? freshData.paidParticipants
            : [];

        if (isGroupForm && paidParticipants.length >= 2) {
          // Group form: split winnings across all paid participants by costShare.
          const allocations = computeWinAllocations(winAmount, paidParticipants);
          updates.winAllocations = allocations;
          for (const allocation of allocations) {
            const participantUserRef = firestore
                .collection("users")
                .doc(allocation.userId);
            transaction.set(participantUserRef, {
              balance: admin.firestore.FieldValue.increment(allocation.amount),
            }, {merge: true});
            console.log(
                "applyLotteryResultToForm group allocation",
                formRef.id,
                "userId=", allocation.userId,
                "amount=", allocation.amount,
            );
          }
          console.log(
              "applyLotteryResultToForm group balance applied",
              formRef.id,
              "winAmount=", winAmount,
              "participants=", paidParticipants.length,
          );
        } else {
          // Personal form (or group with a single participant): credit form owner.
          const userRef = formRef.parent.parent;
          transaction.set(userRef, {
            balance: admin.firestore.FieldValue.increment(winAmount),
          }, {merge: true});
          console.log("applyLotteryResultToForm balance applied", formRef.id, winAmount);
        }

        updates.balanceApplied = true;
      } else {
        updates.balanceApplied = alreadyApplied;
        console.log(
            "applyLotteryResultToForm balance skipped",
            formRef.id,
            "alreadyApplied=",
            alreadyApplied,
            "winAmount=",
            winAmount,
        );
      }

      transaction.update(formRef, updates);
    });
  } catch (error) {
    console.error("applyLotteryResultToForm failed", formRef.id, error);
    throw error;
  }
}

async function fetchNextLotteryMetadata() {
  try {
    console.log("fetchNextLotteryMetadata request", PAIS_NEXT_LOTTERY_URL);
    const response = await fetchWithRetry(PAIS_NEXT_LOTTERY_URL, {
      headers: {"accept": "application/json,text/plain,*/*"},
    });
    console.log("fetchNextLotteryMetadata response status", response.status);

    if (!response.ok) {
      throw new Error(`Pais next lottery request failed: ${response.status}`);
    }

    const payload = await response.json();
    console.log("fetchNextLotteryMetadata raw payload", JSON.stringify(payload));
    if (!Array.isArray(payload) || payload.length === 0) {
      throw new Error("Pais next lottery payload was empty.");
    }

    const nextLottery = payload[0];
    const lotteryId = Number(nextLottery.LotteryNumber);
    const salesCloseAt = parsePaisDateTime(
        nextLottery.nextLottoryDate,
        nextLottery.displayDate,
        nextLottery.displayTime,
    );

    if (!Number.isFinite(lotteryId) || !salesCloseAt) {
      throw new Error("Pais next lottery payload was missing required fields.");
    }

    console.log(
        "fetchNextLotteryMetadata parsed",
        lotteryId,
        nextLottery.displayDate,
        nextLottery.displayTime,
    );

    return {
      lotteryId,
      salesCloseAt,
    };
  } catch (error) {
    console.error("fetchNextLotteryMetadata failed", error);
    throw error;
  }
}

async function fetchLotteryResult(lotteryId) {
  try {
    console.log("fetchLotteryResult request", `${PAIS_CURRENT_LOTTO_URL}${lotteryId}`);
    const response = await fetchWithRetry(`${PAIS_CURRENT_LOTTO_URL}${lotteryId}`);
    console.log("fetchLotteryResult response status", lotteryId, response.status);
    if (!response.ok) {
      throw new Error(`Pais result request failed: ${response.status}`);
    }

    const html = await response.text();
    if (html.includes("דף לא נמצא")) {
      console.log("fetchLotteryResult no page found for lotteryId", lotteryId);
      return null;
    }

    const $ = cheerio.load(html);
    const regularNumbers = parseWinningNumbers($);
    const strongNumber = parseStrongNumber($);
    const dateText = $(".archive_open_dates .cat_archive_txt.open strong")
        .first()
        .text()
        .trim();
    const timeText = $(".archive_open_dates .cat_archive_txt.open.time strong")
        .first()
        .text()
        .trim();
    const parsedPrizeTables = parsePrizeTables($);
    const ticketType = TICKET_TYPES.regularLotto;
    const prizeByCategory = selectPrizeTableForTicketType(
        ticketType,
        parsedPrizeTables,
    );

    if (regularNumbers.length !== 6 || !Number.isFinite(strongNumber)) {
      console.log("fetchLotteryResult results not found yet", lotteryId);
      return null;
    }

    if (prizeByCategory.size === 0) {
      console.error(
          "fetchLotteryResult regular lotto prize table parse failed",
          lotteryId,
      );
      throw new Error("regular lotto prize table parse failed");
    }

    const resultPublishedAt = parsePaisDateTime(
        null,
        dateText || null,
        timeText || null,
    ) || admin.firestore.Timestamp.now();

    console.log(
        "fetchLotteryResult parsed results",
        lotteryId,
        regularNumbers.join(","),
        strongNumber,
    );
    console.log(
        "fetchLotteryResult selected prize table",
        ticketType,
        Array.from(prizeByCategory.keys()).join(","),
    );
    console.log(
        "fetchLotteryResult parsed prize tables",
        lotteryId,
        "regular=",
        Array.from(parsedPrizeTables.regularLottoPrizeTable.keys()).join(","),
        "double=",
        Array.from(parsedPrizeTables.doubleLottoPrizeTable.keys()).join(","),
    );

    return {
      lotteryId,
      ticketType,
      regularNumbers,
      strongNumber,
      prizeByCategory,
      parsedPrizeTables,
      resultPublishedAt,
    };
  } catch (error) {
    console.error("fetchLotteryResult failed", lotteryId, error);
    throw error;
  }
}

function parseWinningNumbers($) {
  const numbers = $(".current_lottery_numgroup .cat_h_data_group.loto.current ol.cat_data_info.current li.loto_info_num div")
      .map((_, element) => Number($(element).text().trim()))
      .get()
      .filter((value) => Number.isFinite(value))
      .slice(0, 6);

  console.log("parseWinningNumbers", numbers.join(","));
  return numbers;
}

function parseStrongNumber($) {
  const strongNumber = Number(
      $(".current_lottery_numgroup .cat_h_data_group.strong_num.current .loto_info_num.strong div")
          .first()
          .text()
          .trim(),
  );
  console.log("parseStrongNumber", strongNumber);
  return strongNumber;
}

function parsePrizeTables($) {
  const regularHeading = findHeadingByText($, "טבלת זכיות לוטו");
  const doubleHeading = findHeadingByText($, "טבלת זכיות דאבל לוטו");

  console.log(
      "parsePrizeTables heading lookup",
      "regularFound=",
      Boolean(regularHeading),
      "doubleFound=",
      Boolean(doubleHeading),
  );

  const regularLottoPrizeTable = parsePrizeTableFromHeading(
      $,
      regularHeading,
      "טבלת זכיות לוטו",
      "regular_lotto",
  );
  const doubleLottoPrizeTable = parsePrizeTableFromHeading(
      $,
      doubleHeading,
      "טבלת זכיות דאבל לוטו",
      "double_lotto",
  );

  console.log("parsePrizeTables detected", {
    regularLottoCategories: Array.from(regularLottoPrizeTable.keys()),
    doubleLottoCategories: Array.from(doubleLottoPrizeTable.keys()),
  });

  return {
    regularLottoPrizeTable,
    doubleLottoPrizeTable,
  };
}

function findHeadingByText($, headingText) {
  const candidates = $("h3.center_title.current")
      .filter((_, element) =>
        normalizePrizeCategory($(element).text()) === headingText,
      );

  const heading = candidates.first();
  if (!heading.length) {
    return null;
  }

  console.log("found heading:", headingText);
  return heading;
}

function parsePrizeTableFromHeading($, headingElement, headingText, tableName) {
  if (!headingElement || !headingElement.length) {
    console.log(`${tableName} heading missing`, headingText);
    return new Map();
  }

  console.log(
      "parsePrizeTableFromHeading heading context",
      "headingTag=",
      headingElement.prop("tagName"),
      "headingClass=",
      headingElement.attr("class") || "",
      "parentTag=",
      headingElement.parent().prop("tagName"),
      "parentClass=",
      headingElement.parent().attr("class") || "",
      "grandparentTag=",
      headingElement.parent().parent().prop("tagName"),
      "grandparentClass=",
      headingElement.parent().parent().attr("class") || "",
  );

  const rowElements = findPrizeRowsForHeading($, headingText);
  console.log(
      "selected prize table:",
      tableName,
      "heading text:",
      headingText,
      "rows parsed candidate count=",
      rowElements.length,
  );

  const prizeByCategory = new Map();
  rowElements.each((_, row) => {
    const parsedRow = parsePrizeRow($, row);
    if (!parsedRow) {
      return;
    }

    prizeByCategory.set(parsedRow.category, parsedRow.prizeAmount);
    console.log(
        "parsePrizeTableFromHeading row",
        tableName,
        "category:",
        parsedRow.category,
        "prize:",
        parsedRow.prizeAmount,
    );
  });

  if (tableName === "regular_lotto" && prizeByCategory.size === 0) {
    rowElements.slice(0, 5).each((index, row) => {
      console.log(
          "parsePrizeTableFromHeading sample row",
          tableName,
          index,
          normalizePrizeCategory($(row).text()),
      );
    });
    console.error("regular lotto prize table parse failed");
  }

  console.log(
      "parsePrizeTableFromHeading complete",
      tableName,
      "rows parsed:",
      prizeByCategory.size,
  );
  if (tableName === "regular_lotto") {
    console.log(
        "parsePrizeTableFromHeading final mapping",
        Array.from(prizeByCategory.entries())
            .map(([category, prize]) => `${category} -> ${prize}`)
            .join(" | "),
    );
  }
  return prizeByCategory;
}

function findPrizeRowsForHeading($, headingText) {
  const heading = findHeadingByText($, headingText);
  if (!heading || !heading.length) {
    return $();
  }

  let container = heading.parent();
  while (container.length) {
    const rows = container.find("li.archive_list_item.current, tr");
    const exactHeadings = container.find("h3.center_title.current").filter((_, element) =>
      isPrizeTableHeadingText(normalizePrizeCategory($(element).text())),
    );

    console.log(
        "findPrizeRowsForHeading container candidate",
        headingText,
        "tag=",
        container.prop("tagName"),
        "class=",
        container.attr("class") || "",
        "rowCount=",
        rows.length,
        "exactHeadingCount=",
        exactHeadings.length,
    );

    if (rows.length > 0) {
      console.log(
          "findPrizeRowsForHeading selected container raw text",
          headingText,
          normalizePrizeCategory(container.text()).slice(0, 1200),
      );
      console.log(
          "findPrizeRowsForHeading",
          headingText,
          "matchedRows=",
          rows.length,
      );
      return rows;
    }

    container = container.parent();
  }

  console.log("findPrizeRowsForHeading", headingText, "matchedRows=", 0);
  return $();
}

function extractPrizeHeadingText($, element) {
  if (!element || !element.length) {
    return null;
  }

  if (element.is("h3.center_title.current")) {
    const ownText = normalizePrizeCategory(element.text());
    if (isPrizeTableHeadingText(ownText)) {
      return ownText.includes("טבלת זכיות דאבל לוטו") ?
        "טבלת זכיות דאבל לוטו" :
        "טבלת זכיות לוטו";
    }
  }

  const nestedHeading = element.find("h3.center_title.current").filter((_, child) => {
    const text = normalizePrizeCategory($(child).text());
    return isPrizeTableHeadingText(text);
  }).first();

  if (nestedHeading.length) {
    const nestedText = normalizePrizeCategory(nestedHeading.text());
    return nestedText.includes("טבלת זכיות דאבל לוטו") ?
      "טבלת זכיות דאבל לוטו" :
      "טבלת זכיות לוטו";
  }

  return null;
}


function isPrizeTableHeadingText(text) {
  return text.includes("טבלת זכיות לוטו") || text.includes("טבלת זכיות דאבל לוטו");
}

function parsePrizeRow($, row) {
  const rowText = normalizePrizeCategory($(row).text());
  const strictParsedRow = parsePrizeRowFromStructuredText(rowText);
  if (strictParsedRow) {
    return strictParsedRow;
  }

  const blocks = $(row).find(".archive_list_block.lotto_current");
  if (blocks.length >= 3) {
    const category = normalizePrizeCategory($(blocks[0]).text());
    if (!PRIZE_CATEGORIES.includes(category)) {
      return parsePrizeRowFromText(rowText);
    }

    return {
      category,
      prizeAmount: parseCurrency($(blocks[2]).text()),
    };
  }

  const cells = $(row).find("td, th");
  if (cells.length >= 2) {
    const cellTexts = cells
        .map((_, cell) => normalizePrizeCategory($(cell).text()))
        .get()
        .filter(Boolean);

    const category = cellTexts.find((text) => PRIZE_CATEGORIES.includes(text));
    if (!category) {
      return null;
    }

    const prizeCellText = cellTexts.find((text) => /[\d,.]+/.test(text) && text !== category);
    return {
      category,
      prizeAmount: parseCurrency(prizeCellText || ""),
    };
  }

  return parsePrizeRowFromText(rowText);
}

function parsePrizeRowFromStructuredText(rowText) {
  if (!rowText) {
    return null;
  }

  const categoryAlternation = [
    "6 \\+ חזק",
    "5 \\+ חזק",
    "4 \\+ חזק",
    "3 \\+ חזק",
    "6",
    "5",
    "4",
    "3",
  ].join("|");

  const structuredRegex = new RegExp(
      `מס['"]?\\s*ניחושים\\s*(${categoryAlternation}).*?גובה\\s*הפרס\\s*([\\d,.]+)`,
  );
  const match = rowText.match(structuredRegex);
  if (!match) {
    return null;
  }

  return {
    category: normalizePrizeCategory(match[1]),
    prizeAmount: parseCurrency(match[2]),
  };
}

function parsePrizeRowFromText(rowText) {
  if (!rowText) {
    return null;
  }

  const category = PRIZE_CATEGORIES.find((candidate) => rowText.includes(candidate));
  if (!category) {
    return null;
  }

  const numberMatches = rowText.match(/[\d,.]+/g) || [];
  const prizeText = numberMatches.length ? numberMatches[numberMatches.length - 1] : "";
  const prizeAmount = parseCurrency(prizeText);

  return {
    category,
    prizeAmount,
  };
}

function parsePrizeTableBySelector($, selector, tableName) {
  const prizeByCategory = new Map();

  $(selector).each((_, row) => {
    const parsedRow = parsePrizeRow($, row);
    if (!parsedRow) {
      return;
    }

    prizeByCategory.set(parsedRow.category, parsedRow.prizeAmount);
  });

  console.log(
      "parsePrizeTableBySelector",
      tableName,
      Array.from(prizeByCategory.keys()).join(","),
  );
  return prizeByCategory;
}

function selectPrizeTableForTicketType(ticketType, parsedTables) {
  let selectedKey = null;
  switch (ticketType) {
    case TICKET_TYPES.regularLotto:
      selectedKey = PRIZE_TABLE_KEYS.regularLotto;
      break;
    case TICKET_TYPES.doubleLotto:
      selectedKey = PRIZE_TABLE_KEYS.doubleLotto;
      break;
    default:
      selectedKey = null;
      break;
  }

  const selectedTable = selectedKey ? parsedTables[selectedKey] : null;
  console.log(
      "selectPrizeTableForTicketType",
      "ticketType=",
      ticketType,
      "selectedKey=",
      selectedKey,
      "categories=",
      selectedTable ? Array.from(selectedTable.keys()).join(",") : "",
  );
  return selectedTable || new Map();
}

function calculateTablePrize(table, result, ticketType) {
  const regularMatches = table.regularNumbers
      .filter((number) => result.regularNumbers.includes(number))
      .length;
  const strongMatches = table.strongNumber === result.strongNumber;
  const category = determinePrizeCategory(regularMatches, strongMatches);

  if (!category) {
    return 0;
  }

  const prizeTable = selectPrizeTableForTicketType(
      ticketType,
      result.parsedPrizeTables || {
        regularLottoPrizeTable: result.prizeByCategory || new Map(),
        doubleLottoPrizeTable: new Map(),
      },
  );
  const prizeAmount = prizeTable.get(category) || 0;
  console.log(
      "calculateTablePrize",
      "tableIndex=",
      table.tableIndex,
      "ticketType=",
      ticketType,
      "regularMatches=",
      regularMatches,
      "strongMatches=",
      strongMatches,
      "category=",
      category,
      "prizeAmount=",
      prizeAmount,
  );

  return prizeAmount;
}

function getTicketTypeForForm(formData) {
  switch (formData.ticketType) {
    case TICKET_TYPES.doubleLotto:
      return TICKET_TYPES.doubleLotto;
    case TICKET_TYPES.regularLotto:
    default:
      return TICKET_TYPES.regularLotto;
  }
}

function determinePrizeCategory(regularMatches, strongMatches) {
  if (regularMatches === 6 && strongMatches) return "6 + חזק";
  if (regularMatches === 6) return "6";
  if (regularMatches === 5 && strongMatches) return "5 + חזק";
  if (regularMatches === 5) return "5";
  if (regularMatches === 4 && strongMatches) return "4 + חזק";
  if (regularMatches === 4) return "4";
  if (regularMatches === 3 && strongMatches) return "3 + חזק";
  if (regularMatches === 3) return "3";
  return null;
}

function normalizePrizeCategory(category) {
  return category
      .replace(/&#x27;/g, "'")
      .replace(/\s+/g, " ")
      .replace(/\u00a0/g, " ")
      .trim();
}

function parseCurrency(value) {
  return Number(String(value).replace(/[^\d.-]/g, "")) || 0;
}

function getAdminCheckSecret() {
  if (typeof process.env.LOTTO_ADMIN_SECRET === "string" &&
    process.env.LOTTO_ADMIN_SECRET.trim()) {
    return process.env.LOTTO_ADMIN_SECRET.trim();
  }

  return null;
}

function validateSubmitPayload(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Invalid submit payload.",
    );
  }

  if (!Array.isArray(data.tables) || data.tables.length !== EXPECTED_TABLE_COUNT) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        `Exactly ${EXPECTED_TABLE_COUNT} tables are required.`,
    );
  }

  let encodedLength = 0;
  try {
    encodedLength = JSON.stringify(data.tables).length;
  } catch (error) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Tables payload could not be encoded.",
    );
  }

  if (encodedLength > MAX_TABLES_JSON_LENGTH) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Tables payload is larger than expected.",
    );
  }

  data.tables.forEach((table, index) => {
    if (!table || typeof table !== "object" || Array.isArray(table)) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          `Table ${index + 1} is malformed.`,
      );
    }

    if (
      table.regularNumbers != null &&
      (!Array.isArray(table.regularNumbers) || table.regularNumbers.length > 6)
    ) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          `Table ${index + 1} regular numbers are malformed.`,
      );
    }

    if (
      table.strongNumber != null &&
      !Number.isFinite(Number(table.strongNumber))
    ) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          `Table ${index + 1} strong number is malformed.`,
      );
    }
  });
}

async function fetchWithRetry(
    url,
    options = {},
    attempts = HTTP_RETRY_ATTEMPTS,
) {
  let lastError;

  for (let attempt = 1; attempt <= attempts; attempt++) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), HTTP_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        ...options,
        signal: controller.signal,
      });
      clearTimeout(timeout);
      return response;
    } catch (error) {
      clearTimeout(timeout);
      lastError = error;
      console.error(
          `HTTP request failed (attempt ${attempt}/${attempts})`,
          url,
          error,
      );

      if (attempt < attempts) {
        await sleep(attempt * 250);
      }
    }
  }

  throw lastError;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function normalizeTables(rawTables) {
  if (!Array.isArray(rawTables)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Tables payload is missing.",
    );
  }

  return rawTables.map((table, index) => {
    if (!table || typeof table !== "object" || Array.isArray(table)) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          `Table ${index + 1} is malformed.`,
      );
    }

    if (table.regularNumbers != null && !Array.isArray(table.regularNumbers)) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          `Table ${index + 1} regular numbers are malformed.`,
      );
    }

    const regularNumbers = Array.isArray(table.regularNumbers) ?
      normalizeRegularNumbers(
          table.regularNumbers
              .map((value) => Number(value))
              .filter(isRegularNumber),
      ) : [];
    const strongNumber = table.strongNumber == null ? null : Number(table.strongNumber);

    return {
      tableIndex: Number(table.tableIndex) || index + 1,
      regularNumbers,
      strongNumber: isStrongNumber(strongNumber) ? strongNumber : null,
      isComplete: isTableComplete({
        regularNumbers,
        strongNumber,
      }),
    };
  });
}

function normalizeRegularNumbers(regularNumbers) {
  return Array.from(regularNumbers).sort((a, b) => a - b);
}

function buildTicketFingerprintSource({lotteryId, tables}) {
  const normalizedLotteryId = Number(lotteryId);
  const tableCount = String(tables.length).padStart(2, "0");
  const tableParts = tables.map((table) => {
    const regulars = normalizeRegularNumbers(table.regularNumbers)
        .map((value) => String(value).padStart(2, "0"))
        .join("");
    const strong = String(table.strongNumber);
    return `${regulars}-${strong}`;
  });

  return `${normalizedLotteryId}-${tableCount}-${tableParts.join("-")}`;
}

function isSubmittedFormValid(tables) {
  return Array.isArray(tables) &&
    tables.length === EXPECTED_TABLE_COUNT &&
    tables.every((table) => isTableComplete(table));
}

function isTableComplete(table) {
  const uniqueRegulars = new Set(table.regularNumbers);
  return table.regularNumbers.length === 6 &&
    uniqueRegulars.size === 6 &&
    table.regularNumbers.every(isRegularNumber) &&
    isStrongNumber(table.strongNumber);
}

function isRegularNumber(value) {
  return Number.isInteger(value) && value >= 1 && value <= 37;
}

function isStrongNumber(value) {
  return Number.isInteger(value) && value >= 1 && value <= 7;
}

function parsePaisDateTime(rawDate, displayDate, displayTime) {
  if (rawDate) {
    const rawMatch = String(rawDate).match(
        /^[A-Za-z]{3}\s+(\d{1,2}),\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/,
    );
    if (rawMatch) {
      const month = monthIndexFromEnglishAbbreviation(rawDate.slice(0, 3));
      const day = Number(rawMatch[1]);
      const year = Number(rawMatch[2]);
      const hour = Number(rawMatch[3]);
      const minute = Number(rawMatch[4]);

      if (month >= 0) {
        return jerusalemTimestampFromParts(year, month, day, hour, minute);
      }
    }
  }

  if (displayDate && displayTime) {
    const dateMatch = String(displayDate).match(
        /^(\d{2})\/(\d{2})\/(\d{4})$/,
    );
    const timeMatch = String(displayTime).match(/^(\d{2}):(\d{2})$/);
    if (dateMatch && timeMatch) {
      const parsed = new Date(
          Number(dateMatch[3]),
          Number(dateMatch[2]) - 1,
          Number(dateMatch[1]),
          Number(timeMatch[1]),
          Number(timeMatch[2]),
          0,
          0,
      );
      if (!Number.isNaN(parsed.getTime())) {
        return jerusalemTimestampFromParts(
            Number(dateMatch[3]),
            Number(dateMatch[2]) - 1,
            Number(dateMatch[1]),
            Number(timeMatch[1]),
            Number(timeMatch[2]),
        );
      }
    }
  }

  return null;
}

function monthIndexFromEnglishAbbreviation(value) {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  return months.indexOf(value);
}

function jerusalemTimestampFromParts(year, monthIndex, day, hour, minute) {
  let utcGuess = Date.UTC(year, monthIndex, day, hour, minute, 0, 0);

  for (let index = 0; index < 3; index++) {
    const parts = formatJerusalemParts(new Date(utcGuess));
    const diffMinutes = differenceInMinutes(
        {year, month: monthIndex + 1, day, hour, minute},
        parts,
    );
    if (diffMinutes === 0) {
      return admin.firestore.Timestamp.fromDate(new Date(utcGuess));
    }
    utcGuess += diffMinutes * 60 * 1000;
  }

  return admin.firestore.Timestamp.fromDate(new Date(utcGuess));
}

function formatJerusalemParts(date) {
  const formatter = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Jerusalem",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });

  const parts = formatter.formatToParts(date);
  return {
    year: Number(parts.find((part) => part.type === "year").value),
    month: Number(parts.find((part) => part.type === "month").value),
    day: Number(parts.find((part) => part.type === "day").value),
    hour: Number(parts.find((part) => part.type === "hour").value),
    minute: Number(parts.find((part) => part.type === "minute").value),
  };
}

function differenceInMinutes(target, actual) {
  const targetValue = Date.UTC(
      target.year,
      target.month - 1,
      target.day,
      target.hour,
      target.minute,
  );
  const actualValue = Date.UTC(
      actual.year,
      actual.month - 1,
      actual.day,
      actual.hour,
      actual.minute,
  );

  return (targetValue - actualValue) / (60 * 1000);
}
