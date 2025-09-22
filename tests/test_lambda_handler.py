import importlib
import json
import os
from types import ModuleType

import pytest
from botocore.stub import Stubber


@pytest.fixture
def handler(monkeypatch) -> ModuleType:
    monkeypatch.setenv("JOB_QUEUE_ARN", "arn:aws:batch:region:123456789012:job-queue/test")
    monkeypatch.setenv("JOB_DEFINITION_ARN", "arn:aws:batch:region:123456789012:job-definition/test")
    monkeypatch.setenv("DEFAULT_VCPU", "2")
    monkeypatch.setenv("DEFAULT_MEMORY", "4096")
    monkeypatch.setenv("DEFAULT_TIMEOUT", "600")

    module = importlib.import_module("lambda.api.handler")
    # ensure globals reflect the environment configured by the fixture
    module = importlib.reload(module)
    return module


def test_submit_job_payload_defaults(handler):
    payload = handler.SubmitJobPayload.from_dict({"s3_prefix": "input/prefix"})

    assert payload.prompt_file == "prompt.txt"
    assert payload.output_file == "output.txt"
    assert payload.vcpus == 2
    assert payload.memory == 4096
    assert payload.timeout_seconds == 600
    assert payload.job_name.startswith("ollama-")


def test_lambda_handler_success(handler):
    event = {
        "body": json.dumps(
            {
                "s3_prefix": "uploads/run-1",
                "prompt_file": "prompt.txt",
                "output_file": "result.txt",
                "model": "llama2",
                "vcpus": 4,
                "memory": 8192,
                "timeout_seconds": 900,
                "job_name": "ollama-test",
            }
        )
    }

    expected_request = {
        "jobName": "ollama-test",
        "jobQueue": os.environ["JOB_QUEUE_ARN"],
        "jobDefinition": os.environ["JOB_DEFINITION_ARN"],
        "containerOverrides": {
            "environment": [
                {"name": "S3_PREFIX", "value": "uploads/run-1"},
                {"name": "PROMPT_FILE", "value": "prompt.txt"},
                {"name": "OUTPUT_FILE", "value": "result.txt"},
                {"name": "OLLAMA_MODEL", "value": "llama2"},
            ],
            "resourceRequirements": [
                {"type": "VCPU", "value": "4"},
                {"type": "MEMORY", "value": "8192"},
            ],
        },
        "timeout": {"attemptDurationSeconds": 900},
    }

    response_payload = {"jobName": "ollama-test", "jobId": "1234567890"}

    with Stubber(handler.BATCH_CLIENT) as stubber:
        stubber.add_response("submit_job", response_payload, expected_request)
        response = handler.lambda_handler(event, None)

    assert response["statusCode"] == 202
    body = json.loads(response["body"])
    assert body["jobId"] == "1234567890"
    assert body["jobName"] == "ollama-test"


@pytest.mark.parametrize("event", [{}, {"body": "not-json"}])
def test_lambda_handler_bad_request(handler, event):
    response = handler.lambda_handler(event, None)

    assert response["statusCode"] == 400
