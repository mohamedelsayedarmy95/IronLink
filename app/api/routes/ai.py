from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.config import settings
from app.core.database import get_db
from app.models import AiScopeType, User
from app.services import ai_consent_service
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
    peer_id: UUID | None = None
    group_id: UUID | None = None


class SmartRepliesOut(BaseModel):
    replies: list[str]


class TranslateIn(BaseModel):
    text: str = Field(..., max_length=MAX_TEXT_CHARS)
    # NLLB language code, e.g. "arb_Arab", "fra_Latn", "eng_Latn".
    target_lang: str = Field(..., max_length=32)

    # Which conversation the text came from. Required, because without it the
    # server has no way to know whose consent applies — the previous version
    # took a bare string and forwarded it, so there was nothing to enforce.
    peer_id: UUID | None = None
    group_id: UUID | None = None


class TranslateOut(BaseModel):
    translation: str


class ModerateIn(BaseModel):
    text: str = Field(..., max_length=MAX_TEXT_CHARS)
    peer_id: UUID | None = None
    group_id: UUID | None = None


class ModerateOut(BaseModel):
    scores: dict[str, float]


class ConsentIn(BaseModel):
    granted: bool
    peer_id: UUID | None = None
    group_id: UUID | None = None


class ConsentOut(BaseModel):
    """Who has agreed, and who has not.

    Both counts are returned so the interface can say "1 of 2" rather than
    just refusing — the user needs to know they are waiting on someone.
    """

    granted: bool
    everyone_agreed: bool
    waiting_on: list[str] = []
    total_participants: int = 0


# ── Consent enforcement ────────────────────────────────────────────────────────

async def _require_consent(
    db: AsyncSession,
    *,
    user: User,
    peer_id: UUID | None,
    group_id: UUID | None,
) -> None:
    """Refuses unless everyone whose words would be sent has agreed.

    Enforced here rather than in the client, because a client-side check is
    a suggestion: the whole point is that a modified build must not be able
    to post someone else's messages to a third party.
    """
    if not settings.AI_FEATURES_ENABLED:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "AI features are disabled on this deployment.",
        )

    if (peer_id is None) == (group_id is None):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "exactly one of peer_id or group_id is required",
        )

    try:
        if group_id is not None:
            await ai_consent_service.require_group(db, group_id=group_id)
        else:
            await ai_consent_service.require_direct(
                db, user_id=user.id, peer_id=peer_id
            )
    except ai_consent_service.AiConsentMissing as missing:
        names = await ai_consent_service.missing_names(db, missing.missing)
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            {
                "reason": "ai_consent_missing",
                "message": (
                    "Everyone in this conversation has to agree before its "
                    "messages can be sent for processing."
                ),
                "waiting_on": names,
                "total_participants": missing.total,
            },
        ) from None


# ── Consent management ─────────────────────────────────────────────────────────

@router.get("/ai/consent", response_model=ConsentOut)
async def read_consent(
    peer_id: UUID | None = None,
    group_id: UUID | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConsentOut:
    """This user's agreement for a conversation, and whether it is enough."""
    if (peer_id is None) == (group_id is None):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "exactly one of peer_id or group_id is required",
        )

    scope_type = AiScopeType.GROUP if group_id else AiScopeType.DIRECT
    scope_id = group_id or peer_id

    granted = await ai_consent_service.has_consent(
        db, user_id=user.id, scope_type=scope_type, scope_id=scope_id
    )

    try:
        if group_id is not None:
            await ai_consent_service.require_group(db, group_id=group_id)
        else:
            await ai_consent_service.require_direct(
                db, user_id=user.id, peer_id=peer_id
            )
        return ConsentOut(
            granted=granted,
            everyone_agreed=True,
            total_participants=2 if peer_id else 0,
        )
    except ai_consent_service.AiConsentMissing as missing:
        return ConsentOut(
            granted=granted,
            everyone_agreed=False,
            waiting_on=await ai_consent_service.missing_names(
                db, [m for m in missing.missing if m != str(user.id)]
            ),
            total_participants=missing.total,
        )


@router.put("/ai/consent", response_model=ConsentOut)
async def set_consent(
    body: ConsentIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConsentOut:
    """Give or withdraw this user's agreement."""
    if (body.peer_id is None) == (body.group_id is None):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "exactly one of peer_id or group_id is required",
        )

    scope_type = AiScopeType.GROUP if body.group_id else AiScopeType.DIRECT
    scope_id = body.group_id or body.peer_id

    if body.granted:
        await ai_consent_service.grant(
            db, user_id=user.id, scope_type=scope_type, scope_id=scope_id
        )
    else:
        await ai_consent_service.revoke(
            db, user_id=user.id, scope_type=scope_type, scope_id=scope_id
        )

    return await read_consent(
        peer_id=body.peer_id, group_id=body.group_id, user=user, db=db
    )


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
    db: AsyncSession = Depends(get_db),
) -> SummaryOut:
    """Summarise a conversation.

    The client posts the message bodies rather than the server reading them
    from the database, because messages are stored encrypted and the server
    has no plaintext. That is also the privacy cost: using this sends the
    conversation to Hugging Face.

    Which is why it is gated. Both people in the conversation must have
    agreed — a summary is made of both their words, so one side cannot
    consent on the other's behalf.
    """
    await _require_consent(db, user=user, peer_id=peer_id, group_id=None)
    summary = await ai_service.summarize_messages(body.messages)
    return SummaryOut(summary=summary)


@router.post("/ai/smart-replies", response_model=SmartRepliesOut)
async def generate_smart_replies(
    body: SmartRepliesIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SmartRepliesOut:
    """Suggest short replies for the current conversation context.

    The context is what the other person said, so this needs their agreement
    as much as a summary does.

    Falls back to generic suggestions when HF_API_TOKEN is unset or the API
    errors, so the UI always has something to render.
    """
    await _require_consent(
        db, user=user, peer_id=body.peer_id, group_id=body.group_id
    )
    replies = await ai_service.generate_smart_replies(
        body.context, num_replies=body.num_replies
    )
    return SmartRepliesOut(replies=replies)


@router.post("/ai/translate", response_model=TranslateOut)
async def translate_message(
    body: TranslateIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> TranslateOut:
    """Translate one message. Returns the original text on failure.

    Gated like the rest: the message being translated is usually the other
    person's, and translating it means handing their words to a third party.
    """
    await _require_consent(
        db, user=user, peer_id=body.peer_id, group_id=body.group_id
    )
    translation = await ai_service.translate_message(body.text, body.target_lang)
    return TranslateOut(translation=translation)


@router.post("/ai/moderate", response_model=ModerateOut)
async def moderate_message(
    body: ModerateIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ModerateOut:
    """Toxicity scores for one message, as {label: score}.

    Gated. Note this is the classifier, not the report flow: reporting a
    message to a human moderator is deliberately NOT behind consent, because
    someone sending abuse does not get to veto being reported. See
    routes/moderation.py.

    An empty dict means "no verdict" — the model was unreachable or returned
    nothing. Callers must not read that as "safe".
    """
    await _require_consent(
        db, user=user, peer_id=body.peer_id, group_id=body.group_id
    )
    scores = await ai_service.moderate_message(body.text)
    return ModerateOut(scores=scores)
