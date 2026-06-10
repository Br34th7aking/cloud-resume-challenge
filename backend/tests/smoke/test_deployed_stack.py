"""Smoke tests — run against the LIVE deployed stack.

Unit tests (../test_lambda_function.py) prove the logic with a fake DynamoDB.
These prove the *deployment*: API Gateway routing, the Lambda's real IAM
permissions, CORS config on the real API, and the real table — any of which
can be broken while every unit test stays green.

Run:    pytest -m smoke          (needs network + AWS creds for the DB read)
Skip:   plain `pytest` excludes these via pytest.ini's addopts.

Note: each full run increments the live visitor counter by ~3. Accepted —
it's a vanity counter.
"""

import json
import os

import boto3
import pytest
import requests

# Overridable so the same tests can point at a staging stack later (step 12).
API_URL = os.environ.get(
    "SMOKE_API_URL",
    "https://z8v6craitg.execute-api.ap-south-1.amazonaws.com/count",
)
BASE_URL = API_URL.rsplit("/", 1)[0]          # https://...amazonaws.com
TABLE_NAME = os.environ.get("SMOKE_TABLE", "cloud-resume-visitors")
REGION = "ap-south-1"
TIMEOUT = 10  # seconds — a hung endpoint should fail the test, not hang it


def read_count_from_dynamodb():
    """Read the stored counter straight from the real table (bypasses the API)."""
    table = boto3.resource("dynamodb", region_name=REGION).Table(TABLE_NAME)
    item = table.get_item(Key={"id": "views"})["Item"]
    return int(item["views"])


pytestmark = pytest.mark.smoke  # marks every test in this file


def test_counter_increments_and_persists_to_dynamodb():
    # Call the real API twice.
    first = requests.post(API_URL, timeout=TIMEOUT)
    second = requests.post(API_URL, timeout=TIMEOUT)
    assert first.status_code == 200
    assert second.status_code == 200

    n1 = first.json()["views"]
    n2 = second.json()["views"]

    # The API increments: two real calls, consecutive values.
    assert n2 == n1 + 1

    # And the write actually landed: the TABLE agrees with the API's answer.
    # (Bypasses the API entirely — catches "returned a number but never wrote".)
    assert read_count_from_dynamodb() == n2


def test_get_method_is_rejected():
    # We registered ONLY "POST /count" (increment mutates state; GET would let
    # prefetchers/bots inflate the count). HTTP API returns 404 for any
    # method+path combo with no matching route — and crucially, the counter
    # must NOT move.
    before = read_count_from_dynamodb()
    resp = requests.get(API_URL, timeout=TIMEOUT)
    assert resp.status_code == 404
    assert read_count_from_dynamodb() == before


def test_unknown_path_is_rejected():
    # Right method, wrong path — bots constantly probe /admin, /.env, /wp-login.
    # Same contract as the wrong method: 404 from the gateway, no side effects.
    before = read_count_from_dynamodb()
    resp = requests.post(f"{BASE_URL}/nonexistent", timeout=TIMEOUT)
    assert resp.status_code == 404
    assert read_count_from_dynamodb() == before


def test_cors_preflight_allows_the_browser_post():
    # Before counter.js's cross-origin POST, the browser silently sends an
    # OPTIONS "preflight" asking permission. API Gateway answers from its CORS
    # config (the Lambda is never invoked). If this breaks, the site still
    # loads — but the counter shows the JS fallback and consoles a CORS error.
    resp = requests.options(
        API_URL,
        headers={
            "Origin": "https://abhijitraj.me",
            "Access-Control-Request-Method": "POST",
        },
        timeout=TIMEOUT,
    )
    assert resp.status_code in (200, 204)
    assert resp.headers.get("Access-Control-Allow-Origin") == "*"
    assert "POST" in resp.headers.get("Access-Control-Allow-Methods", "")


def test_garbage_body_is_ignored_not_a_500():
    # Our handler never reads the request body — by design, there's nothing a
    # client should tell us. So malformed JSON must NOT crash it: the call
    # still succeeds and counts as one (deliberate) increment.
    before = read_count_from_dynamodb()
    resp = requests.post(
        API_URL,
        data="not json {{{",
        headers={"Content-Type": "application/json"},
        timeout=TIMEOUT,
    )
    assert resp.status_code == 200          # not a 500
    assert resp.json()["views"] == before + 1
