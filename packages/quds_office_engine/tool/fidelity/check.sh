#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
dart test test/office_fidelity_oracle_test.dart
dart run tool/fidelity/scenarios.dart
python3 tool/fidelity/corpus.py verify
