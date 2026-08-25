"""The notification boundary.

A push notification is the one part of a messenger that renders outside the
application — on a locked screen, through infrastructure nobody here controls,
after passing through a third party's servers. It is the softest point in the
whole system, and it is the point at which this repository was leaking.

These tests exist because the leak was invisible: the call site read a field
named `content`, which is exactly what a preview should be built from in any
product that is not end-to-end encrypted.
"""

from __future__ import annotations

import inspect

from app.api.routes import websocket as ws_route
from app.services import push_service


class TestNoContentInPush:
    def test_send_message_push_cannot_be_given_message_content(self) -> None:
        """The parameter is gone, not merely unused.

        It used to take `preview` and set it as the notification body. Leaving
        the parameter in place and passing a safe value would leave the next
        caller free to pass an unsafe one; removing it makes the mistake fail
        at import rather than in production.
        """
        params = set(inspect.signature(push_service.send_message_push).parameters)
        assert params == {"fcm_token", "sender_name", "peer_id"}

    def test_the_notification_carries_a_title_and_no_body(self) -> None:
        source = inspect.getsource(push_service.send_message_push)
        assert "Notification(title=sender_name)" in source
        assert "body=" not in source

    def test_the_call_site_does_not_read_the_message_field(self) -> None:
        """The field is the ciphertext envelope when encryption is on and the
        plaintext message when it is off. Neither belongs in a notification.

        Asserted against the whole frame handler rather than one function,
        because the leak was a local variable built two lines above the call.
        """
        source = inspect.getsource(ws_route._handle_frame)
        push_calls = [
            line for line in source.splitlines() if "send_message_push" in line
        ]
        assert push_calls, "the push call should still exist"

        # No line anywhere in the handler may pass a content-derived value to a
        # push. The narrow check — that `preview` is gone — would pass again the
        # moment somebody named the variable something else.
        for line in source.splitlines():
            if "push_service" in line or "preview" in line.lower():
                assert 'frame.get("content")' not in line, line

    def test_ocr_push_still_carries_no_keyword(self) -> None:
        # Same class of leak, fixed earlier: the user's private watchlist must
        # not travel to Google either. Re-asserted here so both live together.
        params = set(inspect.signature(push_service.send_ocr_push).parameters)
        assert "keyword" not in params
        assert "keywords" not in params


class TestNoCiphertextPreview:
    def test_the_conversation_list_never_returns_ciphertext(self) -> None:
        """`chats.py` used to return `content_ciphertext[:20]`.

        Twenty characters of a Signal envelope cannot be decrypted by anybody,
        including the recipient. It was not a leak so much as a preview that
        could not work — and its presence implied that server-side previews are
        a supported concept in this architecture. They are not.
        """
        from app.api.routes import chats

        source = inspect.getsource(chats)
        assert "content_ciphertext or" not in source
        assert "content_ciphertext)[:20]" not in source

    def test_a_message_kind_is_still_allowed(self) -> None:
        # The one thing the server may say about a message it cannot read is
        # what kind it is, which is already visible to it from the column. That
        # covers the case the client cannot: a conversation this device holds
        # no local copy of.
        from app.api.routes import chats

        assert 'f"[{last_msg.message_type}]"' in inspect.getsource(chats)
