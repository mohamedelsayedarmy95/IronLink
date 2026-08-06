from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
from app.api import deps
from app.models.channel import Channel, ChannelPost, ChannelSubscription, ChannelAnalytics
from app.schemas.channel import ChannelCreate, ChannelUpdate, ChannelResponse, ChannelPostCreate, ChannelPostResponse, ChannelSubscriptionCreate, ChannelSubscriptionResponse, ChannelAnalyticsResponse
from app.models.user import User

router = APIRouter()

# Channel CRUD
@router.post("/", response_model=ChannelResponse)
def create_channel(
    channel_in: ChannelCreate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Create a new channel.
    """
    channel = Channel(
        name=channel_in.name,
        description=channel_in.description,
        type=channel_in.type,
        owner_id=current_user.id,
        category=channel_in.category,
    )
    db.add(channel)
    db.commit()
    db.refresh(channel)
    return channel

@router.get("/", response_model=List[ChannelResponse])
def read_channels(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Retrieve channels.
    """
    channels = db.query(Channel).offset(skip).limit(limit).all()
    return channels

@router.get("/{channel_id}", response_model=ChannelResponse)
def read_channel(
    channel_id: int,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Get a specific channel by ID.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")
    return channel

@router.put("/{channel_id}", response_model=ChannelResponse)
def update_channel(
    channel_id: int,
    channel_in: ChannelUpdate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Update a channel.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")
    if channel.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not enough permissions")
    for field, value in channel_in.dict(exclude_unset=True).items():
        setattr(channel, field, value)
    db.commit()
    db.refresh(channel)
    return channel

@router.delete("/{channel_id}", response_model=ChannelResponse)
def delete_channel(
    channel_id: int,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Delete a channel.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")
    if channel.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not enough permissions")
    db.delete(channel)
    db.commit()
    return channel

# Channel Posts
@router.post("/{channel_id}/posts", response_model=ChannelPostResponse)
def create_channel_post(
    channel_id: int,
    post_in: ChannelPostCreate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Create a new post in a channel.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")
    # Check if user is allowed to post (for now, we allow any member; later we can check permissions)
    # For simplicity, we allow any authenticated user to post in public channels.
    # For private channels, we would check subscription.
    post = ChannelPost(
        channel_id=channel_id,
        author_id=current_user.id,
        content=post_in.content,
        media_key=post_in.media_key,
        mime_type=post_in.mime_type,
        scheduled_at=post_in.scheduled_at,
        is_scheduled=post_in.is_scheduled if post_in.scheduled_at else False,
    )
    db.add(post)
    db.commit()
    db.refresh(post)
    return post

@router.get("/{channel_id}/posts", response_model=List[ChannelPostResponse])
def read_channel_posts(
    channel_id: int,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Retrieve posts for a channel.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")
    posts = db.query(ChannelPost).filter(ChannelPost.channel_id == channel_id).offset(skip).limit(limit).all()
    return posts

# Channel Subscriptions
@router.post("/{channel_id}/subscribe", response_model=ChannelSubscriptionResponse)
def subscribe_to_channel(
    channel_id: int,
    subscription_in: ChannelSubscriptionCreate,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Subscribe to a channel.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")
    # Check if already subscribed
    existing = db.query(ChannelSubscription).filter(
        ChannelSubscription.channel_id == channel_id,
        ChannelSubscription.user_id == current_user.id
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Already subscribed to this channel")
    subscription = ChannelSubscription(
        channel_id=channel_id,
        user_id=current_user.id,
        subscription_plan_id=subscription_in.subscription_plan_id,
    )
    db.add(subscription)
    # Update subscriber count
    channel.subscriber_count += 1
    db.commit()
    db.refresh(subscription)
    return subscription

@router.delete("/{channel_id}/unsubscribe")
def unsubscribe_from_channel(
    channel_id: int,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Unsubscribe from a channel.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")
    subscription = db.query(ChannelSubscription).filter(
        ChannelSubscription.channel_id == channel_id,
        ChannelSubscription.user_id == current_user.id
    ).first()
    if not subscription:
        raise HTTPException(status_code=400, detail="Not subscribed to this channel")
    db.delete(subscription)
    channel.subscriber_count -= 1
    db.commit()
    return {"message": "Unsubscribed successfully"}

# Channel Analytics
@router.get("/{channel_id}/analytics", response_model=ChannelAnalyticsResponse)
def read_channel_analytics(
    channel_id: int,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Get analytics for a channel.
    """
    channel = db.query(Channel).filter(Channel.id == channel_id).first()
    if not channel:
        raise HTTPException(status_code=404, detail="Channel not found")
    # For now, we return the latest analytics or create a dummy one if not exists
    analytics = db.query(ChannelAnalytics).filter(ChannelAnalytics.channel_id == channel_id).order_by(ChannelAnalytics.date.desc()).first()
    if not analytics:
        # Create a default analytics record
        analytics = ChannelAnalytics(channel_id=channel_id)
        db.add(analytics)
        db.commit()
        db.refresh(analytics)
    return analytics