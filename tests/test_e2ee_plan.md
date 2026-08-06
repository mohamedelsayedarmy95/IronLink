# End-to-End Encryption Test Plan for IronLink

## Overview
This document outlines the test plan for verifying the End-to-End Encryption (E2EE) implementation in IronLink using the Signal Protocol (X3DH + Double Ratchet).

## Test Categories

### 1. Unit Tests
Test individual components of the encryption service and signal protocol integration.

#### Backend Tests (Python)
- Test identity key pair generation and storage
- Test pre-key generation, storage, and consumption
- Test signed pre-key generation and storage
- Test session storage and retrieval in Redis
- Test X3DH key agreement derivation
- Test encryption and decryption functions

#### Frontend Tests (Flutter/Dart)
- Test identity key pair generation and secure storage
- Test pre-key generation and upload to backend
- Test signed pre-key generation and upload
- Test loading remote keys from backend
- Test session state serialization/deserialization
- Test encryption and decryption of messages

### 2. Integration Tests
Test the complete E2EE flow between two clients.

#### Test Cases
1. **Key Exchange Flow**
   - Alice generates identity key pair and stores it
   - Alice generates and uploads pre-keys to server
   - Bob fetches Alice's pre-keys and identity key
   - Bob performs X3DH to derive shared secret
   - Bob initializes session and sends first message to Alice
   - Alice receives message, computes shared secret, initializes session
   - Both parties can now encrypt/decrypt messages

2. **Message Exchange**
   - Alice sends encrypted message to Bob
   - Bob decrypts message correctly
   - Bob replies with encrypted message
   - Alice decrypts reply correctly
   - Verify ratchet advancement (forward secrecy)

3. **Media Messages**
   - Alice sends encrypted voice message (or other media)
   - Bob decrypts and accesses media correctly
   - Verify media key handling in E2EE context

4. **Session Persistence**
   - Session state is correctly stored in secure storage
   - Session can be restored after app restart
   - Multiple sessions with different contacts work independently

5. **Secret Chat Lifecycle**
   - Starting a secret chat triggers key exchange
   - encryption/decryption works only after successful key exchange
   - Visual indicators show secure status
   - fallback to unencrypted if key exchange fails (with user notification)

### 3. Security Tests
Test security properties and resistance to attacks.

#### Test Cases
1. **Forward Secrecy**
   - Compromise of current session keys does not reveal past messages
   - Verify that ratchet keys change with each message

2. **Break-in Recovery**
   - After a compromise, future messages remain secure once new keys are exchanged

3. **Replay Attack Resistance**
   - Replaying old messages fails decryption
   - Verify use of message counters or similar mechanisms

4. **Man-in-the-Middle Protection**
   - Without authentication, MITM should be detectable
   - Implement safety number verification (to be done in future)

5. **Key Compromise Impersonation Resistance**
   - Long-term key compromise doesn't allow impersonation of past conversations

### 4. Negative Tests
Test error conditions and edge cases.

#### Test Cases
1. **Invalid Keys**
   - Handling of malformed identity keys
   - Handling of malformed pre-keys
   - Handling of expired or used pre-keys

2. **Missing Keys**
   - Behavior when remote pre-keys are not available
   - Behavior when identity key cannot be fetched

3. **Corrupted Messages**
   - Handling of malformed ciphertext
   - Handling of tampered message headers

4. **Storage Failures**
   - Behavior when secure storage is unavailable
   - Behavior when Redis is unavailable (backend)

### 5. Performance Tests
Test performance characteristics.

#### Test Cases
1. **Key Exchange Latency**
   - Time to complete X3DH and initialize session

2. **Encryption/Decryption Speed**
   - Time to encrypt/decrypt typical message sizes
   - Impact on UI responsiveness

3. **Resource Usage**
   - Memory usage during encryption sessions
   - Battery impact on mobile devices

## Test Implementation

### Backend Test Structure
```
tests/
  test_encryption_service.py
  test_keys_routes.py
```

### Frontend Test Structure
```
frontend/test/
  test_signal_service.dart
  test_chat_bloc_e2ee.dart
```

### Required Mocks/Fakes
- Mock Redis backend for testing
- Mock HTTP client for frontend-backend communication
- Fake secure storage implementations

## Pass/Fail Criteria

### Unit Tests
- All unit tests must pass (>90% coverage recommended)

### Integration Tests
- Key exchange must succeed in 95% of test runs
- Message exchange must work bidirectionally without errors
- Session persistence must work across app restarts

### Security Tests
- No information leakage in encrypted channels
- Forward secrecy properties verified
- Replay attacks prevented

### Performance
- Key exchange < 500ms on typical mobile devices
- Encryption/decryption < 50ms for messages < 1KB

## Dependencies
- backend: signal-protocol library
- frontend: libsignal_protocol_dart library
- testing: pytest, flutter_test, mockito/etc.

## Notes
- Safety number verification (comparing public key hashes) is planned for future implementation
- Initial implementation trusts the key delivery mechanism (HTTPS)
- Future work: Implement key verification ceremony (QR code, numeric comparison)