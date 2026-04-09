#!/usr/bin/env python3
import base64
import hashlib
import json
import os
from pathlib import Path
from typing import Optional

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

SUPPORTED_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png"}
MODEL = "claude-opus-4-5"

EXTRACTION_PROMPT = """This is a scanned Israeli Lotto ticket. Extract the data carefully and return ONLY a JSON object.

THE GRID STRUCTURE:
- The ticket has a table with two sections separated by a vertical line: "6/37" on the left and "1/7" on the right.
- Each row is one lottery table, numbered (1), (2), (3), etc. on the FAR RIGHT.
- The "6/37" section contains exactly 6 numbers per row.
- The "1/7" section contains exactly 1 number per row (the strong number).
- Numbers are printed RIGHT-TO-LEFT (Hebrew), so read each row from right to left, but sort them ascending in your output.
- Count rows carefully. Do NOT skip any row and do NOT add extra rows.

FIELDS TO EXTRACT:
1. "lotteryId": integer. Find "משתתף/משתתפת בהגרלה מס':" followed by something like "3890(26)". Extract ONLY the first number (3890).
2. "ticketType": "דאבל לוטו" if the ticket explicitly says "דאבל לוטו", otherwise "רגיל".
3. "tables": one entry per row in the grid.
   - "regularNumbers": exactly 6 integers from the 6/37 column, sorted ascending.
   - "strongNumber": exactly 1 integer from the 1/7 column.

IMPORTANT:
- Every row in the grid must appear in "tables".
- Do not confuse the row index number (1),(2)... with the actual lottery numbers.
- The strong number is ONLY from the 1/7 column.
- Return ONLY valid JSON.

Return this exact shape:
{
  "lotteryId": <number>,
  "ticketType": "<string>",
  "tables": [
    {"regularNumbers": [<6 sorted ints>], "strongNumber": <int>},
    ...
  ]
}"""


def pdf_to_base64_images(pdf_path: str) -> list[str]:
    import fitz

    doc = fitz.open(pdf_path)
    results = []
    for page in doc:
        pix = page.get_pixmap(dpi=300)
        jpeg_bytes = pix.tobytes("jpeg")
        results.append(base64.b64encode(jpeg_bytes).decode())
    doc.close()
    return results


def strip_code_fences(raw: str) -> str:
    raw = raw.strip()
    if raw.startswith("```"):
        parts = raw.split("```")
        if len(parts) >= 2:
            raw = parts[1]
            if raw.startswith("json"):
                raw = raw[4:]
            raw = raw.strip()
    return raw


def normalize_ticket_type(value: str) -> str:
    value = (value or "").strip()
    if value == "דאבל לוטו":
        return "דאבל לוטו"
    return "רגיל"


def normalize_table(table: dict) -> Optional[dict]:
    if not isinstance(table, dict):
        return None

    regular_numbers = table.get("regularNumbers")
    strong_number = table.get("strongNumber")

    if not isinstance(regular_numbers, list) or len(regular_numbers) != 6:
        return None

    try:
        nums = [int(x) for x in regular_numbers]
        strong = int(strong_number)
    except Exception:
        return None

    if any(n < 1 or n > 37 for n in nums):
        return None
    if len(set(nums)) != 6:
        return None
    if strong < 1 or strong > 7:
        return None

    return {
        "regularNumbers": sorted(nums),
        "strongNumber": strong,
    }


def validate_and_normalize(data: dict) -> dict:
    if not isinstance(data, dict):
        raise ValueError("Model response is not a JSON object")

    lottery_id = data.get("lotteryId")
    try:
        lottery_id = int(lottery_id)
    except Exception as e:
        raise ValueError("lotteryId is missing or invalid") from e

    if not (1000 <= lottery_id <= 9999):
        raise ValueError(f"lotteryId out of range: {lottery_id}")

    ticket_type = normalize_ticket_type(str(data.get("ticketType", "")).strip())

    tables_in = data.get("tables")
    if not isinstance(tables_in, list) or len(tables_in) == 0:
        raise ValueError("tables is missing or empty")

    tables = []
    for table in tables_in:
        normalized = normalize_table(table)
        if normalized is None:
            raise ValueError(f"Invalid table: {table}")
        tables.append(normalized)

    return {
        "lotteryId": lottery_id,
        "ticketType": ticket_type,
        "tables": tables,
    }


def build_ticket_fingerprint_source(lottery_id: int, tables: list[dict]) -> str:
    normalized_rows = []
    for table in tables:
        row = "".join(f"{n:02d}" for n in sorted(table["regularNumbers"]))
        normalized_rows.append(f"{row}-{table['strongNumber']}")
    return f"{lottery_id}-{len(tables):02d}-" + "-".join(normalized_rows)


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def enrich_with_fingerprint(data: dict) -> dict:
    source = build_ticket_fingerprint_source(data["lotteryId"], data["tables"])
    fingerprint = sha256_hex(source)
    return {
        **data,
        "ticketFingerprintSource": source,
        "ticketFingerprint": fingerprint,
    }


def extract_lotto_data(file_path: str, api_key: Optional[str] = None) -> dict:
    import anthropic

    path = Path(file_path)
    if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise ValueError(f"Unsupported file type: {path.suffix}")

    key = api_key or os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        raise ValueError("No API key. Use ANTHROPIC_API_KEY or pass api_key.")

    client = anthropic.Anthropic(api_key=key)
    ext = path.suffix.lower()
    content = []

    if ext == ".pdf":
        for b64 in pdf_to_base64_images(str(path)):
            content.append({
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": b64,
                }
            })
    else:
        mime = {
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".png": "image/png",
        }[ext]

        with open(path, "rb") as f:
            b64 = base64.b64encode(f.read()).decode()

        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": mime,
                "data": b64,
            }
        })

    content.append({"type": "text", "text": EXTRACTION_PROMPT})

    response = client.messages.create(
        model=MODEL,
        max_tokens=2000,
        messages=[{"role": "user", "content": content}],
    )

    if not response.content:
        raise RuntimeError("Anthropic response.content is empty")

    raw = response.content[0].text.strip()
    raw = strip_code_fences(raw)

    parsed = json.loads(raw)
    normalized = validate_and_normalize(parsed)
    return enrich_with_fingerprint(normalized)