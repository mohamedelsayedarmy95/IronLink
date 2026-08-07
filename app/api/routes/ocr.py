from __future__ import annotations

from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, TypeAdapter

from app.api.deps import get_current_user
from app.models import User
from app.redis import get_user_keywords, set_user_keywords

router = APIRouter(tags=["ocr"])


class KeywordList(BaseModel):
    keywords: List[str]


@router.get("/ocr/keywords", response_model=KeywordList)
async def get_ocr_keywords(current_user: User = Depends(get_current_user)):
    """Return the authenticated user's OCR keyword set."""
    keywords = await get_user_keywords(str(current_user.id))
    return KeywordList(keywords=list(keywords))


@router.post("/ocr/keywords", response_model=KeywordList)
async def set_ocr_keywords(
    payload: KeywordList,
    current_user: User = Depends(get_current_user),
):
    """Replace the authenticated user's OCR keyword set."""
    # Normalize keywords: lowercase, strip whitespace
    normalized = [k.strip().lower() for k in payload.keywords if k.strip()]
    await set_user_keywords(str(current_user.id), set(normalized))
    return KeywordList(keywords=normalized)


@router.delete("/ocr/keywords", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_ocr_keywords(current_user: User = Depends(get_current_user)):
    """Remove all OCR keywords for the authenticated user."""
    await set_user_keywords(str(current_user.id), set())
    return None