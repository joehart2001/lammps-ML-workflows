#!/usr/bin/env bash
# tests/run_tests.sh — Validate script generators without running LAMMPS.
#
# Tests:
#   1. Bash syntax check on all .sh files
#   2. generate.sh dry-run: verify expected output files are created
#   3. Model injection: verify sentinel block was replaced correctly
#
# Usage: bash tests/run_tests.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"
MOCK_MODEL="${FIXTURES}/mock_model.txt"
MOCK_STRUCTURE="${FIXTURES}/minimal.data"
TMPDIR="${REPO_ROOT}/tests/tmp"

rm -rf "${TMPDIR}"
mkdir -p "${TMPDIR}"

PASS=0
FAIL=0
FAILURES=()

# ---- Helpers ------------------------------------------------------------

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); FAILURES+=("$1"); }

check() {
  local desc="$1"; shift
  if "$@" &>/dev/null; then
    pass "${desc}"
  else
    fail "${desc}"
  fi
}

assert_file() {
  local desc="$1" path="$2"
  if [[ -f "${path}" ]]; then
    pass "${desc}"
  else
    fail "${desc} (missing: ${path})"
  fi
}

assert_contains() {
  local desc="$1" path="$2" pattern="$3"
  if grep -q "${pattern}" "${path}" 2>/dev/null; then
    pass "${desc}"
  else
    fail "${desc} (pattern not found: '${pattern}' in ${path})"
  fi
}

assert_not_contains() {
  local desc="$1" path="$2" pattern="$3"
  if ! grep -q "${pattern}" "${path}" 2>/dev/null; then
    pass "${desc}"
  else
    fail "${desc} (unexpected pattern found: '${pattern}' in ${path})"
  fi
}

# ---- Test 1: Bash syntax ------------------------------------------------

echo ""
echo "=== 1. Bash syntax check ==="
while IFS= read -r -d '' script; do
  rel="${script#${REPO_ROOT}/}"
  check "syntax: ${rel}" bash -n "${script}"
done < <(find "${REPO_ROOT}" -name "*.sh" -not -path "*/\.*" -print0)

# ---- Test 2 & 3: generate.sh dry-runs -----------------------------------

# --- NVT MD ---

echo ""
echo "=== 2a. nvt-md: generate.sh dry-run ==="

NVT_GEN="${REPO_ROOT}/workflows/nvt-md/generate.sh"
NVT_OUT="${TMPDIR}/nvt_out"

bash "${NVT_GEN}" \
  --model-config "${MOCK_MODEL}" \
  --structure    "${MOCK_STRUCTURE}" \
  --temperature  300 \
  --run-ps       10 \
  --dt-fs        1.0 \
  --n-runs       2 \
  --outdir       "${NVT_OUT}" \
  > /dev/null 2>&1

NVT_DIR=$(ls -d "${NVT_OUT}"/nvt_* 2>/dev/null | head -1)

assert_file "nvt: output dir created"        "${NVT_DIR}/run_1/0_nvt.lmp"
assert_file "nvt: SLURM script created"      "${NVT_DIR}/run_1/0_slurm_nvt.slurm"
assert_file "nvt: submit.sh created"         "${NVT_DIR}/run_1/submit.sh"
assert_file "nvt: run_2 created"             "${NVT_DIR}/run_2/0_nvt.lmp"
assert_file "nvt: launch_all_runs.sh"        "${NVT_DIR}/launch_all_runs.sh"

echo ""
echo "=== 3a. nvt-md: model block injection ==="

NVT_LMP="${NVT_DIR}/run_1/0_nvt.lmp"
assert_contains     "nvt: injected pair_style present"   "${NVT_LMP}" "pair_style.*lj/cut"
assert_contains     "nvt: injected pair_coeff present"   "${NVT_LMP}" "pair_coeff.*\* \*.*0\.1"
assert_not_contains "nvt: sentinel placeholder removed"  "${NVT_LMP}" "^pair_style$"

# --- NPT MD ---

echo ""
echo "=== 2b. npt-md: generate.sh dry-run ==="

NPT_GEN="${REPO_ROOT}/workflows/npt-md/generate.sh"
NPT_OUT="${TMPDIR}/npt_out"

bash "${NPT_GEN}" \
  --model-config "${MOCK_MODEL}" \
  --structure    "${MOCK_STRUCTURE}" \
  --t-target     300 \
  --p-target     1.0 \
  --ramp-ps      5 \
  --run-ps       10 \
  --dt-fs        1.0 \
  --n-runs       2 \
  --outdir       "${NPT_OUT}" \
  > /dev/null 2>&1

NPT_DIR=$(ls -d "${NPT_OUT}"/npt_* 2>/dev/null | head -1)

assert_file "npt: output dir created"        "${NPT_DIR}/run_1/0_npt.lmp"
assert_file "npt: SLURM script created"      "${NPT_DIR}/run_1/0_slurm_npt.slurm"
assert_file "npt: submit.sh created"         "${NPT_DIR}/run_1/submit.sh"
assert_file "npt: run_2 created"             "${NPT_DIR}/run_2/0_npt.lmp"
assert_file "npt: launch_all_runs.sh"        "${NPT_DIR}/launch_all_runs.sh"

echo ""
echo "=== 3b. npt-md: model block injection ==="

NPT_LMP="${NPT_DIR}/run_1/0_npt.lmp"
assert_contains     "npt: injected pair_style present"   "${NPT_LMP}" "pair_style.*lj/cut"
assert_contains     "npt: injected pair_coeff present"   "${NPT_LMP}" "pair_coeff.*\* \*.*0\.1"
assert_not_contains "npt: sentinel placeholder removed"  "${NPT_LMP}" "^pair_style$"

# --- Melt-quench ---

echo ""
echo "=== 2c. melt-quench: generate.sh dry-run ==="

MQ_GEN="${REPO_ROOT}/workflows/melt-quench/generate.sh"
MQ_OUT="${TMPDIR}/mq_out"

bash "${MQ_GEN}" \
  --model-config "${MOCK_MODEL}" \
  --element      C \
  --mass         12.011 \
  --rho          2.0 \
  --t-melt       8000 \
  --t-final      300 \
  --melt-ps      5 \
  --equi-ps      10 \
  --quench-rate  1000 \
  --supercell    5 \
  --dt-fs        0.5 \
  --n-runs       2 \
  --outdir       "${MQ_OUT}" \
  > /dev/null 2>&1

MQ_DIR=$(ls -d "${MQ_OUT}"/mq_* 2>/dev/null | head -1)

assert_file "mq: output dir created"         "${MQ_DIR}/run_1/0_melt-quench.lmp"
assert_file "mq: SLURM script created"       "${MQ_DIR}/run_1/0_slurm_melt_quench.slurm"
assert_file "mq: submit.sh created"          "${MQ_DIR}/run_1/submit.sh"
assert_file "mq: run_2 created"              "${MQ_DIR}/run_2/0_melt-quench.lmp"
assert_file "mq: launch_all_runs.sh"         "${MQ_DIR}/launch_all_runs.sh"

echo ""
echo "=== 3c. melt-quench: model block injection ==="

MQ_LMP="${MQ_DIR}/run_1/0_melt-quench.lmp"
assert_contains     "mq: injected pair_style present"    "${MQ_LMP}" "pair_style.*lj/cut"
assert_contains     "mq: injected pair_coeff present"    "${MQ_LMP}" "pair_coeff.*\* \*.*0\.1"
assert_not_contains "mq: sentinel placeholder removed"   "${MQ_LMP}" "^pair_style$"

# ---- Summary ------------------------------------------------------------

echo ""
echo "============================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

if [[ ${FAIL} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for f in "${FAILURES[@]}"; do
    echo "  - ${f}"
  done
  echo ""
  exit 1
fi

echo ""
