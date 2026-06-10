"""Unit tests for the visitor-counter Lambda.

Strategy: moto fakes DynamoDB in-process, so boto3 calls never leave the
machine — no credentials, no cost, safe to run in CI.

Import-order gotcha: lambda_function.py creates its boto3 resource at module
import time, so the moto mock must already be active when the module is first
imported. The `lambda_module` fixture handles that ordering (and reloads the
module so each test gets a fresh table binding).
"""

import importlib
import json
import os
import sys

import boto3
import pytest
from moto import mock_aws

TABLE_NAME = "cloud-resume-visitors"

# Make `import lambda_function` work when pytest runs from anywhere.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


@pytest.fixture()
def lambda_module(monkeypatch):
    # Fake credentials + region: boto3 requires them to build a client, and
    # setting them guarantees we can't accidentally talk to the real account.
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "ap-south-1")

    with mock_aws():
        dynamodb = boto3.resource("dynamodb")
        dynamodb.create_table(
            TableName=TABLE_NAME,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )

        import lambda_function
        # Reload so module-level boto3.resource() binds to THIS mock, not a
        # leftover from a previous test's mock context.
        importlib.reload(lambda_function)

        yield lambda_function


def seed(views):
    """Put the counter item directly into the (fake) table."""
    boto3.resource("dynamodb").Table(TABLE_NAME).put_item(
        Item={"id": "views", "views": views}
    )


def test_returns_200_with_cors_and_json_headers(lambda_module):
    seed(0)
    resp = lambda_module.lambda_handler({}, None)
    assert resp["statusCode"] == 200
    assert resp["headers"]["Access-Control-Allow-Origin"] == "*"
    assert resp["headers"]["Content-Type"] == "application/json"


def test_increments_seeded_count(lambda_module):
    seed(41)
    resp = lambda_module.lambda_handler({}, None)
    assert json.loads(resp["body"]) == {"views": 42}


def test_consecutive_calls_keep_incrementing(lambda_module):
    seed(0)
    counts = [
        json.loads(lambda_module.lambda_handler({}, None)["body"])["views"]
        for _ in range(3)
    ]
    assert counts == [1, 2, 3]


def test_works_when_item_does_not_exist_yet(lambda_module):
    # No seed: ADD on a missing item/attribute treats it as 0, so the very
    # first visit creates the item and returns 1 instead of crashing.
    resp = lambda_module.lambda_handler({}, None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == {"views": 1}


def test_body_views_is_an_int_not_decimal(lambda_module):
    # DynamoDB returns numbers as decimal.Decimal. json.dumps(Decimal) raises
    # TypeError, so the handler must convert with int(...) — this test fails
    # if that conversion is ever removed.
    seed(7)
    body = json.loads(lambda_module.lambda_handler({}, None)["body"])
    assert isinstance(body["views"], int)
    assert body["views"] == 8
