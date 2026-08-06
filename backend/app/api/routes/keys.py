from flask import Blueprint, jsonify, request, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.services.encryption_service import EncryptionService
from app.extensions import redis_client
import logging
import base64

logger = logging.getLogger(__name__)

keys_bp = Blueprint('keys', __name__)

@keys_bp.route('/prekeys/<string:user_id>', methods=['GET'])
@jwt_required(optional=True)  # Optional for fetching others' prekeys
def get_prekeys(user_id):
    """Get pre-keys for a user (for X3DH key exchange)."""
    try:
        # In a production app, you'd want to verify the requester is allowed
        # to fetch this user's prekeys (e.g., they are in each other's contacts)
        # For now, we'll allow any authenticated user to fetch any user's prekeys

        # Get from Redis
        prekeys_hash = f"user:{user_id}:prekeys"
        prekeys = redis_client.hgetall(prekeys_hash)

        if not prekeys:
            return jsonify({"error": "No prekeys found for user"}), 404

        # Format response
        keys_list = []
        for key_id, pub_key_b64 in prekeys.items():
            keys_list.append({
                "publicKey": pub_key_b64.decode('utf-8') if isinstance(pub_key_b64, bytes) else pub_key_b64,
                "keyId": int(key_id)
            })

        return jsonify({
            "userId": user_id,
            "prekeys": keys_list
        }), 200

    except Exception as e:
        logger.error(f"Error fetching prekeys for user {user_id}: {e}")
        return jsonify({"error": "Internal server error"}), 500

@keys_bp.route('/identity', methods=['POST'])
@jwt_required()
def upload_identity_key():
    """Upload or update identity public key for the current user."""
    try:
        user_id = get_jwt_identity()
        data = request.get_json()

        if not data or 'publicKey' not in data:
            return jsonify({"error": "Public key is required"}), 400

        public_key_b64 = data['publicKey']
        # Validate base64
        try:
            public_key_bytes = base64.b64decode(public_key_b64)
        except Exception:
            return jsonify({"error": "Invalid public key format"}), 400

        # Update user's identity public key in database
        from app.models.user import User
        from app.extensions import db

        user = User.query.get(user_id)
        if not user:
            return jsonify({"error": "User not found"}), 404

        user.identity_public_key = public_key_b64
        # Note: We don't update the private key here - that's generated client-side
        # and never sent to the server
        db.session.commit()

        logger.info(f"Updated identity public key for user {user_id}")
        return jsonify({"message": "Identity key updated successfully"}), 200

    except Exception as e:
        logger.error(f"Error uploading identity key: {e}")
        return jsonify({"error": "Internal server error"}), 500

@keys_bp.route('/prekey', methods=['POST'])
@jwt_required()
def upload_prekey():
    """Upload a single pre-key (client-generated)."""
    try:
        user_id = get_jwt_identity()
        data = request.get_json()

        if not data or 'publicKey' not in data or 'keyId' not in data:
            return jsonify({"error": "Public key and key ID are required"}), 400

        public_key_b64 = data['publicKey']
        key_id = data['keyId']

        # Validate inputs
        try:
            public_key_bytes = base64.b64decode(public_key_b64)
        except Exception:
            return jsonify({"error": "Invalid public key format"}), 400

        if not isinstance(key_id, int) or key_id < 0:
            return jsonify({"error": "Key ID must be a non-negative integer"}), 400

        # Use encryption service to store the pre-key
        from app.services.encryption_service import EncryptionService
        enc_service = EncryptionService(user_id, redis_client)
        success = enc_service.store_pre_key(key_id, public_key_bytes)

        if success:
            logger.info(f"Stored client-uploaded pre-key {key_id} for user {user_id}")
            return jsonify({"message": "Pre-key stored successfully"}), 200
        else:
            return jsonify({"error": "Failed to store pre-key"}), 500

    except Exception as e:
        logger.error(f"Error uploading prekey: {e}")
        return jsonify({"error": "Internal server error"}), 500

@keys_bp.route('/signed_prekey', methods=['POST'])
@jwt_required()
def upload_signed_prekey():
    """Upload a signed pre-key (client-generated)."""
    try:
        user_id = get_jwt_identity()
        data = request.get_json()

        if not data or 'publicKey' not in data or 'keyId' not in data or 'signature' not in data:
            return jsonify({"error": "Public key, key ID, and signature are required"}), 400

        public_key_b64 = data['publicKey']
        key_id = data['keyId']
        signature_b64 = data['signature']

        # Validate inputs
        try:
            public_key_bytes = base64.b64decode(public_key_b64)
            signature_bytes = base64.b64decode(signature_b64)
        except Exception:
            return jsonify({"error": "Invalid public key or signature format"}), 400

        if not isinstance(key_id, int) or key_id < 0:
            return jsonify({"error": "Key ID must be a non-negative integer"}), 400

        # Store signed pre-key in Redis
        redis_client.hset(
            f"user:{user_id}:signed_prekey",
            "publicKey",
            public_key_b64
        )
        redis_client.hset(
            f"user:{user_id}:signed_prekey",
            "signature",
            signature_b64
        )
        redis_client.expire(f"user:{user_id}:signed_prekey", 30 * 24 * 3600)  # 30 days

        # Also store the private key? The client should have generated the keypair
        # and kept the private part locally. For the server to use it in X3DH,
        # we need the private part. However, in the Signal Protocol, the server
        # doesn't need the private part of the signed pre-key for X3DH -
        # only the public part and signature are needed.
        # The private part is used by the client to sign the pre-key.

        logger.info(f"Stored client-uploaded signed pre-key {key_id} for user {user_id}")
        return jsonify({"message": "Signed pre-key stored successfully"}), 200

    except Exception as e:
        logger.error(f"Error uploading signed prekey: {e}")
        return jsonify({"error": "Internal server error"}), 500

@keys_bp.route('/<string:user_id>/signed_prekey', methods=['GET'])
@jwt_required(optional=True)
def get_signed_prekey(user_id):
    """Get signed pre-key for a user."""
    try:
        # Fetch from Redis
        public_key_b64 = redis_client.hget(f"user:{user_id}:signed_prekey", "publicKey")
        signature_b64 = redis_client.hget(f"user:{user_id}:signed_prekey", "signature")

        if not public_key_b64 or not signature_b64:
            return jsonify({"error": "Signed pre-key not found for user"}), 404

        return jsonify({
            "userId": user_id,
            "publicKey": public_key_b64.decode('utf-8') if isinstance(public_key_b64, bytes) else public_key_b64,
            "signature": signature_b64.decode('utf-8') if isinstance(signature_b64, bytes) else signature_b64,
            "keyId": 0xFFFF  # Fixed ID for signed pre-key
        }), 200

    except Exception as e:
        logger.error(f"Error fetching signed prekey for user {user_id}: {e}")
        return jsonify({"error": "Internal server error"}), 500