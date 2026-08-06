from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from app.models.creator import PayoutStatus

class SubscriptionPlanBase(BaseModel):
    name: str = Field(..., max_length=100)
    description: Optional[str] = None
    price: float = Field(..., gt=0)
    currency: str = Field(default="USD", max_length=3)
    interval: str = Field(default="month", max_length=20)  # e.g., month, year
    is_active: bool = True

class SubscriptionPlanCreate(SubscriptionPlanBase):
    pass

class SubscriptionPlanResponse(SubscriptionPlanBase):
    id: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        orm_mode = True

class CreatorDashboardBase(BaseModel):
    pass

class CreatorDashboardResponse(CreatorDashboardBase):
    id: int
    user_id: int
    total_earnings: float
    total_subscribers: int
    total_views: int
    total_posts: int
    last_updated: Optional[datetime] = None

    class Config:
        orm_mode = True

class PayoutBase(BaseModel):
    amount: float = Field(..., gt=0)
    currency: str = Field(default="USD", max_length=3)

class PayoutCreate(PayoutBase):
    pass

class PayoutResponse(PayoutBase):
    id: int
    creator_id: int
    status: PayoutStatus
    created_at: datetime
    processed_at: Optional[datetime] = None

    class Config:
        orm_mode = True