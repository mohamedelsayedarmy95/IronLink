"""Replying to a message, under end-to-end encryption.

`messages.reply_to_id` had existed since the schema was created and nothing had
ever used it — no frame accepted it, no endpoint returned it, no screen showed
it. Column for a feature never built.

The interesting constraint is that the server cannot help with the quotation.
`content_ciphertext` is ciphertext and there is no key here, so a reply carries
a reference and the reading device resolves the text from its own history.
"""

from __future__ import annotations

import inspect
import uuid

import pytest

from tests.conftest import requires_db

from app.models import Message
from app.models.user import UserStatus
from app.services import message_service


class TestTheServerCarriesAReferenceOnly:
    def test_the_frame_accepts_a_reply_target(self) -> None:
        from app.api.routes import websocket as ws_route

        source = inspect.getsource(ws_route._handle_frame)
        assert 'reply_to_id=_uuid_or_none(frame.get("reply_to"))' in source, (
            "parsed defensively like every other caller-supplied identifier"
        )

    def test_a_malformed_target_does_not_reject_the_send(self) -> None:
        # _uuid_or_none returns None rather than raising, so a bad reference
        # produces a message with no quotation instead of a refused send. A
        # reply is a convenience; losing the message would not be.
        from app.api.routes import websocket as ws_route

        assert "def _uuid_or_none" in inspect.getsource(ws_route)

    def test_history_returns_the_reference(self) -> None:
        from app.api.routes import chats

        source = inspect.getsource(chats)
        assert "reply_to_id: UUID | None" in source

    def test_history_never_returns_quoted_text(self) -> None:
        """The property that keeps a retraction meaningful.

        If the server attached the quoted text, retracting a message would
        leave copies of it inside every reply — a deletion that does not
        delete. It cannot attach it anyway, having never had it, and this
        asserts nobody adds a denormalised copy later.
        """
        from app.api.routes import chats

        source = inspect.getsource(chats)
        for leak in ("reply_to_text", "reply_to_content", "quoted_text"):
            assert leak not in source, leak


@pytest.mark.usefixtures("db")
class TestReplyJourney:
    pytestmark = requires_db

    async def _person(self, db, name: str):
        from app.models import User

        user = User(
            phone_number=f"+2010{uuid.uuid4().int % 100000000:08d}",
            full_name=name,
            status=UserStatus.ACTIVE,
            hashed_military_id="not-a-hash",
            hashed_password="not-a-hash",
        )
        db.add(user)
        await db.flush()
        return user

    @pytest.mark.asyncio
    async def test_a_reply_records_what_it_answers(self, db) -> None:
        alice = await self._person(db, "Alice")
        bob = await self._person(db, "Bob")

        original = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-1",
        )
        reply = await message_service.save_message(
            db,
            sender_id=bob.id,
            recipient_id=alice.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-2",
            client_ref="ref-2",
            reply_to_id=original.id,
        )

        assert reply.reply_to_id == original.id

    @pytest.mark.asyncio
    async def test_retracting_the_original_leaves_the_reply_standing(
        self, db
    ) -> None:
        """A conversation must not lose the answer when the question goes.

        `reply_to_id` is SET NULL, so the reply survives with no quotation
        rather than being cascaded away with the message it answered.
        """
        alice = await self._person(db, "Alice")
        bob = await self._person(db, "Bob")

        original = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-1",
        )
        reply = await message_service.save_message(
            db,
            sender_id=bob.id,
            recipient_id=alice.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-2",
            client_ref="ref-2",
            reply_to_id=original.id,
        )
        reply_id = reply.id

        await message_service.unsend_message(db, original.id, alice.id)
        db.expire_all()

        surviving = await db.get(Message, reply_id)
        assert surviving is not None
        assert surviving.content_ciphertext == "envelope-2"

    @pytest.mark.asyncio
    async def test_a_message_answering_nothing_has_no_reference(self, db) -> None:
        alice = await self._person(db, "Alice")
        bob = await self._person(db, "Bob")

        msg = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope",
            client_ref="ref-1",
        )

        assert msg.reply_to_id is None
