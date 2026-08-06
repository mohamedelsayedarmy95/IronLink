from __future__ import annotations

import structlog

from app.config import settings

logger = structlog.get_logger("sms")


class SmsGateway:
    """SMS delivery abstraction.

    Production: wire to the unit's SMS provider (e.g. an internal SMPP bridge
    or Twilio-compatible HTTP API) via env-configured credentials.

    Development: logs a delivery EVENT only — the OTP code itself is NEVER
    logged, in any environment. Use the provider's test console or the Redis
    key (DB index 1) to read codes during local development.
    """

    async def send_otp(self, phone_number: str, code: str) -> None:
        if settings.ENV == "development":
            # Masked phone, no code — safe even if logs are shipped somewhere.
            logger.info("otp_dispatched", phone=phone_number[:5] + "********")
            return
        # TODO(sprint-2): production SMS provider integration
        raise NotImplementedError("Production SMS provider not configured yet")
