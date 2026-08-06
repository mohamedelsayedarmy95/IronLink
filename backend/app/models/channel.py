from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey, Enum, Float
from sqlalchemy.orm relationship
from sqlalchemy.sql import func
import enum
from app.models.base import Base  # Assuming we have a base model

class ChannelType(str, enum.Enum):
    PUBLIC = "public"
    PRIVATE = "private"

class Channel(Base):
    __tablename__ = "channels"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False, index=True)
    description = Column(Text)
    type = Column(Enum(ChannelType), default=ChannelType.PUBLIC, nullable=False)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False)  # Assuming User model has id
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    is_verified = Column(Boolean, default=False)
    category = Column(String(50), index=True)  # e.g., Technology, Gaming, News
    subscriber_count = Column(Integer, default=0)
    # Relationships
    posts = relationship("ChannelPost", back_populates="channel", cascade="all, delete-orphan")
    subscriptions = relationship("ChannelSubscription", back_populates="channel", cascade="all, delete-orphan")
    analytics = relationship("ChannelAnalytics", uselist=False, back_populates="channel")

class ChannelPost(Base):
    __tablename__ = "channel_posts"

    id = Column(Integer, primary_key=True, index=True)
    channel_id = Column(Integer, ForeignKey("channels.id"), nullable=False)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)  # The user who posted
    content = Column(Text, nullable=False)
    media_key = Column(String(255))  # Reference to media in MinIO
    mime_type = Column(String(100))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    scheduled_at = Column(DateTime(timezone=True))  # For scheduled posts
    is_scheduled = Column(Boolean, default=False)
    view_count = Column(Integer, default=0)
    # Relationships
    channel = relationship("Channel", back_populates="posts")
    author = relationship("User")  # Assuming User model

class ChannelSubscription(Base):
    __tablename__ = "channel_subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    channel_id = Column(Integer, ForeignKey("channels.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    subscribed_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Boolean, default=True)
    # For paid subscriptions
    subscription_plan_id = Column(Integer, ForeignKey("subscription_plans.id"), nullable=True)
    # Relationships
    channel = relationship("Channel", back_populates="subscriptions")
    user = relationship("User")
    subscription_plan = relationship("SubscriptionPlan")

class ChannelAnalytics(Base):
    __tablename__ = "channel_analytics"

    id = Column(Integer, primary_key=True, index=True)
    channel_id = Column(Integer, ForeignKey("channels.id"), nullable=False)
    date = Column(DateTime(timezone=True), server_default=func.now())
    new_subscribers = Column(Integer, default=0)
    total_views = Column(Integer, default=0)
    total_posts = Column(Integer, default=0)
    engagement_rate = Column(Float, default=0.0)  # e.g., (likes + comments) / views
    # Relationships
    channel = relationship("Channel", back_populates="analytics")