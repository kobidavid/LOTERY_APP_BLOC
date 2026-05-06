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
const MAX_TABLE_COUNT = 14;
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
const DEBUG_GROUP_RESULT_GROUP_IDS = new Set([
  "pK4GpdLHXvVBpbNusbwj",
  "cgx55IjGvs68IoiqP1He",
]);
const DEFAULT_REPAIR_STAGE_LIMIT = 100;
const DEFAULT_RESULT_FORM_LIMIT = 100;
const UPCOMING_LOTTERY_CACHE_DOC = firestore
    .collection("app_config")
    .doc("upcoming_lottery");

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
      drawNumber: nextLottery.lotteryId,
      salesCloseAt: nextLottery.salesCloseAt,
      drawDate: nextLottery.salesCloseAt,
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

exports.getUpcomingLotteryMetadata = functions.https.onCall(async () => {
  try {
    return await fetchNextLotteryMetadata();
  } catch (error) {
    console.error("getUpcomingLotteryMetadata failed", error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
        "internal",
        "Upcoming lottery metadata lookup failed.",
    );
  }
});

exports.getLotteryMetadataByLotteryId = functions.https.onCall(async (data) => {
  try {
    const lotteryId = Number(data?.lotteryId ?? data?.drawNumber);
    if (!Number.isFinite(lotteryId) || lotteryId <= 0) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "lotteryId is required.",
      );
    }

    const metadata = await findLotteryMetadataByLotteryId(lotteryId, {
      scope: "getLotteryMetadataByLotteryId",
      lotteryId,
    });
    return buildLotteryMetadataPatch(metadata);
  } catch (error) {
    console.error("getLotteryMetadataByLotteryId failed", error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
        "internal",
        "Lottery metadata lookup by lotteryId failed.",
    );
  }
});

exports.getReceiptOpenTarget = functions.https.onCall(async (data, context) => {
  try {
    const authenticatedUserId = await resolveAuthenticatedUserId(data, context);
    if (!authenticatedUserId) {
      throw new functions.https.HttpsError(
          "unauthenticated",
          "Authentication is required.",
      );
    }

    const ownerUserId = asTrimmedString(data?.ownerUserId);
    const formId = asTrimmedString(data?.formId);
    if (!ownerUserId || !formId) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "ownerUserId and formId are required.",
      );
    }

    const formRef = firestore
        .collection("users")
        .doc(ownerUserId)
        .collection("forms")
        .doc(formId);
    const formSnapshot = await formRef.get();
    if (!formSnapshot.exists) {
      throw new functions.https.HttpsError(
          "not-found",
          "הטופס לא נמצא.",
      );
    }

    const formData = formSnapshot.data() || {};
    const groupId = asTrimmedString(formData.groupId);
    const canRead = authenticatedUserId === ownerUserId ||
      (groupId &&
        (await firestore
            .collection("lottery_groups")
            .doc(groupId)
            .collection("memberships")
            .doc(authenticatedUserId)
            .get()).exists);

    if (!canRead) {
      throw new functions.https.HttpsError(
          "permission-denied",
          "אין הרשאה לצפות בקבלה עבור טופס זה.",
      );
    }

    const directTarget = await resolveReceiptOpenTargetFromData(formData);
    if (directTarget) {
      return {
        matched: asTrimmedString(formData.stationReceiptMatchStatus) === "matched",
        targetUrl: directTarget.targetUrl,
        targetStoragePath: directTarget.targetStoragePath,
        source: "form",
      };
    }

    const intakeId = asTrimmedString(formData.stationReceiptIntakeId);
    if (!intakeId) {
      return {
        matched: asTrimmedString(formData.stationReceiptMatchStatus) === "matched",
        targetUrl: null,
        targetStoragePath: null,
        source: null,
      };
    }

    const intakeSnapshot = await firestore.collection("receipt_intake").doc(intakeId).get();
    if (!intakeSnapshot.exists) {
      return {
        matched: asTrimmedString(formData.stationReceiptMatchStatus) === "matched",
        targetUrl: null,
        targetStoragePath: null,
        source: null,
      };
    }

    const intakeData = intakeSnapshot.data() || {};
    const intakeTarget = await resolveReceiptOpenTargetFromData(intakeData);
    return {
      matched: asTrimmedString(formData.stationReceiptMatchStatus) === "matched",
      targetUrl: intakeTarget ? intakeTarget.targetUrl : null,
      targetStoragePath: intakeTarget ? intakeTarget.targetStoragePath : null,
      source: intakeTarget ? "receipt_intake" : null,
    };
  } catch (error) {
    console.error("getReceiptOpenTarget failed", error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
        "internal",
        "Receipt open target lookup failed.",
    );
  }
});

exports.chargeUserWallet = functions.https.onCall(async (data, context) => {
  try {
    const authenticatedUserId = await resolveAuthenticatedUserId(data, context);
    if (!authenticatedUserId) {
      throw new functions.https.HttpsError(
          "unauthenticated",
          "Authentication is required.",
      );
    }

    const userId = asTrimmedString(data?.userId, authenticatedUserId);
    const groupId = asTrimmedString(data?.groupId);
    const formId = asTrimmedString(data?.formId);
    const amount = asPositiveNumber(data?.amount);

    if (userId !== authenticatedUserId) {
      throw new functions.https.HttpsError(
          "permission-denied",
          "Authenticated user does not match wallet owner.",
      );
    }
    if (amount <= 0) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "amount must be greater than zero.",
      );
    }

    let updatedBalance = 0;
    await firestore.runTransaction(async (transaction) => {
      const userRef = firestore.collection("users").doc(userId);
      const formRef = formId ? firestore.collection("users")
          .doc(userId)
          .collection("forms")
          .doc(formId) : null;
      const groupRef = groupId ? firestore.collection("lottery_groups").doc(groupId) : null;
      const membershipRef = groupRef ?
        groupRef.collection("memberships").doc(userId) :
        null;

      const userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "המשתמש לא נמצא.",
        );
      }

      const formSnapshot = formRef ? await transaction.get(formRef) : null;
      const groupSnapshot = groupRef ? await transaction.get(groupRef) : null;
      const membershipSnapshot = membershipRef ?
        await transaction.get(membershipRef) :
        null;
      const membershipsSnapshot = groupRef ?
        await transaction.get(groupRef.collection("memberships")) :
        null;

      const userData = userSnapshot.data() || {};
      const currentBalance = asPositiveNumber(userData.balance);
      if (currentBalance < amount) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "אין יתרה מספיקה לביצוע התשלום.",
        );
      }

      if (groupId) {
        if (!groupSnapshot || !groupSnapshot.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "הקבוצה לא נמצאה.",
          );
        }
        if (!membershipSnapshot || !membershipSnapshot.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "פרטי ההשתתפות בקבוצה לא נמצאו.",
          );
        }

        const groupData = groupSnapshot.data() || {};
        const membershipData = membershipSnapshot.data() || {};
        if (!membershipData.lockedIn) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              "רק משתתפים שננעלו יכולים לשלם.",
          );
        }

        if (asTrimmedString(membershipData.paymentStatus) === "paid") {
          return;
        }

        const expectedAmount =
          asPositiveNumber(membershipData.costShare) ||
          asPositiveNumber(groupData.currentPerParticipantCost);
        if (expectedAmount <= 0) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              "לא ניתן לחשב את עלות ההשתתפות בקבוצה.",
          );
        }

        if (Math.abs(expectedAmount - amount) > 0.01) {
          throw new functions.https.HttpsError(
              "invalid-argument",
              "סכום התשלום אינו תואם לעלות ההשתתפות בקבוצה.",
          );
        }

        const now = admin.firestore.FieldValue.serverTimestamp();
        const memberships = (membershipsSnapshot?.docs ?? []).map((doc) => {
          const docData = {...(doc.data() || {})};
          if (doc.id === userId) {
            docData.paymentStatus = "paid";
            docData.paidAt = now;
            docData.walletChargeAmount = amount;
          }
          return {
            userId: doc.id,
            ...docData,
          };
        });

        transaction.set(membershipRef, {
          paymentStatus: "paid",
          paidAt: now,
          walletChargeAmount: amount,
          paymentMethod: "wallet",
        }, {merge: true});

        const paidLockedInMemberships = memberships.filter((membership) =>
          membership.lockedIn &&
          asTrimmedString(membership.paymentStatus) === "paid",
        );
        const validPaidMemberships = computeStableValidMemberships(
            paidLockedInMemberships,
        );
        const readyForSubmission = validPaidMemberships.length > 0;

        if (readyForSubmission) {
          transaction.set(groupRef, {
            status: "ready_for_submission",
            currentPerParticipantCost:
              asPositiveNumber(groupData.baseTicketCost) /
              validPaidMemberships.length,
            updatedAt: now,
          }, {merge: true});
        } else if (asTrimmedString(groupData.status) !== "awaiting_payments") {
          transaction.set(groupRef, {
            status: "awaiting_payments",
            updatedAt: now,
          }, {merge: true});
        }
      }

      if (formId && formRef) {
        if (!formSnapshot || !formSnapshot.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "הטופס לא נמצא.",
          );
        }
        transaction.set(formRef, {
          walletChargeAmount: amount,
          paymentMethod: "wallet",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      updatedBalance = currentBalance - amount;
      transaction.set(userRef, {
        balance: updatedBalance,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    });

    return {
      success: true,
      userId,
      groupId: groupId || null,
      formId: formId || null,
      amountCharged: amount,
      updatedBalance,
    };
  } catch (error) {
    console.error("chargeUserWallet failed", error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
        "internal",
        "חיוב היתרה נכשל.",
    );
  }
});

exports.cancelGroupDraft = functions.https.onCall(async (data, context) => {
  try {
    const authenticatedUserId = await resolveAuthenticatedUserId(data, context);
    if (!authenticatedUserId) {
      throw new functions.https.HttpsError(
          "unauthenticated",
          "Authentication is required.",
      );
    }

    const groupId = typeof data?.groupId === "string" ? data.groupId.trim() : "";
    if (!groupId) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          "groupId is required.",
      );
    }

    const groupRef = firestore.collection("lottery_groups").doc(groupId);
    const membershipsQuery = groupRef.collection("memberships");
    const now = admin.firestore.FieldValue.serverTimestamp();

    await firestore.runTransaction(async (transaction) => {
      const groupSnapshot = await transaction.get(groupRef);
      if (!groupSnapshot.exists) {
        throw new functions.https.HttpsError(
            "not-found",
            "הקבוצה לא נמצאה.",
        );
      }

      const groupData = groupSnapshot.data() || {};
      const creatorUserId = asTrimmedString(groupData.creatorUserId);
      if (creatorUserId !== authenticatedUserId) {
        throw new functions.https.HttpsError(
            "permission-denied",
            "רק יוצר הקבוצה יכול לבטל את הטופס הקבוצתי.",
        );
      }

      const groupStatus = asTrimmedString(groupData.status);
      if (groupStatus === "submitted") {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "לא ניתן לבטל קבוצה שכבר נשלחה.",
        );
      }
      if (groupStatus === "cancelled") {
        return;
      }

      const membershipsSnapshot = await transaction.get(membershipsQuery);
      const memberships = membershipsSnapshot.docs.map((doc) => ({
        userId: doc.id,
        ...doc.data(),
      }));
      const cancelledByDisplayName = creatorDisplayNameFromMemberships(
          memberships,
          authenticatedUserId,
      );
      const currentPerParticipantCost = asPositiveNumber(
          groupData.currentPerParticipantCost,
      );
      const sourceFormId = asTrimmedString(groupData.sourceFormId);
      const groupName = asTrimmedString(groupData.groupName, groupId);

      const cancelledSummaryUserIds = new Set([creatorUserId]);
      let totalRefundedAmount = 0;

      for (const membership of memberships) {
        const refundAmount = refundAmountForMembership(
            membership,
            currentPerParticipantCost,
        );
        if (refundAmount <= 0) {
          continue;
        }

        cancelledSummaryUserIds.add(membership.userId);
        totalRefundedAmount += refundAmount;

        const userRef = firestore.collection("users").doc(membership.userId);
        transaction.set(userRef, {
          balance: admin.firestore.FieldValue.increment(refundAmount),
        }, {merge: true});
      }

      if (sourceFormId) {
        const creatorRefundAmount = refundAmountForUser(
            memberships,
            creatorUserId,
            currentPerParticipantCost,
        );
        transaction.set(
            firestore.collection("users")
                .doc(creatorUserId)
                .collection("forms")
                .doc(sourceFormId),
            {
              status: "cancelled",
              updatedAt: now,
              cancelledAt: now,
              cancelledByUserId: authenticatedUserId,
              cancelledByDisplayName,
              refundAmount: creatorRefundAmount,
              isEditable: false,
            },
            {merge: true},
        );
      }

      transaction.set(groupRef, {
        status: "cancelled",
        updatedAt: now,
        cancelledAt: now,
        cancelledByUserId: authenticatedUserId,
        cancelledByDisplayName,
        totalRefundedAmount,
      }, {merge: true});

      for (const membership of memberships) {
        const refundAmount = refundAmountForMembership(
            membership,
            currentPerParticipantCost,
        );
        transaction.set(
            groupRef.collection("memberships").doc(membership.userId),
            {
              refundAmount,
              ...(refundAmount > 0 ? {refundedAt: now} : {}),
            },
            {merge: true},
        );
        transaction.delete(
            firestore.collection("users")
                .doc(membership.userId)
                .collection("active_groups")
                .doc(groupId),
        );
      }

      transaction.delete(
          firestore.collection("users")
              .doc(creatorUserId)
              .collection("active_groups")
              .doc(groupId),
      );

      for (const userId of cancelledSummaryUserIds) {
        transaction.set(
            firestore.collection("users")
                .doc(userId)
                .collection("cancelled_groups")
                .doc(groupId),
            {
              groupId,
              groupName,
              creatorUserId,
              creatorName: cancelledByDisplayName,
              groupStatus: "cancelled",
              cancelledAt: now,
              cancelledByUserId: authenticatedUserId,
              cancelledByDisplayName,
              myRefundAmount: refundAmountForUser(
                  memberships,
                  userId,
                  currentPerParticipantCost,
              ),
              updatedAt: now,
            },
            {merge: true},
        );
      }
    });

    return {success: true, groupId};
  } catch (error) {
    console.error("cancelGroupDraft failed", error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError(
        "internal",
        "ביטול הטופס הקבוצתי נכשל.",
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

async function resolveReceiptOpenTargetFromData(rawData) {
  const directUrl = firstValidReceiptUrl(rawData);
  if (directUrl) {
    return {
      targetUrl: directUrl,
      targetStoragePath: firstReceiptStoragePath(rawData),
    };
  }

  const storagePath = firstReceiptStoragePath(rawData);
  if (!storagePath) {
    return null;
  }

  const signedUrl = await buildSignedStorageUrl(storagePath);
  if (!signedUrl) {
    return null;
  }

  return {
    targetUrl: signedUrl,
    targetStoragePath: storagePath,
  };
}

function firstValidReceiptUrl(rawData) {
  const candidateKeys = [
    "stationReceiptUrl",
    "receiptUrl",
    "uploadedReceiptUrl",
    "downloadUrl",
  ];
  for (const key of candidateKeys) {
    const value = asTrimmedString(rawData?.[key]);
    if (isValidHttpUrl(value)) {
      return value;
    }
  }
  return null;
}

function firstReceiptStoragePath(rawData) {
  const candidateKeys = [
    "stationReceiptStoragePath",
    "receiptStoragePath",
    "uploadedReceiptStoragePath",
    "storagePath",
  ];
  for (const key of candidateKeys) {
    const value = asTrimmedString(rawData?.[key]);
    if (value) {
      return value;
    }
  }
  return null;
}

async function buildSignedStorageUrl(storagePath) {
  try {
    const [signedUrl] = await admin.storage().bucket().file(storagePath).getSignedUrl({
      action: "read",
      expires: "2100-01-01",
    });
    return isValidHttpUrl(signedUrl) ? signedUrl : null;
  } catch (error) {
    console.error("buildSignedStorageUrl failed", {storagePath, error});
    return null;
  }
}

function isValidHttpUrl(value) {
  if (!value) {
    return false;
  }
  try {
    const parsed = new URL(value);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch (_) {
    return false;
  }
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

exports.refreshUpcomingLotteryCache = functions.pubsub
    .schedule("every 6 hours")
    .timeZone("Asia/Jerusalem")
    .onRun(async () => {
      try {
        await syncUpcomingLotteryCache({reason: "scheduled_refresh"});
      } catch (error) {
        console.error("refreshUpcomingLotteryCache scheduler failed", error);
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

function normalizeRunLimit(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.min(Math.floor(parsed), fallback);
}

function buildProcessingOptions(rawOptions = {}) {
  return {
    uid: asTrimmedString(rawOptions.uid) || null,
    submissionId: asTrimmedString(rawOptions.submissionId) || null,
    groupId: asTrimmedString(rawOptions.groupId) || null,
    stageLimit: normalizeRunLimit(
        rawOptions.stageLimit ?? rawOptions.limit,
        DEFAULT_REPAIR_STAGE_LIMIT,
    ),
    resultFormLimit: normalizeRunLimit(
        rawOptions.resultFormLimit ?? rawOptions.limit,
        DEFAULT_RESULT_FORM_LIMIT,
    ),
  };
}

function isTargetedPersonalSubmissionMode(options = {}) {
  return Boolean(options.uid && options.submissionId && !options.groupId);
}

function isTargetedGroupMode(options = {}) {
  return Boolean(options.groupId && !options.submissionId);
}

async function runProcessingStage(summary, stageName, runner) {
  const startedAt = Date.now();
  console.log(`${stageName} stage start`, {
    options: summary.options,
  });
  try {
    const counts = await runner();
    summary.stages[stageName] = {
      success: true,
      durationMs: Date.now() - startedAt,
      ...(counts || {}),
    };
    console.log(`${stageName} stage end`, summary.stages[stageName]);
  } catch (error) {
    summary.partialSuccess = true;
    summary.errors.push({
      stage: stageName,
      message: error && error.message ? error.message : String(error),
    });
    summary.stages[stageName] = {
      success: false,
      durationMs: Date.now() - startedAt,
      message: error && error.message ? error.message : String(error),
    };
    console.error(`${stageName} stage failed`, {
      message: error && error.message ? error.message : String(error),
      stack: error && error.stack ? error.stack : null,
    });
  }
}

function logFirestoreQueryFailure({
  scope,
  queryLabel,
  collectionPath,
  whereClauses = [],
  orderByClauses = [],
  error,
  extra = {},
}) {
  console.error(`${scope} Firestore query failed`, {
    queryLabel,
    collectionPath,
    whereClauses,
    orderByClauses,
    code: error && error.code ? error.code : null,
    message: error && error.message ? error.message : String(error),
    stack: error && error.stack ? error.stack : null,
    ...extra,
  });
}

async function loadTargetGroupDocs(options) {
  if (options.groupId) {
    const snapshot = await firestore.collection("lottery_groups").doc(options.groupId).get();
    return snapshot.exists ? [snapshot] : [];
  }

  let query = firestore.collection("lottery_groups");
  if (options.uid) {
    query = query.where("creatorUserId", "==", options.uid);
  }
  const snapshot = await query.limit(options.stageLimit).get();
  return snapshot.docs;
}

async function loadTargetPersonalSubmissionDocs(options) {
  if (options.submissionId && options.uid) {
    const queryLabel = "targeted personal submission doc";
    try {
      const snapshot = await firestore
          .collection("users")
          .doc(options.uid)
          .collection("submissions")
          .doc(options.submissionId)
          .get();
      return snapshot.exists ? [snapshot] : [];
    } catch (error) {
      logFirestoreQueryFailure({
        scope: "loadTargetPersonalSubmissionDocs",
        queryLabel,
        collectionPath: `users/${options.uid}/submissions/${options.submissionId}`,
        whereClauses: [],
        orderByClauses: [],
        error,
        extra: {options},
      });
      throw error;
    }
  }

  let query = firestore.collectionGroup("submissions");
  const whereClauses = [];
  if (options.submissionId) {
    query = query.where("submissionId", "==", options.submissionId);
    whereClauses.push(`submissionId == ${options.submissionId}`);
  } else if (options.uid) {
    query = query.where("userId", "==", options.uid);
    whereClauses.push(`userId == ${options.uid}`);
  }
  let snapshot;
  try {
    snapshot = await query.limit(options.stageLimit).get();
  } catch (error) {
    logFirestoreQueryFailure({
      scope: "loadTargetPersonalSubmissionDocs",
      queryLabel: "collectionGroup(submissions).limit(stageLimit)",
      collectionPath: "collectionGroup(submissions)",
      whereClauses,
      orderByClauses: [],
      error,
      extra: {options},
    });
    throw error;
  }
  return snapshot.docs.filter((doc) => {
    const data = doc.data() || {};
    return asTrimmedString(data.type) === "personal" &&
      asTrimmedString(data.status) === "submitted";
  });
}

async function loadCanonicalWaitingResultDocs(options) {
  if (options.groupId) {
    let snapshot;
    try {
      snapshot = await firestore
          .collection("lottery_groups")
          .doc(options.groupId)
          .collection("forms")
          .limit(options.resultFormLimit)
          .get();
    } catch (error) {
      logFirestoreQueryFailure({
        scope: "loadCanonicalWaitingResultDocs",
        queryLabel: "targeted group canonical forms",
        collectionPath: `lottery_groups/${options.groupId}/forms`,
        whereClauses: [],
        orderByClauses: [],
        error,
        extra: {options},
      });
      throw error;
    }
    return snapshot.docs.filter((doc) => shouldProcessCanonicalResultDoc(doc.data() || {}));
  }

  if (options.submissionId && options.uid) {
    let snapshot;
    try {
      snapshot = await firestore
          .collection("users")
          .doc(options.uid)
          .collection("forms")
          .where("submissionId", "==", options.submissionId)
          .limit(options.resultFormLimit)
          .get();
    } catch (error) {
      logFirestoreQueryFailure({
        scope: "loadCanonicalWaitingResultDocs",
        queryLabel: "targeted personal canonical forms",
        collectionPath: `users/${options.uid}/forms`,
        whereClauses: [`submissionId == ${options.submissionId}`],
        orderByClauses: [],
        error,
        extra: {options},
      });
      throw error;
    }
    return snapshot.docs.filter((doc) => shouldProcessCanonicalResultDoc(doc.data() || {}));
  }

  if (options.uid) {
    let snapshot;
    try {
      snapshot = await firestore
          .collection("users")
          .doc(options.uid)
          .collection("forms")
          .limit(options.resultFormLimit)
          .get();
    } catch (error) {
      logFirestoreQueryFailure({
        scope: "loadCanonicalWaitingResultDocs",
        queryLabel: "targeted user canonical forms",
        collectionPath: `users/${options.uid}/forms`,
        whereClauses: [],
        orderByClauses: [],
        error,
        extra: {options},
      });
      throw error;
    }
    return snapshot.docs.filter((doc) => shouldProcessCanonicalResultDoc(doc.data() || {}));
  }

  if (options.submissionId) {
    let snapshot;
    try {
      snapshot = await firestore
          .collectionGroup("forms")
          .where("submissionId", "==", options.submissionId)
          .limit(options.resultFormLimit)
          .get();
    } catch (error) {
      logFirestoreQueryFailure({
        scope: "loadCanonicalWaitingResultDocs",
        queryLabel: "submissionId scoped canonical forms",
        collectionPath: "collectionGroup(forms)",
        whereClauses: [`submissionId == ${options.submissionId}`],
        orderByClauses: [],
        error,
        extra: {options},
      });
      throw error;
    }
    return snapshot.docs.filter((doc) => shouldProcessCanonicalResultDoc(doc.data() || {}));
  }

  if (!options.uid && !options.submissionId && !options.groupId) {
    let snapshot;
    try {
      snapshot = await firestore
          .collectionGroup("forms")
          .limit(options.resultFormLimit)
          .get();
    } catch (error) {
      logFirestoreQueryFailure({
        scope: "loadCanonicalWaitingResultDocs",
        queryLabel: "global canonical forms scan",
        collectionPath: "collectionGroup(forms)",
        whereClauses: [],
        orderByClauses: [],
        error,
        extra: {options},
      });
      throw error;
    }
    return snapshot.docs.filter((doc) =>
      shouldProcessCanonicalResultDoc(doc.data() || {}));
  }

  let snapshot;
  try {
    snapshot = await firestore
        .collectionGroup("forms")
        .where("status", "==", "submitted")
        .limit(options.resultFormLimit)
        .get();
  } catch (error) {
    logFirestoreQueryFailure({
      scope: "loadCanonicalWaitingResultDocs",
      queryLabel: "fallback submitted canonical forms",
      collectionPath: "collectionGroup(forms)",
      whereClauses: ["status == submitted"],
      orderByClauses: [],
      error,
      extra: {options},
    });
    throw error;
  }
  return snapshot.docs.filter((doc) => shouldProcessCanonicalResultDoc(doc.data() || {}));
}

function matchesProcessingTarget(doc, data, options) {
  if (options.groupId) {
    if (!isGroupFormDocument(doc.ref)) {
      return false;
    }
    return doc.ref.parent.parent && doc.ref.parent.parent.id === options.groupId;
  }

  if (options.submissionId) {
    return asTrimmedString(data.submissionId) === options.submissionId;
  }

  if (options.uid) {
    return asTrimmedString(data.userId, data.creatorUserId) === options.uid;
  }

  return true;
}

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

        const options = buildProcessingOptions({
          ...((req.query && typeof req.query === "object") ? req.query : {}),
          ...((req.body && typeof req.body === "object") ? req.body : {}),
        });
        failureStage = "process-waiting-results";
        const summary = await processWaitingLotteryResults(options);
        return res.status(200).json({
          success: !summary.partialSuccess,
          partialSuccess: summary.partialSuccess,
          message: summary.partialSuccess ?
            "Lottery results processed with partial completion." :
            "Lottery results processed.",
          options,
          summary,
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

async function processWaitingLotteryResults(rawOptions = {}) {
  const options = buildProcessingOptions(rawOptions);
  const summary = {
    options,
    partialSuccess: false,
    stages: {},
    errors: [],
  };
  try {
    if (isTargetedPersonalSubmissionMode(options)) {
      await runProcessingStage(
          summary,
          "repairCanonicalPersonalSubmissionForms",
          () => repairCanonicalPersonalSubmissionForms(options),
      );
      await runProcessingStage(
          summary,
          "repairMissingPersonalSubmissionLotteryMetadata",
          () => repairMissingPersonalSubmissionLotteryMetadata(options),
      );
      await runProcessingStage(
          summary,
          "rebuildPersonalSummaries",
          () => repairPersonalSubmissionSummaries(options),
      );
    } else if (isTargetedGroupMode(options)) {
      await runProcessingStage(
          summary,
          "repairCanonicalGroupForms",
          () => repairCanonicalGroupForms(options),
      );
      await runProcessingStage(
          summary,
          "repairMissingGroupLotteryMetadata",
          () => repairMissingGroupLotteryMetadata(options),
      );
      await runProcessingStage(
          summary,
          "rebuildGroupSummaries",
          () => repairMissingGroupResultSummaries(options),
      );
    } else {
      await runProcessingStage(
          summary,
          "repairCanonicalGroupForms",
          () => repairCanonicalGroupForms(options),
      );
      await runProcessingStage(
          summary,
          "repairCanonicalPersonalSubmissionForms",
          () => repairCanonicalPersonalSubmissionForms(options),
      );
      await runProcessingStage(
          summary,
          "repairMissingPersonalSubmissionLotteryMetadata",
          () => repairMissingPersonalSubmissionLotteryMetadata(options),
      );
      await runProcessingStage(
          summary,
          "repairMissingGroupLotteryMetadata",
          () => repairMissingGroupLotteryMetadata(options),
      );
      await runProcessingStage(
          summary,
          "rebuildGroupSummaries",
          () => repairMissingGroupResultSummaries(options),
      );
      await runProcessingStage(
          summary,
          "rebuildPersonalSummaries",
          () => repairPersonalSubmissionSummaries(options),
      );
    }
    await runProcessingStage(summary, "processCanonicalForms", async () => {
      console.log("processCanonicalForms query start", {
        query: "targeted canonical waiting forms",
        options,
      });
      let candidateDocs = [];
      try {
        candidateDocs = await loadCanonicalWaitingResultDocs(options);
      } catch (error) {
        logFirestoreQueryFailure({
          scope: "processCanonicalForms",
          queryLabel: "loadCanonicalWaitingResultDocs",
          collectionPath: "multiple canonical forms sources",
          whereClauses: [],
          orderByClauses: [],
          error,
          extra: {options},
        });
        throw error;
      }

      let matched = 0;
      let skipped = 0;
      let processed = 0;
      let publishedLotteries = 0;
      const formsByLotteryId = new Map();

      for (const doc of candidateDocs) {
        const data = doc.data() || {};
        if (!isCanonicalSubmittedResultDoc(doc.ref, data)) {
          skipped += 1;
          continue;
        }
        if (!matchesProcessingTarget(doc, data, options)) {
          skipped += 1;
          continue;
        }

        matched += 1;
        let metadata;
        try {
          metadata = await resolveAndRepairLotteryMetadataForFormDoc(doc, options);
        } catch (error) {
          summary.partialSuccess = true;
          summary.errors.push({
            stage: "processCanonicalForms",
            formId: doc.id,
            path: doc.ref.path,
            message: error && error.message ? error.message : String(error),
          });
          console.error("processCanonicalForms metadata resolution failed", {
            formId: doc.id,
            path: doc.ref.path,
            message: error && error.message ? error.message : String(error),
            stack: error && error.stack ? error.stack : null,
          });
          skipped += 1;
          continue;
        }
        const lotteryId = Number(metadata.lotteryId);
        if (!Number.isFinite(lotteryId)) {
          skipped += 1;
          continue;
        }

        if (!formsByLotteryId.has(lotteryId)) {
          formsByLotteryId.set(lotteryId, []);
        }

        formsByLotteryId.get(lotteryId).push(doc);
      }

      console.log(
          "processCanonicalForms lotteryIds",
          Array.from(formsByLotteryId.keys()).join(","),
      );

      for (const [lotteryId, docs] of formsByLotteryId.entries()) {
        try {
          console.log("processCanonicalForms fetching lottery result", {
            lotteryId,
            forms: docs.length,
          });
          const result = await fetchLotteryResult(lotteryId);
          if (!result) {
            continue;
          }

          publishedLotteries += 1;
          for (const doc of docs) {
            try {
              await applyLotteryResultToForm(doc.ref, doc.data(), result);
              processed += 1;
            } catch (error) {
              summary.partialSuccess = true;
              summary.errors.push({
                stage: "processCanonicalForms",
                formId: doc.id,
                lotteryId,
                message: error && error.message ? error.message : String(error),
              });
              console.error("applyLotteryResultToForm failed", {
                formId: doc.id,
                lotteryId,
                message: error && error.message ? error.message : String(error),
                stack: error && error.stack ? error.stack : null,
              });
            }
          }
        } catch (error) {
          summary.partialSuccess = true;
          summary.errors.push({
            stage: "processCanonicalForms",
            lotteryId,
            message: error && error.message ? error.message : String(error),
          });
          console.error("fetchLotteryResult group failed", {
            lotteryId,
            message: error && error.message ? error.message : String(error),
            stack: error && error.stack ? error.stack : null,
          });
        }
      }

      return {
        queriedDocs: candidateDocs.length,
        matchedDocs: matched,
        skippedDocs: skipped,
        processedDocs: processed,
        publishedLotteries,
      };
    });
  } catch (error) {
    console.error("processWaitingLotteryResults failed", {
      message: error && error.message ? error.message : String(error),
      stack: error && error.stack ? error.stack : null,
    });
    throw error;
  }
  return summary;
}

async function repairCanonicalGroupForms(options = {}) {
  console.log("repairCanonicalGroupForms query start", {
    query: options.groupId ?
      `lottery_groups/${options.groupId}` :
      "collection(lottery_groups).limit(stageLimit)",
    options,
  });
  const groupDocs = await loadTargetGroupDocs(options);
  console.log("repairCanonicalGroupForms scan", groupDocs.length);

  let batch = firestore.batch();
  let operations = 0;
  let updatedDocs = 0;
  let matchedGroups = 0;

  const commitBatchIfNeeded = async (force = false) => {
    if (operations === 0) {
      return;
    }
    if (!force && operations < 350) {
      return;
    }
    await batch.commit();
    batch = firestore.batch();
    operations = 0;
  };

  for (const groupDoc of groupDocs) {
    const groupData = groupDoc.data() || {};
    if (asTrimmedString(groupData.status) !== "submitted") {
      continue;
    }
    matchedGroups += 1;

    const bundleType = asTrimmedString(groupData.bundleType, "single_form");
    if (bundleType === "multi_form") {
      console.log("repairCanonicalGroupForms query start", {
        groupId: groupDoc.id,
        query: `lottery_groups/${groupDoc.id}/forms.get()`,
      });
      const groupFormsSnapshot = await groupDoc.ref.collection("forms").get();
      for (const groupFormDoc of groupFormsSnapshot.docs) {
        const groupFormData = groupFormDoc.data() || {};
        batch.set(groupFormDoc.ref, {
          formId: groupFormDoc.id,
          groupId: groupDoc.id,
          submissionType: "group",
          mode: "group",
          userId: asTrimmedString(
              groupFormData.userId,
              asTrimmedString(groupData.creatorUserId),
          ),
          creatorUserId: asTrimmedString(groupData.creatorUserId),
          creatorDisplayName: asTrimmedString(
              groupFormData.creatorDisplayName,
              asTrimmedString(groupData.creatorName, groupData.creatorUserId),
          ),
          groupName: asTrimmedString(groupData.groupName),
          status: "submitted",
          resultStatus: asTrimmedString(
              groupFormData.resultStatus,
              RESULT_STATUS.waiting,
          ),
          baseTicketCost: firstFiniteNumber([
            groupFormData.baseTicketCost,
            groupData.baseTicketCost,
          ]) || 0,
          effectiveParticipantCount: firstFiniteNumber([
            groupFormData.effectiveParticipantCount,
            groupData.effectiveParticipantCount,
            groupData.finalizedParticipantCount,
          ]) || 1,
          effectiveCostPerPaidParticipant: firstFiniteNumber([
            groupFormData.effectiveCostPerPaidParticipant,
            groupData.currentPerParticipantCost,
          ]) || 0,
          lotteryId: firstFiniteNumber([
            groupFormData.lotteryId,
            groupFormData.drawNumber,
            groupData.lotteryId,
            groupData.drawNumber,
          ]),
          drawNumber: firstFiniteNumber([
            groupFormData.drawNumber,
            groupFormData.lotteryId,
            groupData.drawNumber,
            groupData.lotteryId,
          ]),
          salesCloseAt:
            groupFormData.salesCloseAt ||
            groupFormData.drawDate ||
            groupData.salesCloseAt ||
            groupData.drawDate ||
            null,
          drawDate:
            groupFormData.drawDate ||
            groupFormData.salesCloseAt ||
            groupData.drawDate ||
            groupData.salesCloseAt ||
            null,
          updatedAt:
            groupFormData.updatedAt ||
            admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        if (DEBUG_GROUP_RESULT_GROUP_IDS.has(groupDoc.id)) {
          console.log("repairCanonicalGroupForms normalized child status", {
            groupId: groupDoc.id,
            formId: groupFormDoc.id,
            previousStatus: asTrimmedString(groupFormData.status),
            nextStatus: "submitted",
          });
        }
        operations += 1;
        updatedDocs += 1;
        await commitBatchIfNeeded();
      }
      continue;
    }

    const creatorUserId = asTrimmedString(groupData.creatorUserId);
    const sourceFormId =
      asTrimmedString(groupData.submittedFormId) ||
      asTrimmedString(groupData.sourceFormId);
    if (!creatorUserId || !sourceFormId) {
      continue;
    }

    console.log("repairCanonicalGroupForms query start", {
      groupId: groupDoc.id,
      query: `users/${creatorUserId}/forms/${sourceFormId}`,
    });
    const sourceFormSnapshot = await firestore
        .collection("users")
        .doc(creatorUserId)
        .collection("forms")
        .doc(sourceFormId)
        .get();
    if (!sourceFormSnapshot.exists) {
      continue;
    }

    const sourceFormData = sourceFormSnapshot.data() || {};
    const rawTables = Array.isArray(sourceFormData.tables) ? sourceFormData.tables : [];
    const tableCount = typeof sourceFormData.tableCount === "number" ?
      sourceFormData.tableCount :
      rawTables.filter((table) => normalizeTable(table).regularNumbers.length > 0).length;
    const canonicalGroupFormRef = groupDoc.ref.collection("forms").doc(sourceFormId);
    batch.set(canonicalGroupFormRef, {
      formId: sourceFormId,
      groupId: groupDoc.id,
      displayOrder: 1,
      sourceUserId: creatorUserId,
      sourceDraftNumber: 1,
      status: "submitted",
      submissionType: "group",
      mode: "group",
      userId: creatorUserId,
      creatorUserId,
      creatorDisplayName: asTrimmedString(
          sourceFormData.creatorDisplayName,
          asTrimmedString(groupData.creatorName, creatorUserId),
      ),
      groupName: asTrimmedString(groupData.groupName),
      dispatchStatus: asTrimmedString(
          sourceFormData.dispatchStatus,
          asTrimmedString(groupData.dispatchStatus),
      ),
      baseTicketCost: firstFiniteNumber([
        sourceFormData.baseTicketCost,
        groupData.baseTicketCost,
      ]) || 0,
      effectiveParticipantCount: firstFiniteNumber([
        sourceFormData.effectiveParticipantCount,
        groupData.effectiveParticipantCount,
        groupData.finalizedParticipantCount,
      ]) || 1,
      effectiveCostPerPaidParticipant: firstFiniteNumber([
        sourceFormData.effectiveCostPerPaidParticipant,
        groupData.currentPerParticipantCost,
      ]) || 0,
      submittedParticipantUserIds:
        sourceFormData.submittedParticipantUserIds || [],
      paidParticipants: sourceFormData.paidParticipants || [],
      isDoubleMode: Boolean(sourceFormData.isDoubleMode),
      lotteryId: firstFiniteNumber([
        sourceFormData.lotteryId,
        sourceFormData.drawNumber,
        groupData.lotteryId,
        groupData.drawNumber,
      ]),
      drawNumber: firstFiniteNumber([
        sourceFormData.drawNumber,
        sourceFormData.lotteryId,
        groupData.drawNumber,
        groupData.lotteryId,
      ]),
      salesCloseAt:
        sourceFormData.salesCloseAt ||
        sourceFormData.drawDate ||
        groupData.salesCloseAt ||
        groupData.drawDate ||
        null,
      drawDate:
        sourceFormData.drawDate ||
        sourceFormData.salesCloseAt ||
        groupData.drawDate ||
        groupData.salesCloseAt ||
        null,
      tableCount,
      cost: firstFiniteNumber([
        sourceFormData.cost,
        groupData.baseTicketCost,
      ]) || 0,
      tables: rawTables,
      isComplete: sourceFormData.isComplete !== false,
      createdAt:
        sourceFormData.createdAt ||
        sourceFormData.savedAt ||
        groupData.createdAt ||
        null,
      updatedAt:
        sourceFormData.updatedAt ||
        groupData.updatedAt ||
        admin.firestore.FieldValue.serverTimestamp(),
      submittedAt:
        sourceFormData.submittedAt ||
        groupData.submittedAt ||
        null,
      resultStatus: asTrimmedString(
          sourceFormData.resultStatus,
          RESULT_STATUS.waiting,
      ),
      resultPublishedAt: sourceFormData.resultPublishedAt || null,
      winAmount: firstFiniteNumber([
        sourceFormData.winAmount,
        sourceFormData.winningAmount,
      ]) || 0,
      checkedAt: sourceFormData.checkedAt || null,
      balanceApplied: sourceFormData.balanceApplied === true,
      winAllocations: sourceFormData.winAllocations || null,
      ticketFingerprint: asTrimmedString(sourceFormData.ticketFingerprint) || null,
      ticketFingerprintSource:
        asTrimmedString(sourceFormData.ticketFingerprintSource) || null,
      fingerprintVersion: firstFiniteNumber([
        sourceFormData.fingerprintVersion,
      ]),
      printedAt: sourceFormData.printedAt || null,
      submittedToStationAt: sourceFormData.submittedToStationAt || null,
      printReadyUrl: asTrimmedString(sourceFormData.printReadyUrl) || null,
      printReadyGeneratedAt: sourceFormData.printReadyGeneratedAt || null,
      printReadyStoragePath:
        asTrimmedString(sourceFormData.printReadyStoragePath) || null,
    }, {merge: true});
    if (DEBUG_GROUP_RESULT_GROUP_IDS.has(groupDoc.id)) {
      console.log("repairCanonicalGroupForms normalized single-form child status", {
        groupId: groupDoc.id,
        formId: sourceFormId,
        previousStatus: asTrimmedString(sourceFormData.status),
        nextStatus: "submitted",
      });
    }
    operations += 1;
    updatedDocs += 1;
    await commitBatchIfNeeded();
  }

  await commitBatchIfNeeded(true);
  return {
    scannedGroups: groupDocs.length,
    matchedGroups,
    updatedDocs,
  };
}

async function repairCanonicalPersonalSubmissionForms(options = {}) {
  console.log("repairCanonicalPersonalSubmissionForms query start", {
    query: options.submissionId || options.uid ?
      "targeted personal submissions" :
      "collectionGroup(submissions).limit(stageLimit)",
    options,
  });
  const submissionDocs = await loadTargetPersonalSubmissionDocs(options);
  console.log(
      "repairCanonicalPersonalSubmissionForms scan",
      submissionDocs.length,
  );

  let batch = firestore.batch();
  let operations = 0;
  let updatedDocs = 0;
  let matchedSubmissions = 0;

  const commitBatchIfNeeded = async (force = false) => {
    if (operations === 0) {
      return;
    }
    if (!force && operations < 300) {
      return;
    }
    await batch.commit();
    batch = firestore.batch();
    operations = 0;
  };

  for (const submissionDoc of submissionDocs) {
    const submissionData = submissionDoc.data() || {};
    if (asTrimmedString(submissionData.type) !== "personal" ||
        asTrimmedString(submissionData.status) !== "submitted") {
      continue;
    }
    matchedSubmissions += 1;

    const userId = asTrimmedString(
        submissionData.userId,
        submissionDoc.ref.parent.parent ? submissionDoc.ref.parent.parent.id : "",
    );
    if (!userId) {
      continue;
    }

    console.log("repairCanonicalPersonalSubmissionForms query start", {
      submissionId: submissionDoc.id,
      userId,
      query: `users/${userId}/forms.where(submissionId==${submissionDoc.id})`,
    });
    const canonicalSnapshot = await firestore
        .collection("users")
        .doc(userId)
        .collection("forms")
        .where("submissionId", "==", submissionDoc.id)
        .get();
    const existingCanonicalIds = new Set(
        canonicalSnapshot.docs.map((doc) => doc.id),
    );

    console.log("repairCanonicalPersonalSubmissionForms query start", {
      submissionId: submissionDoc.id,
      userId,
      query: `${submissionDoc.ref.path}/forms.get()`,
    });
    const legacySnapshot = await submissionDoc.ref.collection("forms").get();
    for (const legacyFormDoc of legacySnapshot.docs) {
      if (existingCanonicalIds.has(legacyFormDoc.id)) {
        continue;
      }

      const legacyData = legacyFormDoc.data() || {};
      const canonicalFormRef = firestore
          .collection("users")
          .doc(userId)
          .collection("forms")
          .doc(legacyFormDoc.id);
      batch.set(canonicalFormRef, {
        formId: legacyFormDoc.id,
        submissionId: submissionDoc.id,
        userId,
        displayOrder: firstFiniteNumber([legacyData.displayOrder]) || 0,
        status: "submitted",
        submissionType: "personal",
        mode: "personal",
        isDoubleMode: Boolean(legacyData.isDoubleMode),
        tableCount: firstFiniteNumber([
          legacyData.tableCount,
          Array.isArray(legacyData.tables) ? legacyData.tables.length : 0,
        ]) || 0,
        cost: firstFiniteNumber([legacyData.cost]) || 0,
        tables: Array.isArray(legacyData.tables) ? legacyData.tables : [],
        isComplete: legacyData.isComplete !== false,
        createdAt:
          legacyData.createdAt ||
          submissionData.createdAt ||
          null,
        updatedAt:
          legacyData.updatedAt ||
          submissionData.updatedAt ||
          admin.firestore.FieldValue.serverTimestamp(),
        submittedAt:
          legacyData.submittedAt ||
          submissionData.submittedAt ||
          null,
        savedAt: legacyData.savedAt || null,
        source: "personal_submission_bundle",
        version: firstFiniteNumber([legacyData.version]) || 1,
        lotteryId: firstFiniteNumber([
          legacyData.lotteryId,
          legacyData.drawNumber,
        ]),
        drawNumber: firstFiniteNumber([
          legacyData.drawNumber,
          legacyData.lotteryId,
        ]),
        salesCloseAt: legacyData.salesCloseAt || legacyData.drawDate || null,
        drawDate: legacyData.drawDate || legacyData.salesCloseAt || null,
        resultStatus: asTrimmedString(
            legacyData.resultStatus,
            RESULT_STATUS.waiting,
        ),
        resultPublishedAt: legacyData.resultPublishedAt || null,
        winAmount: firstFiniteNumber([
          legacyData.winAmount,
          legacyData.winningAmount,
        ]) || 0,
        checkedAt: legacyData.checkedAt || null,
        balanceApplied: legacyData.balanceApplied === true,
        printedAt: legacyData.printedAt || null,
        submittedToStationAt: legacyData.submittedToStationAt || null,
        receiptUrl: asTrimmedString(legacyData.receiptUrl) || null,
      }, {merge: true});
      operations += 1;
      updatedDocs += 1;
      await commitBatchIfNeeded();
    }
  }

  await commitBatchIfNeeded(true);
  return {
    scannedSubmissions: submissionDocs.length,
    matchedSubmissions,
    updatedDocs,
  };
}

async function repairMissingPersonalSubmissionLotteryMetadata(options = {}) {
  console.log("repairMissingPersonalSubmissionLotteryMetadata query start", {
    query: options.submissionId || options.uid ?
      "targeted personal submissions" :
      "collectionGroup(submissions).limit(stageLimit)",
    options,
  });
  const submissionDocs = await loadTargetPersonalSubmissionDocs(options);
  console.log(
      "repairMissingPersonalSubmissionLotteryMetadata scan",
      submissionDocs.length,
  );

  let batch = firestore.batch();
  let operations = 0;
  let updatedDocs = 0;
  let matchedSubmissions = 0;
  let queryFailures = 0;

  const commitBatchIfNeeded = async (force = false) => {
    if (operations === 0) {
      return;
    }
    if (!force && operations < 300) {
      return;
    }
    await batch.commit();
    batch = firestore.batch();
    operations = 0;
  };

  for (const submissionDoc of submissionDocs) {
    const submissionData = submissionDoc.data() || {};
    if (asTrimmedString(submissionData.type) !== "personal" ||
        asTrimmedString(submissionData.status) !== "submitted") {
      continue;
    }
    matchedSubmissions += 1;

    const userId = asTrimmedString(
        submissionData.userId,
        submissionDoc.ref.parent.parent ? submissionDoc.ref.parent.parent.id : "",
    );
    if (!userId) {
      continue;
    }

    const canonicalQueryLabel =
      `users/${userId}/forms.where(submissionId==${submissionDoc.id})`;
    console.log("repairMissingPersonalSubmissionLotteryMetadata query start", {
      submissionId: submissionDoc.id,
      userId,
      query: canonicalQueryLabel,
    });
    let canonicalSnapshot;
    try {
      canonicalSnapshot = await firestore
          .collection("users")
          .doc(userId)
          .collection("forms")
          .where("submissionId", "==", submissionDoc.id)
          .get();
    } catch (error) {
      queryFailures += 1;
      logFirestoreQueryFailure({
        scope: "repairMissingPersonalSubmissionLotteryMetadata",
        queryLabel: canonicalQueryLabel,
        collectionPath: `users/${userId}/forms`,
        whereClauses: [
          `submissionId == ${submissionDoc.id}`,
        ],
        orderByClauses: [],
        error,
        extra: {
          submissionId: submissionDoc.id,
          userId,
        },
      });
      continue;
    }

    if (canonicalSnapshot.empty) {
      continue;
    }

    const repairEventDate =
      asDate(submissionData.submittedAt) ||
      asDate(submissionData.createdAt) ||
      asDate(submissionData.drawDate) ||
      asDate(submissionData.salesCloseAt);
    const submissionCurrentMetadata = normalizeLotteryMetadata(submissionData);
    const submissionHasInvalidMetadata = hasInvalidLotteryAssignment(
        submissionCurrentMetadata,
        repairEventDate,
    );
    let hintedLotteryId = normalizeLotteryMetadata(submissionData).lotteryId;
    let hintedDrawDate = coerceValidLotteryDateForEvent(
        asDate(submissionData.salesCloseAt || submissionData.drawDate),
        repairEventDate,
        {
          scope: "repairMissingPersonalSubmissionLotteryMetadata",
          submissionId: submissionDoc.id,
          userId,
          source: "parentSubmission",
        },
    );
    for (const formDoc of canonicalSnapshot.docs) {
      const formMetadata = normalizeLotteryMetadata(formDoc.data() || {});
      if (hasInvalidLotteryAssignment(formMetadata, repairEventDate)) {
        console.log("invalidPastLotteryAssignment", {
          scope: "repairMissingPersonalSubmissionLotteryMetadata",
          submissionId: submissionDoc.id,
          userId,
          source: `childForm:${formDoc.id}`,
          resolvedLotteryId: formMetadata.lotteryId,
          resolvedDrawDate:
            formMetadata.salesCloseAt ? formMetadata.salesCloseAt.toISOString() : null,
          eventDate: repairEventDate ? repairEventDate.toISOString() : null,
        });
        continue;
      }
      if (!hintedLotteryId && formMetadata.lotteryId) {
        hintedLotteryId = formMetadata.lotteryId;
      }
      if (!hintedDrawDate) {
        hintedDrawDate = coerceValidLotteryDateForEvent(
            formMetadata.salesCloseAt,
            repairEventDate,
            {
              scope: "repairMissingPersonalSubmissionLotteryMetadata",
              submissionId: submissionDoc.id,
              userId,
              source: `childForm:${formDoc.id}`,
              candidateLotteryId: formMetadata.lotteryId,
            },
        );
      }
    }
    let metadata = {
      lotteryId: hintedLotteryId,
      drawNumber: hintedLotteryId,
      salesCloseAt: hintedDrawDate,
      drawDate: hintedDrawDate,
    };
    console.log("repairMissingPersonalSubmissionLotteryMetadata candidate", {
      submissionId: submissionDoc.id,
      userId,
      salesCloseAt:
        asDate(submissionData.salesCloseAt || submissionData.drawDate)?.toISOString() ||
        null,
      drawDate:
        asDate(submissionData.drawDate || submissionData.salesCloseAt)?.toISOString() ||
        null,
      resolvedEventDate: repairEventDate ? repairEventDate.toISOString() : null,
      currentLotteryId: hintedLotteryId,
      currentDrawNumber: hintedLotteryId,
      hintedDrawDate: hintedDrawDate ? hintedDrawDate.toISOString() : null,
      submissionHasInvalidMetadata,
    });

    if (isTargetedPersonalSubmissionMode(options)) {
      metadata = await resolveTargetedPersonalSubmissionLotteryMetadata({
        submissionId: submissionDoc.id,
        userId,
        repairEventDate,
        hintedLotteryId,
        hintedDrawDate,
      });
    } else {
      if (!metadata.lotteryId || !metadata.salesCloseAt) {
        try {
          metadata = await resolveLotteryMetadataFallback({
            directData: {
              lotteryId: hintedLotteryId,
              drawNumber: hintedLotteryId,
              salesCloseAt: hintedDrawDate,
              drawDate: hintedDrawDate,
            },
            eventDate: repairEventDate,
            debugContext: {
              scope: "repairMissingPersonalSubmissionLotteryMetadata",
              submissionId: submissionDoc.id,
              userId,
            },
          });
        } catch (error) {
          queryFailures += 1;
          logFirestoreQueryFailure({
            scope: "repairMissingPersonalSubmissionLotteryMetadata",
            queryLabel: "resolveLotteryMetadataFallback",
            collectionPath: "multiple helper queries",
            whereClauses: [
              "collectionGroup(forms).where(lotteryId == hintedLotteryId)",
              "collectionGroup(forms).where(drawNumber == hintedLotteryId)",
              "collectionGroup(forms).where(salesCloseAt == hintedDrawDate)",
              "collectionGroup(forms).where(drawDate == hintedDrawDate)",
            ],
            orderByClauses: [],
            error,
            extra: {
              submissionId: submissionDoc.id,
              userId,
              hintedLotteryId,
              hintedDrawDate: hintedDrawDate ? hintedDrawDate.toISOString() : null,
            },
          });
          metadata = emptyLotteryMetadata();
        }
      }

      metadata = ensureSafeLotteryMetadataForEventDate(
          metadata,
          repairEventDate,
          {
            scope: "repairMissingPersonalSubmissionLotteryMetadata",
            submissionId: submissionDoc.id,
            userId,
            source: "finalValidation",
          },
      );

      if (!metadata.lotteryId || !metadata.salesCloseAt) {
        try {
          metadata = await findEarliestFutureLotteryMetadata(repairEventDate, {
            scope: "repairMissingPersonalSubmissionLotteryMetadata",
            submissionId: submissionDoc.id,
            userId,
          });
        } catch (error) {
          queryFailures += 1;
          logFirestoreQueryFailure({
            scope: "repairMissingPersonalSubmissionLotteryMetadata",
            queryLabel: "findEarliestFutureLotteryMetadata",
            collectionPath: "collectionGroup(forms)",
            whereClauses: [
              repairEventDate ?
                `salesCloseAt >= ${repairEventDate.toISOString()}` :
                "salesCloseAt >= null",
            ],
            orderByClauses: [],
            error,
            extra: {
              submissionId: submissionDoc.id,
              userId,
              repairEventDate: repairEventDate ? repairEventDate.toISOString() : null,
            },
          });
          metadata = emptyLotteryMetadata();
        }
      }

      metadata = ensureSafeLotteryMetadataForEventDate(
          metadata,
          repairEventDate,
          {
            scope: "repairMissingPersonalSubmissionLotteryMetadata",
            submissionId: submissionDoc.id,
            userId,
            source: "futureLotteryValidation",
          },
      );
    }

    const shouldCleanupSubmission =
      submissionHasInvalidMetadata ||
      hasInvalidLotteryAssignment(submissionCurrentMetadata, repairEventDate);

    if (!metadata.lotteryId && !metadata.salesCloseAt) {
      if (shouldCleanupSubmission) {
        batch.set(submissionDoc.ref, {
          ...buildInvalidLotteryCleanupPatch(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        operations += 1;
        updatedDocs += 1;
        for (const formDoc of canonicalSnapshot.docs) {
          batch.set(formDoc.ref, {
            ...buildInvalidLotteryCleanupPatch(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          operations += 1;
          updatedDocs += 1;
          await commitBatchIfNeeded();
        }
      }
      console.log("repairMissingPersonalSubmissionLotteryMetadata unresolved", {
        submissionId: submissionDoc.id,
        userId,
        resolvedEventDate: repairEventDate ? repairEventDate.toISOString() : null,
        cleanedInvalidMetadata: shouldCleanupSubmission,
      });
      continue;
    }

    const metadataPatch = buildLotteryMetadataPatch(metadata);
    console.log("repairMissingPersonalSubmissionLotteryMetadata resolved", {
      submissionId: submissionDoc.id,
      userId,
      resolvedLotteryId: metadata.lotteryId,
      resolvedDrawNumber: metadata.drawNumber,
      updatePayload: metadataPatch,
      shouldCleanupSubmission,
    });
    if (shouldCleanupSubmission) {
      batch.set(submissionDoc.ref, {
        ...buildInvalidLotteryCleanupPatch(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      operations += 1;
      updatedDocs += 1;
    }
    if (needsLotteryMetadataPatch(submissionData, metadata) || shouldCleanupSubmission) {
      batch.set(submissionDoc.ref, {
        ...metadataPatch,
        ...emptyDerivedResultPatch(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      operations += 1;
      updatedDocs += 1;
    }

    for (const formDoc of canonicalSnapshot.docs) {
      const formData = formDoc.data() || {};
      const formCurrentMetadata = normalizeLotteryMetadata(formData);
      const formHasInvalidMetadata = hasInvalidLotteryAssignment(
          formCurrentMetadata,
          repairEventDate,
      );
      if (formHasInvalidMetadata) {
        batch.set(formDoc.ref, {
          ...buildInvalidLotteryCleanupPatch(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        operations += 1;
        updatedDocs += 1;
      }
      if (!needsLotteryMetadataPatch(formData, metadata) && !formHasInvalidMetadata) {
        continue;
      }
      batch.set(formDoc.ref, {
        ...metadataPatch,
        ...emptyDerivedResultPatch(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      operations += 1;
      updatedDocs += 1;
      await commitBatchIfNeeded();
    }
  }

  await commitBatchIfNeeded(true);
  return {
    scannedSubmissions: submissionDocs.length,
    matchedSubmissions,
    updatedDocs,
    queryFailures,
  };
}

async function repairMissingGroupLotteryMetadata(options = {}) {
  console.log("repairMissingGroupLotteryMetadata query start", {
    query: options.groupId ?
      `lottery_groups/${options.groupId}` :
      "collection(lottery_groups).limit(stageLimit)",
    options,
  });
  const groupDocs = await loadTargetGroupDocs(options);
  console.log("repairMissingGroupLotteryMetadata scan", groupDocs.length);

  let batch = firestore.batch();
  let operations = 0;
  let updatedDocs = 0;
  let matchedGroups = 0;

  const commitBatchIfNeeded = async (force = false) => {
    if (operations === 0) {
      return;
    }
    if (!force && operations < 350) {
      return;
    }
    await batch.commit();
    batch = firestore.batch();
    operations = 0;
  };

  for (const groupDoc of groupDocs) {
    const groupData = groupDoc.data() || {};
    matchedGroups += 1;
    console.log("repairMissingGroupLotteryMetadata query start", {
      query: `lottery_groups/${groupDoc.id}/forms.get()`,
      groupId: groupDoc.id,
    });
    const formsSnapshot = await groupDoc.ref.collection("forms").get();
    const metadata = await resolveGroupLotteryMetadata({
      groupId: groupDoc.id,
      groupData,
      groupFormsDocs: formsSnapshot.docs,
    });

    if (!metadata.lotteryId && !metadata.salesCloseAt) {
      continue;
    }

    const groupPatch = buildLotteryMetadataPatch(metadata);
    if (needsLotteryMetadataPatch(groupData, metadata)) {
      batch.set(groupDoc.ref, groupPatch, {merge: true});
      operations += 1;
      updatedDocs += 1;
    }

    for (const formDoc of formsSnapshot.docs) {
      const formData = formDoc.data() || {};
      if (!needsLotteryMetadataPatch(formData, metadata)) {
        continue;
      }
      batch.set(formDoc.ref, {
        ...groupPatch,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      operations += 1;
      updatedDocs += 1;
      await commitBatchIfNeeded();
    }
  }

  await commitBatchIfNeeded(true);
  return {
    scannedGroups: groupDocs.length,
    matchedGroups,
    updatedDocs,
  };
}

async function resolveAndRepairLotteryMetadataForFormDoc(doc, options = {}) {
  const data = doc.data() || {};
  let metadata = normalizeLotteryMetadata(data);
  if (!metadata.lotteryId || !metadata.salesCloseAt) {
    if (isGroupFormDocument(doc.ref)) {
      const groupRef = doc.ref.parent.parent;
      const groupSnapshot = groupRef ? await groupRef.get() : null;
      const groupData = groupSnapshot && groupSnapshot.exists ?
        (groupSnapshot.data() || {}) :
        {};
      metadata = await resolveGroupLotteryMetadata({
        groupId: groupRef ? groupRef.id : "",
        groupData,
        groupFormsDocs: [doc],
      });
      if (needsLotteryMetadataPatch(data, metadata)) {
        await doc.ref.set(buildLotteryMetadataPatch(metadata), {merge: true});
      }
      if (groupRef && groupSnapshot && needsLotteryMetadataPatch(groupData, metadata)) {
        await groupRef.set(buildLotteryMetadataPatch(metadata), {merge: true});
      }
    } else {
      if (isTargetedPersonalSubmissionMode(options)) {
        console.log("resolveAndRepairLotteryMetadataForFormDoc targeted personal skip fallback", {
          formPath: doc.ref.path,
          submissionId: asTrimmedString(data.submissionId),
          userId: asTrimmedString(data.userId),
          query: "no collectionGroup fallback in targeted personal mode",
        });
      } else {
        metadata = await resolveLotteryMetadataFallback({
          directData: data,
          eventDate:
            asDate(data.submittedAt) ||
            asDate(data.createdAt) ||
            asDate(data.savedAt),
        });
        if (needsLotteryMetadataPatch(data, metadata)) {
          await doc.ref.set(buildLotteryMetadataPatch(metadata), {merge: true});
        }
      }
    }
  }

  return metadata;
}

async function repairMissingGroupResultSummaries(options = {}) {
  console.log("repairMissingGroupResultSummaries query start", {
    query: options.groupId ?
      `lottery_groups/${options.groupId}` :
      "collection(lottery_groups).limit(stageLimit)",
    options,
  });
  const groupDocs = await loadTargetGroupDocs(options);
  console.log("repairMissingGroupResultSummaries scan", groupDocs.length);
  let rebuiltGroups = 0;
  let matchedGroups = 0;

  for (const groupDoc of groupDocs) {
    const groupData = groupDoc.data() || {};
    if (asTrimmedString(groupData.status) !== "submitted") {
      continue;
    }
    matchedGroups += 1;

    console.log("repairMissingGroupResultSummaries repairing", {
      groupId: groupDoc.id,
      bundleType: asTrimmedString(groupData.bundleType, "single_form"),
      submittedFormId: asTrimmedString(groupData.submittedFormId),
      sourceFormId: asTrimmedString(groupData.sourceFormId),
      creatorUserId: asTrimmedString(groupData.creatorUserId),
      repairNeeded: needsGroupResultSummaryRepair(groupData),
    });

    await reconcileGroupResultSummary({
      groupRef: groupDoc.ref,
      fallbackData: groupData,
      repairReason: "missing_group_result_summary",
    });
    rebuiltGroups += 1;
  }
  return {
    scannedGroups: groupDocs.length,
    matchedGroups,
    rebuiltGroups,
  };
}

async function repairPersonalSubmissionSummaries(options = {}) {
  console.log("repairPersonalSubmissionSummaries query start", {
    query: options.submissionId || options.uid ?
      "targeted personal submissions" :
      "collectionGroup(submissions).limit(stageLimit)",
    options,
  });
  const submissionDocs = await loadTargetPersonalSubmissionDocs(options);
  console.log("repairPersonalSubmissionSummaries scan", submissionDocs.length);
  let rebuiltSubmissions = 0;
  let matchedSubmissions = 0;

  for (const submissionDoc of submissionDocs) {
    const submissionData = submissionDoc.data() || {};
    if (asTrimmedString(submissionData.type) !== "personal" ||
        asTrimmedString(submissionData.status) !== "submitted") {
      continue;
    }
    matchedSubmissions += 1;

    const userId = asTrimmedString(
        submissionData.userId,
        submissionDoc.ref.parent.parent ? submissionDoc.ref.parent.parent.id : "",
    );
    if (!userId) {
      continue;
    }

    await reconcilePersonalSubmissionSummary({
      submissionRef: submissionDoc.ref,
      userId,
      submissionId: submissionDoc.id,
      fallbackData: submissionData,
      repairReason: "summary_rebuild_scan",
    });
    rebuiltSubmissions += 1;
  }
  return {
    scannedSubmissions: submissionDocs.length,
    matchedSubmissions,
    rebuiltSubmissions,
  };
}

async function reconcilePersonalSubmissionSummary({
  submissionRef,
  userId,
  submissionId,
  fallbackData = {},
  repairReason = "unknown",
}) {
  console.log("reconcilePersonalSubmissionSummary query start", {
    submissionId,
    userId,
    query: `users/${userId}/forms.where(submissionId==${submissionId})`,
    repairReason,
  });
  const canonicalSnapshot = await firestore
      .collection("users")
      .doc(userId)
      .collection("forms")
      .where("submissionId", "==", submissionId)
      .get();

  let sourceForms = canonicalSnapshot.docs
      .filter((doc) =>
        asTrimmedString(doc.data()?.status) === "submitted" &&
        isCanonicalSubmittedResultDoc(doc.ref, doc.data() || {}))
      .map((doc) => ({ref: doc.ref, data: doc.data() || {}}));

  if (!sourceForms.length) {
    console.log("reconcilePersonalSubmissionSummary query start", {
      submissionId,
      userId,
      query: `${submissionRef.path}/forms.get()`,
      repairReason,
    });
    const legacySnapshot = await submissionRef.collection("forms").get();
    sourceForms = legacySnapshot.docs.map((doc) => ({
      ref: doc.ref,
      data: doc.data() || {},
    }));
  }

  if (!sourceForms.length) {
    return;
  }

  const publishedForms = sourceForms.filter((entry) => isResultPublished(entry.data));
  const allPublished = publishedForms.length === sourceForms.length;
  const anyPublished = publishedForms.length > 0;
  const totalWinningAmount = sourceForms.reduce(
      (sum, entry) => sum + resultAmountFromData(entry.data),
      0,
  );
  const resultPublishedAt = publishedForms.reduce((latest, entry) => {
    const date = asDate(entry.data.resultPublishedAt);
    if (!date) {
      return latest;
    }
    return !latest || date.getTime() > latest.getTime() ? date : latest;
  }, null);
  const totalCost = sourceForms.reduce(
      (sum, entry) => sum + (firstFiniteNumber([entry.data.cost]) || 0),
      0,
  );
  const formCount = sourceForms.length;
  const primaryMetadata = sourceForms.reduce(
      (metadata, entry) => mergeLotteryMetadata(
          metadata,
          normalizeLotteryMetadata(entry.data),
      ),
      normalizeLotteryMetadata(fallbackData),
  );

  let resultStatus = asTrimmedString(fallbackData.resultStatus);
  if (allPublished) {
    resultStatus = totalWinningAmount > 0 ? RESULT_STATUS.winner : RESULT_STATUS.loser;
  } else if (anyPublished) {
    resultStatus = RESULT_STATUS.checked;
  } else if (!resultStatus) {
    resultStatus = RESULT_STATUS.waiting;
  }

  const summaryPatch = {
    resultStatus,
    resultPublishedAt: resultPublishedAt || null,
    totalWinningAmount,
    winAmount: totalWinningAmount,
    winningAmount: totalWinningAmount,
    formCount,
    totalCost,
    lotteryId: primaryMetadata.lotteryId ?? null,
    drawNumber: primaryMetadata.drawNumber ?? primaryMetadata.lotteryId ?? null,
    salesCloseAt: primaryMetadata.salesCloseAt ?? null,
    drawDate: primaryMetadata.drawDate ?? primaryMetadata.salesCloseAt ?? null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  console.log("reconcilePersonalSubmissionSummary patch", {
    submissionId,
    userId,
    formCount,
    totalWinningAmount,
    resultStatus,
    resultPublishedAtExists: Boolean(summaryPatch.resultPublishedAt),
    repairReason,
  });

  await submissionRef.set(summaryPatch, {merge: true});
}

function needsGroupResultSummaryRepair(groupData) {
  const resultStatus = asTrimmedString(groupData?.resultStatus);
  const hasResultPublishedAt = Boolean(asDate(groupData?.resultPublishedAt));
  const hasGroupWinningAmount = typeof groupData?.groupWinningAmount === "number" &&
    Number.isFinite(groupData.groupWinningAmount);
  const hasMyWinningAmount = typeof groupData?.myWinningAmount === "number" &&
    Number.isFinite(groupData.myWinningAmount);
  const hasLegacyWinningAmount = typeof groupData?.winAmount === "number" &&
    Number.isFinite(groupData.winAmount);

  return !hasResultPublishedAt ||
    !resultStatus ||
    !hasGroupWinningAmount ||
    !hasMyWinningAmount ||
    !hasLegacyWinningAmount;
}

async function reconcileGroupResultSummary({
  sourceFormRef,
  groupRef,
  fallbackData,
  repairReason = "unknown",
}) {
  const groupId = asTrimmedString(fallbackData.groupId);
  if (!groupId) {
    return;
  }

  const resolvedGroupRef =
    groupRef || firestore.collection("lottery_groups").doc(groupId);
  const groupSnapshot = await resolvedGroupRef.get();
  if (!groupSnapshot.exists) {
    console.log("reconcileGroupResultSummary missing group", {
      groupId,
      formPath: sourceFormRef ? sourceFormRef.path : null,
      repairReason,
    });
    return;
  }

  const groupData = groupSnapshot.data() || {};
  const creatorUserId = asTrimmedString(
      groupData.creatorUserId,
      asTrimmedString(fallbackData.creatorUserId),
  );
  const bundleType = asTrimmedString(groupData.bundleType, "single_form");

  let sourceForms = [];
  console.log("reconcileGroupResultSummary query start", {
    groupId,
    query: `lottery_groups/${groupId}/forms.get()`,
    repairReason,
  });
  const canonicalFormsSnapshot = await resolvedGroupRef.collection("forms").get();
  sourceForms = canonicalFormsSnapshot.docs.map((doc) => ({
    ref: doc.ref,
    data: doc.data() || {},
  }));

  if (!sourceForms.length) {
    const submittedFormId = asTrimmedString(groupData.submittedFormId);
    const sourceFormId = asTrimmedString(groupData.sourceFormId);
    const formId = submittedFormId || sourceFormId;
    if (!creatorUserId || !formId) {
      console.log("reconcileGroupResultSummary missing single-form refs", {
        groupId,
        creatorUserId,
        submittedFormId,
        sourceFormId,
      });
      return;
    }
    console.log("reconcileGroupResultSummary query start", {
      groupId,
      query: `users/${creatorUserId}/forms/${formId}`,
      repairReason,
    });
    const sourceFormSnapshot = await firestore
        .collection("users")
        .doc(creatorUserId)
        .collection("forms")
        .doc(formId)
        .get();
    if (!sourceFormSnapshot.exists) {
      console.log("reconcileGroupResultSummary source form missing", {
        groupId,
        creatorUserId,
        formId,
        repairReason,
      });
      return;
    }
    sourceForms = [{
      ref: sourceFormSnapshot.ref,
      data: sourceFormSnapshot.data() || {},
    }];
  }

  if (!sourceForms.length) {
    return;
  }

  const publishedForms = sourceForms.filter((entry) => isResultPublished(entry.data));
  const allPublished = publishedForms.length === sourceForms.length;
  const anyPublished = publishedForms.length > 0;
  const totalWinAmount = sourceForms.reduce(
      (sum, entry) => sum + resultAmountFromData(entry.data),
      0,
  );
  const resultPublishedAt = publishedForms.reduce((latest, entry) => {
    const date =
      asDate(entry.data.resultPublishedAt) ||
      asDate(entry.data.checkedAt) ||
      asDate(entry.data.updatedAt);
    if (!date) {
      return latest;
    }
    return !latest || date.getTime() > latest.getTime() ? date : latest;
  }, null);

  let groupResultStatus = asTrimmedString(groupData.resultStatus);
  if (allPublished) {
    groupResultStatus = totalWinAmount > 0 ? RESULT_STATUS.winner : RESULT_STATUS.loser;
  } else if (anyPublished) {
    groupResultStatus = RESULT_STATUS.checked;
  }

  const participantUserIds = extractParticipantUserIds(sourceForms, groupData);
  const effectiveParticipantCount = Number(
      groupData.effectiveParticipantCount ||
      groupData.finalizedParticipantCount ||
      participantUserIds.length,
  ) || participantUserIds.length;
  const myWinningAmounts = new Map();
  for (const userId of participantUserIds) {
    myWinningAmounts.set(
        userId,
        sourceForms.reduce(
            (sum, entry) =>
              sum + resolveUserWinningAmountFromForm(entry.data, userId, participantUserIds.length),
            0,
        ),
    );
  }
  const creatorWinningAmount = creatorUserId ?
    (myWinningAmounts.get(creatorUserId) || 0) :
    0;

  const summaryPatch = {
    resultStatus: groupResultStatus || null,
    resultPublishedAt: resultPublishedAt || null,
    groupWinningAmount: totalWinAmount,
    myWinningAmount: creatorWinningAmount,
    winAmount: totalWinAmount,
    winningAmount: totalWinAmount,
    effectiveParticipantCount,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  console.log("reconcileGroupResultSummary patch", {
    groupId,
    bundleType,
    allPublished,
    anyPublished,
    resultStatus: summaryPatch.resultStatus,
    resultPublishedAtExists: Boolean(summaryPatch.resultPublishedAt),
    totalWinAmount,
    creatorWinningAmount,
    participantCount: participantUserIds.length,
    repairReason,
  });

  if (DEBUG_GROUP_RESULT_GROUP_IDS.has(groupId)) {
    console.log("reconcileGroupResultSummary debug target hit", {
      groupId,
      repairReason,
      creatorUserId,
      sourceFormPath:
        sourceForms.length === 1 && sourceForms[0].ref ?
          sourceForms[0].ref.path :
          null,
      sourceFormsCount: sourceForms.length,
      sourceForms: sourceForms.map((entry) => ({
        path: entry.ref ? entry.ref.path : null,
        resultStatus: asTrimmedString(entry.data.resultStatus),
        resultPublishedAtExists: Boolean(asDate(entry.data.resultPublishedAt)),
        winAmount: firstFiniteNumber([
          entry.data.winAmount,
          entry.data.winningAmount,
          entry.data.groupWinningAmount,
        ]),
        myWinningAmount: firstFiniteNumber([entry.data.myWinningAmount]),
      })),
      groupPatchPreview: summaryPatch,
      submittedGroupsTargets: participantUserIds.map((userId) => ({
        userId,
        path: `users/${userId}/submitted_groups/${groupId}`,
        myWinningAmount: myWinningAmounts.get(userId) || 0,
      })),
    });
  }

  const batch = firestore.batch();
  batch.set(resolvedGroupRef, summaryPatch, {merge: true});

  for (const userId of participantUserIds) {
    batch.set(
        firestore
            .collection("users")
            .doc(userId)
            .collection("submitted_groups")
            .doc(groupId),
        {
          ...summaryPatch,
          myWinningAmount: myWinningAmounts.get(userId) || 0,
        },
        {merge: true},
    );
  }

  await batch.commit();
}

async function resolveGroupLotteryMetadata({
  groupId,
  groupData,
  groupFormsDocs = [],
}) {
  let metadata = normalizeLotteryMetadata(groupData);
  if (metadata.lotteryId && metadata.salesCloseAt) {
    return metadata;
  }

  const snapshotData = groupData.formSnapshot || {};
  metadata = mergeLotteryMetadata(metadata, normalizeLotteryMetadata(snapshotData));
  if (metadata.lotteryId && metadata.salesCloseAt) {
    return metadata;
  }

  for (const formDoc of groupFormsDocs) {
    const formData = typeof formDoc.data === "function" ? formDoc.data() || {} : {};
    metadata = mergeLotteryMetadata(metadata, normalizeLotteryMetadata(formData));
    if (metadata.lotteryId && metadata.salesCloseAt) {
      return metadata;
    }
  }

  const creatorUserId = asTrimmedString(groupData.creatorUserId);
  const submittedFormId = asTrimmedString(groupData.submittedFormId);
  const sourceFormId = asTrimmedString(groupData.sourceFormId);
  for (const formId of [submittedFormId, sourceFormId]) {
    if (!creatorUserId || !formId) {
      continue;
    }
    console.log("resolveGroupLotteryMetadata source form query start", {
      groupId,
      creatorUserId,
      formId,
      query: `users/${creatorUserId}/forms/${formId}`,
    });
    const sourceSnapshot = await firestore
        .collection("users")
        .doc(creatorUserId)
        .collection("forms")
        .doc(formId)
        .get();
    console.log("resolveGroupLotteryMetadata source form query done", {
      groupId,
      creatorUserId,
      formId,
      exists: sourceSnapshot.exists,
    });
    if (!sourceSnapshot.exists) {
      continue;
    }
    metadata = mergeLotteryMetadata(
        metadata,
        normalizeLotteryMetadata(sourceSnapshot.data() || {}),
    );
    if (metadata.lotteryId && metadata.salesCloseAt) {
      return metadata;
    }
  }

  metadata = await resolveLotteryMetadataFallback({
    directData: groupData,
    eventDate:
      metadata.salesCloseAt ||
      asDate(groupData.submittedAt) ||
      asDate(groupData.createdAt),
  });

  if (!metadata.lotteryId || !metadata.salesCloseAt) {
    console.log("resolveGroupLotteryMetadata unresolved", groupId);
  }

  return metadata;
}

async function resolveTargetedPersonalSubmissionLotteryMetadata({
  submissionId,
  userId,
  repairEventDate,
  hintedLotteryId,
  hintedDrawDate,
}) {
  let metadata = {
    lotteryId: hintedLotteryId || null,
    drawNumber: hintedLotteryId || null,
    salesCloseAt: hintedDrawDate || null,
    drawDate: hintedDrawDate || null,
  };

  metadata = ensureSafeLotteryMetadataForEventDate(
      metadata,
      repairEventDate,
      {
        scope: "repairMissingPersonalSubmissionLotteryMetadata",
        submissionId,
        userId,
        source: "targetedDirectHints",
      },
  );

  if (metadata.lotteryId && metadata.salesCloseAt) {
    console.log("repairMissingPersonalSubmissionLotteryMetadata targeted resolved", {
      submissionId,
      userId,
      query: "direct submission + child forms hints",
      resolvedLotteryId: metadata.lotteryId,
      resolvedDrawDate: metadata.salesCloseAt.toISOString(),
      sourceOfDrawDate: "childFormOrParentSubmission",
    });
    return metadata;
  }

  console.log("repairMissingPersonalSubmissionLotteryMetadata targeted next-lottery lookup", {
    submissionId,
    userId,
    query: "fetchNextLotteryMetadata()",
    eventDate: repairEventDate ? repairEventDate.toISOString() : null,
  });

  try {
    const nextLottery = await fetchNextLotteryMetadata();
    const nextMetadata = ensureSafeLotteryMetadataForEventDate({
      lotteryId: firstFiniteNumber([
        nextLottery?.lotteryId,
        nextLottery?.drawNumber,
      ]),
      drawNumber: firstFiniteNumber([
        nextLottery?.drawNumber,
        nextLottery?.lotteryId,
      ]),
      salesCloseAt: asDate(nextLottery?.salesCloseAt || nextLottery?.drawDate),
      drawDate: asDate(nextLottery?.drawDate || nextLottery?.salesCloseAt),
    }, repairEventDate, {
      scope: "repairMissingPersonalSubmissionLotteryMetadata",
      submissionId,
      userId,
      source: "officialNextLottery",
    });

    if (nextMetadata.lotteryId && nextMetadata.salesCloseAt) {
      console.log("repairMissingPersonalSubmissionLotteryMetadata targeted next-lottery match", {
        submissionId,
        userId,
        matchedDocId: String(nextMetadata.lotteryId),
        resolvedLotteryId: nextMetadata.lotteryId,
        resolvedDrawDate: nextMetadata.salesCloseAt.toISOString(),
        sourceOfDrawDate: "lotteryMetadata",
      });
      return nextMetadata;
    }
  } catch (error) {
    console.error("repairMissingPersonalSubmissionLotteryMetadata targeted next-lottery lookup failed", {
      submissionId,
      userId,
      query: "fetchNextLotteryMetadata()",
      message: error && error.message ? error.message : String(error),
      stack: error && error.stack ? error.stack : null,
    });
  }

  console.log("repairMissingPersonalSubmissionLotteryMetadata targeted unresolved", {
    submissionId,
    userId,
    eventDate: repairEventDate ? repairEventDate.toISOString() : null,
    sourceOfDrawDate: "none",
  });
  return emptyLotteryMetadata();
}

async function resolveLotteryMetadataFallback({
  directData,
  eventDate,
  debugContext = null,
}) {
  let metadata = normalizeLotteryMetadata(directData);
  if (metadata.salesCloseAt) {
    metadata = {
      lotteryId: metadata.lotteryId,
      drawNumber: metadata.drawNumber,
      salesCloseAt: coerceValidLotteryDateForEvent(
          metadata.salesCloseAt,
          eventDate,
          {
            ...(debugContext || {}),
            source: "directData",
            candidateLotteryId: metadata.lotteryId,
          },
      ),
      drawDate: coerceValidLotteryDateForEvent(
          metadata.drawDate,
          eventDate,
          {
            ...(debugContext || {}),
            source: "directData",
            candidateLotteryId: metadata.lotteryId,
          },
      ),
    };
  }
  if (metadata.lotteryId && metadata.salesCloseAt) {
    return metadata;
  }

  if (metadata.lotteryId && !metadata.salesCloseAt) {
    if (debugContext) {
      console.log("resolveLotteryMetadataFallback exact-lotteryId search", {
        ...debugContext,
        lotteryId: metadata.lotteryId,
      });
    }
    metadata = mergeLotteryMetadata(
        metadata,
        await findLotteryMetadataByLotteryId(metadata.lotteryId, debugContext),
    );
    metadata = ensureSafeLotteryMetadataForEventDate(metadata, eventDate, {
      ...(debugContext || {}),
      source: "lotteryMetadata",
    });
  }

  if ((!metadata.lotteryId || !metadata.salesCloseAt) && metadata.salesCloseAt) {
    if (debugContext) {
      console.log("resolveLotteryMetadataFallback searching", {
        ...debugContext,
        targetDate: metadata.salesCloseAt.toISOString(),
      });
    }
    metadata = mergeLotteryMetadata(
        metadata,
        await findLotteryMetadataBySalesCloseAt(metadata.salesCloseAt, debugContext),
    );
    metadata = ensureSafeLotteryMetadataForEventDate(metadata, eventDate, {
      ...(debugContext || {}),
      source: "fallback",
    });
  }

  return metadata;
}

async function findLotteryMetadataByLotteryId(lotteryId, debugContext = null) {
  if (!Number.isFinite(Number(lotteryId)) || Number(lotteryId) <= 0) {
    return emptyLotteryMetadata();
  }

  try {
    const upcomingLottery = await fetchNextLotteryMetadata();
    if (
      Number(upcomingLottery?.lotteryId) === Number(lotteryId) &&
      upcomingLottery?.salesCloseAt
    ) {
      const officialMetadata = {
        lotteryId: Number(lotteryId),
        drawNumber: Number(lotteryId),
        salesCloseAt: asDate(upcomingLottery.salesCloseAt),
        drawDate: asDate(upcomingLottery.salesCloseAt),
      };
      console.log("findLotteryMetadataByLotteryId official upcoming match", {
        lotteryId,
        resolvedLotteryId: officialMetadata.lotteryId,
        resolvedDrawDate: officialMetadata.salesCloseAt.toISOString(),
        ...(debugContext || {}),
      });
      return officialMetadata;
    }
  } catch (error) {
    console.error("findLotteryMetadataByLotteryId official upcoming lookup failed", {
      lotteryId,
      code: error && error.code ? error.code : null,
      message: error && error.message ? error.message : String(error),
      ...(debugContext || {}),
    });
  }

  console.log("findLotteryMetadataByLotteryId query start", {
    query: "collectionGroup(forms).where(lotteryId==lotteryId).limit(20)",
    lotteryId,
    ...(debugContext || {}),
  });
  let directSnapshot;
  try {
    directSnapshot = await firestore
        .collectionGroup("forms")
        .where("lotteryId", "==", Number(lotteryId))
        .limit(20)
        .get();
  } catch (error) {
    console.error("findLotteryMetadataByLotteryId query failed", {
      query: "collectionGroup(forms).where(lotteryId==lotteryId).limit(20)",
      lotteryId,
      code: error && error.code ? error.code : null,
      message: error && error.message ? error.message : String(error),
      ...(debugContext || {}),
    });
    throw error;
  }
  if (!directSnapshot.empty) {
    const directMatch = metadataFromDocsWithLotteryIdMatch(
        directSnapshot.docs,
        Number(lotteryId),
        "forms.lotteryId==lotteryId",
        debugContext,
    );
    if (directMatch.salesCloseAt) {
      return directMatch;
    }
  }

  console.log("findLotteryMetadataByLotteryId query start", {
    query: "collectionGroup(forms).where(drawNumber==lotteryId).limit(20)",
    lotteryId,
    ...(debugContext || {}),
  });
  let drawNumberSnapshot;
  try {
    drawNumberSnapshot = await firestore
        .collectionGroup("forms")
        .where("drawNumber", "==", Number(lotteryId))
        .limit(20)
        .get();
  } catch (error) {
    console.error("findLotteryMetadataByLotteryId query failed", {
      query: "collectionGroup(forms).where(drawNumber==lotteryId).limit(20)",
      lotteryId,
      code: error && error.code ? error.code : null,
      message: error && error.message ? error.message : String(error),
      ...(debugContext || {}),
    });
    throw error;
  }
  if (!drawNumberSnapshot.empty) {
    const drawNumberMatch = metadataFromDocsWithLotteryIdMatch(
        drawNumberSnapshot.docs,
        Number(lotteryId),
        "forms.drawNumber==lotteryId",
        debugContext,
    );
    if (drawNumberMatch.salesCloseAt) {
      return drawNumberMatch;
    }
  }

  return emptyLotteryMetadata();
}

function metadataFromDocsWithLotteryIdMatch(
    docs,
    lotteryId,
    queryLabel,
    debugContext = null,
) {
  for (const doc of docs) {
    const data = doc.data() || {};
    const metadata = normalizeLotteryMetadata(data);
    if (metadata.lotteryId !== Number(lotteryId) || !metadata.salesCloseAt) {
      continue;
    }
    console.log("findLotteryMetadataByLotteryId match", {
      ...(debugContext || {}),
      queryLabel,
      lotteryId,
      matchedDocPath: doc.ref.path,
      matchedDocId: doc.id,
      resolvedLotteryId: metadata.lotteryId,
      resolvedDrawDate:
        metadata.salesCloseAt ? metadata.salesCloseAt.toISOString() : null,
      sourceOfDrawDate: "lotteryMetadata",
    });
    return metadata;
  }
  console.log("findLotteryMetadataByLotteryId no-valid-metadata", {
    ...(debugContext || {}),
    queryLabel,
    lotteryId,
    scannedDocs: docs.length,
  });
  return emptyLotteryMetadata();
}

function metadataFromDocsWithDateMatch(docs, targetDate, queryLabel, debugContext = null) {
  for (const doc of docs) {
    const data = doc.data() || {};
    const metadata = normalizeLotteryMetadata(data);
    if (!metadata.lotteryId) {
      continue;
    }
    console.log("findLotteryMetadataBySalesCloseAt match", {
      ...(debugContext || {}),
      queryLabel,
      targetDate: targetDate.toISOString(),
      matchedDocPath: doc.ref.path,
      matchedDocId: doc.id,
      resolvedLotteryId: metadata.lotteryId,
      resolvedDrawNumber: metadata.drawNumber,
      resolvedDrawDate:
        metadata.salesCloseAt ? metadata.salesCloseAt.toISOString() : null,
      sourceOfDrawDate: "fallback",
    });
    return metadata;
  }
  console.log("findLotteryMetadataBySalesCloseAt no-valid-metadata", {
    ...(debugContext || {}),
    queryLabel,
    targetDate: targetDate.toISOString(),
    scannedDocs: docs.length,
  });
  return emptyLotteryMetadata();
}

async function findLotteryMetadataBySalesCloseAt(targetDate, debugContext = null) {
  if (!targetDate) {
    return emptyLotteryMetadata();
  }

  console.log("findLotteryMetadataBySalesCloseAt query start", {
    query: "collectionGroup(forms).where(salesCloseAt==targetDate).limit(20)",
    targetDate: targetDate.toISOString(),
    ...(debugContext || {}),
  });
  let exactSnapshot;
  try {
    exactSnapshot = await firestore
        .collectionGroup("forms")
        .where("salesCloseAt", "==", admin.firestore.Timestamp.fromDate(targetDate))
        .limit(20)
        .get();
  } catch (error) {
    console.error("findLotteryMetadataBySalesCloseAt query failed", {
      query: "collectionGroup(forms).where(salesCloseAt==targetDate).limit(20)",
      targetDate: targetDate.toISOString(),
      code: error && error.code ? error.code : null,
      message: error && error.message ? error.message : String(error),
      ...(debugContext || {}),
    });
    throw error;
  }
  if (!exactSnapshot.empty) {
    const exactMatch = metadataFromDocsWithDateMatch(
        exactSnapshot.docs,
        targetDate,
        "forms.salesCloseAt==targetDate",
        debugContext,
    );
    if (exactMatch.lotteryId) {
      return exactMatch;
    }
  }

  console.log("findLotteryMetadataBySalesCloseAt query start", {
    query: "collectionGroup(forms).where(drawDate==targetDate).limit(20)",
    targetDate: targetDate.toISOString(),
    ...(debugContext || {}),
  });
  let exactDrawDateSnapshot;
  try {
    exactDrawDateSnapshot = await firestore
        .collectionGroup("forms")
        .where("drawDate", "==", admin.firestore.Timestamp.fromDate(targetDate))
        .limit(20)
        .get();
  } catch (error) {
    console.error("findLotteryMetadataBySalesCloseAt query failed", {
      query: "collectionGroup(forms).where(drawDate==targetDate).limit(20)",
      targetDate: targetDate.toISOString(),
      code: error && error.code ? error.code : null,
      message: error && error.message ? error.message : String(error),
      ...(debugContext || {}),
    });
    throw error;
  }
  if (!exactDrawDateSnapshot.empty) {
    const exactDrawDateMatch = metadataFromDocsWithDateMatch(
        exactDrawDateSnapshot.docs,
        targetDate,
        "forms.drawDate==targetDate",
        debugContext,
    );
    if (exactDrawDateMatch.lotteryId) {
      return exactDrawDateMatch;
    }
  }

  return emptyLotteryMetadata();
}

async function findEarliestFutureLotteryMetadata(eventDate, debugContext = null) {
  if (!eventDate) {
    return emptyLotteryMetadata();
  }

  console.log("findEarliestFutureLotteryMetadata query start", {
    query: "collectionGroup(forms).where(salesCloseAt>=eventDate).limit(20)",
    eventDate: eventDate.toISOString(),
    ...(debugContext || {}),
  });
  let snapshot;
  try {
    snapshot = await firestore
        .collectionGroup("forms")
        .where("salesCloseAt", ">=", admin.firestore.Timestamp.fromDate(eventDate))
        .limit(20)
        .get();
  } catch (error) {
    console.error("findEarliestFutureLotteryMetadata query failed", {
      query: "collectionGroup(forms).where(salesCloseAt>=eventDate).limit(20)",
      eventDate: eventDate.toISOString(),
      code: error && error.code ? error.code : null,
      message: error && error.message ? error.message : String(error),
      ...(debugContext || {}),
    });
    throw error;
  }

  let bestMetadata = null;
  let bestDoc = null;
  for (const doc of snapshot.docs) {
    const metadata = normalizeLotteryMetadata(doc.data() || {});
    if (!metadata.lotteryId || !metadata.salesCloseAt) {
      continue;
    }
    if (metadata.salesCloseAt.getTime() < eventDate.getTime()) {
      continue;
    }
    if (!bestMetadata ||
        metadata.salesCloseAt.getTime() < bestMetadata.salesCloseAt.getTime()) {
      bestMetadata = metadata;
      bestDoc = doc;
    }
  }

  if (!bestMetadata) {
    console.log("findEarliestFutureLotteryMetadata no-valid-metadata", {
      eventDate: eventDate.toISOString(),
      scannedDocs: snapshot.docs.length,
      ...(debugContext || {}),
    });
    return emptyLotteryMetadata();
  }

  console.log("findEarliestFutureLotteryMetadata match", {
    eventDate: eventDate.toISOString(),
    matchedDocPath: bestDoc.ref.path,
    matchedDocId: bestDoc.id,
    resolvedLotteryId: bestMetadata.lotteryId,
    resolvedDrawDate: bestMetadata.salesCloseAt.toISOString(),
    sourceOfDrawDate: "futureLotteryMetadata",
    ...(debugContext || {}),
  });
  return bestMetadata;
}

function isGroupFormDocument(formRef) {
  return formRef.parent &&
    formRef.parent.id === "forms" &&
    formRef.parent.parent &&
    formRef.parent.parent.parent &&
    formRef.parent.parent.parent.id === "lottery_groups";
}

function isUserFormDocument(formRef) {
  return formRef.parent &&
    formRef.parent.id === "forms" &&
    formRef.parent.parent &&
    formRef.parent.parent.parent &&
    formRef.parent.parent.parent.id === "users";
}

function isCanonicalSubmittedResultDoc(formRef, data) {
  if (isGroupFormDocument(formRef)) {
    return true;
  }
  if (!isUserFormDocument(formRef)) {
    return false;
  }

  const submissionType = asTrimmedString(data?.submissionType);
  const source = asTrimmedString(data?.source);
  if (submissionType === "group" || source === "group_snapshot") {
    return false;
  }

  return true;
}

function shouldProcessCanonicalResultDoc(data) {
  const resultStatus = asTrimmedString(data.resultStatus, RESULT_STATUS.waiting);
  if (isResultPublished(data)) {
    return false;
  }

  const status = asTrimmedString(data.status);
  const submissionType = asTrimmedString(data.submissionType);
  const hasLotteryId = firstFiniteNumber([data.lotteryId, data.drawNumber]) !== null;
  const drawDate = asDate(data.salesCloseAt || data.drawDate);
  const isPastDraw = Boolean(drawDate && drawDate.getTime() <= Date.now());
  const isAllowedGroupLockedState =
    submissionType === "group" &&
    status === "locked_for_group" &&
    hasLotteryId &&
    isPastDraw;

  if (status !== "submitted" && !isAllowedGroupLockedState) {
    return false;
  }

  return (
    !resultStatus ||
    resultStatus === RESULT_STATUS.waiting ||
    resultStatus === "pending"
  );
}

function emptyLotteryMetadata() {
  return {
    lotteryId: null,
    drawNumber: null,
    salesCloseAt: null,
    drawDate: null,
  };
}

function emptyDerivedResultPatch() {
  return {
    resultStatus: RESULT_STATUS.waiting,
    resultPublishedAt: null,
    winAmount: 0,
    winningAmount: 0,
    totalWinningAmount: 0,
    checkedAt: null,
    balanceApplied: false,
  };
}

function buildInvalidLotteryCleanupPatch() {
  return {
    lotteryId: null,
    drawNumber: null,
    salesCloseAt: null,
    drawDate: null,
    ...emptyDerivedResultPatch(),
  };
}

function hasInvalidLotteryAssignment(metadata, eventDate) {
  return Boolean(
      eventDate &&
      metadata &&
      metadata.salesCloseAt &&
      metadata.salesCloseAt.getTime() < eventDate.getTime(),
  );
}

function coerceValidLotteryDateForEvent(dateValue, eventDate, debugContext = null) {
  const date = asDate(dateValue);
  if (!date) {
    return null;
  }
  if (!eventDate) {
    return date;
  }
  if (date.getTime() >= eventDate.getTime()) {
    return date;
  }
  console.log("invalidPastLotteryAssignment", {
    ...(debugContext || {}),
    eventDate: eventDate.toISOString(),
    candidateDrawDate: date.toISOString(),
  });
  return null;
}

function ensureSafeLotteryMetadataForEventDate(
    metadata,
    eventDate,
    debugContext = null,
) {
  if (!eventDate || !metadata.salesCloseAt) {
    return metadata;
  }
  if (metadata.salesCloseAt.getTime() >= eventDate.getTime()) {
    return metadata;
  }
  console.log("invalidPastLotteryAssignment", {
    ...(debugContext || {}),
    resolvedLotteryId: metadata.lotteryId,
    resolvedDrawDate: metadata.salesCloseAt.toISOString(),
    eventDate: eventDate.toISOString(),
  });
  return emptyLotteryMetadata();
}

function isResultPublished(data) {
  const resultStatus = asTrimmedString(data?.resultStatus);
  const hasExplicitAmount =
    firstFiniteNumber([
      data?.groupWinningAmount,
      data?.winAmount,
      data?.winningAmount,
    ]) !== null;
  return Boolean(asDate(data?.resultPublishedAt)) ||
    resultStatus === RESULT_STATUS.winner ||
    resultStatus === RESULT_STATUS.loser ||
    resultStatus === RESULT_STATUS.checked ||
    (hasExplicitAmount && !isWaitingResultStatus(resultStatus));
}

function isWaitingResultStatus(resultStatus) {
  const normalized = asTrimmedString(resultStatus).toLowerCase();
  return !normalized ||
    normalized === RESULT_STATUS.waiting ||
    normalized === "waitingforresults" ||
    normalized === "pending";
}

function resultAmountFromData(data) {
  const candidates = [
    data?.groupWinningAmount,
    data?.winAmount,
    data?.winningAmount,
  ];
  for (const value of candidates) {
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
  }
  return 0;
}

function extractParticipantUserIds(sourceForms, groupData) {
  const ids = new Set();
  for (const entry of sourceForms) {
    const data = entry.data || {};
    const directUserIds = Array.isArray(data.submittedParticipantUserIds) ?
      data.submittedParticipantUserIds :
      [];
    for (const rawUserId of directUserIds) {
      const userId = asTrimmedString(rawUserId);
      if (userId) {
        ids.add(userId);
      }
    }
    const paidParticipants = Array.isArray(data.paidParticipants) ?
      data.paidParticipants :
      [];
    for (const participant of paidParticipants) {
      const userId = asTrimmedString(participant?.userId);
      if (userId) {
        ids.add(userId);
      }
    }
  }
  if (!ids.size) {
    const creatorUserId = asTrimmedString(groupData?.creatorUserId);
    if (creatorUserId) {
      ids.add(creatorUserId);
    }
  }
  return Array.from(ids);
}

function resolveUserWinningAmountFromForm(data, userId, participantCount) {
  const directAmount = firstFiniteNumber([
    data?.myWinningAmount,
  ]);
  if (directAmount !== null && directAmount > 0) {
    return directAmount;
  }

  const fromAllocations = extractWinningAllocationForUser(
      data?.winAllocations,
      userId,
  );
  if (fromAllocations !== null) {
    return fromAllocations;
  }

  if (participantCount === 1) {
    return resultAmountFromData(data);
  }

  return 0;
}

function extractWinningAllocationForUser(winAllocations, userId) {
  if (!winAllocations) {
    return null;
  }
  if (Array.isArray(winAllocations)) {
    for (const entry of winAllocations) {
      if (asTrimmedString(entry?.userId) === userId) {
        return Number(entry?.amount) || 0;
      }
    }
    return null;
  }
  if (typeof winAllocations === "object") {
    const direct = winAllocations[userId];
    if (typeof direct === "number" && Number.isFinite(direct)) {
      return direct;
    }
    for (const [key, value] of Object.entries(winAllocations)) {
      if (asTrimmedString(key) === userId &&
          typeof value === "number" &&
          Number.isFinite(value)) {
        return value;
      }
    }
  }
  return null;
}

function firstFiniteNumber(candidates) {
  for (const value of candidates) {
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
  }
  return null;
}

function normalizeLotteryMetadata(data) {
  const directLotteryId = Number(data?.lotteryId ?? data?.drawNumber);
  const lotteryId = Number.isFinite(directLotteryId) && directLotteryId > 0 ?
    directLotteryId :
    null;
  const salesCloseAt = asDate(data?.salesCloseAt ?? data?.drawDate);
  return {
    lotteryId,
    drawNumber: lotteryId,
    salesCloseAt,
    drawDate: salesCloseAt,
  };
}

function mergeLotteryMetadata(primary, fallback) {
  return {
    lotteryId: primary.lotteryId ?? fallback.lotteryId ?? null,
    drawNumber:
      primary.drawNumber ?? primary.lotteryId ??
      fallback.drawNumber ?? fallback.lotteryId ?? null,
    salesCloseAt: primary.salesCloseAt ?? fallback.salesCloseAt ?? null,
    drawDate: primary.drawDate ?? primary.salesCloseAt ??
      fallback.drawDate ?? fallback.salesCloseAt ?? null,
  };
}

function buildLotteryMetadataPatch(metadata) {
  return {
    lotteryId: metadata.lotteryId ?? null,
    drawNumber: metadata.drawNumber ?? metadata.lotteryId ?? null,
    salesCloseAt: metadata.salesCloseAt ?? null,
    drawDate: metadata.drawDate ?? metadata.salesCloseAt ?? null,
  };
}

function needsLotteryMetadataPatch(currentData, metadata) {
  const current = normalizeLotteryMetadata(currentData);
  return (
    current.lotteryId !== metadata.lotteryId ||
    current.drawNumber !== (metadata.drawNumber ?? metadata.lotteryId ?? null) ||
    dateMillis(current.salesCloseAt) !== dateMillis(metadata.salesCloseAt) ||
    dateMillis(current.drawDate) !==
      dateMillis(metadata.drawDate ?? metadata.salesCloseAt ?? null)
  );
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
        winningAmount: winAmount,
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
          updates.groupWinningAmount = winAmount;
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
          const ownerUserId = asTrimmedString(freshData.userId);
          if (!ownerUserId) {
            throw new Error(`Could not resolve owner userId for form ${formRef.id}`);
          }
          if (isGroupForm) {
            updates.groupWinningAmount = winAmount;
            updates.myWinningAmount = winAmount;
          }
          const userRef = firestore.collection("users").doc(ownerUserId);
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

      if (freshData.submissionType === "group" &&
          !Object.prototype.hasOwnProperty.call(updates, "groupWinningAmount")) {
        updates.groupWinningAmount = winAmount;
      }

      transaction.update(formRef, updates);
    });

    if (asTrimmedString(formData.submissionType) === "group") {
      const groupId =
        formRef.parent && formRef.parent.parent ? formRef.parent.parent.id : null;
      if (groupId && DEBUG_GROUP_RESULT_GROUP_IDS.has(groupId)) {
        console.log("applyLotteryResultToForm debug target hit", {
          groupId,
          formPath: formRef.path,
          resultStatus,
          winAmount,
          resultPublishedAt: result.resultPublishedAt ?
            result.resultPublishedAt.toDate().toISOString() :
            null,
        });
      }
      await reconcileGroupResultSummary({
        sourceFormRef: formRef,
        fallbackData: formData,
        repairReason: "post_form_result_application",
      });
    } else {
      const submissionId = asTrimmedString(formData.submissionId);
      const userId = asTrimmedString(formData.userId);
      if (submissionId && userId) {
        await reconcilePersonalSubmissionSummary({
          submissionRef: firestore
              .collection("users")
              .doc(userId)
              .collection("submissions")
              .doc(submissionId),
          userId,
          submissionId,
          repairReason: "post_form_result_application",
        });
      }
    }
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
    const displayDate = asTrimmedString(nextLottery.displayDate);
    const displayTime = asTrimmedString(nextLottery.displayTime);
    const regularLottoPrize = formatUpcomingFirstPrize(nextLottery.firstPrize);
    const doubleLottoPrize =
        deriveDoublePrizeTextFromFirstPrize(regularLottoPrize);

    if (!Number.isFinite(lotteryId) || !salesCloseAt) {
      throw new Error("Pais next lottery payload was missing required fields.");
    }

    console.log(
        "fetchNextLotteryMetadata parsed",
        lotteryId,
        nextLottery.displayDate,
        nextLottery.displayTime,
    );
    console.log("upcoming lottery final response", {
      displayDate,
      firstPrize: nextLottery.firstPrize,
      regularLottoPrize,
      doubleLottoPrize,
    });

    return {
      lotteryId,
      salesCloseAt,
      displayDate,
      displayTime,
      regularLottoPrize,
      doubleLottoPrize,
    };
  } catch (error) {
    console.error("fetchNextLotteryMetadata failed", error);
    throw error;
  }
}

function buildUpcomingLotteryCachePayload(metadata, reason = "unknown") {
  return {
    lotteryId: metadata.lotteryId,
    drawNumber: metadata.lotteryId,
    drawDate: metadata.salesCloseAt,
    salesCloseAt: metadata.salesCloseAt,
    displayDate: metadata.displayDate || null,
    displayTime: metadata.displayTime || null,
    regularFirstPrize: metadata.regularLottoPrize || null,
    doubleFirstPrize: metadata.doubleLottoPrize || null,
    regularLottoPrize: metadata.regularLottoPrize || null,
    doubleLottoPrize: metadata.doubleLottoPrize || null,
    source: `fetchNextLotteryMetadata:${reason}`,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function syncUpcomingLotteryCache({reason = "manual"} = {}) {
  const metadata = await fetchNextLotteryMetadata();
  const payload = buildUpcomingLotteryCachePayload(metadata, reason);
  await UPCOMING_LOTTERY_CACHE_DOC.set(payload, {merge: true});
  console.log("syncUpcomingLotteryCache success", {
    reason,
    lotteryId: metadata.lotteryId,
    salesCloseAt: metadata.salesCloseAt ?
      metadata.salesCloseAt.toISOString() :
      null,
    displayDate: metadata.displayDate || null,
    displayTime: metadata.displayTime || null,
  });
  return metadata;
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

function extractUpcomingPrizeValue(payload, candidateKeys) {
  for (const key of candidateKeys) {
    const value = asTrimmedString(payload[key]);
    if (value) {
      return value;
    }
  }

  for (const [key, rawValue] of Object.entries(payload)) {
    const normalizedSourceKey = String(key).toLowerCase().replace(/[^a-z0-9]/g, "");
    const matchesCandidate = candidateKeys.some((candidate) => {
      const normalizedCandidate = String(candidate).toLowerCase().replace(/[^a-z0-9]/g, "");
      return normalizedSourceKey.includes(normalizedCandidate) ||
        normalizedCandidate.includes(normalizedSourceKey);
    });
    if (!matchesCandidate) {
      continue;
    }

    const value = asTrimmedString(rawValue);
    if (value) {
      return value;
    }
  }

  const nestedValue = extractUpcomingPrizeValueFromNested(payload, candidateKeys);
  if (nestedValue) {
    return nestedValue;
  }

  return null;
}

function deriveDoublePrizeTextFromFirstPrize(firstPrizeText) {
  const normalized = asTrimmedString(firstPrizeText);
  if (!normalized) {
    return null;
  }

  const match = normalized.match(/([\d.,]+)/);
  if (!match) {
    return null;
  }

  const numericPortion = Number(match[1].replace(/,/g, ""));
  if (!Number.isFinite(numericPortion)) {
    return null;
  }

  const doubled = numericPortion * 2;
  const suffix = normalized.replace(match[1], "").trim();
  const formattedValue = Number.isInteger(doubled)
    ? String(doubled)
    : doubled.toFixed(1).replace(/\.0$/, "");

  return suffix ? `${formattedValue} ${suffix}` : formattedValue;
}

function formatUpcomingFirstPrize(rawValue) {
  const numericValue = Number(rawValue);
  if (!Number.isFinite(numericValue) || numericValue <= 0) {
    return null;
  }

  const millions = numericValue / 1000000;
  const formattedMillions = Number.isInteger(millions)
    ? String(millions)
    : millions.toFixed(1).replace(/\.0$/, "");

  return `${formattedMillions} מיליון`;
}

function extractUpcomingPrizeValueFromNested(payload, candidateKeys) {
  const queue = [payload];
  const visited = new Set();
  const normalizedCandidates = candidateKeys.map((candidate) =>
    String(candidate).toLowerCase().replace(/[^a-z0-9]/g, ""),
  );

  while (queue.length > 0) {
    const current = queue.shift();
    if (!current || typeof current !== "object" || visited.has(current)) {
      continue;
    }
    visited.add(current);

    for (const [key, rawValue] of Object.entries(current)) {
      const normalizedSourceKey = String(key).toLowerCase().replace(/[^a-z0-9]/g, "");
      const matchesCandidate = normalizedCandidates.some((candidate) =>
        normalizedSourceKey.includes(candidate) ||
        candidate.includes(normalizedSourceKey),
      );

      if (matchesCandidate) {
        const value = asTrimmedString(rawValue);
        if (value) {
          return value;
        }
      }

      if (rawValue && typeof rawValue === "object") {
        queue.push(rawValue);
      }
    }
  }

  return null;
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

  if (!Array.isArray(data.tables) ||
      data.tables.length < 1 ||
      data.tables.length > MAX_TABLE_COUNT) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        `Between 1 and ${MAX_TABLE_COUNT} tables are required.`,
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

function asTrimmedString(value, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function asDate(value) {
  if (!value) {
    return null;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value.toDate === "function") {
    try {
      return value.toDate();
    } catch (_) {
      return null;
    }
  }
  return null;
}

function dateMillis(value) {
  const date = asDate(value);
  return date ? date.getTime() : null;
}

function asPositiveNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function refundAmountForMembership(membership, currentPerParticipantCost) {
  if (asTrimmedString(membership.paymentStatus) !== "paid") {
    return 0;
  }

  const directShare = asPositiveNumber(membership.costShare);
  if (directShare > 0) {
    return directShare;
  }

  return asPositiveNumber(currentPerParticipantCost);
}

function refundAmountForUser(memberships, userId, currentPerParticipantCost) {
  const membership = memberships.find((entry) => entry.userId === userId);
  if (!membership) {
    return 0;
  }
  return refundAmountForMembership(membership, currentPerParticipantCost);
}

function computeStableValidMemberships(memberships) {
  let current = Array.isArray(memberships) ? [...memberships] : [];

  while (true) {
    const participantCount = current.length;
    const next = current.filter((membership) =>
      participantCount >=
        (Number(membership.minimumParticipantsRequired) || 1),
    );
    if (next.length === current.length) {
      return next;
    }
    current = next;
  }
}

function creatorDisplayNameFromMemberships(memberships, creatorUserId) {
  const creatorMembership = memberships.find((entry) =>
    entry.userId === creatorUserId &&
      typeof entry.displayName === "string" &&
      entry.displayName.trim(),
  );

  if (creatorMembership && creatorMembership.displayName.trim()) {
    return creatorMembership.displayName.trim();
  }

  return creatorUserId;
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

  return rawTables.map((table, index) => normalizeTable(table, index));
}

function normalizeTable(table, index = 0) {
  if (!table || typeof table !== "object" || Array.isArray(table)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        `Table ${index + 1} is malformed.`,
    );
  }

  const rawRegularNumbers = Array.isArray(table.regularNumbers) ?
    table.regularNumbers :
    Array.isArray(table.numbers) ?
      table.numbers :
      Array.isArray(table.selectedNumbers) ?
        table.selectedNumbers :
        [];
  if (!Array.isArray(rawRegularNumbers)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        `Table ${index + 1} regular numbers are malformed.`,
    );
  }

  const regularNumbers = normalizeRegularNumbers(
      rawRegularNumbers
          .map((value) => Number(value))
          .filter(isRegularNumber),
  );
  const rawStrongNumber =
    table.strongNumber != null ? table.strongNumber : table.strong;
  const strongNumber =
    rawStrongNumber == null ? null : Number(rawStrongNumber);

  return {
    tableIndex: Number(table.tableIndex) || index + 1,
    regularNumbers,
    strongNumber: isStrongNumber(strongNumber) ? strongNumber : null,
    isComplete: isTableComplete({
      regularNumbers,
      strongNumber,
    }),
  };
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
    tables.length >= 1 &&
    tables.length <= MAX_TABLE_COUNT &&
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
