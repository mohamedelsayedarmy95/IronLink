from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Path, status
from pydantic import BaseModel, Field

from app.api.deps import get_current_user
from app.models import User
from app.services.ai_service import ai_service

# No prefix: the Flutter client already calls three paths under /ai and one
# under /chats, and the contract is fixed by shipped code. Grouping them here
# keeps every Hugging Face call in one file rather than splitting the summary
# endpoint into chats.py purely for its URL.
router = APIRouter(tags=["ai"])

# Ceilings exist because each call is a paid, slow round-trip to Hugging Face.
# Without them a single request can pin the worker for the full 30s timeout.
MAX_TEXT_CHARS = 5_000
MAX_CONTEXT_CHARS = 10_000
MAX_MESSAGES = 200


# ── Schemas ────────────────────────────────────────────────────────────────────
# Field names mirror what the client already sends; do not rename them without
# shipping a new app build. See frontend/lib/features/chat/bloc/chat_bloc.dart.

class SummaryIn(BaseModel):
    messages: list[str] = Field(..., max_length=MAX_MESSAGES)


class SummaryOut(BaseModel):
    summary: str


class SmartRepliesIn(BaseModel):
    context: str = Field(..., max_length=MAX_CONTEXT_CHARS)
    num_replies: int = Field(3, ge=1, le=5)


class SmartRepliesOut(BaseModel):
    replies: list[str]


class TranslateIn(BaseModel):
    text: str = Field(..., max_length=MAX_TEXT_CHARS)
    # NLLB language code, e.g. "arb_Arab", "fra_Latn", "eng_Latn".
    target_lang: str = Field(..., max_length=32)


class TranslateOut(BaseModel):
    translation: str


class ModerateIn(BaseModel):
    text: str = Field(..., max_length=MAX_TEXT_CHARS)


class ModerateOut(BaseModel):
    scores: dict[str, float]


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post(
    "/chats/{peer_id}/summary",
    response_model=SummaryOut,
    status_code=status.HTTP_200_OK,
)
async def summarize_conversation(
    body: SummaryIn,
    peer_id: UUID = Path(...),
    user: User = Depends(get_current_user),
) -> SummaryOut:
    """Summarise a conversation.

    The client posts the message bodies rather than the server reading them from
    the database, because messages are stored encrypted and the server has no
    plaintext. That is also the privacy cost of this feature: using it sends the
    conversation to Hugging Face. It should be opt-in per conversation, and the
    UI should say so.

    peer_id is not used to fetch anything — it identifies the conversation for
    logging and future per-conversation opt-out.
    """
    summary = await ai_service.summarize_messages(body.messages)
    return SummaryOut(summary=summary)


@router.post("/ai/smart-replies", response_model=SmartRepliesOut)
async def generate_smart_replies(
    body: SmartRepliesIn,
    user: User = Depends(get_current_user),
) -> SmartRepliesOut:
    """Suggest short replies for the current conversation context.

    Falls back to generic suggestions when HF_API_TOKEN is unset or the API
    errors, so the UI always has something to render.
    """
    replies = await ai_service.generate_smart_replies(
        body.context, num_replies=body.num_replies
    )
    return SmartRepliesOut(replies=replies)


@router.post("/ai/translate", response_model=TranslateOut)
async def translate_message(
    body: TranslateIn,
    user: User = Depends(get_current_user),
) -> TranslateOut:
    """Translate one message. Returns the original text on failure."""
    translation = await ai_service.translate_message(body.text, body.target_lang)
    return TranslateOut(translation=translation)


@router.post("/ai/moderate", response_model=ModerateOut)
async def moderate_message(
    body: ModerateIn,
    user: User = Depends(get_current_user),
) -> ModerateOut:
    """Toxicity scores for one message, as {label: score}.

    An empty dict means "no verdict" — the model was unreachable or returned
    nothing. Callers must not read that as "safe".
    """
    scores = await ai_service.moderate_message(body.text)
    return ModerateOut(scores=scores)
