#!/usr/bin/env bash
# generate.sh — Generate LAMMPS input and SLURM scripts for melt-quench.
#
# Usage:
#   bash generate.sh --model-config <path> \
#     --element <EL> --mass <g/mol> --rho <g/cc> \
#     --t-melt <K> --t-final <K> \
#     --melt-ps <ps> --equi-ps <ps> [--quench-rate <K/ps>] \
#     --supercell <n> --dt-fs <fs> --seed <n> [--n-runs <n>]
set -euo pipefail

# =====================================================================
# ---- SLURM SETTINGS — edit these for your cluster -------------------
# =====================================================================
SLURM_ACCOUNT=""
SLURM_PARTITION=""
LMP_EXE="${LMP_EXE:-lmp}"
VENV_ACTIVATE="${VENV_ACTIVATE:-source /path/to/venv_mace/bin/activate}"
MODULES_LOAD="${MODULES_LOAD:-}"
TIME_MQ="${TIME_MQ:-12:00:00}"
# =====================================================================

MODEL_CONFIG=""
ELEMENT=""
MASS=""
RHO=""
T_MELT=""
T_FINAL="300"
MELT_PS="5"
QUENCH_RATE="1000"
EQUI_PS="10"
SUPERCELL="10"
DT_FS="0.5"
BASE_SEED="12345"
N_RUNS="1"
OUTDIR=""

usage() {
  cat <<EOU
Usage:
  $0 --model-config <path> --element <EL> --mass <g/mol> --rho <g/cc> \
     --t-melt <K> [--t-final <K>] [--melt-ps <ps>] [--equi-ps <ps>] \
     [--quench-rate <K/ps>] [--supercell <n>] [--dt-fs <fs>] \
     [--seed <n>] [--n-runs <n>] [--outdir <path>]

Required:
  --model-config   Model config file
  --element        Element symbol (e.g. C, Fe, Si)
  --mass           Atomic mass (g/mol, e.g. 12.011 for C)
  --rho            Target density (g/cc)
  --t-melt         Melt temperature (K)

Options:
  --t-final <K>      Final temperature after quench (default: 300)
  --melt-ps <ps>     Melt hold duration (default: 5)
  --quench-rate <K/ps> Quench rate (default: 1000)
  --equi-ps <ps>     Equilibration hold at T_FINAL (default: 10)
  --supercell <n>    NxNxN supercell repeat (default: 10)
  --dt-fs <fs>       Timestep (default: 0.5)
  --seed <n>         Base RNG seed (default: 12345)
  --n-runs <n>       Number of replicates (default: 1)
  --outdir <path>    Parent output directory (default: current dir)
EOU
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-config)  MODEL_CONFIG="$2"; shift 2 ;;
    --element)       ELEMENT="$2"; shift 2 ;;
    --mass)          MASS="$2"; shift 2 ;;
    --rho)           RHO="$2"; shift 2 ;;
    --t-melt)        T_MELT="$2"; shift 2 ;;
    --t-final)       T_FINAL="$2"; shift 2 ;;
    --melt-ps)       MELT_PS="$2"; shift 2 ;;
    --quench-rate)   QUENCH_RATE="$2"; shift 2 ;;
    --equi-ps)       EQUI_PS="$2"; shift 2 ;;
    --supercell)     SUPERCELL="$2"; shift 2 ;;
    --dt-fs)         DT_FS="$2"; shift 2 ;;
    --seed)          BASE_SEED="$2"; shift 2 ;;
    --n-runs)        N_RUNS="$2"; shift 2 ;;
    --outdir)        OUTDIR="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "${MODEL_CONFIG}" ]] || { echo "ERROR: --model-config required" >&2; usage; exit 1; }
[[ -n "${ELEMENT}" ]]      || { echo "ERROR: --element required" >&2; usage; exit 1; }
[[ -n "${MASS}" ]]         || { echo "ERROR: --mass required" >&2; usage; exit 1; }
[[ -n "${RHO}" ]]          || { echo "ERROR: --rho required" >&2; usage; exit 1; }
[[ -n "${T_MELT}" ]]       || { echo "ERROR: --t-melt required" >&2; usage; exit 1; }
[[ -f "${MODEL_CONFIG}" ]] || { echo "ERROR: model config not found: ${MODEL_CONFIG}" >&2; exit 1; }
[[ "${N_RUNS}" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --n-runs must be a positive integer" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LMP_TPL="${SCRIPT_DIR}/melt-quench_template.lmp"
[[ -f "${LMP_TPL}" ]] || { echo "ERROR: template not found: ${LMP_TPL}" >&2; exit 1; }

MODEL_BLOCK="$(cat "${MODEL_CONFIG}")"
DIR_NAME="mq_${ELEMENT}_${SUPERCELL}x${SUPERCELL}_rho${RHO}_Tmelt${T_MELT}_Tfinal${T_FINAL}"
BASE_OUTDIR="${OUTDIR:-.}"
OUTDIR_FULL="${BASE_OUTDIR}/${DIR_NAME}"
mkdir -p "${OUTDIR_FULL}"

LMP_OUT="0_melt-quench.lmp"
SLURM_OUT="0_slurm_melt_quench.slurm"

inject_model_block() {
  local src="$1" dst="$2"
  awk -v model_block="${MODEL_BLOCK}" '
    BEGIN { n = split(model_block, lines, "\n"); in_block = 0 }
    /^#==== define model ====#$/ { print; for(i=1;i<=n;i++) print lines[i]; in_block=1; next }
    in_block && /^#======================#[[:space:]]*$/ { print; in_block=0; next }
    in_block { next }
    { print }
  ' "${src}" > "${dst}"
}

SBATCH_ACCOUNT_FLAG=""
[[ -n "${SLURM_ACCOUNT}" ]] && SBATCH_ACCOUNT_FLAG="#SBATCH --account=${SLURM_ACCOUNT}"
SBATCH_PARTITION_FLAG=""
[[ -n "${SLURM_PARTITION}" ]] && SBATCH_PARTITION_FLAG="#SBATCH --partition=${SLURM_PARTITION}"

echo ""
echo "============================================"
echo "  melt-quench workflow"
echo "============================================"
echo "  Model config: ${MODEL_CONFIG}"
echo "  Element:      ${ELEMENT} (mass ${MASS} g/mol)"
echo "  Rho:          ${RHO} g/cc | Supercell: ${SUPERCELL}x${SUPERCELL}x${SUPERCELL}"
echo "  T_melt:       ${T_MELT} K → T_final: ${T_FINAL} K (${QUENCH_RATE} K/ps)"
echo "  Melt:         ${MELT_PS} ps | Equi: ${EQUI_PS} ps | dt: ${DT_FS} fs"
echo "  N runs:       ${N_RUNS} (base seed: ${BASE_SEED})"
echo "  Output:       ${OUTDIR_FULL}"
echo "============================================"
echo ""

for ((run_idx=1; run_idx<=N_RUNS; run_idx++)); do
  RUN_DIR="${OUTDIR_FULL}/run_${run_idx}"
  RUN_SEED=$((BASE_SEED + run_idx - 1))
  mkdir -p "${RUN_DIR}"

  inject_model_block "${LMP_TPL}" "${RUN_DIR}/${LMP_OUT}"

  cat > "${RUN_DIR}/${SLURM_OUT}" <<SLURM
#!/bin/bash
#SBATCH --job-name=mq_${ELEMENT}_rho${RHO}_r${run_idx}
#SBATCH --gpus=1
#SBATCH --time=${TIME_MQ}
${SBATCH_ACCOUNT_FLAG}
${SBATCH_PARTITION_FLAG}

${MODULES_LOAD}
${VENV_ACTIVATE}

cd "\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

srun ${LMP_EXE} \\
  -k on g 1 -sf kk -pk kokkos newton on neigh half \\
  -in "${LMP_OUT}" \\
  -var ELEMENT "${ELEMENT}" \\
  -var MASS "${MASS}" \\
  -var RHO "${RHO}" \\
  -var N_SUPERCELLS "${SUPERCELL}" \\
  -var T_MELT "${T_MELT}" \\
  -var T_FINAL "${T_FINAL}" \\
  -var MELT_PS "${MELT_PS}" \\
  -var QUENCH_RATE "${QUENCH_RATE}" \\
  -var EQUI_PS "${EQUI_PS}" \\
  -var DT_FS "${DT_FS}" \\
  -var SEED "${RUN_SEED}"
SLURM
  chmod +x "${RUN_DIR}/${SLURM_OUT}"

  cat > "${RUN_DIR}/submit.sh" <<SUBMIT
#!/usr/bin/env bash
set -euo pipefail
cd "\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
JOBID=\$(sbatch "${SLURM_OUT}" | awk '{print \$4}')
echo "run_${run_idx}: submitted \${JOBID}"
echo "\${JOBID}" > job_id.txt
SUBMIT
  chmod +x "${RUN_DIR}/submit.sh"

  echo "  Created run_${run_idx}/ (seed=${RUN_SEED})"
done

cat > "${OUTDIR_FULL}/launch_all_runs.sh" <<LAUNCH
#!/usr/bin/env bash
set -euo pipefail
cd "\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
echo "Launching all runs in: \$(pwd)"
for run_dir in run_*/; do
  [[ -d "\${run_dir}" ]] || continue
  [[ -x "\${run_dir}/submit.sh" ]] && (cd "\${run_dir}" && ./submit.sh) || echo "Skipping \${run_dir}"
done
echo "Done."
LAUNCH
chmod +x "${OUTDIR_FULL}/launch_all_runs.sh"

echo ""
echo "Done. To submit: cd ${OUTDIR_FULL} && ./launch_all_runs.sh"
