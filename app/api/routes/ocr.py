"""Legacy server-side keyword management.

DEPRECATED — see docs/SMART_KEYWORD_ALERT_AUDIT.md. Keyword rules are now
per-conversation and live on the device, where the plaintext they match
against also lives. These endpoints remain for the plaintext-attachment
deployment mode and for clients that have not yet migrated.

Every route here returned 500 before this change: the handlers awaited
functions that were declared ``def``, so ``await`` was applied to a ``set``
and a ``bool``. The store is async now, which makes the awaits real.

The add/remove semantics were also wrong in a way the client made damaging.
``POST`` replaced the entire set, so the client's "add one keyword" call
(ocr_settings_bloc.dart) deleted every other keyword the user had. ``DELETE``
cleared everything and ignored the body the client sent naming a single
keyword to remove. Both now do what the caller means, and a full replace is
available explicitly.
"""
from __future__ import annotations

from typing import List

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field

from app.api.deps import get_current_user
from app.models import User
from app.redis import (
    add_user_keywords,
    get_user_keywords,
    remove_user_keywords,
    set_user_keywords,
)

router = APIRouter(tags=["ocr"])

#: A keyword long enough to be meaningless as a filter is a denial-of-service
#: vector against the matcher, not a feature.
MAX_KEYWORD_LENGTH = 64
MAX_KEYWORDS = 100


class KeywordList(BaseModel):
    keywords: List[str] = Field(default_factory=list)


class KeywordDelete(BaseModel):
    """Empty body, or ``{"keyword": "x"}``, or ``{"keywords": [...]}``.

    An empty body still means "clear everything", which is what the endpoint
    did unconditionally before.
    """

    keyword: str | None = None
    keywords: List[str] | None = None


def _clean(raw: List[str]) -> list[str]:
    """Trim, lowercase, drop blanks and duplicates, preserving order."""
    seen: set[str] = set()
    out: list[str] = []
    for item in raw:
        value = item.strip().lower()[:MAX_KEYWORD_LENGTH]
        if value and value not in seen:
            seen.add(value)
            out.append(value)
    return out[:MAX_KEYWORDS]


@router.get("/ocr/keywords", response_model=KeywordList)
async def get_ocr_keywords(current_user: User = Depends(get_current_user)):
    """Return the authenticated user's OCR keyword set."""
    keywords = await get_user_keywords(str(current_user.id))
    # Redis sets have no order; sorting makes the response stable so a client
    # list does not reshuffle itself on every refresh.
    return KeywordList(keywords=sorted(keywords))


@router.post("/ocr/keywords", response_model=KeywordList)
async def add_ocr_keywords(
    payload: KeywordList,
    replace: bool = False,
    current_user: User = Depends(get_current_user),
):
    """Add keywords to the set, or replace it wholesale with ``?replace=true``."""
    user_id = str(current_user.id)
    cleaned = _clean(payload.keywords)
    if replace:
        await set_user_keywords(user_id, set(cleaned))
    else:
        await add_user_keywords(user_id, set(cleaned))
    return KeywordList(keywords=sorted(await get_user_keywords(user_id)))


@router.delete("/ocr/keywords", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_ocr_keywords(
    payload: KeywordDelete | None = None,
    current_user: User = Depends(get_current_user),
):
    """Remove the named keywords, or all of them when none are named."""
    user_id = str(current_user.id)
    named = _clean(
        [*( [payload.keyword] if payload and payload.keyword else [] ),
         *(payload.keywords or [] if payload else [])]
    )
    if named:
        await remove_user_keywords(user_id, set(named))
    else:
        await set_user_keywords(user_id, set())
    return None
