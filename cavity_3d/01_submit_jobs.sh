#!/bin/bash
# =============================================================================
# 01_submit_jobs.sh
# Generate one SLURM job script per case and submit them all.
#
# Cluster: 2 nodes x 2 sockets x 18 cores (Xeon Gold 6154) = 72 cores total
#   np <= 36 : runs on node1 only  (intra-node)
#   np = 72  : runs on node1+node2 (cross-node)
# =============================================================================
set -e

BASE_DIR="$PWD/cavity3D_benchmark"

# ---- Cluster configuration: EDIT THESE ----
NODE1="pca1"              # hostname of node 1
NODE2="pca2"              # hostname of node 2
PARTITION="debug"         # SLURM partition name
TIME_LIMIT_1M="00:20:00"
TIME_LIMIT_8M="01:00:00"
TIME_LIMIT_64M="04:00:00"
# -------------------------------------------

declare -A WALL_TIME
WALL_TIME["1M"]=$TIME_LIMIT_1M
WALL_TIME["8M"]=$TIME_LIMIT_8M
WALL_TIME["64M"]=$TIME_LIMIT_64M

JOB_IDS=()

echo "============================================================"
echo " Submitting cavity3D Strong Scaling jobs"
echo " Cluster  : 2 nodes x 36 cores (Xeon Gold 6154 dual-socket)"
echo " Partition: $PARTITION"
echo " Nodes    : $NODE1, $NODE2"
echo "============================================================"

for CASE_DIR in $(ls -d "$BASE_DIR"/*/ 2>/dev/null | sort -V); do
    META="$CASE_DIR/.benchmark_meta"
    [ -f "$META" ] || continue
    source "$META"

    WTIME="${WALL_TIME[$MESH]:-01:00:00}"

    # Node allocation
    # np=1..36  → 1 node, tasks_per_node=np
    # np=72     → 2 nodes, tasks_per_node=36
    if [ "$NP" -le 36 ]; then
        SLURM_NODES=1
        TASKS_PER_NODE=$NP
        NODELIST="$NODE1"
    else
        SLURM_NODES=2
        TASKS_PER_NODE=36
        NODELIST="${NODE1},${NODE2}"
    fi

    CASE_NAME=$(basename "$CASE_DIR")
    JOBSCRIPT="$CASE_DIR/run.slurm"

    # Skip if already completed
    if [ -f "$CASE_DIR/log.icoFoam" ]; then
        echo "  SKIP     : $CASE_NAME (log.icoFoam exists)"
        continue
    fi

    # ------------------------------------------------------------------
    # Generate SLURM job script
    # ------------------------------------------------------------------
    cat > "$JOBSCRIPT" << EOF
#!/bin/bash
#SBATCH --job-name=cav_${CASE_NAME}
#SBATCH --output=${CASE_DIR}/slurm_%j.out
#SBATCH --error=${CASE_DIR}/slurm_%j.err
#SBATCH --partition=${PARTITION}
#SBATCH --nodes=${SLURM_NODES}
#SBATCH --ntasks=${NP}
#SBATCH --ntasks-per-node=${TASKS_PER_NODE}
#SBATCH --nodelist=${NODELIST}
#SBATCH --time=${WTIME}
#SBATCH --exclusive           # avoid noisy-neighbour effects on timing

# ---- Environment ----------------------------------------------------
# Uncomment if OpenFOAM is not already loaded:
# spack load openfoam

cd "${CASE_DIR}"
echo "====== START: ${CASE_NAME}  np=${NP}  \$(date) ======"

# ---- 1. Build mesh --------------------------------------------------
echo "--- blockMesh ---"
blockMesh > log.blockMesh 2>&1
echo "    done: \$(grep -c 'cells' log.blockMesh || echo 0) lines mentioning cells"

# ---- 2. Mesh quality check -----------------------------------------
echo "--- checkMesh ---"
checkMesh -latestTime > log.checkMesh 2>&1
echo "    \$(grep 'cells:' log.checkMesh || echo 'cells: (see log.checkMesh)')"

# ---- 3. Domain decomposition (parallel only) -----------------------
if [ ${NP} -gt 1 ]; then
    echo "--- decomposePar ---"
    decomposePar > log.decomposePar 2>&1
    echo "    subdomains created: \$(ls -d processor* 2>/dev/null | wc -l)"
fi

# ---- 4. Solve -------------------------------------------------------
echo "--- icoFoam (np=${NP}) ---"
echo "    SLURM_JOB_NODELIST : \$SLURM_JOB_NODELIST"
echo "    SLURM_NTASKS       : \$SLURM_NTASKS"
if [ ${NP} -gt 1 ]; then
    # Use srun (SLURM-native) instead of mpirun.
    # srun reads the full node allocation directly from the SLURM environment,
    # which guarantees all ${NP} ranks are distributed correctly across nodes.
    # mpirun without explicit PMI/PMIx integration defaults to local-only
    # slot discovery and fails when np > cores-per-node (e.g. np=72 on 2 nodes).
    srun --ntasks=${NP} \\
         --ntasks-per-node=${TASKS_PER_NODE} \\
         --cpu-bind=cores \\
         icoFoam -parallel > log.icoFoam 2>&1
else
    icoFoam > log.icoFoam 2>&1
fi

# ---- 5. Quick timing summary ----------------------------------------
echo ""
echo "--- Timing summary ---"
grep "ExecutionTime" log.icoFoam | tail -3
echo "====== END: ${CASE_NAME}  \$(date) ======"
EOF

    chmod +x "$JOBSCRIPT"

    JOB_ID=$(sbatch --parsable "$JOBSCRIPT")
    JOB_IDS+=("$JOB_ID")
    echo "  Submitted: $CASE_NAME  (nodes=$SLURM_NODES, np=$NP, walltime=$WTIME) -> Job $JOB_ID"
done

echo ""
echo "============================================================"
echo " ${#JOB_IDS[@]} jobs submitted."
echo ""
echo " Monitor:   squeue -j $(IFS=,; echo "${JOB_IDS[*]}")"
echo " Watch all: watch -n 10 squeue -u \$USER"
echo ""
echo " After all jobs finish, run:"
echo "   bash 02_collect_results.sh"
echo "============================================================"

# Save job ID list for easy re-monitoring
printf "%s\n" "${JOB_IDS[@]}" > "$BASE_DIR/.submitted_job_ids"