"""Pydantic models for the subscriber API."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field

# E.164: leading "+", first digit 1-9, 8 to 15 digits in total.
MSISDN_PATTERN = r"^\+[1-9]\d{7,14}$"
# Commercial plan codes are upper-case identifiers, e.g. PREPAID_5GB or POSTPAID_UNLIMITED.
PLAN_PATTERN = r"^[A-Z][A-Z0-9_]{2,31}$"


class SubscriberStatus(StrEnum):
    ACTIVE = "ACTIVE"
    SUSPENDED = "SUSPENDED"


class SubscriberCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    msisdn: str = Field(pattern=MSISDN_PATTERN, examples=["+21650123456"])
    plan: str = Field(pattern=PLAN_PATTERN, examples=["PREPAID_5GB"])


class Subscriber(BaseModel):
    msisdn: str
    plan: str
    status: SubscriberStatus
    created_at: datetime
    updated_at: datetime


class SubscriberList(BaseModel):
    items: list[Subscriber]
    total: int


class Info(BaseModel):
    service: str
    version: str
    environment: str
    hostname: str
    started_at: datetime


class Problem(BaseModel):
    """Error body, loosely modelled on RFC 9457."""

    title: str
    status: int
    detail: str | None = None
