"""AWS Batch entrypoint that orchestrates Ollama invocations."""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List

try:
    import boto3  # type: ignore
except ModuleNotFoundError:  # pragma: no cover - exercised only when boto3 missing locally
    boto3 = None  # type: ignore

try:
    from botocore.exceptions import NoRegionError  # type: ignore
except ModuleNotFoundError:  # pragma: no cover - exercised when botocore unavailable
    class NoRegionError(Exception):  # type: ignore
        """Fallback exception used when botocore isn't installed locally."""

        pass

LOGGER = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

class _MissingClient:
    """Placeholder for boto3 clients when AWS dependencies aren't configured."""

    def __init__(self, service_name: str, reason: str) -> None:
        self._service_name = service_name
        self._reason = reason

    def __getattr__(self, item: str):  # pragma: no cover - exercised only when misconfigured
        raise RuntimeError(
            "Unable to use boto3 client for '%s' (attempted attribute '%s'): %s"
            % (self._service_name, item, self._reason)
        )


def _create_boto3_client(service_name: str):
    if boto3 is None:  # pragma: no cover - exercised when boto3 unavailable
        return _MissingClient(service_name, "boto3 is not installed")

    try:
        return boto3.client(service_name)
    except NoRegionError:  # pragma: no cover - exercised when AWS region is not configured
        return _MissingClient(
            service_name,
            "AWS region is not configured. Set AWS_REGION or AWS_DEFAULT_REGION to create clients.",
        )


S3_CLIENT = _create_boto3_client("s3")
SNS_CLIENT = _create_boto3_client("sns")


def _required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _download_prefix(bucket: str, prefix: str, destination: Path) -> List[Path]:
    LOGGER.info("Downloading prefix s3://%s/%s", bucket, prefix)
    destination.mkdir(parents=True, exist_ok=True)

    downloaded: List[Path] = []
    paginator = S3_CLIENT.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            rel = key[len(prefix) :].lstrip("/")
            if not rel:
                continue
            target = destination / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            LOGGER.info("Downloading %s to %s", key, target)
            S3_CLIENT.download_file(bucket, key, str(target))
            downloaded.append(target)
    return downloaded


def _read_file(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _build_prompt(prompt_text: str, contexts: List[Path]) -> str:
    if not contexts:
        return prompt_text

    context_payload = "\n\n".join(_read_file(path) for path in contexts if path.is_file())
    if "{{context}}" in prompt_text:
        return prompt_text.replace("{{context}}", context_payload)

    return f"{prompt_text}\n\nContext:\n{context_payload}"


def _run_ollama(prompt: str, model: str) -> str:
    LOGGER.info("Invoking ollama model=%s", model)
    try:
        result = subprocess.run(
            ["ollama", "run", model],
            input=prompt,
            text=True,
            check=True,
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        LOGGER.error("Ollama invocation failed: %s", exc.stderr)
        raise

    LOGGER.info("Ollama completed successfully")
    return result.stdout


def _publish_sns(topic_arn: str, subject: str, payload: dict) -> None:
    if not topic_arn:
        LOGGER.warning("SNS topic ARN not configured; skipping notification")
        return

    message = json.dumps(payload, ensure_ascii=False, indent=2)
    LOGGER.info("Publishing SNS notification to %s", topic_arn)
    SNS_CLIENT.publish(TopicArn=topic_arn, Subject=subject[:100], Message=message)


def main() -> int:
    input_bucket = _required_env("INPUT_BUCKET")
    output_bucket = _required_env("OUTPUT_BUCKET")
    s3_prefix = _required_env("S3_PREFIX")
    sns_topic_arn = os.environ.get("SNS_TOPIC_ARN", "")

    prompt_file = os.environ.get("PROMPT_FILE") or os.environ.get("DEFAULT_PROMPT_FILE", "prompt.txt")
    output_file = os.environ.get("OUTPUT_FILE") or os.environ.get("DEFAULT_OUTPUT_FILE", "output.txt")
    model = os.environ.get("OLLAMA_MODEL", os.environ.get("DEFAULT_OLLAMA_MODEL", "llama2"))

    contexts_prefix = f"{s3_prefix.rstrip('/')}/contexts"
    prompt_key = f"{s3_prefix.rstrip('/')}/{prompt_file}"

    workdir = Path(tempfile.mkdtemp(prefix="ollama-work-"))
    LOGGER.info("Working directory: %s", workdir)

    try:
        contexts_dir = workdir / "contexts"
        downloaded_contexts = _download_prefix(input_bucket, contexts_prefix, contexts_dir)

        prompt_path = workdir / prompt_file
        prompt_path.parent.mkdir(parents=True, exist_ok=True)
        LOGGER.info("Downloading prompt file s3://%s/%s", input_bucket, prompt_key)
        S3_CLIENT.download_file(input_bucket, prompt_key, str(prompt_path))

        prompt_content = _read_file(prompt_path)
        prompt_payload = _build_prompt(prompt_content, sorted(downloaded_contexts))

        ollama_output = _run_ollama(prompt_payload, model)

        output_path = workdir / output_file
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(ollama_output, encoding="utf-8")

        output_key = f"{s3_prefix.rstrip('/')}/{output_file}"
        LOGGER.info("Uploading result to s3://%s/%s", output_bucket, output_key)
        S3_CLIENT.upload_file(str(output_path), output_bucket, output_key)

        _publish_sns(
            sns_topic_arn,
            subject="Ollama batch job completed",
            payload={
                "status": "SUCCEEDED",
                "model": model,
                "input_prefix": s3_prefix,
                "output_key": output_key,
            },
        )
    except Exception as exc:  # pragma: no cover - Batch failure path
        LOGGER.exception("Batch job failed")
        _publish_sns(
            sns_topic_arn,
            subject="Ollama batch job failed",
            payload={
                "status": "FAILED",
                "model": model,
                "input_prefix": s3_prefix,
                "error": str(exc),
            },
        )
        raise
    finally:
        LOGGER.info("Cleaning up working directory")
        shutil.rmtree(workdir, ignore_errors=True)

    return 0


if __name__ == "__main__":  # pragma: no cover - manual execution
    sys.exit(main())
