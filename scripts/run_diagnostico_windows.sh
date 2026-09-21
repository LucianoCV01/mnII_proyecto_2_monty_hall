#!/bin/bash
# ============================================================
# run_diagnostico_windows.sh
#
# Corre, en la notebook Windows, los dos chequeos que dependen
# de esa arquitectura especifica (Problemas #1 y #3 de la
# Bitacora, Plan_de_Desarrollo_Monty_Hall.md Seccion 5.1).
# Pensado para correrse con bash (Git Bash o WSL).
#
# A diferencia del script de Mac, este NO corta la ejecucion
# si algo falla al compilar -- una falla de compilacion es
# justamente uno de los sintomas que se esta buscando detectar
# (Problema #3), asi que se documenta el error tal cual en vez
# de abortar el script.
#
# Uso (desde cualquier carpeta del repo):
#   bash scripts/run_diagnostico_windows.sh
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SRC="diagnostico/src"
BIN="diagnostico/bin"
OUT="diagnostico/resultados"

mkdir -p "$BIN" "$OUT"

echo "Repositorio: $REPO_ROOT"
echo ""

if ! command -v gcc >/dev/null 2>&1; then
    echo "ERROR: no se encontro gcc en el PATH."
    exit 1
fi

# ------------------------------------------------------------
# Problema #3 (objetivo): rand_r en Windows
# ------------------------------------------------------------
echo ">> Problema #3 (objetivo) -- check_rand_r_toolchain"
{
    echo "== Compilacion =="
    if gcc -Wall -o "$BIN/check_rand_r" "$SRC/check_rand_r_toolchain.c"; then
        echo "Compilo OK."
        echo ""
        echo "== Ejecucion =="
        if [ -f "$BIN/check_rand_r.exe" ]; then
            "$BIN/check_rand_r.exe"
        else
            "$BIN/check_rand_r"
        fi
    else
        echo ""
        echo "FALLO LA COMPILACION -- este es justamente el sintoma esperado"
        echo "si el toolchain no provee rand_r (Problema #3). Copiar este"
        echo "mensaje de error tal cual para sumarlo a la Bitacora."
    fi
} 2>&1 | tee "$OUT/problema3_windows.txt"
echo ""

# ------------------------------------------------------------
# Problema #1 (objetivo): overflow en Windows
# ------------------------------------------------------------
echo ">> Problema #1 (objetivo) -- monty_hall_v1_naive, Paso C"
if ! command -v mpicc >/dev/null 2>&1; then
    echo "ERROR: no se encontro mpicc. Instalar OpenMPI/MPICH, o correr" | tee "$OUT/problema1_windows.txt"
    echo "este paso desde WSL en vez de Git Bash." | tee -a "$OUT/problema1_windows.txt"
else
    {
        echo "== Compilacion =="
        mpicc -O2 -Wall -o "$BIN/monty_naive" "$SRC/monty_hall_v1_naive.c"
        echo ""
        echo "== Ejecucion (N=2200000000, P=1; puede tardar) =="
        echo "Mirar bien la linea [DEBUG]: el 'N parseado' deberia diferir"
        echo "de 2200000000 si se reproduce el Problema #1."
        mpirun -np 1 "$BIN/monty_naive" 2200000000
    } 2>&1 | tee "$OUT/problema1_windows.txt"
fi
echo ""

echo "============================================================"
echo "Listo. Revisar:"
echo "  $OUT/problema1_windows.txt"
echo "  $OUT/problema3_windows.txt"
echo "y avisar al grupo para cerrar el diagnostico en la Bitacora."
echo "============================================================"