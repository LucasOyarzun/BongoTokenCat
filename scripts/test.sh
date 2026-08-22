#!/bin/bash
# Run the test suite. Exits non-zero on any failure, so it works as a pre-commit
# or CI gate.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift run --scratch-path "${SCRATCH_PATH:-/tmp/bongo-build}" BongoTests
