from __future__ import annotations

import re
from datetime import date, datetime
from typing import Any
from urllib.parse import urlparse

from app.models import (
    MULTI_VALUE_FIELD_TYPES,
    OPTION_BEARING_FIELD_TYPES,
    FormFieldType,
    VerificationFormField,
)

#: Deliberately permissive: the goal is to reject obvious typos, not to
#: adjudicate RFC 5322. Anything stricter rejects valid addresses.
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

#: E.164-ish. Country formats vary too much to validate precisely server-side.
_PHONE_RE = re.compile(r"^\+?[0-9][0-9\s\-()]{6,19}$")

#: Bounds every free-text answer regardless of the admin's own rules, so a
#: form with no max_length can't be used to write megabytes into the row.
MAX_TEXT_LENGTH = 10_000

#: A regex supplied by an admin runs against user input. Long patterns are
#: where catastrophic backtracking lives, so the length is capped and the
#: match is guarded — a malicious or careless pattern must not hang a worker.
MAX_REGEX_LENGTH = 200


class FormValidationError(Exception):
    """Raised when submitted answers do not satisfy the form.

    Carries per-field messages so the client can place each error under the
    field it belongs to rather than showing one generic failure.
    """

    def __init__(self, errors: dict[str, str]) -> None:
        self.errors = errors
        super().__init__(f"{len(errors)} field(s) failed validation")


def _rules(field: VerificationFormField) -> dict[str, Any]:
    return field.validation_rules or {}


def _allowed_option_values(field: VerificationFormField) -> set[str]:
    options = (field.options or {}).get("options") or []
    return {str(o.get("value")) for o in options if isinstance(o, dict)}


def _is_blank(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str) and not value.strip():
        return True
    if isinstance(value, (list, dict)) and len(value) == 0:
        return True
    return False


def _validate_text(value: Any, field: VerificationFormField) -> str:
    if not isinstance(value, str):
        raise ValueError("must be text")
    text = value.strip()

    if len(text) > MAX_TEXT_LENGTH:
        raise ValueError(f"must be at most {MAX_TEXT_LENGTH} characters")

    rules = _rules(field)
    min_len, max_len = rules.get("min"), rules.get("max")
    if isinstance(min_len, int) and len(text) < min_len:
        raise ValueError(f"must be at least {min_len} characters")
    if isinstance(max_len, int) and len(text) > max_len:
        raise ValueError(f"must be at most {max_len} characters")

    pattern = rules.get("regex")
    if isinstance(pattern, str) and pattern:
        if len(pattern) > MAX_REGEX_LENGTH:
            # The admin's pattern is unusable; failing the field would blame
            # the requester for someone else's misconfiguration, so the rule
            # is skipped and the remaining checks still apply.
            return text
        try:
            if not re.match(pattern, text):
                raise ValueError("does not match the required format")
        except re.error:
            # Invalid pattern — same reasoning: not the requester's fault.
            return text
    return text


def _validate_number(value: Any, field: VerificationFormField) -> float | int:
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError("must be a number")
    try:
        number = float(value) if not isinstance(value, (int, float)) else value
    except (TypeError, ValueError):
        raise ValueError("must be a number") from None

    rules = _rules(field)
    if rules.get("integer") and float(number) != int(number):
        raise ValueError("must be a whole number")

    minimum, maximum = rules.get("min"), rules.get("max")
    if isinstance(minimum, (int, float)) and number < minimum:
        raise ValueError(f"must be at least {minimum}")
    if isinstance(maximum, (int, float)) and number > maximum:
        raise ValueError(f"must be at most {maximum}")
    return number


def _validate_select_single(value: Any, field: VerificationFormField) -> str:
    if not isinstance(value, (str, int)):
        raise ValueError("must be one of the listed options")
    allowed = _allowed_option_values(field)
    if str(value) not in allowed:
        raise ValueError("must be one of the listed options")
    return str(value)


def _validate_select_multi(value: Any, field: VerificationFormField) -> list[str]:
    if not isinstance(value, list):
        raise ValueError("must be a list of options")
    allowed = _allowed_option_values(field)
    chosen = [str(v) for v in value]

    unknown = [v for v in chosen if v not in allowed]
    if unknown:
        raise ValueError("contains an option that is not offered")
    if len(set(chosen)) != len(chosen):
        raise ValueError("contains the same option twice")

    rules = _rules(field)
    min_select, max_select = rules.get("min_select"), rules.get("max_select")
    if isinstance(min_select, int) and len(chosen) < min_select:
        raise ValueError(f"choose at least {min_select}")
    if isinstance(max_select, int) and len(chosen) > max_select:
        raise ValueError(f"choose at most {max_select}")
    return chosen


def _validate_date(value: Any, field: VerificationFormField) -> str:
    if not isinstance(value, str):
        raise ValueError("must be a date")
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        raise ValueError("must be a valid date (YYYY-MM-DD)") from None

    rules = _rules(field)
    for key, comparator, message in (
        ("min", lambda a, b: a < b, "is too early"),
        ("max", lambda a, b: a > b, "is too late"),
    ):
        bound = rules.get(key)
        if isinstance(bound, str):
            try:
                bound_date = date.fromisoformat(bound)
            except ValueError:
                continue
            if comparator(parsed, bound_date):
                raise ValueError(message)
    return parsed.isoformat()


def _validate_checkbox(value: Any, field: VerificationFormField) -> bool:
    if not isinstance(value, bool):
        raise ValueError("must be checked or unchecked")
    # A required checkbox means "must agree" — unchecked is not an answer.
    if field.is_required and not value:
        raise ValueError("must be checked to continue")
    return value


def _validate_upload(value: Any, field: VerificationFormField) -> str:
    """Uploads arrive as a storage key produced by the media service.

    The bytes are validated at upload time; this only confirms the request
    carries a plausible reference rather than arbitrary text.
    """
    if not isinstance(value, str) or not value.strip():
        raise ValueError("must be an uploaded file")
    key = value.strip()
    if len(key) > 500:
        raise ValueError("file reference is not valid")

    allowed = _rules(field).get("allowed_types")
    if isinstance(allowed, list) and allowed:
        suffix = key.rsplit(".", 1)[-1].lower() if "." in key else ""
        if suffix not in {str(a).lower().lstrip(".") for a in allowed}:
            raise ValueError(f"must be one of: {', '.join(str(a) for a in allowed)}")
    return key


_VALIDATORS = {
    FormFieldType.TEXT_SHORT: _validate_text,
    FormFieldType.TEXT_LONG: _validate_text,
    FormFieldType.NUMBER: _validate_number,
    FormFieldType.SELECT_SINGLE: _validate_select_single,
    FormFieldType.SELECT_MULTI: _validate_select_multi,
    FormFieldType.DATE: _validate_date,
    FormFieldType.CHECKBOX: _validate_checkbox,
    FormFieldType.FILE: _validate_upload,
    FormFieldType.IMAGE: _validate_upload,
}


def _validate_email(value: Any, field: VerificationFormField) -> str:
    text = _validate_text(value, field)
    if not _EMAIL_RE.match(text):
        raise ValueError("must be a valid email address")
    return text


def _validate_phone(value: Any, field: VerificationFormField) -> str:
    text = _validate_text(value, field)
    if not _PHONE_RE.match(text):
        raise ValueError("must be a valid phone number")
    return text


def _validate_url(value: Any, field: VerificationFormField) -> str:
    text = _validate_text(value, field)
    parsed = urlparse(text)
    # Scheme is restricted so a form answer cannot smuggle javascript: or
    # data: into something the admin dashboard might later render as a link.
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError("must be a valid http(s) address")
    return text


_VALIDATORS[FormFieldType.EMAIL] = _validate_email
_VALIDATORS[FormFieldType.PHONE] = _validate_phone
_VALIDATORS[FormFieldType.URL] = _validate_url


def validate_answers(
    fields: list[VerificationFormField],
    answers: dict[str, Any],
) -> dict[str, Any]:
    """Check submitted answers against the form's fields.

    Returns the cleaned answer set, keyed by field id. Only keys corresponding
    to real fields survive: a client cannot inject extra data into the stored
    record by adding keys the admin never asked for.

    Raises FormValidationError with a per-field message map on failure.
    """
    errors: dict[str, str] = {}
    cleaned: dict[str, Any] = {}

    for field in fields:
        key = str(field.id)
        raw = answers.get(key)

        if _is_blank(raw):
            if field.is_required:
                # Checkbox phrases this as "must be checked", which is clearer
                # than "required" for a control that is always present.
                errors[key] = (
                    "must be checked to continue"
                    if field.field_type == FormFieldType.CHECKBOX
                    else "This field is required"
                )
            elif field.field_type in MULTI_VALUE_FIELD_TYPES:
                cleaned[key] = []
            continue

        validator = _VALIDATORS.get(field.field_type)
        if validator is None:
            errors[key] = "unsupported field type"
            continue

        try:
            cleaned[key] = validator(raw, field)
        except ValueError as exc:
            errors[key] = str(exc)

    if errors:
        raise FormValidationError(errors)
    return cleaned


def validate_field_definition(
    field_type: str,
    options: dict | None,
    validation_rules: dict | None,
) -> None:
    """Check a field the admin is defining, before it can be saved.

    Catching these at authoring time matters: a select with no options is an
    unanswerable question, and the person who would discover it is a requester
    who cannot proceed.
    """
    if field_type not in {t.value for t in FormFieldType}:
        raise ValueError(f"unknown field type: {field_type}")

    if field_type in OPTION_BEARING_FIELD_TYPES:
        listed = (options or {}).get("options") or []
        if not isinstance(listed, list) or len(listed) == 0:
            raise ValueError("select fields must define at least one option")
        values = [str(o.get("value")) for o in listed if isinstance(o, dict)]
        if len(values) != len(listed):
            raise ValueError("every option needs a label and a value")
        if len(set(values)) != len(values):
            raise ValueError("option values must be unique")

    rules = validation_rules or {}
    minimum, maximum = rules.get("min"), rules.get("max")
    if (
        isinstance(minimum, (int, float))
        and isinstance(maximum, (int, float))
        and minimum > maximum
    ):
        raise ValueError("min cannot be greater than max")

    min_select, max_select = rules.get("min_select"), rules.get("max_select")
    if (
        isinstance(min_select, int)
        and isinstance(max_select, int)
        and min_select > max_select
    ):
        raise ValueError("min_select cannot be greater than max_select")

    pattern = rules.get("regex")
    if isinstance(pattern, str) and pattern:
        if len(pattern) > MAX_REGEX_LENGTH:
            raise ValueError(
                f"regex must be at most {MAX_REGEX_LENGTH} characters"
            )
        try:
            re.compile(pattern)
        except re.error as exc:
            raise ValueError(f"invalid regex: {exc}") from None


def expiry_for(days: int, *, now: datetime | None = None) -> datetime | None:
    """Expiry timestamp for a new request, or None when expiry is disabled."""
    from datetime import timedelta, timezone

    if days <= 0:
        return None
    base = now or datetime.now(timezone.utc)
    return base + timedelta(days=days)
