from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from app.models.community import CommunityRole
from app.models.creator import PayoutStatus

class CommunityBase(BaseModel):
    name: str = Field(..., max_length=100)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=50)

class CommunityCreate(CommunityBase):
    pass

class CommunityUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=50)
    is_verified: Optional[bool] = None

class CommunityResponse(CommunityBase):
    id: int
    owner_id: int
    created_at: datetime
    updated_at: Optional[datetime] = None
    is_verified: bool
    member_count: int

    class Config:
        orm_mode = True

class CommunityMemberBase(BaseModel):
    role: CommunityRole

class CommunityMemberCreate(CommunityMemberBase):
    user_id: int

class CommunityMemberResponse(CommunityMemberBase):
    id: int
    community_id: int
    user_id: int
    joined_at: datetime

    class Config:
        orm_mode = True

class CommunityPermissionResponse(BaseModel):
    id: int
    community_id: int
    role: CommunityRole
    can_post: bool
    can_comment: bool
    can_delete_own_posts: bool
    can_delete_any_posts: bool
    can_mute_members: bool
    can_ban_members: bool
    can_invite_members: bool
    can_change_settings: bool

    class Config:
        orm_mode = True

class CommunityEventBase(BaseModel):
    title: str = Field(..., max_length=200)
    description: Optional[str] = None
    start_time: datetime
    end_time: Optional[datetime] = None
    location: Optional[str] = Field(None, max_length=255)

class CommunityEventCreate(CommunityEventBase):
    pass

class CommunityEventResponse(CommunityEventBase):
    id: int
    community_id: int
    created_by: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        orm_mode = True

class CommunityEventRSVPBase(BaseModel):
    response: str = Field(..., max_length=20)  # e.g., 'going', 'maybe', 'not going'

class CommunityEventRSVPCreate(CommunityEventRSVPBase):
    pass

class CommunityEventRSVPResponse(CommunityEventRSVPBase):
    id: int
    event_id: int
    user_id: int
    responded_at: datetime

    class Config:
        orm_mode = True

class CommunityResourceBase(BaseModel):
    title: str = Field(..., max_length=200)
    url: Optional[str] = Field(None, max_length=500)
    resource_type: Optional[str] = Field(None, max_length=50)

class CommunityResourceCreate(CommunityResourceBase):
    pass

class CommunityResourceResponse(CommunityResourceBase):
    id: int
    community_id: int
    created_by: int
    created_at: datetime

    class Config:
        orm_mode = True