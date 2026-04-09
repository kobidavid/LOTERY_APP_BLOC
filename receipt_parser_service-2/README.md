# Lotto ticket parser

Parser for scanned Israeli lottery tickets (PDF/image) such as files created by **Import from iPhone -> Scan Documents** on macOS.

## What it extracts
- `lotteryId`
- `ticketType` (`"דאבל לוטו"` or `"רגיל"`)
- `tables` with:
  - `regularNumbers`
  - `strongNumber`

## Install
```bash
pip install -r requirements.txt
```

System requirements:
- `tesseract` must be installed
- Hebrew language data for tesseract is recommended (`heb`)

macOS example:
```bash
brew install tesseract tesseract-lang poppler
```

## Run
```bash
python parser.py "/path/to/Scanned Document 8.pdf" --pretty
```

## Expected output on your sample
```json
{
  "lotteryId": 3890,
  "ticketType": "דאבל לוטו",
  "tables": [
    { "regularNumbers": [3, 5, 8, 9, 11, 25], "strongNumber": 5 },
    { "regularNumbers": [7, 14, 17, 19, 30, 34], "strongNumber": 2 },
    { "regularNumbers": [1, 6, 14, 15, 23, 36], "strongNumber": 4 },
    { "regularNumbers": [2, 8, 18, 24, 26, 27], "strongNumber": 3 },
    { "regularNumbers": [3, 4, 6, 12, 17, 23], "strongNumber": 2 },
    { "regularNumbers": [5, 6, 9, 14, 22, 35], "strongNumber": 7 }
  ]
}
```

## Notes
- The parser is tuned for relatively clean scans.
- If you later support casual camera photos, you will likely want stronger preprocessing and maybe a layout detector.
- For production, add validation rules and logging of OCR text for failures.
