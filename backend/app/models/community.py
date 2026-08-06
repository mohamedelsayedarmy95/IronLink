from sqlalchemy import Column, Integer, String, Text, DateTime, Boolean, ForeignKey, Enum, Float
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum
from app.models.base import Base

class CommunityRole(str, enum.Enum):
    OWNER = "owner"
    ADMIN = "admin"
    MODERATOR = "moderator"
    MEMBER = "member"

class Community(Base):
    __tablename__ = "communities"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False, index=True)
    description = Column(Text)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    is_verified = Column(Boolean, default=False)
    category = Column(String(50), index=True)  # e.g., Technology, Gaming, News
    member_count = Column(Integer, default=0)
    # Relationships
    members = relationship("CommunityMember", back_populates="community", cascade="all, delete-orphan")
    events = relationship("CommunityEvent", back_populates="community", cascade="all, delete-orphan")
    resources = relationship("CommunityResource", back_populates="community", cascade="all, delete-orphan")

class CommunityMember(Base):
    __tablename__ = "community_members"

    id = Column(Integer, primary_key=True, index=True)
    community_id = Column(Integer, ForeignKey("communities.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    role = Column(Enum(CommunityRole), default=CommunityRole.MEMBER, nullable=False)
    joined_at = Column(DateTime(timezone=True), server_default=func.now())
    # Relationships
    community = relationship("Community", back_populates="members")
    user = relationship("User")

class CommunityPermission(Base):
    __tablename__ = "community_permissions"

    id = Column(Integer, primary_key=True, index=True)
    community_id = Column(Integer, ForeignKey("communities.id"), nullable=False)
    role = Column(Enum(CommunityRole), nullable=False)
    can_post = Column(Boolean, default=False)
    can_comment = Column(Boolean, default=False)
    can_delete_own_posts = Column(Boolean, default=False)
    can_delete_any_posts = Column(Boolean, default=False)
    can_mute_members = Column(Boolean, default=False)
    can_ban_members = Column(Boolean, default=False)
    can_invite_members = Column(Boolean, default=False)
    can_change_settings = Column(Boolean, default=False)
    # Relationships
    community = relationship("Community")

class CommunityEvent(Base):
    __tablename__ = "community_events"

    id = Column(Integer, primary_key=True, index=True)
    community_id = Column(Integer, ForeignKey("communities.id"), nullable=False)
    title = Column(String(200), nullable=False)
    description = Column(Text)
    start_time = Column(DateTime(timezone=True), nullable=False)
    end_time = Column(DateTime(timezone=True))
    location = Column(String(255))  # Could be a URL for online event
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    # Relationships
    community = relationship("Community", back_populates="events")
    creator = relationship("User")
    rsvps = relationship("CommunityEventRSVP", back_populates="event", cascade="all, delete-orphan")

class CommunityEventRSVP(Base):
    __tablename__ = "community_event_rsvps"

    id = Column(Integer, primary_key=True, index=True)
    event_id = Column(Integer, ForeignKey("community_events.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    response = Column(String(20), nullable=False)  # e.g., 'going', 'maybe', 'not going'
    responded_at = Column(DateTime(timezone=True), server_default=func.now())
    # Relationships
    event = relationship("CommunityEvent", back_populates="rsvps")
    user = relationship("User")

class CommunityResource(Base):
    __tablename__ = "community_resources"

    id = Column(Integer, primary_key=True, index=True)
    community_id = Column(Integer, ForeignKey("communities.id"), nullable=False)
    title = Column(String(200), nullable=False)
    url = Column(String(500))  # Link to external resource or file in MinIO
    resource_type = Column(String(50))  # e.g., 'link', 'file', 'note'
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    # Relationships
    community = relationship("Community", back_populates="resources")
    creator = relationship("User")