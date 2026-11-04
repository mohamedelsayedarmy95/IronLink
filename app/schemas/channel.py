from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models.channel import ChannelType


class ChannelBase(BaseModel):
    name: str = Field(..., max_length=100)
    description: str | None = None
    channel_type: ChannelType = ChannelType.PUBLIC
    category: str | None = Field(None, max_length=50)


class ChannelCreate(ChannelBase):
    pass


class ChannelUpdate(BaseModel):
    name: str | None = Field(None, max_length=100)
    description: str | None = None
    channel_type: ChannelType | None = None
    category: str | None = Field(None, max_length=50)


class ChannelResponse(ChannelBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    owner_id: UUID
    created_at: datetime
    updated_at: datetime
    is_verified: bool
    subscriber_count: int


class ChannelPostBase(BaseModel):
    content: str
    media_key: str | None = None
    mime_type: str | None = None
    scheduled_at: datetime | None = None
    is_scheduled: bool = False


class ChannelPostCreate(ChannelPostBase):
    pass


class ChannelPostResponse(ChannelPostBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    channel_id: UUID
    author_id: UUID
    created_at: datetime
    updated_at: datetime
    view_count: int


class ChannelSubscriptionBase(BaseModel):
    subscription_plan_id: UUID | None = None


class ChannelSubscriptionCreate(ChannelSubscriptionBase):
    pass


class ChannelSubscriptionResponse(ChannelSubscriptionBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    channel_id: UUID
    user_id: UUID
    created_at: datetime
    is_active: bool


class ChannelAnalyticsResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    channel_id: UUID
    created_at: datetime
    new_subscribers: int
    total_views: int
    total_posts: int
    engagement_rate: float
