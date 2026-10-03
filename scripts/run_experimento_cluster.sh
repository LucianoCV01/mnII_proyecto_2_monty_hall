#!/bin/bash
# ============================================================
# run_experimento.sh (V2)
#
# Uso:
#   bash scripts/run_experimento.sh [LISTA_N] [LISTA_M] [REPETICIONES] [PASO_P] [ETIQUETA] [OPT] [P_MAX]
#
#   LISTA_N       N separados por coma. Default: 1e5,1e6,1e7,1e8,1e9
#   LISTA_M       M separados por coma. Default: 3   (Fase 2: "3,5,10,50")
#   REPETICIONES  corridas por combinacion (M,N,P). Default: 10
#   PASO_P        incremento entre valores de P. Default: 1
#   ETIQUETA      fuerza el nombre de arquitectura en el archivo de salida
#   OPT           flag de optimizacion. Default: -O2
#   P_MAX         fuerza el P maximo (util en el cluster: nproc mide el nodo
#                 de login, no la asignacion real). Default: nucleos detectados
#
# Variables de entorno opcionales:
#   LANZADOR      comando de lanzamiento. Default: "mpirun -np"
#                 (en un cluster con Slurm: LANZADOR="srun -n")
#   PERMITIR_SOBRESUSCRIPCION=1   permite P_MAX mayor que la cuota de CPU del
#                 contenedor (NO recomendado: el kernel estrangula la CPU y
#                 los tiempos dejan de ser validos)
#
# Protecciones: (1) una sola corrida a la vez por directorio de datos (lock);
# (2) en Linux se lee la cuota de CPU del contenedor (cgroup) y P_MAX no puede
# superarla: nproc mide el NODO FISICO, no la cuota asignada.
#
# Ejemplos:
#   Mac, Fase 1:     bash scripts/run_experimento.sh
#   Mac, Fase 2:     bash scripts/run_experimento.sh "" 5,10,50
#   Comparar -O3:    bash scripts/run_experimento.sh "" 3 10 1 "" -O3
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

LISTA_N_STR="${1:-100000,1000000,10000000,100000000,1000000000}"
LISTA_M_STR="${2:-3}"
REPETICIONES="${3:-10}"
PASO_P="${4:-1}"
ETIQUETA_FORZADA="${5:-}"
OPT_FLAG="${6:--O2}"
P_MAX_FORZADO="${7:-}"
LANZADOR="${LANZADOR:-mpirun -np}"

SRC="src/monty_hall.c"
BIN_DIR="bin"
OUT_DIR="analisis/datos"
mkdir -p "$BIN_DIR" "$OUT_DIR"

IFS=',' read -r -a LISTA_N <<< "$LISTA_N_STR"
IFS=',' read -r -a LISTA_M <<< "$LISTA_M_STR"

# --- Arquitectura y nucleos ---
SISTEMA="$(uname -s)"
case "$SISTEMA" in
    Darwin) ARQ="mac"; NUCLEOS=$(sysctl -n hw.ncpu) ;;
    Linux)  ARQ="linux"; NUCLEOS=$(nproc) ;;
    *)      ARQ="desconocido"; NUCLEOS=1 ;;
esac
[ -n "$ETIQUETA_FORZADA" ] && ARQ="$ETIQUETA_FORZADA"

# Cuota de CPU del contenedor (cgroup v2): "cuota periodo" o "max periodo"
NUCLEOS_DETECTADOS=$NUCLEOS
CUOTA=""
CGROUP_CPU_MAX="${CGROUP_CPU_MAX:-/sys/fs/cgroup/cpu.max}"
if [ "$SISTEMA" = "Linux" ] && [ -r "$CGROUP_CPU_MAX" ]; then
    read -r q_cg per_cg < "$CGROUP_CPU_MAX"
    if [ "$q_cg" != "max" ] && [ -n "$per_cg" ]; then
        CUOTA=$(awk -v q="$q_cg" -v p="$per_cg" 'BEGIN{printf "%d", q/p}')
    fi
fi
if [ -n "$CUOTA" ] && [ "$CUOTA" -ge 1 ] && [ "$CUOTA" -lt "$NUCLEOS" ] && [ -z "$P_MAX_FORZADO" ]; then
    echo "AVISO: nproc=$NUCLEOS pero la cuota de CPU del contenedor es $CUOTA; P_MAX se limita a $CUOTA."
    NUCLEOS=$CUOTA
fi
[ -n "$P_MAX_FORZADO" ] && NUCLEOS="$P_MAX_FORZADO"
if [ -n "$CUOTA" ] && [ "$CUOTA" -ge 1 ] && [ "$NUCLEOS" -gt "$CUOTA" ] && [ "${PERMITIR_SOBRESUSCRIPCION:-0}" != "1" ]; then
    echo "ERROR: P_MAX=$NUCLEOS supera la cuota de CPU del contenedor ($CUOTA nucleos)."
    echo "       Usar P_MAX <= $CUOTA (o PERMITIR_SOBRESUSCRIPCION=1 bajo su responsabilidad)."
    exit 1
fi

if [ "$SISTEMA" = "Darwin" ] && [ "$NUCLEOS" -lt 8 ]; then
    echo "ADVERTENCIA: se detectaron $NUCLEOS nucleos; el minimo pedido en Mac es P=1..8."
fi

LISTA_P=()
p=1
while [ "$p" -le "$NUCLEOS" ]; do
    LISTA_P+=("$p")
    p=$((p + PASO_P))
done

# Archivo de salida: version 2 (no se mezcla con resultados_<arq>.csv de la v1);
# si se usa otro flag de optimizacion, va a un archivo aparte.
SUFIJO_OPT=""
[ "$OPT_FLAG" != "-O2" ] && SUFIJO_OPT="_${OPT_FLAG#-}"
OUT_FILE="$OUT_DIR/resultados_${ARQ}_v2${SUFIJO_OPT}.csv"
LOG_ERR="$OUT_DIR/errores_${ARQ}_v2${SUFIJO_OPT}.log"
HEADER="n_procesos,tiempo,N,M,victorias_cambiando,victorias_manteniendo,p_empirico,p_teorico,error_abs,semilla"

echo "Arquitectura            : $ARQ"
echo "Optimizacion            : $OPT_FLAG"
echo "Lanzador                : $LANZADOR"
echo "nproc / cuota CPU        : $NUCLEOS_DETECTADOS / ${CUOTA:-sin cuota detectada}"
echo "Valores de P a probar   : ${LISTA_P[*]}"
echo "Valores de N a probar   : ${LISTA_N[*]}"
echo "Valores de M a probar   : ${LISTA_M[*]}"
echo "Repeticiones            : $REPETICIONES"
echo "Salida                  : $OUT_FILE"
echo ""

if ! command -v mpicc >/dev/null 2>&1; then
    echo "ERROR: no se encontro mpicc en el PATH."
    exit 1
fi

echo ">> Compilando $SRC con $OPT_FLAG"
if ! mpicc "$OPT_FLAG" -Wall -o "$BIN_DIR/monty_hall" "$SRC" -lm; then
    echo "ERROR: fallo la compilacion. Revisar $SRC antes de continuar."
    exit 1
fi

# Encabezado: si el archivo ya existe con otro formato, se aborta en vez de mezclar columnas
if [ -f "$OUT_FILE" ]; then
    if [ "$(head -n 1 "$OUT_FILE")" != "$HEADER" ]; then
        echo "ERROR: $OUT_FILE existe con un encabezado distinto (¿datos de otra version?)."
        echo "       Renombrarlo o moverlo antes de correr."
        exit 1
    fi
    echo "AVISO: $OUT_FILE ya existe; se agregan filas ($(( $(wc -l < "$OUT_FILE") - 1 )) previas)."
else
    echo "$HEADER" > "$OUT_FILE"
fi

# Una sola corrida a la vez: dos instancias compiten por la CPU y falsean los tiempos
LOCK_DIR="$OUT_DIR/.lock_corrida"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    PID_PREV=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$PID_PREV" ] && kill -0 "$PID_PREV" 2>/dev/null; then
        echo "ERROR: ya hay una corrida activa (PID $PID_PREV). No se lanza otra."
        echo "       Ver progreso: tail -f <log>.  Detenerla: kill $PID_PREV"
        exit 1
    fi
    echo "AVISO: lock de una corrida anterior que ya no existe; se reutiliza."
    rm -rf "$LOCK_DIR"; mkdir "$LOCK_DIR" || exit 1
fi
echo $$ > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT
trap 'exit 130' INT TERM

# En Mac, evitar que el equipo se suspenda mientras corre el script
if [ "$SISTEMA" = "Darwin" ] && command -v caffeinate >/dev/null 2>&1; then
    caffeinate -i -w $$ &
fi

TOTAL_CORRIDAS=$(( ${#LISTA_N[@]} * ${#LISTA_M[@]} * ${#LISTA_P[@]} * REPETICIONES ))
CONTADOR=0
FALLOS=0
INICIO_GLOBAL=$(date +%s)

# La repeticion es el bucle EXTERIOR: cada configuracion se mide una vez por ronda,
# asi el estado termico/de frecuencia del equipo no queda asociado a una sola configuracion.
for r in $(seq 1 "$REPETICIONES"); do
    echo ">> Ronda $r/$REPETICIONES"
    for m in "${LISTA_M[@]}"; do
        for n in "${LISTA_N[@]}"; do
            for p in "${LISTA_P[@]}"; do
                CONTADOR=$((CONTADOR + 1))
                printf "   corrida %d/%d (M=%s, N=%s, P=%d, ronda %d/%d)\n" \
                       "$CONTADOR" "$TOTAL_CORRIDAS" "$m" "$n" "$p" "$r" "$REPETICIONES"
                salida=$($LANZADOR "$p" "$BIN_DIR/monty_hall" "$n" "$m" 2>>"$LOG_ERR")
                rc=$?
                linea=$(printf '%s\n' "$salida" | tail -n 1)
                campos=$(printf '%s' "$linea" | awk -F, '{print NF}')
                if [ "$rc" -eq 0 ] && [ "$campos" -eq 10 ]; then
                    echo "$linea" >> "$OUT_FILE"
                else
                    FALLOS=$((FALLOS + 1))
                    echo "   AVISO: corrida fallida (codigo $rc); no se registra. Ver $LOG_ERR"
                fi
            done
        done
    done
done

FIN_GLOBAL=$(date +%s)
FILAS=$(( $(wc -l < "$OUT_FILE") - 1 ))
SEMILLAS=$(tail -n +2 "$OUT_FILE" | cut -d, -f10 | sort -u | wc -l | tr -d ' ')

echo ""
echo "============================================================"
echo "Listo. Resultados en: $OUT_FILE"
echo "Corridas: $CONTADOR (fallidas: $FALLOS). Filas en el CSV: $FILAS"
echo "Semillas distintas: $SEMILLAS de $FILAS"
echo "Tiempo total: $((FIN_GLOBAL - INICIO_GLOBAL)) segundos"
echo "============================================================"