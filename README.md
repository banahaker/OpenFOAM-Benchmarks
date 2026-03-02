# OpenFOAM HPC Benchmark Suite

Scripts and documentation for running HPC benchmarks on OpenFOAM solvers.

---

## Benchmarks

- **`cavity_3d/`** — Strong scaling benchmark using `icoFoam` on 3D lid-driven cavity flow (1M/8M/64M cells, up to 72 cores).

---

## Prerequisites

- OpenFOAM (v2006 or newer)
- MPI (OpenMPI recommended)
- SLURM workload manager
- Bash 4.0+

---

## References

- [OpenFOAM HPC Technical Committee](https://develop.openfoam.com/committees/hpc)
- [OpenFOAM User Guide - Parallel Running](https://www.openfoam.com/documentation/user-guide/3-running-applications/3.2-running-applications-in-parallel)
