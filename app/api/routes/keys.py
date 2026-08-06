from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel

from app.api.deps import get_current_user
from app.models import User
from app.services.encryption_service import encryption_service

router = APIRouter(tags=["keys"])


class PreKeyResponse(BaseModel):
    key_id: int
    public_key: str


class IdentityKeyResponse(BaseModel):
    public_key: str


class PreKeyUpload(BaseModel):
    key_id: int
    public_key: str


class SignedPreKeyUpload(BaseModel):
    key_id: int
    public_key: str
    signature: str


@router.get(
    "/keys/prekeys/{user_id}",
    response_model=List[PreKeyResponse],
    status_code=status.HTTP_200_OK,
)
async def get_prekeys(
    user_id: UUID = Path(...),
    current_user: User = Depends(get_current_user),
):
    """
    Return pre-keys for the specified user.
    Used by another user to initiate a secret chat (X3DH).
    """
    # In a production system, you might want to restrict this to only allow
    # fetching prekeys for users you are allowed to chat with.
    # For simplicity, we allow any authenticated user to fetch any user's prekeys.
    prekeys = await encryption_service.get_pre_keys(user_id)
    if not prekeys:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No prekeys found for user",
        )
    return [
        PreKeyResponse(key_id=key_id, public_key=key_pair["public"])
        for key_id, key_pair in prekeys
    ]


@router.post(
    "/keys/identity",
    status_code=status.HTTP_201_CREATED,
)
async def register_identity_key(
    identity_key: IdentityKeyResponse,
    current_user: User = Depends(get_current_user),
):
    """
    Register the user's identity key.
    Called when the user installs the app or resets their identity.
    """
    # In a real implementation, we would also store the private key securely
    # on the device and only ever send the public key to the server.
    # Here, we are only receiving the public key from the client.
    # The private key never leaves the client.
    # We generate a mock identity key pair for the user and store it.
    # In reality, the client would generate the key pair and send only the public part.
    # We'll store a mock pair (both public and private) for demonstration.
    # NOTE: This is insecure. In production, the server should never see the private key.
    # We are doing this only for the sake of having a complete example.
    identity_key_pair = encryption_service.generate_identity_key_pair()
    # Override the public key with the one provided by the client (if we trusted the client to generate it)
    # But for simplicity, we ignore the client's public key and use our mock.
    # In a real implementation, the client would generate the key pair locally,
    # encrypt the private key with a key derived from their password,
    # and send the encrypted private key and public key to the server for backup.
    # The server would store the encrypted private key and public key.
    # When the user logs in, they would decrypt the private key locally.
    await encryption_service.store_identity_key(current_user.id, identity_key_pair)
    return {"status": "identity key registered"}


@router.post(
    "/keys/prekey",
    status_code=status.HTTP_201_CREATED,
)
async def upload_prekey(
    prekey: PreKeyUpload,
    current_user: User = Depends(get_current_user),
):
    """
    Upload a new pre-key for the user.
    Called by the client to add a new one-time pre-key.
    """
    # In reality, the client would generate a key pair locally and send the public key.
    # The private key remains on the client.
    # Here, we generate a mock key pair and store it.
    # We ignore the public key provided by the client and use our mock.
    key_pair = encryption_service.generate_pre_key_pair()
    await encryption_service.store_pre_key(current_user.id, prekey.key_id, key_pair)
    return {"status": "prekey uploaded"}


@router.post(
    "/keys/signed_prekey",
    status_code=status.HTTP_201_CREATED,
)
async def upload_signed_prekey(
    signed_prekey: SignedPreKeyUpload,
    current_user: User = Depends(get_current_user),
):
    """
    Upload a new signed pre-key for the user.
    Called by the client to rotate their signed pre-key.
    """
    # In reality, the client would generate a key pair locally, sign it with their identity key,
    # and send the public key, the private key (encrypted), and the signature.
    # Here, we generate a mock key pair and signature.
    key_pair = encryption_service.generate_pre_key_pair()  # Using pre-key for simplicity
    signature = "mock_signature_from_client"
    # In a real implementation, we would verify the signature against the user's identity key.
    # We skip verification for this mock.
    await encryption_service.store_signed_pre_key(
        current_user.id, signed_prekey.key_id, key_pair, signature
    )
    return {"status": "signed prekey uploaded"}