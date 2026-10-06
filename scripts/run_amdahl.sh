#!/bin/bash
# =============================================================================
# run_amdahl.sh — Demostración de la Ley de Amdahl en el clúster
#
# Objetivo:
#   Barrer P=1..28 completo (sin saltear valores, según requisito de cátedra)
#   para N desde 10^4 hasta 10^9, mostrando que el punto óptimo P* depende
#   del tamaño del problema:
#     - N chico (10^4 - 10^5) → P* temprano, codo visible, eficiencia cae
#     - N grande (10^8 - 10^9) → P*=28, curva todavía lineal
#
# Parámetros:
#   N     ∈ {10^4, 10^5, 10^6, 10^7, 10^8, 10^9}
#   P     ∈ {1, 2, 3, ..., 28}   (barrido completo, sin huecos)
#   M     = 3
#   Reps  = 3
#
# Salida:
#   analisis/datos/amdahl_<timestamp>.csv      (una línea por corrida)
#   analisis/logs/amdahl_<timestamp>.log       (progreso + errores)
#   analisis/logs/errores_<timestamp>.log      (solo si hubo fallas)
#
# Duración estimada: ~15 minutos con N=10^9 incluido.
#
# Uso:
#   nohup bash scripts/run_amdahl.sh > analisis/logs/nohup_amdahl.log 2>&1 &
#   echo $! > /tmp/amdahl.pid
#
#   # Monitorear:
#   tail -f analisis/logs/amdahl_*.log
# =============================================================================

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

BIN="bin/monty_hall"
SRC="src/monty_hall.c"
OUT_DIR="analisis/datos"
LOG_DIR="analisis/logs"
STAMP="$(date +%Y%m%d_%H%M)"

mkdir -p bin "$OUT_DIR" "$LOG_DIR"

# --- Compilación ---
echo ">> Compilando $SRC con -O2..."
if ! mpicc -O2 -Wall -o "$BIN" "$SRC" -lm; then
    echo "ERROR: fallo la compilación. Abortando."
    exit 1
fi
echo ">> Compilación OK: $BIN"

# --- Archivos de salida ---
OUT="$OUT_DIR/amdahl_${STAMP}.csv"
LOG="$LOG_DIR/amdahl_${STAMP}.log"
ERRLOG="$LOG_DIR/errores_${STAMP}.log"

HDR="n_procesos,tiempo,N,M,victorias_cambiando,victorias_manteniendo,p_empirico,p_teorico,error_abs,semilla"
echo "$HDR" > "$OUT"
: > "$LOG"
: > "$ERRLOG"

# --- Parámetros ---
N_LIST=(10000 100000 1000000 10000000 100000000 1000000000)
P_LIST=($(seq 1 28))
REPS=3
M=3

TOTAL_CORRIDAS=$(( ${#N_LIST[@]} * ${#P_LIST[@]} * REPS ))
CONTADOR=0
INICIO_GLOBAL=$(date +%s)

# --- Encabezado del log ---
{
    echo "============================================================"
    echo "Experimento Amdahl — P=1..28, N variable"
    echo "Inicio: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Valores de N : ${N_LIST[*]}"
    echo "Valores de P : ${P_LIST[*]}"
    echo "M            : $M"
    echo "Repeticiones : $REPS"
    echo "Total corridas: $TOTAL_CORRIDAS"
    echo "Salida CSV   : $OUT"
    echo "============================================================"
} | tee -a "$LOG"

# --- Bucle principal (repetición EXTERIOR para mitigar deriva térmica) ---
for r in $(seq 1 $REPS); do
    for n in "${N_LIST[@]}"; do
        for p in "${P_LIST[@]}"; do
            CONTADOR=$((CONTADOR + 1))
            NOW=$(date '+%H:%M:%S')
            printf "[%s] corrida %4d/%d  rep=%d  N=%-11s P=%2d\n" \
                   "$NOW" "$CONTADOR" "$TOTAL_CORRIDAS" "$r" "$n" "$p" \
                   | tee -a "$LOG"

            if ! mpirun -np "$p" "$REPO_ROOT/$BIN" "$n" "$M" >> "$OUT" 2>>"$ERRLOG"; then
                echo "  FALLO: rep=$r N=$n P=$p" | tee -a "$LOG"
                echo "FALLO: rep=$r N=$n P=$p" >> "$ERRLOG"
            fi
        done
    done
done

# --- Verificación de integridad ---
FILAS_ESPERADAS=$((TOTAL_CORRIDAS + 1))   # +1 por el header
FILAS_REALES=$(wc -l < "$OUT")

FIN_GLOBAL=$(date +%s)
DURACION=$((FIN_GLOBAL - INICIO_GLOBAL))

{
    echo "============================================================"
    echo "Fin: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Duración: $DURACION segundos (~$((DURACION/60)) min)"
    echo "Filas esperadas: $FILAS_ESPERADAS"
    echo "Filas reales   : $FILAS_REALES"
    if [ "$FILAS_ESPERADAS" -ne "$FILAS_REALES" ]; then
        echo "ADVERTENCIA: faltan $((FILAS_ESPERADAS - FILAS_REALES)) filas."
        echo "Revisar $ERRLOG"
    else
        echo "OK: CSV completo."
    fi
    echo "============================================================"
} | tee -a "$LOG"