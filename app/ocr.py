import re
import logging
from typing import Set
import pytesseract
from PIL import Image
import PyPDF2
import docx
import openpyxl

from app.redis import get_user_keywords

logger = logging.getLogger(__name__)

def normalize_text(text: str) -> str:
    """Normalize text for keyword matching: lowercase, remove extra whitespace and punctuation."""
    # Convert to lowercase
    text = text.lower()
    # Replace non-alphanumeric characters (except spaces) with space
    text = re.sub(r'[^a-z0-9\s]', ' ', text)
    # Collapse multiple spaces
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def extract_text(file_path: str, mime_type: str) -> str:
    """
    Extract text from a file based on its MIME type.
    Supports: images (via Tesseract), PDF, DOCX, XLSX, TXT.
    Returns empty string on failure.
    """
    try:
        if mime_type.startswith('image/'):
            # Use Tesseract OCR for images
            img = Image.open(file_path)
            # Configure Tesseract to use English and Arabic (if needed)
            # We'll use the default language (eng) but can be extended
            text = pytesseract.image_to_string(img, lang='eng+ara')
            return text

        elif mime_type == 'application/pdf':
            text = []
            with open(file_path, 'rb') as f:
                reader = PyPDF2.PdfReader(f)
                for page in reader.pages:
                    text.append(page.extract_text())
            return '\n'.join(text)

        elif mime_type in ['application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                           'application/msword']:
            # .docx
            doc = docx.Document(file_path)
            text = [para.text for para in doc.paragraphs]
            return '\n'.join(text)

        elif mime_type in ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                           'application/vnd.ms-excel']:
            # .xlsx
            wb = openpyxl.load_workbook(file_path, read_only=True, data_only=True)
            text = []
            for sheet in wb.worksheets:
                for row in sheet.iter_rows(values_only=True):
                    # Convert each cell to string and join by space
                    row_text = ' '.join(str(cell) for cell in row if cell is not None)
                    if row_text:
                        text.append(row_text)
            return '\n'.join(text)

        elif mime_type.startswith('text/'):
            # Plain text, CSV, etc.
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                return f.read()

        else:
            logger.warning(f"Unsupported MIME type for OCR: {mime_type}")
            return ""

    except Exception as e:
        logger.error(f"OCR extraction failed for {file_path} ({mime_type}): {e}")
        return ""

def contains_keywords(text: str, keywords: Set[str]) -> bool:
    """
    Check if any of the keywords (already normalized) appear in the normalized text.
    """
    normalized = normalize_text(text)
    # Split into words and check for any keyword
    words = set(normalized.split())
    return bool(words & keywords)

async def load_user_keywords(user_id: str) -> Set[str]:
    """
    Load OCR keywords for a user from Redis.
    Returns an empty set if none or on error.

    Async because the underlying store is the application's async Redis client
    (app/redis.py). It was previously declared sync while its caller in
    media.py used it as a plain value, which worked only because the call it
    delegated to could never succeed.
    """
    return await get_user_keywords(user_id)