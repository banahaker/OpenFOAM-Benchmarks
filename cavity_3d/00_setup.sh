#!/bin/bash
# =============================================================================
# 00_setup.sh
# Strong Scaling Benchmark - cavity3D (fixedIter)
# Setup: clone HPC repo, prepare case directories, write decomposeParDict
#
# Cluster: 2 nodes x 2 sockets x 18 cores = 72 cores total
#   CPU   : Intel Xeon Gold 6154 (18c/socket, 128 GB/s BW)
#   NUMA  : 1 domain per socket → 2 NUMA/node → 4 NUMA total
#
# NUMA boundaries (expected scaling inflection points):
#   np=18 → fills socket 0          (1 NUMA domain)
#   np=36 → fills node 1 completely (2 NUMA, intra-node)
#   np=72 → both nodes              (4 NUMA, cross-node)
#
# Test matrix: mesh (1M / 8M / 64M) x cores (1 / 2 / 4 / 9 / 18 / 36 / 72)
# =============================================================================
set -e

REPO_URL="https://develop.openfoam.com/committees/hpc.git"
BASE_DIR="$PWD/cavity3D_benchmark"
VARIANT="fixedIter"

MESHES=(1M 8M 64M)
CORES=(1 2 4 9 18 36 72)   # 72 = full cluster (2 nodes x 36 cores)

# Skip combinations that are impractical
skip_case() {
    local mesh=$1 np=$2
    # 64M/1core: serial run would take too long (~hours)
    [[ "$mesh" == "64M" && "$np" -eq 1 ]] && return 0
    return 1
}

echo "============================================================"
echo " cavity3D Strong Scaling Benchmark Setup"
echo " Variant : $VARIANT"
echo " Meshes  : ${MESHES[*]}"
echo " Cores   : ${CORES[*]}"
echo " Base dir: $BASE_DIR"
echo "============================================================"

# Clone repo (shallow clone to save time/space)
if [ ! -d "hpc" ]; then
    echo ""
    echo "[1/2] Cloning HPC benchmark repo..."
    git clone --depth=1 "$REPO_URL" hpc
else
    echo "[1/2] hpc already exists, skipping clone."
fi

echo ""
echo "[2/2] Creating case directories..."
mkdir -p "$BASE_DIR"

for MESH in "${MESHES[@]}"; do
    SRC="hpc/incompressible/icoFoam/cavity3D/${MESH}/${VARIANT}"

    if [ ! -d "$SRC" ]; then
        echo "  WARNING: $SRC not found, skipping mesh=$MESH"
        continue
    fi

    for NP in "${CORES[@]}"; do
        if skip_case "$MESH" "$NP"; then
            echo "  SKIP  : mesh=$MESH np=$NP (impractical)"
            continue
        fi

        CASE_DIR="$BASE_DIR/${MESH}_np${NP}"

        if [ -d "$CASE_DIR" ]; then
            echo "  EXISTS: $CASE_DIR (remove manually to re-setup)"
            continue
        fi

        cp -r "$SRC" "$CASE_DIR"

        # ---- Write decomposeParDict (only needed for parallel runs) ----
        if [ "$NP" -gt 1 ]; then
            cat > "$CASE_DIR/system/decomposeParDict" << EOF
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    location    "system";
    object      decomposeParDict;
}
// -----------------------------------------------------------------------
// numberOfSubdomains: total MPI ranks = $NP
// method: scotch  -> automatic load balancing, minimises processor boundaries
// -----------------------------------------------------------------------
numberOfSubdomains  $NP;
method  scotch;
EOF
        fi

        # ---- Metadata for result collection script ----
        # Node layout: 36 cores/node → np<=36 fits in 1 node, np=72 needs 2
        cat > "$CASE_DIR/.benchmark_meta" << EOF
MESH=$MESH
NP=$NP
NODES=$([ "$NP" -le 36 ] && echo 1 || echo 2)
EOF

        echo "  READY : $CASE_DIR"
    done
done

echo ""
echo "============================================================"
echo " Setup complete."
echo " Next step: edit NODE1/NODE2 in 01_submit_jobs.sh,"
echo "            then run:  bash 01_submit_jobs.sh"
echo "============================================================"