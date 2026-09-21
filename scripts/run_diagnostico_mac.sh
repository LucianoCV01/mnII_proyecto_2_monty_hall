#!/bin/bash
# ============================================================
# run_diagnostico_mac.sh
#
# Corre todos los programas de diagnostico de la Bitacora
# (Plan_de_Desarrollo_Monty_Hall.md, Seccion 5.1) en Mac, y
# guarda la salida COMPLETA de cada uno como evidencia real en
# diagnostico/resultados/ -- reemplazando los datos que hasta
# ahora estaban escritos a mano en los documentos.
#
# Uso (desde cualquier carpeta del repo):
#   bash scripts/run_diagnostico_mac.sh
# ============================================================

# Ubicarse en la raiz del repo sin importar desde donde se invoque
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SRC="diagnostico/src"
BIN="diagnostico/bin"
OUT="diagnostico/resultados"

mkdir -p "$BIN" "$OUT"

echo "Repositorio: $REPO_ROOT"
echo ""

# --- Chequeo de herramientas ---
if ! command -v gcc >/dev/null 2>&1; then
    echo "ERROR: no se encontro gcc en el PATH."
    exit 1
fi
if ! command -v mpicc >/dev/null 2>&1; then
    echo "ERROR: no se encontro mpicc (instalar OpenMPI/MPICH)."
    exit 1
fi

# ------------------------------------------------------------
# Problema #3 (control): rand_r en esta maquina
# ------------------------------------------------------------
echo ">> Problema #3 (control) -- check_rand_r_toolchain"
{
    gcc -Wall -o "$BIN/check_rand_r" "$SRC/check_rand_r_toolchain.c" && "$BIN/check_rand_r"
} 2>&1 | tee "$OUT/problema3_control_mac.txt"
echo ""

# ------------------------------------------------------------
# Problema #4: balanceo de carga (no requiere MPI)
# ------------------------------------------------------------
echo ">> Problema #4 -- demo_balanceo_carga"
{
    gcc -Wall -Wextra -o "$BIN/demo_balanceo" "$SRC/demo_balanceo_carga.c" && "$BIN/demo_balanceo"
} 2>&1 | tee "$OUT/problema4_mac.txt"
echo ""

# ------------------------------------------------------------
# Problema #1 (control) + Pasos A y B: monty_hall_v1_naive
# ------------------------------------------------------------
echo ">> Problema #1 (control) -- monty_hall_v1_naive (Pasos A, B y D)"
mpicc -O2 -Wall -o "$BIN/monty_naive" "$SRC/monty_hall_v1_naive.c"
if [ $? -eq 0 ]; then
    {
        echo "===== PASO A: sanity check (N=1000000, P=1) ====="
        mpirun -np 1 "$BIN/monty_naive" 1000000

        echo ""
        echo "===== PASO B: balanceo de carga (N=1000000, variando P) ====="
        for p in 2 4 5 7; do
            mpirun -np "$p" "$BIN/monty_naive" 1000000
        done

        echo ""
        echo "===== PASO D: corrida de CONTROL (N=2200000000, P=1) ====="
        echo "(puede tardar ~40 segundos)"
        mpirun -np 1 "$BIN/monty_naive" 2200000000
    } 2>&1 | tee "$OUT/problema1_control_mac.txt"
else
    echo "ERROR: fallo la compilacion de monty_hall_v1_naive.c" | tee "$OUT/problema1_control_mac.txt"
fi
echo ""

# ------------------------------------------------------------
# Problema #2: monty_hall_v2_seed_fix (demostracion de semillas)
# ------------------------------------------------------------
echo ">> Problema #2 -- monty_hall_v2_seed_fix (-DDEBUG_SEEDS)"
mpicc -O2 -Wall -DDEBUG_SEEDS -o "$BIN/monty_v2_debug" "$SRC/monty_hall_v2_seed_fix.c"
if [ $? -eq 0 ]; then
    mpirun -np 4 "$BIN/monty_v2_debug" 1000 2>&1 | tee "$OUT/problema2_mac.txt"
else
    echo "ERROR: fallo la compilacion de monty_hall_v2_seed_fix.c" | tee "$OUT/problema2_mac.txt"
fi
echo ""

echo "============================================================"
echo "Listo. Evidencia guardada en: $OUT/*_mac.txt"
echo "============================================================"