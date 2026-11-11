#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
dart test test/office_fidelity_oracle_test.dart test/office_steps_test.dart test/numbering_collision_test.dart test/rich_note_test.dart
dart run tool/fidelity/scenarios.dart
python3 tool/fidelity/corpus.py verify
dart run tool/fidelity/cross_format.dart
python3 tool/fidelity/cross_oracle.py
dart run tool/fidelity/notes.dart
python3 tool/fidelity/notes_oracle.py
dart run tool/fidelity/office_steps.dart modify test/fixtures/fidelity/word.docx tool/fidelity/example_steps.json build/fidelity-script.docx
dart run tool/fidelity/office_steps.dart inspect build/fidelity-script.docx > build/fidelity-script.json
