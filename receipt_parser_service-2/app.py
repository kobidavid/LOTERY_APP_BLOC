from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
import tempfile
import os
import traceback

from lotto_extractor_anthropic import extract_lotto_data

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # לפיתוח בלבד
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {"ok": True, "message": "lotto extractor api is running"}


@app.post("/extract-lotto-ticket")
async def extract_lotto_ticket(file: UploadFile = File(...)):
    suffix = Path(file.filename or "upload.pdf").suffix.lower()

    if suffix not in {".pdf", ".jpg", ".jpeg", ".png"}:
        raise HTTPException(status_code=400, detail="Unsupported file type")

    tmp_path = None

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(await file.read())
            tmp_path = tmp.name

        result = extract_lotto_data(tmp_path)
        return {"ok": True, "data": result}

    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)