#!/bin/bash
# ============================================================
# run_serial.sh: corre la version SERIAL (sin MPI) para tener la linea base.
#
# Uso:
#   bash scripts/run_serial.sh [LISTA_N] [LISTA_M] [REPETICIONES] [ETIQUETA]
#     LISTA_N       default: 1e5,1e6,1e7,1e8,1e9 (como en los otros experimentos)
#     LISTA_M       default: 3
#     REPETICIONES  default: 10
#     ETIQUETA      nombre de la plataforma en el archivo de salida (default: mac o linux)
#
# Salida: analisis/datos/resultados_<arq>_serial.csv  (n_procesos = 0 indica serial)
# Es un programa de UN solo nucleo: en el cluster alcanza la sesion mas chica.
# ============================================================
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

LISTA_N_STR="${1:-100000,1000000,10000000,100000000,1000000000}"
LISTA_M_STR="${2:-3}"
REPETICIONES="${3:-10}"
ETIQUETA="${4:-}"

SRC="diagnostico/src/monty_hall_serial.c"; BIN_DIR="bin"; OUT_DIR="analisis/datos"
mkdir -p "$BIN_DIR" "$OUT_DIR"
IFS=',' read -r -a LISTA_N <<< "$LISTA_N_STR"
IFS=',' read -r -a LISTA_M <<< "$LISTA_M_STR"

case "$(uname -s)" in Darwin) ARQ="mac";; Linux) ARQ="linux";; *) ARQ="desconocido";; esac
[ -n "$ETIQUETA" ] && ARQ="$ETIQUETA"
OUT_FILE="$OUT_DIR/resultados_${ARQ}_serial.csv"
HEADER="n_procesos,tiempo,N,M,victorias_cambiando,victorias_manteniendo,p_empirico,p_teorico,error_abs,semilla"

CC_BIN="${CC:-gcc}"
echo ">> Compilando $SRC con $CC_BIN -O2"
if ! "$CC_BIN" -O2 -Wall -o "$BIN_DIR/monty_hall_serial" "$SRC" -lm; then
    echo "ERROR: fallo la compilacion."; exit 1
fi

if [ -f "$OUT_FILE" ]; then
    if [ "$(head -n 1 "$OUT_FILE")" != "$HEADER" ]; then
        echo "ERROR: $OUT_FILE existe con un encabezado distinto."; exit 1
    fi
    echo "AVISO: $OUT_FILE ya existe; se agregan filas."
else
    echo "$HEADER" > "$OUT_FILE"
fi

# Una sola corrida a la vez (dos instancias compiten por la CPU y falsean los tiempos)
LOCK_DIR="$OUT_DIR/.lock_corrida"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    PID_PREV=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$PID_PREV" ] && kill -0 "$PID_PREV" 2>/dev/null; then
        echo "ERROR: ya hay una corrida activa (PID $PID_PREV)."; exit 1
    fi
    rm -rf "$LOCK_DIR"; mkdir "$LOCK_DIR" || exit 1
fi
echo $$ > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT
trap 'exit 130' INT TERM
[ "$(uname -s)" = "Darwin" ] && command -v caffeinate >/dev/null 2>&1 && caffeinate -i -w $$ &

TOTAL=$(( ${#LISTA_N[@]} * ${#LISTA_M[@]} * REPETICIONES )); K=0; FALLOS=0
INICIO=$(date +%s)
for r in $(seq 1 "$REPETICIONES"); do
    echo ">> Ronda $r/$REPETICIONES"
    for m in "${LISTA_M[@]}"; do
        for n in "${LISTA_N[@]}"; do
            K=$((K + 1)); printf "   corrida %d/%d (M=%s, N=%s)\n" "$K" "$TOTAL" "$m" "$n"
            linea=$("$BIN_DIR/monty_hall_serial" "$n" "$m" 2>/dev/null | tail -n 1)
            if [ "$(printf '%s' "$linea" | awk -F, '{print NF}')" -eq 10 ]; then
                echo "$linea" >> "$OUT_FILE"
            else
                FALLOS=$((FALLOS + 1)); echo "   AVISO: corrida fallida"
            fi
        done
    done
done
FILAS=$(( $(wc -l < "$OUT_FILE") - 1 ))
SEMILLAS=$(tail -n +2 "$OUT_FILE" | cut -d, -f10 | sort -u | wc -l | tr -d ' ')
echo "============================================================"
echo "Listo: $OUT_FILE | corridas: $K (fallidas: $FALLOS) | filas: $FILAS | semillas distintas: $SEMILLAS"
echo "Tiempo total: $(( $(date +%s) - INICIO )) s"
echo "============================================================"