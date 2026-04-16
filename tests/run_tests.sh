#!/usr/bin/env bash
# tests/run_tests.sh — Validate script generators and optionally run short LAMMPS smoke tests.
#
# Tests:
#   1. Bash syntax check on all .sh files
#   2. generate.sh dry-run: verify expected output files are created
#   3. Model injection: verify sentinel block was replaced correctly
#   4. Optional: run short local LAMMPS jobs from compatibility copies of the
#      generated inputs, using a user-supplied executable
#
# Usage:
#   bash tests/run_tests.sh
#   bash tests/run_tests.sh --run-lammps --lmp-exe /path/to/lmp
#
# Environment:
#   RUN_LAMMPS_TESTS=1
#   LMP_EXE=/path/to/lmp
set -euo pipefail

usage() {
  cat <<'EOU'
Usage:
  bash tests/run_tests.sh [--run-lammps] [--lmp-exe <path>]

Options:
  --run-lammps        Run short local LAMMPS smoke tests after generation.
  --lmp-exe <path>    LAMMPS executable to use for smoke tests.
  -h, --help          Show this help text.

Environment:
  RUN_LAMMPS_TESTS=1  Same as --run-lammps
  LMP_EXE=<path>      Same as --lmp-exe
EOU
}

RUN_LAMMPS="${RUN_LAMMPS_TESTS:-0}"
LMP_EXE="${LMP_EXE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-lammps) RUN_LAMMPS="1"; shift ;;
    --lmp-exe)    LMP_EXE="$2"; RUN_LAMMPS="1"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"
MOCK_MODEL="${FIXTURES}/mock_model.txt"
MOCK_STRUCTURE="${FIXTURES}/minimal.data"
RUNTIME_STRUCTURE="${FIXTURES}/minimal_4atom.data"
TMPDIR="${REPO_ROOT}/tests/tmp"

resolve_executable() {
  local exe="$1"
  if [[ "${exe}" == */* ]]; then
    printf '%s\n' "${exe}"
  else
    command -v "${exe}"
  fi
}

if [[ "${RUN_LAMMPS}" == "1" ]]; then
  if [[ -z "${LMP_EXE}" ]]; then
    LMP_EXE="$(resolve_executable lmp 2>/dev/null || true)"
  else
    LMP_EXE="$(resolve_executable "${LMP_EXE}" 2>/dev/null || true)"
  fi

  [[ -n "${LMP_EXE}" ]] || {
    echo "ERROR: --run-lammps requires --lmp-exe or an 'lmp' executable on PATH" >&2
    exit 1
  }
  [[ -x "${LMP_EXE}" ]] || {
    echo "ERROR: LAMMPS executable is not runnable: ${LMP_EXE}" >&2
    exit 1
  }
fi

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

run_logged() {
  local desc="$1" workdir="$2" logfile="$3"; shift 3
  if (
    cd "${workdir}"
    "$@"
  ) >"${logfile}" 2>&1; then
    pass "${desc}"
    return 0
  else
    fail "${desc} (see ${logfile})"
    return 1
  fi
}

make_runtime_compatible_copy() {
  local src="$1" dst="$2"

  awk '
    /^dump [^ ]+ all dcd / {
      sub(/ dcd /, " custom ")
      sub(/\.dcd/, ".lammpstrj")
      print $0 " id type x y z"
      next
    }

    /^fix[[:space:]]+fNVT[[:space:]]+all[[:space:]]+temp\/csvr[[:space:]]+/ {
      print $1, $2, $3, "nvt", "temp", $5, $6, $7
      next
    }

    /^fix[[:space:]]+fNVE[[:space:]]+all[[:space:]]+nve$/ { next }
    /^unfix[[:space:]]+fNVE$/ { next }

    /^fix[[:space:]]+VLOG_(ramp|hold)[[:space:]]+all[[:space:]]+ave\/time[[:space:]]+/ {
      sub(/v_time_ps[[:space:]]+vol[[:space:]]+file/, "v_time_ps v_boxvol file")
      print
      next
    }

    { print }
  ' "${src}" > "${dst}"
}

run_nvt_runtime_test() {
  local outdir="${TMPDIR}/nvt_runtime"
  local run_dir compat_lmp log_file nvt_out

  bash "${REPO_ROOT}/workflows/nvt-md/generate.sh" \
    --model-config "${MOCK_MODEL}" \
    --structure    "${RUNTIME_STRUCTURE}" \
    --temperature  300 \
    --run-ps       0.02 \
    --dt-fs        1.0 \
    --n-runs       1 \
    --outdir       "${outdir}" \
    > /dev/null 2>&1

  run_dir="$(ls -d "${outdir}"/nvt_* 2>/dev/null | head -1)/run_1"
  compat_lmp="${run_dir}/0_nvt.runtime_test.lmp"
  log_file="${run_dir}/lammps_runtime.log"
  nvt_out="${run_dir}/nvt_outputs"

  make_runtime_compatible_copy "${run_dir}/0_nvt.lmp" "${compat_lmp}"

  if ! run_logged \
    "nvt: local LAMMPS run completed" \
    "${run_dir}" \
    "${log_file}" \
    "${LMP_EXE}" \
    -in "$(basename "${compat_lmp}")" \
    -var STRUCTURE_FILE "${RUNTIME_STRUCTURE}" \
    -var T_START 300 \
    -var T_TARGET 300 \
    -var DT_FS 1.0 \
    -var RUN_PS 0.02 \
    -var TDUMP_EVERY 5 \
    -var THERMO_EVERY 5 \
    -var SEED 12345; then
    return
  fi

  assert_file "nvt: runtime final.data written"      "${nvt_out}/final.data"
  assert_file "nvt: runtime restart written"         "${nvt_out}/final.restart"
  assert_file "nvt: runtime trajectory written"      "${nvt_out}/traj.lammpstrj"
  assert_file "nvt: runtime completion marker"       "${nvt_out}/_done.txt"
  assert_contains "nvt: runtime completion text"     "${nvt_out}/_done.txt" "DONE nvt"
}

run_npt_runtime_test() {
  local outdir="${TMPDIR}/npt_runtime"
  local run_dir compat_lmp log_file npt_out

  bash "${REPO_ROOT}/workflows/npt-md/generate.sh" \
    --model-config "${MOCK_MODEL}" \
    --structure    "${RUNTIME_STRUCTURE}" \
    --t-target     300 \
    --p-target     1.0 \
    --ramp-ps      0.01 \
    --run-ps       0.02 \
    --dt-fs        1.0 \
    --n-runs       1 \
    --outdir       "${outdir}" \
    > /dev/null 2>&1

  run_dir="$(ls -d "${outdir}"/npt_* 2>/dev/null | head -1)/run_1"
  compat_lmp="${run_dir}/0_npt.runtime_test.lmp"
  log_file="${run_dir}/lammps_runtime.log"
  npt_out="${run_dir}/npt_outputs"

  make_runtime_compatible_copy "${run_dir}/0_npt.lmp" "${compat_lmp}"

  if ! run_logged \
    "npt: local LAMMPS run completed" \
    "${run_dir}" \
    "${log_file}" \
    "${LMP_EXE}" \
    -in "$(basename "${compat_lmp}")" \
    -var STRUCTURE_FILE "${RUNTIME_STRUCTURE}" \
    -var T_START 300 \
    -var T_TARGET 300 \
    -var P_TARGET 1.0 \
    -var DT_FS 1.0 \
    -var RAMP_PS 0.01 \
    -var RUN_PS 0.02 \
    -var MINIMISE 1 \
    -var TDUMP_EVERY 5 \
    -var THERMO_EVERY 5 \
    -var SEED 12345; then
    return
  fi

  assert_file "npt: runtime final.data written"      "${npt_out}/final.data"
  assert_file "npt: runtime restart written"         "${npt_out}/final.restart"
  assert_file "npt: runtime hold trajectory written" "${npt_out}/hold_traj.lammpstrj"
  assert_file "npt: runtime ramp trajectory written" "${npt_out}/ramp_traj.lammpstrj"
  assert_file "npt: runtime completion marker"       "${npt_out}/_done.txt"
  assert_contains "npt: runtime completion text"     "${npt_out}/_done.txt" "DONE npt"
}

run_mq_runtime_test() {
  local outdir="${TMPDIR}/mq_runtime"
  local run_dir compat_lmp log_file mq_out

  bash "${REPO_ROOT}/workflows/melt-quench/generate.sh" \
    --model-config "${MOCK_MODEL}" \
    --element      Ar \
    --mass         39.948 \
    --rho          1.0 \
    --t-melt       600 \
    --t-final      300 \
    --melt-ps      0.005 \
    --equi-ps      0.005 \
    --quench-rate  1000 \
    --supercell    2 \
    --dt-fs        1.0 \
    --n-runs       1 \
    --outdir       "${outdir}" \
    > /dev/null 2>&1

  run_dir="$(ls -d "${outdir}"/mq_* 2>/dev/null | head -1)/run_1"
  compat_lmp="${run_dir}/0_melt-quench.runtime_test.lmp"
  log_file="${run_dir}/lammps_runtime.log"

  make_runtime_compatible_copy "${run_dir}/0_melt-quench.lmp" "${compat_lmp}"

  if ! run_logged \
    "mq: local LAMMPS run completed" \
    "${run_dir}" \
    "${log_file}" \
    "${LMP_EXE}" \
    -in "$(basename "${compat_lmp}")" \
    -var ELEMENT Ar \
    -var MASS 39.948 \
    -var RHO 1.0 \
    -var N_SUPERCELLS 2 \
    -var T_MELT 600 \
    -var T_FINAL 300 \
    -var MELT_PS 0.005 \
    -var QUENCH_RATE 1000 \
    -var EQUI_PS 0.005 \
    -var DT_FS 1.0 \
    -var SEED 12345; then
    return
  fi

  mq_out="$(find "${run_dir}" -maxdepth 1 -type d -name 'melt_quench_*' | head -1)"

  assert_file "mq: runtime final.data written"       "${mq_out}/final.data"
  assert_file "mq: runtime restart written"          "${mq_out}/final.restart"
  assert_file "mq: runtime melt trajectory written"  "${mq_out}/melt_traj.lammpstrj"
  assert_file "mq: runtime quench trajectory written" "${mq_out}/quench_traj.lammpstrj"
  assert_file "mq: runtime equi trajectory written"  "${mq_out}/equi_traj.lammpstrj"
  assert_file "mq: runtime completion marker"        "${mq_out}/_done.txt"
  assert_contains "mq: runtime completion text"      "${mq_out}/_done.txt" "DONE melt-quench"
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
assert_file "nvt: structure staged"          "${NVT_DIR}/minimal.data"
assert_file "nvt: SLURM script created"      "${NVT_DIR}/run_1/0_slurm_nvt.slurm"
assert_file "nvt: submit.sh created"         "${NVT_DIR}/run_1/submit.sh"
assert_file "nvt: run_2 created"             "${NVT_DIR}/run_2/0_nvt.lmp"
assert_file "nvt: launch_all_runs.sh"        "${NVT_DIR}/launch_all_runs.sh"
assert_contains "nvt: staged structure path used" "${NVT_DIR}/run_1/0_slurm_nvt.slurm" '\.\./minimal\.data'

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
assert_file "npt: structure staged"          "${NPT_DIR}/minimal.data"
assert_file "npt: SLURM script created"      "${NPT_DIR}/run_1/0_slurm_npt.slurm"
assert_file "npt: submit.sh created"         "${NPT_DIR}/run_1/submit.sh"
assert_file "npt: run_2 created"             "${NPT_DIR}/run_2/0_npt.lmp"
assert_file "npt: launch_all_runs.sh"        "${NPT_DIR}/launch_all_runs.sh"
assert_contains "npt: staged structure path used" "${NPT_DIR}/run_1/0_slurm_npt.slurm" '\.\./minimal\.data'

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

if [[ "${RUN_LAMMPS}" == "1" ]]; then
  echo ""
  echo "=== 4a. nvt-md: local LAMMPS smoke test ==="
  echo "  Using LMP_EXE=${LMP_EXE}"
  run_nvt_runtime_test

  echo ""
  echo "=== 4b. npt-md: local LAMMPS smoke test ==="
  run_npt_runtime_test

  echo ""
  echo "=== 4c. melt-quench: local LAMMPS smoke test ==="
  run_mq_runtime_test
fi

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
