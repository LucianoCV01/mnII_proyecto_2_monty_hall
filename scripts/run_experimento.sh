#!/bin/bash
# ============================================================
# run_experimento.sh
#
# Paso 10 del plan: automatiza el escalado fuerte Y el barrido
# de tamanos de problema. Compila src/monty_hall.c y lo corre
# REPETICIONES veces por cada combinacion (N, P), guardando cada
# linea de resultado (CSV) en analisis/datos/resultados_<arq>.csv
#
# P recorre TODOS los enteros de 1 hasta los nucleos logicos
# disponibles (no solo potencias de 2), para poder ver escalones
# de rendimiento puntuales (por ej. el techo de nucleos de
# rendimiento en Apple Silicon) que un muestreo mas espaciado
# no mostraria.
#
# Uso:
#   bash scripts/run_experimento.sh [LISTA_N] [M] [REPETICIONES] [PASO_P] [ETIQUETA]
#
#   LISTA_N   (opcional) valores de N separados por coma,
#             default: "100000,1000000,10000000,100000000,1000000000"
#             (chico, mediano, grande, super grande)
#   M         (opcional) cantidad de puertas, default 3
#   REPETICIONES (opcional) corridas por combinacion (N,P), default 10
#   PASO_P    (opcional) incremento entre valores de P, default 1
#             (poner un valor mayor en el cluster si hay muchos
#             nucleos y probar cada uno resulta excesivo)
#   ETIQUETA  (opcional) fuerza el nombre de arquitectura en el
#             archivo de salida (util en WSL, donde uname da
#             "Linux" igual que en el cluster)
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

LISTA_N_STR="${1:-100000,1000000,10000000,100000000,1000000000}"
M="${2:-3}"
REPETICIONES="${3:-10}"
PASO_P="${4:-1}"
ETIQUETA_FORZADA="${5:-}"

SRC="src/monty_hall.c"
BIN_DIR="bin"
OUT_DIR="analisis/datos"

mkdir -p "$BIN_DIR" "$OUT_DIR"

IFS=',' read -r -a LISTA_N <<< "$LISTA_N_STR"

# --- Deteccion de arquitectura y nucleos logicos (Mac / Linux-WSL / Windows-MinGW) ---
SISTEMA="$(uname -s)"
case "$SISTEMA" in
    Darwin) ARQ="mac"; NUCLEOS=$(sysctl -n hw.ncpu) ;;
    Linux)  ARQ="linux"; NUCLEOS=$(nproc) ;;
    MINGW*|MSYS*|CYGWIN*) ARQ="windows"; NUCLEOS=$(nproc 2>/dev/null || echo "$NUMBER_OF_PROCESSORS") ;;
    *) ARQ="desconocido"; NUCLEOS=1 ;;
esac
if [ -n "$ETIQUETA_FORZADA" ]; then
    ARQ="$ETIQUETA_FORZADA"
fi

# Lista de P: TODOS los enteros de 1 a NUCLEOS, saltando de a PASO_P
LISTA_P=()
p=1
while [ "$p" -le "$NUCLEOS" ]; do
    LISTA_P+=("$p")
    p=$((p + PASO_P))
done

OUT_FILE="$OUT_DIR/resultados_${ARQ}.csv"

echo "Arquitectura detectada  : $ARQ"
echo "Nucleos logicos         : $NUCLEOS"
echo "Valores de P a probar   : ${LISTA_P[*]}"
echo "Valores de N a probar   : ${LISTA_N[*]}"
echo "M (puertas)             : $M"
echo "Repeticiones por combo  : $REPETICIONES"
echo "Salida                  : $OUT_FILE"
echo ""

if ! command -v mpicc >/dev/null 2>&1; then
    echo "ERROR: no se encontro mpicc en el PATH."
    exit 1
fi

echo ">> Compilando $SRC"
if ! mpicc -O2 -Wall -o "$BIN_DIR/monty_hall" "$SRC"; then
    echo "ERROR: fallo la compilacion. Revisar $SRC antes de continuar."
    exit 1
fi

# Encabezado del CSV (una sola vez, si el archivo no existe)
if [ ! -f "$OUT_FILE" ]; then
    echo "n_procesos,tiempo,N,M,victorias_cambiando,victorias_manteniendo,p_empirico,p_teorico,error_abs" > "$OUT_FILE"
fi

TOTAL_CORRIDAS=$(( ${#LISTA_N[@]} * ${#LISTA_P[@]} * REPETICIONES ))
CONTADOR=0
INICIO_GLOBAL=$(date +%s)

for n in "${LISTA_N[@]}"; do
    echo ">> N=$n"
    for p in "${LISTA_P[@]}"; do
        for r in $(seq 1 "$REPETICIONES"); do
            CONTADOR=$((CONTADOR + 1))
            printf "   corrida %d/%d (N=%s, P=%d, repeticion %d/%d)\n" \
                   "$CONTADOR" "$TOTAL_CORRIDAS" "$n" "$p" "$r" "$REPETICIONES"
            mpirun -np "$p" "$BIN_DIR/monty_hall" "$n" "$M" >> "$OUT_FILE"
        done
    done
done

FIN_GLOBAL=$(date +%s)

echo ""
echo "============================================================"
echo "Listo. Resultados acumulados en: $OUT_FILE"
echo "Total de corridas: $CONTADOR"
echo "Tiempo total del script: $((FIN_GLOBAL - INICIO_GLOBAL)) segundos"
echo "============================================================"