"""Small Robot Framework library for TLS checks (standard library only)."""

from __future__ import annotations

import socket
import ssl
from datetime import UTC, datetime


def days_until_certificate_expiry(host: str, port: int = 443, timeout: float = 10.0) -> int:
    """Return the number of days before the certificate served by host:port expires."""
    context = ssl.create_default_context()
    with socket.create_connection((host, int(port)), timeout=timeout) as sock, context.wrap_socket(
        sock, server_hostname=host
    ) as tls:
        cert = tls.getpeercert()
    not_after = datetime.strptime(cert["notAfter"], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=UTC)
    return (not_after - datetime.now(tz=UTC)).days


def certificate_subject_matches(host: str, port: int = 443) -> bool:
    """True when the certificate is valid for host (hostname verification done by ssl)."""
    try:
        days_until_certificate_expiry(host, port)
    except ssl.SSLCertVerificationError:
        return False
    return True
