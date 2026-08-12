import io
import json
import os
from datetime import date
from typing import List, Optional

import psycopg2
import pytesseract
import requests
from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image, ImageOps
from psycopg2.extras import RealDictCursor
from pydantic import BaseModel

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://ollama:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3.2:3b")

DB_HOST = os.environ.get("DB_HOST", "receipt-db")
DB_USER = os.environ.get("DB_USER")
DB_PASSWORD = os.environ.get("DB_PASSWORD")
DB_NAME = os.environ.get("DB_NAME")

app = FastAPI(title="Receipt Tracker")


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


class ReceiptItem(BaseModel):
    name: str
    price: float
    quantity: float = 1


class ReceiptIn(BaseModel):
    store: Optional[str] = None
    purchased_at: Optional[date] = None
    subtotal: Optional[float] = None
    tax: Optional[float] = None
    total: Optional[float] = None
    items: List[ReceiptItem] = []


EXTRACTION_PROMPT = """You are given the raw OCR text of a grocery store receipt. \
Extract the following as JSON and return ONLY the JSON, no other text, no markdown fences:

{{
  "store": string or null,
  "purchased_at": "YYYY-MM-DD" or null,
  "subtotal": number or null,
  "tax": number or null,
  "total": number or null,
  "items": [
    {{"name": string, "price": number, "quantity": number}}
  ]
}}

Rules:
- OCR text can be messy or misspelled; use your best judgement to fix obvious OCR errors in item names.
- If quantity isn't shown, assume 1.
- Only include lines that are actual purchased items, not headers, barcodes, loyalty numbers, or payment/card info.
- All monetary values should be plain numbers (no currency symbols, no commas).

OCR TEXT:
{ocr_text}
"""


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/receipts/extract")
async def extract_receipt(file: UploadFile = File(...)):
    """Takes a receipt photo, OCRs it, and asks the local LLM to structure it.
    Returns the parsed data WITHOUT saving it, so the caller (the Shortcut)
    can show it to the user for a quick confirm/edit before committing.
    """
    image_bytes = await file.read()
    try:
        image = Image.open(io.BytesIO(image_bytes))
        # Respect the phone’s orientation tag
        image = ImageOps.exif_transpose(image)
        # Make sure Tesseract gets a format it likes
        image = image.convert("RGB")
    except Exception:
        raise HTTPException(status_code=400, detail="Could not read image file")

    ocr_text = pytesseract.image_to_string(image)
    if not ocr_text.strip():
        raise HTTPException(status_code=422, detail="No text detected in image")

    prompt = EXTRACTION_PROMPT.format(ocr_text=ocr_text)

    try:
        response = requests.post(
            f"{OLLAMA_HOST}/api/generate",
            json={
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False,
                "format": "json",
            },
            timeout=120,
        )
        response.raise_for_status()
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"Ollama request failed: {exc}")

    raw_output = response.json().get("response", "")
    try:
        parsed = json.loads(raw_output)
    except json.JSONDecodeError:
        raise HTTPException(status_code=502, detail="Model did not return valid JSON")

    return {"raw_ocr_text": ocr_text, "parsed": parsed}


@app.post("/api/receipts")
def create_receipt(receipt: ReceiptIn):
    """Commits a (possibly user-corrected) parsed receipt to the database."""
    conn = get_db_connection()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO receipts (store, purchased_at, subtotal, tax, total)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id
                """,
                (receipt.store, receipt.purchased_at, receipt.subtotal, receipt.tax, receipt.total),
            )
            receipt_id = cur.fetchone()[0]

            for item in receipt.items:
                cur.execute(
                    """
                    INSERT INTO receipt_items (receipt_id, name, price, quantity)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (receipt_id, item.name, item.price, item.quantity),
                )
        return {"id": receipt_id, "status": "saved"}
    finally:
        conn.close()


@app.get("/api/receipts")
def list_receipts(limit: int = 50):
    conn = get_db_connection()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT * FROM receipts
                ORDER BY purchased_at DESC NULLS LAST, id DESC
                LIMIT %s
                """,
                (limit,),
            )
            return cur.fetchall()
    finally:
        conn.close()
