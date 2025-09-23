#!/usr/bin/env bash
set -euo pipefail

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(tests)
fi

if python - <<'PY'
import importlib.util
import sys
sys.exit(0 if importlib.util.find_spec("pytest_cov") else 1)
PY
then
  exec pytest --cov=lambda --cov=job --cov-report=term-missing "${TARGETS[@]}"
else
  >&2 echo "pytest-cov not installed; running pytest without coverage"
  exec pytest "${TARGETS[@]}"
fi
