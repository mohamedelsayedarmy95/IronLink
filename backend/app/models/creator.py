from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey, Float
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum
from app.models.base import Base

class PayoutStatus(str, enum.Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"

class SubscriptionPlan(Base):
    __tablename__ = "subscription_plans"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    description = Column(Text)
    price = Column(Float, nullable=False)  # Price in USD
    currency = Column(String(3), default="USD")
    interval = Column(String(20), default="month")  # e.g., month, year
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    # Relationships
    subscriptions = relationship("ChannelSubscription", back_populates="subscription_plan")

class CreatorDashboard(Base):
    __tablename__ = "creator_dashboards"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)  # The creator
    total_earnings = Column(Float, default=0.0)
    total_subscribers = Column(Integer, default=0)
    total_views = Column(Integer, default=0)
    total_posts = Column(Integer, default=0)
    last_updated = Column(DateTime(timezone=True), onupdate=func.now())
    # Relationships
    user = relationship("User")
    payouts = relationship("Payout", back_populates="creator")

class Payout(Base):
    __tablename__ = "payouts"

    id = Column(Integer, primary_key=True, index=True)
    creator_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    amount = Column(Float, nullable=False)
    currency = Column(String(3), default="USD")
    status = Column(Enum(PayoutStatus), default=PayoutStatus.PENDING)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    processed_at = Column(DateTime(timezone=True))
    # Relationships
    creator = relationship("User", foreign_keys=[creator_id])