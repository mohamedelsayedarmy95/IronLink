from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user import User


class FormFieldType(str, Enum):
    """Field types an admin can place on a verification form.

    Values are stored verbatim, so renaming one is a data migration — the
    Flutter client switches on these same strings to pick an input widget.
    """

    TEXT_SHORT = "text_short"
    TEXT_LONG = "text_long"
    NUMBER = "number"
    SELECT_SINGLE = "select_single"
    SELECT_MULTI = "select_multi"
    DATE = "date"
    PHONE = "phone"
    FILE = "file"
    IMAGE = "image"
    CHECKBOX = "checkbox"
    URL = "url"
    EMAIL = "email"


#: Types whose answer is a list rather than a scalar. Kept beside the enum so
#: validation and the client stay in agreement about answer shape.
MULTI_VALUE_FIELD_TYPES: frozenset[str] = frozenset({FormFieldType.SELECT_MULTI})

#: Types that require `options` to be defined by the admin. A select with no
#: options is an unanswerable question, so this is enforced at write time.
OPTION_BEARING_FIELD_TYPES: frozenset[str] = frozenset(
    {FormFieldType.SELECT_SINGLE, FormFieldType.SELECT_MULTI}
)


class VerificationForm(Base):
    """A set of questions an admin requires before granting group entry.

    Forms are versioned by reference, not by mutation: a group points at an
    active form, and a submitted request records the form it answered. Editing
    a form therefore cannot retroactively change what a pending request was
    asked — see the `form_id` snapshot on GroupJoinRequest.
    """

    __tablename__ = "verification_forms"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    is_template: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
        comment="Reusable starting point (Military / Government / Enterprise)",
    )

    created_by_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    fields: Mapped[list[VerificationFormField]] = relationship(
        "VerificationFormField",
        back_populates="form",
        cascade="all, delete-orphan",
        order_by="VerificationFormField.order_index",
    )

    created_by: Mapped[User] = relationship("User")

    __table_args__ = (
        Index("ix_verification_forms_created_by", "created_by_id"),
        Index("ix_verification_forms_template", "is_template"),
    )


class VerificationFormField(Base):
    """One question on a verification form."""

    __tablename__ = "verification_form_fields"

    form_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("verification_forms.id", ondelete="CASCADE"),
        nullable=False,
    )

    field_type: Mapped[str] = mapped_column(String(50), nullable=False)
    label: Mapped[str] = mapped_column(Text, nullable=False)
    placeholder: Mapped[str | None] = mapped_column(Text, nullable=True)
    helper_text: Mapped[str | None] = mapped_column(Text, nullable=True)

    is_required: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )

    validation_rules: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        comment="{min, max, regex, allowed_types, max_size, min_select, max_select}",
    )
    options: Mapped[dict | None] = mapped_column(
        JSONB, nullable=True, comment='{"options": [{"label": ..., "value": ...}]}'
    )

    icon: Mapped[str | None] = mapped_column(String(50), nullable=True)

    order_index: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )

    form: Mapped[VerificationForm] = relationship(
        "VerificationForm", back_populates="fields"
    )

    __table_args__ = (
        Index("ix_form_fields_form_order", "form_id", "order_index"),
        # Two fields sharing an order within one form would make the rendered
        # sequence depend on insertion order, which is not stable across reads.
        UniqueConstraint("form_id", "order_index", name="uq_form_field_order"),
    )


class GroupAuditAction(str, Enum):
    """Actions worth a permanent record, per the spec's audit requirements."""

    APPROVE_REQUEST = "approve_request"
    REJECT_REQUEST = "reject_request"
    REQUEST_MORE_INFO = "request_more_info"
    BULK_APPROVE = "bulk_approve"
    BULK_REJECT = "bulk_reject"
    REMOVE_MEMBER = "remove_member"
    BAN_MEMBER = "ban_member"
    UNBAN_MEMBER = "unban_member"
    CHANGE_JOIN_MODE = "change_join_mode"
    UPDATE_FORM = "update_form"
    ASSIGN_MODERATOR = "assign_moderator"
    REOPEN_REQUEST = "reopen_request"
    EXPORT_AUDIT_LOG = "export_audit_log"


class GroupAuditLog(Base):
    """Append-only record of sensitive group actions.

    Rows are never updated or deleted by application code: an audit trail that
    can be edited is not evidence of anything.
    """

    __tablename__ = "group_audit_logs"

    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=False,
    )
    action: Mapped[str] = mapped_column(String(50), nullable=False)

    performed_by_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    target_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )

    details: Mapped[dict | None] = mapped_column(
        JSONB, nullable=True, comment="{count, reason, form_id, old_mode, new_mode}"
    )

    __table_args__ = (
        Index("ix_audit_group_created", "group_id", "created_at"),
        Index("ix_audit_performed_by", "performed_by_id"),
        Index("ix_audit_group_action", "group_id", "action"),
    )


class GroupBan(Base):
    """Blocks one user from one group.

    Distinct from a platform ban in scope and in who may lift it; the two are
    deliberately separate tables so a query can never conflate them.
    """

    __tablename__ = "group_bans"

    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    banned_by_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    is_permanent: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_ban_user"),
        Index("ix_group_bans_group_user", "group_id", "user_id"),
    )


class PlatformBan(Base):
    """Blocks one user from joining any group platform-wide.

    Reason is NOT NULL here while it is optional on GroupBan: a platform-wide
    restriction is severe enough that an unexplained one should be impossible
    to create.
    """

    __tablename__ = "platform_bans"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    banned_by_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    reason: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", name="uq_platform_ban_user"),
    )
