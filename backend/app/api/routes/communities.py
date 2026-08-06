from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from app.api import deps
from app.models.community import Community, CommunityMember, CommunityPermission, CommunityEvent, CommunityEventRSVP, CommunityResource
from app.schemas.community import CommunityCreate, CommunityUpdate, CommunityResponse, CommunityMemberCreate, CommunityMemberResponse, CommunityPermissionResponse, CommunityEventCreate, CommunityEventResponse, CommunityEventRSVPCreate, CommunityEventRSVPResponse, CommunityResourceCreate, CommunityResourceResponse
from app.models.user import User

router = APIRouter()

# Community CRUD
@router.post("/", response_model=CommunityResponse)
def create_community(
    community_in: CommunityCreate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Create a new community.
    """
    community = Community(
        name=community_in.name,
        description=community_in.description,
        owner_id=current_user.id,
        category=community_in.category,
    )
    db.add(community)
    db.commit()
    db.refresh(community)
    # Create owner membership
    member = CommunityMember(
        community_id=community.id,
        user_id=current_user.id,
        role=CommunityRole.OWNER,
    )
    db.add(member)
    # Create default permissions for roles
    # We'll create permissions for each role (this is a simplification; in reality, we might have a default set)
    for role in [CommunityRole.OWNER, CommunityRole.ADMIN, CommunityRole.MODERATOR, CommunityRole.MEMBER]:
        permission = CommunityPermission(
            community_id=community.id,
            role=role,
            can_post=(role in [CommunityRole.OWNER, CommunityRole.ADMIN, CommunityRole.MODERATOR, CommunityRole.MEMBER]),
            can_comment=(role in [CommunityRole.OWNER, CommunityRole.ADMIN, CommunityRole.MODERATOR, CommunityRole.MEMBER]),
            can_delete_own_posts=(role in [CommunityRole.OWNER, CommunityRole.ADMIN, CommunityRole.MODERATOR, CommunityRole.MEMBER]),
            can_delete_any_posts=(role in [CommunityRole.OWNER, CommunityRole.ADMIN]),
            can_mute_members=(role in [CommunityRole.OWNER, CommunityRole.ADMIN, CommunityRole.MODERATOR]),
            can_ban_members=(role in [CommunityRole.OWNER, CommunityRole.ADMIN]),
            can_invite_members=(role in [CommunityRole.OWNER, CommunityRole.ADMIN, CommunityRole.MODERATOR]),
            can_change_settings=(role in [CommunityRole.OWNER, CommunityRole.ADMIN]),
        )
        db.add(permission)
    db.commit()
    return community

@router.get("/", response_model=List[CommunityResponse])
def read_communities(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Retrieve communities.
    """
    communities = db.query(Community).offset(skip).limit(limit).all()
    return communities

@router.get("/{community_id}", response_model=CommunityResponse)
def read_community(
    community_id: int,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Get a specific community by ID.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    return community

@router.put("/{community_id}", response_model=CommunityResponse)
def update_community(
    community_id: int,
    community_in: CommunityUpdate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Update a community.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    if community.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not enough permissions")
    for field, value in community_in.dict(exclude_unset=True).items():
        setattr(community, field, value)
    db.commit()
    db.refresh(community)
    return community

@router.delete("/{community_id}", response_model=CommunityResponse)
def delete_community(
    community_id: int,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Delete a community.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    if community.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not enough permissions")
    db.delete(community)
    db.commit()
    return community

# Community Members
@router.post("/{community_id}/members", response_model=CommunityMemberResponse)
def add_community_member(
    community_id: int,
    member_in: CommunityMemberCreate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Add a member to a community (invite or approve).
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    # Check if current user has permission to invite members
    # We'll check the permission for the current user's role in this community
    # For simplicity, we allow owner and admins to invite; in a real app, we'd check the permission table.
    member = db.query(CommunityMember).filter(
        CommunityMember.community_id == community_id,
        CommunityMember.user_id == current_user.id
    ).first()
    if not member or member.role not in [CommunityRole.OWNER, CommunityRole.ADMIN]:
        raise HTTPException(status_code=403, detail="Not enough permissions to invite members")
    # Check if user is already a member
    existing = db.query(CommunityMember).filter(
        CommunityMember.community_id == community_id,
        CommunityMember.user_id == member_in.user_id
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="User is already a member of this community")
    new_member = CommunityMember(
        community_id=community_id,
        user_id=member_in.user_id,
        role=member_in.role,
    )
    db.add(new_member)
    # Update member count
    community.member_count += 1
    db.commit()
    db.refresh(new_member)
    return new_member

@router.get("/{community_id}/members", response_model=List[CommunityMemberResponse])
def read_community_members(
    community_id: int,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Retrieve members of a community.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    members = db.query(CommunityMember).filter(CommunityMember.community_id == community_id).offset(skip).limit(limit).all()
    return members

# Community Events
@router.post("/{community_id}/events", response_model=CommunityEventResponse)
def create_community_event(
    community_id: int,
    event_in: CommunityEventCreate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Create a new event in a community.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    # Check if user has permission to create events (we'll allow owners and admins for now)
    member = db.query(CommunityMember).filter(
        CommunityMember.community_id == community_id,
        CommunityMember.user_id == current_user.id
    ).first()
    if not member or member.role not in [CommunityRole.OWNER, CommunityRole.ADMIN]:
        raise HTTPException(status_code=403, detail="Not enough permissions to create events")
    event = CommunityEvent(
        community_id=community_id,
        title=event_in.title,
        description=event_in.description,
        start_time=event_in.start_time,
        end_time=event_in.end_time,
        location=event_in.location,
        created_by=current_user.id,
    )
    db.add(event)
    db.commit()
    db.refresh(event)
    return event

@router.get("/{community_id}/events", response_model=List[CommunityEventResponse])
def read_community_events(
    community_id: int,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Retrieve events for a community.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    events = db.query(CommunityEvent).filter(CommunityEvent.community_id == community_id).offset(skip).limit(limit).all()
    return events

@router.post("/{community_id}/events/{event_id}/rsvp", response_model=CommunityEventRSVPResponse)
def rsvp_to_community_event(
    community_id: int,
    event_id: int,
    rsvp_in: CommunityEventRSVPCreate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    RSVP to a community event.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    event = db.query(CommunityEvent).filter(
        CommunityEvent.id == event_id,
        CommunityEvent.community_id == community_id
    ).first()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    # Check if user is a member of the community
    member = db.query(CommunityMember).filter(
        CommunityMember.community_id == community_id,
        CommunityMember.user_id == current_user.id
    ).first()
    if not member:
        raise HTTPException(status_code=403, detail="You must be a member of the community to RSVP")
    # Check if already RSVP'd
    existing = db.query(CommunityEventRSVP).filter(
        CommunityEventRSVP.event_id == event_id,
        CommunityEventRSVP.user_id == current_user.id
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="You have already RSVP'd to this event")
    rsvp = CommunityEventRSVP(
        event_id=event_id,
        user_id=current_user.id,
        response=rsvp_in.response,
    )
    db.add(rsvp)
    db.commit()
    db.refresh(rsvp)
    return rsvp

# Community Resources
@router.post("/{community_id}/resources", response_model=CommunityResourceResponse)
def add_community_resource(
    community_id: int,
    resource_in: CommunityResourceCreate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Add a resource to a community.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    # Check if user has permission to add resources (we'll allow owners and admins for now)
    member = db.query(CommunityMember).filter(
        CommunityMember.community_id == community_id,
        CommunityMember.user_id == current_user.id
    ).first()
    if not member or member.role not in [CommunityRole.OWNER, CommunityRole.ADMIN]:
        raise HTTPException(status_code=403, detail="Not enough permissions to add resources")
    resource = CommunityResource(
        community_id=community_id,
        title=resource_in.title,
        url=resource_in.url,
        resource_type=resource_in.resource_type,
        created_by=current_user.id,
    )
    db.add(resource)
    db.commit()
    db.refresh(resource)
    return resource

@router.get("/{community_id}/resources", response_model=List[CommunityResourceResponse])
def read_community_resources(
    community_id: int,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Retrieve resources for a community.
    """
    community = db.query(Community).filter(Community.id == community_id).first()
    if not community:
        raise HTTPException(status_code=404, detail="Community not found")
    resources = db.query(CommunityResource).filter(CommunityResource.community_id == community_id).offset(skip).limit(limit).all()
    return resources