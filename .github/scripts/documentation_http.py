#!/usr/bin/env python3
"""Provide the restricted HTTP transport used for documentation verification."""

from __future__ import annotations

import http.client
import urllib.parse


LOCAL_HTTP_HOSTS = {"127.0.0.1", "localhost"}


class HttpTransportError(ValueError):
    """Raised when a URL falls outside the documentation transport policy."""


def _validate_transport_scheme(parsed: urllib.parse.SplitResult) -> None:
    if parsed.scheme == "http":
        if parsed.hostname not in LOCAL_HTTP_HOSTS:
            raise HttpTransportError(
                "URL must use HTTPS, except HTTP is allowed for localhost tests."
            )
        return
    if parsed.scheme != "https":
        raise HttpTransportError(
            "URL must use HTTPS, except HTTP is allowed for localhost tests."
        )


def parse_http_url(url: str) -> urllib.parse.SplitResult:
    """Parse a URL after enforcing the supported HTTP transport policy."""
    try:
        parsed = urllib.parse.urlsplit(url)
        hostname = parsed.hostname
        parsed.port
    except ValueError as error:
        raise HttpTransportError(f"Invalid HTTP URL: {url!r}.") from error

    _validate_transport_scheme(parsed)
    if not hostname:
        raise HttpTransportError("HTTP URL must include a hostname.")
    if parsed.username is not None or parsed.password is not None:
        raise HttpTransportError("HTTP URL must not include user information.")
    if parsed.fragment:
        raise HttpTransportError("HTTP URL must not include a fragment.")
    return parsed


def _request_target(parsed: urllib.parse.SplitResult) -> str:
    return urllib.parse.urlunsplit(("", "", parsed.path or "/", parsed.query, ""))


def read_http_response(
    request_url: str,
    maximum_body_bytes: int,
    timeout: float,
) -> tuple[int, bytes]:
    """Issue one non-redirecting GET and return a size-bounded response body."""
    parsed = parse_http_url(request_url)
    connection_type = (
        http.client.HTTPSConnection
        if parsed.scheme == "https"
        else http.client.HTTPConnection
    )
    connection = connection_type(parsed.hostname, parsed.port, timeout=timeout)
    try:
        connection.request(
            "GET",
            _request_target(parsed),
            headers={
                "Accept-Encoding": "identity",
                "Cache-Control": "no-cache",
                "User-Agent": "TheCleaners-documentation-verifier/1",
            },
        )
        response = connection.getresponse()
        try:
            return response.status, response.read(maximum_body_bytes + 1)
        finally:
            response.close()
    finally:
        connection.close()
