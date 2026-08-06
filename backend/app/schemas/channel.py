from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from app.models.channel import ChannelType

class ChannelBase(BaseModel):
    name: str = Field(..., max_length=100)
    description: Optional[str] = None
    type: ChannelType
    category: Optional[str] = Field(None, max_length=50)

class ChannelCreate(ChannelBase):
    pass

class ChannelUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    description: Optional[str] = None
    type: Optional[ChannelType] = None
    category: Optional[str] = Field(None, max_length=50)
    is_verified: Optional[bool] = None

class ChannelResponse(ChannelBase):
    id: int
    owner_id: int
    created_at: datetime
    updated_at: Optional[datetime] = None
    is_verified: bool
    subscriber_count: int

    class Config:
        orm_mode = True

class ChannelPostBase(BaseModel):
    content: str
    media_key: Optional[str] = None
    mime_type: Optional[str] = None
    scheduled_at: Optional[datetime] = None
    is_scheduled: bool = False

class ChannelPostCreate(ChannelPostBase):
    pass

class ChannelPostResponse(ChannelPostBase):
    id: int
    channel_id: int
    author_id: int
    created_at: datetime
    updated_at: Optional[datetime] = None
    view_count: int

    class Config:
        orm_mode = True

class ChannelSubscriptionBase(BaseModel):
    subscription_plan_id: Optional[int] = None

class ChannelSubscriptionCreate(ChannelSubscriptionBase):
    pass

class ChannelSubscriptionResponse(ChannelSubscriptionBase):
    id: int
    channel_id: int
    user_id: int
    subscribed_at: datetime
    is_active: bool

    class Config:
        orm_mode = True

class ChannelAnalyticsResponse(BaseModel):
    id: int
    channel_id: int
    date: datetime
    new_subscribers: int
    total_views: int
    total_posts: int
    engagement_rate: float

    class Config:
        orm_mode = True