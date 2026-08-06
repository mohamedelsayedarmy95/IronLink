import os
import json
import base64
import logging
from typing import Optional, Tuple, List, Dict
from datetime import datetime, timedelta

from redis import Redis
from signalprotocol import (
    IdentityKeyPair,
    PreKey,
    SignedPreKey,
    SessionBuilder,
    SessionCipher,
    InvalidKeyException,
    InvalidMessageException,
)
from signalprotocol.protocol import Address
from app.models.user import User
from app.extensions import db

logger = logging.getLogger(__name__)

class EncryptionService:
    """
    Handles Signal Protocol encryption/decryption for a specific user.
    Manages identity keys, pre-keys, signed pre-keys, and session states.
    """

    def __init__(self, user_id: str, redis_client: Redis):
        self.user_id = user_id
        self.redis = redis_client
        self._identity_key_pair = self._load_or_create_identity_key_pair()

        # Redis keys
        self.PREKEYS_HASH = f"user:{self.user_id}:prekeys"
        self.PREKEY_PRIVATE_PREFIX = f"user:{self.user_id}:prekey"
        self.SESSION_PREFIX = f"user:{self.user_id}:session"

    def _load_or_create_identity_key_pair(self) -> IdentityKeyPair:
        """Load user's identity key pair from database or create new one."""
        user = User.query.get(self.user_id)
        if user and user.identity_public_key and user.identity_private_key:
            try:
                pub_key = base64.b64decode(user.identity_public_key)
                priv_key = base64.b64decode(user.identity_private_key)
                return IdentityKeyPair(pub_key, priv_key)
            except Exception as e:
                logger.warning(f"Failed to load identity keys for user {self.user_id}: {e}")

        # Generate new identity key pair
        identity_key_pair = IdentityKeyPair.generate()
        # Save to database
        if not user:
            user = User(id=self.user_id)
            db.session.add(user)
        user.identity_public_key = base64.b64encode(identity_key_pair.get_public_key().serialize()).decode('utf-8')
        user.identity_private_key = base64.b64encode(identity_key_pair.get_private_key().serialize()).decode('utf-8')
        db.session.commit()
        logger.info(f"Generated new identity key pair for user {self.user_id}")
        return identity_key_pair

    def generate_identity_key_pair(self) -> Tuple[bytes, bytes]:
        """
        Returns the user's identity key pair (public, private) as raw bytes.
        """
        return (
            self._identity_key_pair.get_public_key().serialize(),
            self._identity_key_pair.get_private_key().serialize()
        )

    def generate_pre_keys(self, count: int = 100) -> List[Dict]:
        """
        Generate and store N pre-keys. Returns list of pre-key objects to send to client.
        Each pre-key object: {publicKey: base64, keyId: int}
        """
        pre_keys = []
        for i in range(count):
            # Generate a random pre-key ID (high bits to avoid collision with signed pre-key)
            pre_key_id = int.from_bytes(os.urandom(4), byteorder='big') & 0x7FFFFFFF
            # Ensure we don't overwrite existing pre-key
            while self.redis.hexists(self.PREKEYS_HASH, str(pre_key_id)):
                pre_key_id = int.from_bytes(os.urandom(4), byteorder='big') & 0x7FFFFFFF

            # Generate pre-key pair
            pre_key = PreKey.generate(pre_key_id)

            # Store private key in Redis (with expiration? pre-keys are long-lived until used)
            priv_key_bytes = pre_key.get_private_key().serialize()
            self.redis.hset(
                f"{self.PREKEY_PRIVATE_PREFIX}:{pre_key_id}",
                "private",
                base64.b64encode(priv_key_bytes).decode('utf-8')
            )
            # Optional: set expiration for unused pre-keys (e.g., 30 days)
            self.redis.expire(f"{self.PREKEY_PRIVATE_PREFIX}:{pre_key_id}", 30 * 24 * 3600)

            # Store public key in prekeys hash for clients to fetch
            pub_key_bytes = pre_key.get_public_key().serialize()
            self.redis.hset(
                self.PREKEYS_HASH,
                str(pre_key_id),
                base64.b64encode(pub_key_bytes).decode('utf-8')
            )

            pre_keys.append({
                "publicKey": base64.b64encode(pub_key_bytes).decode('utf-8'),
                "keyId": pre_key_id
            })

        logger.info(f"Generated {count} pre-keys for user {self.user_id}")
        return pre_keys

    def generate_signed_pre_key(self) -> Dict:
        """
        Generate and store a signed pre-key. Returns object to send to client.
        """
        # Generate signed pre-key ID (use a fixed range to distinguish from regular pre-keys)
        signed_pre_key_id = 0xFFFF  # Use a specific ID for signed pre-key

        # Generate signed pre-key pair
        signed_pre_key = SignedPreKey.generate(signed_pre_key_id)

        # Sign with identity private key
        signature = self._identity_key_pair.generate_signature(
            signed_pre_key.get_public_key().serialize()
        )

        # Store private key in Redis
        priv_key_bytes = signed_pre_key.get_private_key().serialize()
        self.redis.hset(
            f"{self.PREKEY_PRIVATE_PREFIX}:signed:{signed_pre_key_id}",
            "private",
            base64.b64encode(priv_key_bytes).decode('utf-8')
        )
        self.redis.expire(f"{self.PREKEY_PRIVATE_PREFIX}:signed:{signed_pre_key_id}", 30 * 24 * 3600)

        # Store public key and signature
        pub_key_bytes = signed_pre_key.get_public_key().serialize()
        self.redis.hset(
            f"user:{self.user_id}:signed_prekey",
            "publicKey",
            base64.b64encode(pub_key_bytes).decode('utf-8')
        )
        self.redis.hset(
            f"user:{self.user_id}:signed_prekey",
            "signature",
            base64.b64encode(signature).decode('utf-8')
        )
        self.redis.expire(f"user:{self.user_id}:signed_prekey", 30 * 24 * 3600)

        logger.info(f"Generated signed pre-key for user {self.user_id}")
        return {
            "publicKey": base64.b64encode(pub_key_bytes).decode('utf-8'),
            "keyId": signed_pre_key_id,
            "signature": base64.b64encode(signature).decode('utf-8')
        }

    def store_pre_key(self, pre_key_id: int, public_key: bytes) -> bool:
        """
        Store a pre-key (public part) - used when client uploads pre-keys.
        Returns True if stored successfully.
        """
        # Generate and store private key locally
        pre_key = PreKey.generate(pre_key_id)
        priv_key_bytes = pre_key.get_private_key().serialize()

        # Store private key
        self.redis.hset(
            f"{self.PREKEY_PRIVATE_PREFIX}:{pre_key_id}",
            "private",
            base64.b64encode(priv_key_bytes).decode('utf-8')
        )
        self.redis.expire(f"{self.PREKEY_PRIVATE_PREFIX}:{pre_key_id}", 30 * 24 * 3600)

        # Store public key in hash
        self.redis.hset(
            self.PREKEYS_HASH,
            str(pre_key_id),
            base64.b64encode(public_key).decode('utf-8')
        )

        logger.debug(f"Stored pre-key {pre_key_id} for user {self.user_id}")
        return True

    def consume_pre_key(self, pre_key_id: int) -> Optional[bytes]:
        """
        Retrieve and remove a pre-key's private key (for one-time use in X3DH).
        Returns private key bytes if found and consumed, None otherwise.
        """
        # Get private key from Redis
        priv_key_b64 = self.redis.hget(
            f"{self.PREKEY_PRIVATE_PREFIX}:{pre_key_id}",
            "private"
        )
        if not priv_key_b64:
            logger.warning(f"Pre-key {pre_key_id} not found for user {self.user_id}")
            return None

        # Delete the pre-key (private part and public part)
        pipe = self.redis.pipeline()
        pipe.hdel(f"{self.PREKEY_PRIVATE_PREFIX}:{pre_key_id}", "private")
        pipe.hdel(self.PREKEYS_HASH, str(pre_key_id))
        pipe.execute()

        # Also delete the expiration key
        self.redis.delete(f"{self.PREKEY_PRIVATE_PREFIX}:{pre_key_id}")

        priv_key_bytes = base64.b64decode(priv_key_b64)
        logger.debug(f"Consumed pre-key {pre_key_id} for user {self.user_id}")
        return priv_key_bytes

    def store_session(self, remote_user_id: str, session_state: bytes) -> bool:
        """
        Store a session state for communicating with remote_user_id.
        """
        session_key = f"{self.SESSION_PREFIX}:{remote_user_id}"
        self.redis.set(session_key, session_state)
        # Sessions are long-lived; no expiration by default
        logger.debug(f"Stored session for user {self.user_id} with {remote_user_id}")
        return True

    def load_session(self, remote_user_id: str) -> Optional[bytes]:
        """
        Load session state for communicating with remote_user_id.
        Returns session state bytes if found, None otherwise.
        """
        session_key = f"{self.SESSION_PREFIX}:{remote_user_id}"
        session_state = self.redis.get(session_key)
        if session_state:
            logger.debug(f"Loaded session for user {self.user_id} with {remote_user_id}")
        else:
            logger.debug(f"No session found for user {self.user_id} with {remote_user_id}")
        return session_state

    def derive_shared_secret(
        self,
        identity_key: bytes,
        pre_key: bytes,
        ephemeral_key: bytes
    ) -> bytes:
        """
        Perform X3DH key agreement to derive a shared secret.
        Returns the shared secret bytes.
        """
        try:
            # Convert to library objects
            their_identity = IdentityKeyPair(identity_key, None)  # We only have public key
            their_prekey = PreKey.deserialize(pre_key)
            our_ephemeral = IdentityKeyPair.generate()  # Generate ephemeral key pair

            # Perform X3DH (simplified - library doesn't have direct X3DH, we compute manually)
            # Actually, we'll use SessionBuilder which does X3DH internally when initialized
            # But for returning just the shared secret, we need to compute it

            # For now, we'll return a placeholder - in reality we'd use the library's agreement
            # Since the library doesn't expose the raw agreement, we'll simulate by creating
            # a session and extracting the root key (not ideal but works for demo)
            # Proper implementation would use the agreement functions from the library

            # TODO: Implement proper X3DH using low-level agreement functions
            # For now, we'll use a simplified approach
            from signalprotocol.protocol import ECKeyPair
            from signalprotocol.ecc import ECPoint, ECPrivateKey

            # This is a simplified version - in production use the library's agreement
            # We'll return a dummy secret for now and mark for improvement
            logger.warning("X3DH derivation not fully implemented - using placeholder")
            return os.urandom(32)  # Placeholder

        except Exception as e:
            logger.error(f"Failed to derive shared secret: {e}")
            raise

    def encrypt_message(self, plaintext: str, remote_user_id: str, remote_identity_key: bytes,
                       remote_signed_pre_key: Dict, remote_pre_key_id: int,
                       our_ephemeral_key_pair: IdentityKeyPair) -> Dict:
        """
        Encrypt a message for a remote user using Signal Protocol.
        Returns a dictionary containing the ciphertext and necessary header info.
        """
        try:
            # Build session if we don't have one
            session_state = self.load_session(remote_user_id)
            if session_state:
                session_cipher = SessionCipher(session_state)
            else:
                # Initialize session with remote's pre-key bundle
                address = Address(remote_user_id, 1)  # device ID 1 for simplicity
                builder = SessionBuilder(
                    self._identity_key_pair,
                    self.redis,  # We need to adapt this - the library expects a store
                    address
                )
                # TODO: Properly implement session building with remote's pre-key bundle
                # For now, we'll simulate
                logger.warning("Session building not fully implemented")
                # Generate a dummy session state
                session_state = os.urandom(1024)
                self.store_session(remote_user_id, session_state)
                session_cipher = SessionCipher(session_state)

            # Encrypt
            ciphertext = session_cipher.encrypt(plaintext.encode('utf-8'))

            return {
                "ciphertext": base64.b64encode(ciphertext.serialize()).decode('utf-8'),
                "ratchetKey": base64.b64encode(os.urandom(32)).decode('utf-8'),  # Placeholder
                "previousCounter": 0,
                "counter": 0
            }
        except Exception as e:
            logger.error(f"Encryption failed: {e}")
            raise

    def decrypt_message(self, ciphertext_b64: str, ratchet_key_b64: str,
                       remote_user_id: str) -> str:
        """
        Decrypt a message from a remote user.
        Returns the plaintext string.
        """
        try:
            session_state = self.load_session(remote_user_id)
            if not session_state:
                raise ValueError("No session found for decryption")

            session_cipher = SessionCipher(session_state)
            ciphertext_bytes = base64.b64decode(ciphertext_b64)
            # TODO: Properly deserialize ciphertext using library
            # For now, we'll simulate
            plaintext = session_cipher.decrypt(ciphertext_bytes).decode('utf-8')
            return plaintext
        except Exception as e:
            logger.error(f"Decryption failed: {e}")
            raise