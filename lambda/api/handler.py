"""Lambda entrypoint that receives API Gateway requests and submits AWS Batch jobs."""
from __future__ import annotations

import base64
import json
import logging
import os
import time
import uuid
from dataclasses import dataclass
from typing import Any, Dict, Optional

try:
    import boto3  # type: ignore
except ModuleNotFoundError:  # pragma: no cover - exercised only when boto3 missing locally
    boto3 = None  # type: ignore

try:
    from botocore.exceptions import NoRegionError  # type: ignore
except ModuleNotFoundError:  # pragma: no cover - exercised when botocore isn't installed
    class NoRegionError(Exception):  # type: ignore
        """Fallback used when botocore isn't available locally."""

        pass

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

class _MissingBatchClient:
    """Placeholder returned when a real boto3 Batch client can't be created."""

    def __init__(self, reason: str) -> None:
        self._reason = reason

    def submit_job(self, **_: Any) -> Dict[str, Any]:  # noqa: ANN401 - boto3 payload is dynamic
        raise RuntimeError(
            "Unable to create boto3 Batch client: %s. Configure AWS credentials/region and install boto3."
            % self._reason
        )


def _create_batch_client():
    if boto3 is None:  # pragma: no cover - exercised when boto3 unavailable
        return _MissingBatchClient("boto3 is not installed")

    try:
        return boto3.client("batch")
    except NoRegionError:  # pragma: no cover - exercised when AWS region is unset locally
        return _MissingBatchClient("AWS region is not configured")


BATCH_CLIENT = _create_batch_client()

JOB_QUEUE_ARN = os.environ["JOB_QUEUE_ARN"]
JOB_DEFINITION_ARN = os.environ["JOB_DEFINITION_ARN"]
DEFAULT_VCPU = int(os.environ.get("DEFAULT_VCPU", "4"))
DEFAULT_MEMORY = int(os.environ.get("DEFAULT_MEMORY", "16384"))
DEFAULT_TIMEOUT = int(os.environ.get("DEFAULT_TIMEOUT", "3600"))


@dataclass
class SubmitJobPayload:
    """Payload expected from the API consumer."""

    s3_prefix: str
    prompt_file: str
    output_file: str
    model: Optional[str]
    vcpus: int
    memory: int
    timeout_seconds: int
    job_name: str

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "SubmitJobPayload":
        if "s3_prefix" not in payload:
            raise ValueError("'s3_prefix' is a required field")

        prompt_file = payload.get("prompt_file") or os.environ.get("DEFAULT_PROMPT_FILE", "prompt.txt")
        output_file = payload.get("output_file") or os.environ.get("DEFAULT_OUTPUT_FILE", "output.txt")

        vcpus = int(payload.get("vcpus", DEFAULT_VCPU))
        memory = int(payload.get("memory", DEFAULT_MEMORY))
        timeout_seconds = int(payload.get("timeout_seconds", DEFAULT_TIMEOUT))

        job_name = payload.get("job_name") or f"ollama-{int(time.time())}-{uuid.uuid4().hex[:8]}"

        model = payload.get("model")

        return cls(
            s3_prefix=payload["s3_prefix"],
            prompt_file=prompt_file,
            output_file=output_file,
            model=model,
            vcpus=vcpus,
            memory=memory,
            timeout_seconds=timeout_seconds,
            job_name=job_name,
        )


class BadRequestError(Exception):
    """Error raised for invalid payloads."""


def _parse_event_body(event: Dict[str, Any]) -> Dict[str, Any]:
    if "body" not in event:
        raise BadRequestError("Request body is missing")

    body = event["body"]
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body)

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive branch
        raise BadRequestError("Invalid JSON payload") from exc


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:  # pragma: no cover - AWS entrypoint
    LOGGER.info("Received event: %s", json.dumps(event))

    try:
        payload_dict = _parse_event_body(event)
        submit_payload = SubmitJobPayload.from_dict(payload_dict)
    except (BadRequestError, ValueError) as exc:
        LOGGER.exception("Failed to parse request body")
        return {
            "statusCode": 400,
            "body": json.dumps({"message": str(exc)}),
        }

    container_overrides = {
        "environment": [
            {"name": "S3_PREFIX", "value": submit_payload.s3_prefix},
            {"name": "PROMPT_FILE", "value": submit_payload.prompt_file},
            {"name": "OUTPUT_FILE", "value": submit_payload.output_file},
        ],
        "resourceRequirements": [
            {"type": "VCPU", "value": str(submit_payload.vcpus)},
            {"type": "MEMORY", "value": str(submit_payload.memory)},
        ],
    }

    if submit_payload.model:
        container_overrides["environment"].append({"name": "OLLAMA_MODEL", "value": submit_payload.model})

    request: Dict[str, Any] = {
        "jobName": submit_payload.job_name,
        "jobQueue": JOB_QUEUE_ARN,
        "jobDefinition": JOB_DEFINITION_ARN,
        "containerOverrides": container_overrides,
    }

    if submit_payload.timeout_seconds:
        request["timeout"] = {"attemptDurationSeconds": submit_payload.timeout_seconds}

    LOGGER.info("Submitting job: %s", json.dumps(request))
    response = BATCH_CLIENT.submit_job(**request)

    LOGGER.info("SubmitJob response: %s", json.dumps(response, default=str))

    return {
        "statusCode": 202,
        "body": json.dumps({
            "message": "Job submitted",
            "jobId": response.get("jobId"),
            "jobName": response.get("jobName"),
        }),
    }
