#!/usr/bin/env bash
# ============================================================
# run_experimento_windows.sh (Version directa sin bloqueos)
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

LISTA_N_STR="${1:-100000,1000000,10000000,100000000,1000000000}"
LISTA_M_STR="${2:-3,5,10,50}"
REPETICIONES="${3:-5}"
PASO_P="${4:-1}"
ETIQUETA_FORZADA="${5:-windows}"
OPT_FLAG="${6:--O2}"
P_MAX_FORZADO="${7:-8}"

EXE_WIN="$(cygpath -w "$REPO_ROOT/bin/monty_hall.exe")"
OUT_DIR="$REPO_ROOT/analisis/datos"
mkdir -p "$OUT_DIR"

IFS=',' read -r -a LISTA_N <<< "$LISTA_N_STR"
IFS=',' read -r -a LISTA_M <<< "$LISTA_M_STR"

LISTA_P=()
p=1
while [ "$p" -le "$P_MAX_FORZADO" ]; do
    LISTA_P+=("$p")
    p=$((p + PASO_P))
done

OUT_FILE="$OUT_DIR/resultados_${ETIQUETA_FORZADA}_v2.csv"
HEADER="n_procesos,tiempo,N,M,victorias_cambiando,victorias_manteniendo,p_empirico,p_teorico,error_abs,semilla"

if [ ! -f "$OUT_FILE" ]; then
    echo "$HEADER" > "$OUT_FILE"
fi

TOTAL_CORRIDAS=$(( ${#LISTA_N[@]} * ${#LISTA_M[@]} * ${#LISTA_P[@]} * REPETICIONES ))
CONTADOR=0

echo "Iniciando experimento: $TOTAL_CORRIDAS corridas programadas."
echo "Destino: $OUT_FILE"

for r in $(seq 1 "$REPETICIONES"); do
    echo ">> Ronda $r/$REPETICIONES"
    for m in "${LISTA_M[@]}"; do
        for n in "${LISTA_N[@]}"; do
            for p in "${LISTA_P[@]}"; do
                CONTADOR=$((CONTADOR + 1))
                printf "   [%d/%d] M=%s N=%s P=%d (Ronda %d)... " "$CONTADOR" "$TOTAL_CORRIDAS" "$m" "$n" "$p" "$r"
                
                # Ejecucion con redireccion directa a disco (evita colgar el buffer de bash)
                mpiexec -n "$p" "$EXE_WIN" "$n" "$m" >> "$OUT_FILE"
                
                echo "OK"
            done
        done
    done
done

echo "Finalizado con exito."