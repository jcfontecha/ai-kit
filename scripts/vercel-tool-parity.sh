#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
tput sgr0 >/dev/null 2>&1 || true

DEFAULT_SCENARIOS=(auto-single-tool-call multi-tool-handoff tool-json-result sequential-image-tools interleaved-image-tools)

LIVE_MODE=false
if [[ ${1:-} == "--live" ]]; then
  LIVE_MODE=true
  shift
fi

SCENARIOS=("$@")
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  SCENARIOS=(${DEFAULT_SCENARIOS[@]})
fi

pushd "${REPO_ROOT}" >/dev/null

if [[ "${LIVE_MODE}" == "true" ]]; then
  echo "[tool-parity] Running live comparisons against OpenAI (${SCENARIOS[*]})"
  for scenario in "${SCENARIOS[@]}"; do
    case "${scenario}" in
      auto-single-tool-call)
        swift test --filter RealVercelToolParityTests/testAutoSingleToolCall
        ;;
      multi-tool-handoff)
        swift test --filter RealVercelToolParityTests/testMultiToolHandoff
        ;;
      tool-json-result)
        swift test --filter RealVercelToolParityTests/testToolJsonResult
        ;;
      sequential-image-tools)
        swift test --filter RealVercelToolParityTests/testSequentialImageTools
        ;;
      interleaved-image-tools)
        swift test --filter RealVercelToolParityTests/testInterleavedImageTools
        ;;
      *)
        echo "[tool-parity] Skipping unsupported live scenario '${scenario}'" >&2
        ;;
    esac
  done
else
  echo "[tool-parity] Regenerating Vercel fixtures for (${SCENARIOS[*]})"
  node tools/vercel-comparison/run-scenarios.mjs "${SCENARIOS[@]}"

  for scenario in "${SCENARIOS[@]}"; do
    case "${scenario}" in
      auto-single-tool-call)
        testName=testAutoSingleToolCallMatchesVercel
        ;;
      multi-tool-handoff)
        testName=testMultiToolHandoffMatchesVercel
        ;;
      tool-json-result)
        testName=testToolJsonResultMatchesVercel
        ;;
      tool-execution-error)
        testName=testToolExecutionErrorMatchesVercel
        ;;
      sequential-image-tools)
        testName=testSequentialImageToolsMatchesVercel
        ;;
      interleaved-image-tools)
        testName=testInterleavedImageToolsMatchesVercel
        ;;
      *)
        echo "[tool-parity] No offline test mapping for scenario '${scenario}'" >&2
        continue
        ;;
    esac
    echo "[tool-parity] Running offline parity test for ${scenario}"
    swift test --filter "VercelToolParityTests/${testName}"
  done
fi

popd >/dev/null
