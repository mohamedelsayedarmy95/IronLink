from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models.creator import PayoutStatus


class SubscriptionPlanBase(BaseModel):
    name: str = Field(..., max_length=100)
    description: str | None = None
    price: float = Field(..., gt=0)
    currency: str = Field(default="USD", max_length=3)
    interval: str = Field(default="month", max_length=20)
    is_active: bool = True


class SubscriptionPlanCreate(SubscriptionPlanBase):
    pass


class SubscriptionPlanResponse(SubscriptionPlanBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    created_at: datetime
    updated_at: datetime


class CreatorDashboardResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    total_earnings: float
    total_subscribers: int
    total_views: int
    total_posts: int
    updated_at: datetime


class PayoutBase(BaseModel):
    amount: float = Field(..., gt=0)
    currency: str = Field(default="USD", max_length=3)


class PayoutCreate(PayoutBase):
    pass


class PayoutResponse(PayoutBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    creator_id: UUID
    status: PayoutStatus
    created_at: datetime
    processed_at: datetime | None = None
