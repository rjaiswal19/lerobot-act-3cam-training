#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/python_deps.sh"

CONFIG_PATH="${CHEMIST_CONFIG:-$ROOT_DIR/configs/demos/chemist_mix.env}"

"$(project_python)" "$ROOT_DIR/scripts/chemist_llm_planner.py" --config "$CONFIG_PATH" "$@"
