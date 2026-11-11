"""Thread-safe in-memory subscriber store.

The API is stateless from the platform's point of view (no persistent volume, safe to scale
and roll), which keeps the delivery-chain exercise focused on the platform itself. Swapping in
PostgreSQL would only touch this module.
"""

from __future__ import annotations

import threading
from datetime import UTC, datetime

from .models import Subscriber, SubscriberCreate, SubscriberStatus


class DuplicateSubscriber(Exception):
    pass


class UnknownSubscriber(Exception):
    pass


class SubscriberStore:
    def __init__(self) -> None:
        self._items: dict[str, Subscriber] = {}
        self._lock = threading.Lock()

    @staticmethod
    def _now() -> datetime:
        return datetime.now(tz=UTC)

    def create(self, payload: SubscriberCreate) -> Subscriber:
        with self._lock:
            if payload.msisdn in self._items:
                raise DuplicateSubscriber(payload.msisdn)
            now = self._now()
            sub = Subscriber(
                msisdn=payload.msisdn,
                plan=payload.plan,
                status=SubscriberStatus.ACTIVE,
                created_at=now,
                updated_at=now,
            )
            self._items[payload.msisdn] = sub
            return sub

    def get(self, msisdn: str) -> Subscriber:
        with self._lock:
            try:
                return self._items[msisdn]
            except KeyError as exc:
                raise UnknownSubscriber(msisdn) from exc

    def list(self, status: SubscriberStatus | None = None) -> list[Subscriber]:
        with self._lock:
            items = list(self._items.values())
        if status is not None:
            items = [s for s in items if s.status == status]
        return sorted(items, key=lambda s: s.msisdn)

    def set_status(self, msisdn: str, status: SubscriberStatus) -> Subscriber:
        with self._lock:
            current = self._items.get(msisdn)
            if current is None:
                raise UnknownSubscriber(msisdn)
            updated = current.model_copy(update={"status": status, "updated_at": self._now()})
            self._items[msisdn] = updated
            return updated

    def delete(self, msisdn: str) -> None:
        with self._lock:
            if self._items.pop(msisdn, None) is None:
                raise UnknownSubscriber(msisdn)

    def count(self) -> int:
        with self._lock:
            return len(self._items)
