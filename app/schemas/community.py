from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models.community import CommunityRole


class CommunityBase(BaseModel):
    name: str = Field(..., max_length=100)
    description: str | None = None
    category: str | None = Field(None, max_length=50)


class CommunityCreate(CommunityBase):
    pass


class CommunityUpdate(BaseModel):
    name: str | None = Field(None, max_length=100)
    description: str | None = None
    category: str | None = Field(None, max_length=50)


class CommunityResponse(CommunityBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    owner_id: UUID
    created_at: datetime
    updated_at: datetime
    is_verified: bool
    member_count: int


class CommunityMemberBase(BaseModel):
    role: CommunityRole = CommunityRole.MEMBER


class CommunityMemberCreate(CommunityMemberBase):
    user_id: UUID


class CommunityMemberResponse(CommunityMemberBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    community_id: UUID
    user_id: UUID
    created_at: datetime


class CommunityPermissionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    community_id: UUID
    role: CommunityRole
    can_post: bool
    can_comment: bool
    can_delete_own_posts: bool
    can_delete_any_posts: bool
    can_mute_members: bool
    can_ban_members: bool
    can_invite_members: bool
    can_change_settings: bool


class CommunityEventBase(BaseModel):
    title: str = Field(..., max_length=200)
    description: str | None = None
    start_time: datetime
    end_time: datetime | None = None
    location: str | None = Field(None, max_length=255)


class CommunityEventCreate(CommunityEventBase):
    pass


class CommunityEventResponse(CommunityEventBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    community_id: UUID
    created_by: UUID
    created_at: datetime
    updated_at: datetime


class CommunityEventRSVPBase(BaseModel):
    response: str = Field(..., max_length=20)


class CommunityEventRSVPCreate(CommunityEventRSVPBase):
    pass


class CommunityEventRSVPResponse(CommunityEventRSVPBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    event_id: UUID
    user_id: UUID
    created_at: datetime


class CommunityResourceBase(BaseModel):
    title: str = Field(..., max_length=200)
    url: str | None = Field(None, max_length=500)
    resource_type: str | None = Field(None, max_length=50)


class CommunityResourceCreate(CommunityResourceBase):
    pass


class CommunityResourceResponse(CommunityResourceBase):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    community_id: UUID
    created_by: UUID
    created_at: datetime
