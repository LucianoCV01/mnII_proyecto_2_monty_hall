#!/bin/bash
# ============================================================
# diagnostico_cluster.sh
# Recolecta el contexto del entorno (hardware, limites del contenedor, MPI,
# planificador) y corre un micro-benchmark con el simulador real.
# Dura ~1-2 minutos. NO vuelca variables de entorno completas (hay tokens de
# JupyterHub): solo las que se listan abajo. El hostname se oculta si contiene
# el usuario.
#
# Uso (desde la raiz del repo, en la terminal de la sesion del cluster):
#   bash scripts/diagnostico_cluster.sh [P_MAX] [N_BENCH]
#     P_MAX    (opcional) fuerza el maximo de procesos a probar
#     N_BENCH  (opcional) N del micro-benchmark. Default 100000000
#
# Salida: analisis/datos/diagnostico_cluster.txt  (subir ese archivo)
# IMPORTANTE: correrlo en una sesion con el MISMO tamano de recursos que se
# usara en las corridas (los limites dependen del recurso elegido al entrar).
# ============================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
OUT_DIR="analisis/datos"; mkdir -p "$OUT_DIR" bin
OUT="$OUT_DIR/diagnostico_cluster.txt"
P_MAX_ARG="${1:-}"
N_BENCH="${2:-100000000}"
TMPD="$(mktemp -d)"
export LC_ALL=C

: > "$OUT"
sec() { { echo; echo "=================== $1 ==================="; } | tee -a "$OUT"; }
run() { { echo "\$ $*"; eval "$*" 2>&1 || echo "(fallo o no disponible: codigo $?)"; } | tee -a "$OUT"; }
say() { echo "$*" | tee -a "$OUT"; }

sec "1. IDENTIFICACION"
say "fecha: $(date '+%Y-%m-%d %H:%M:%S %Z')"
say "hostname: $(hostname | sed -E 's/^jupyter-.*/jupyter-<oculto>/')"
run "uname -srm"
run "grep -E '^(PRETTY_NAME)' /etc/os-release"
say "contenedor: $([ -f /.dockerenv ] && echo 'si (/.dockerenv)' || echo 'no detectado')  kubernetes: $([ -n "$KUBERNETES_SERVICE_HOST" ] && echo si || echo no)"

sec "2. CPU"
run "lscpu"
run "nproc; nproc --all; getconf _NPROCESSORS_ONLN"
run "grep -E 'Cpus_allowed_list' /proc/self/status"
run "taskset -cp \$\$"
run "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
run "grep -m1 'cpu MHz' /proc/cpuinfo"

sec "3. LIMITES DEL CONTENEDOR (cgroup y variables del spawner)"
run "cat /sys/fs/cgroup/cpu.max"
run "cat /sys/fs/cgroup/cpuset.cpus.effective"
run "cat /sys/fs/cgroup/memory.max"
run "cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us /sys/fs/cgroup/cpu/cpu.cfs_period_us"
run "env | grep -E '^(CPU_LIMIT|CPU_GUARANTEE|MEM_LIMIT|MEM_GUARANTEE|SLURM_[A-Z_]*|PBS_[A-Z_]*|OMP_[A-Z_]*|OMPI_[A-Z_]*|PMIX_[A-Z_]*)='"

sec "4. MEMORIA Y DISCO"
run "free -h"
run "df -h \$HOME | tail -n 2"

sec "5. CARGA ACTUAL (otros usuarios / ruido)"
run "uptime"
run "cat /proc/loadavg"
run "top -bn1 | head -n 15"

sec "6. SOFTWARE"
run "which mpicc mpirun mpiexec gcc"
run "mpirun --version | head -n 3"
run "mpicc --showme 2>/dev/null || mpicc -show"
run "gcc --version | head -n 1"
run "python3 --version"
run "md5sum src/monty_hall.c scripts/run_experimento.sh"

sec "7. PLANIFICADOR (si existe)"
run "which sbatch srun squeue qsub"
run "sinfo 2>&1 | head -n 8"

# ---- cores efectivos ----
NPROC=$(nproc)
CUOTA=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r q p < /sys/fs/cgroup/cpu.max
    [ "$q" != "max" ] && CUOTA=$(awk -v q="$q" -v p="$p" 'BEGIN{printf "%d", q/p}')
elif [ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
    q=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us); p=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
    [ "$q" -gt 0 ] 2>/dev/null && CUOTA=$(awk -v q="$q" -v p="$p" 'BEGIN{printf "%d", q/p}')
fi
CORES=$NPROC
[ -n "$CUOTA" ] && [ "$CUOTA" -lt "$CORES" ] && CORES=$CUOTA
[ -n "$P_MAX_ARG" ] && CORES=$P_MAX_ARG
SMT=$(lscpu | awk -F: '/Thread\(s\) per core/{gsub(/ /,"",$2); print $2}')

sec "8. PRUEBA MPI: hola (host, rank, cpu fisico)"
cat > "$TMPD/hola.c" <<'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <sched.h>
#include <mpi.h>
int main(int c, char **v){ int r,s,l; char h[MPI_MAX_PROCESSOR_NAME];
  MPI_Init(&c,&v); MPI_Comm_rank(MPI_COMM_WORLD,&r); MPI_Comm_size(MPI_COMM_WORLD,&s);
  MPI_Get_processor_name(h,&l); printf("rank %d/%d cpu=%d\n", r, s, sched_getcpu());
  MPI_Finalize(); return 0; }
CEOF
if mpicc -O2 -o "$TMPD/hola" "$TMPD/hola.c" 2>"$TMPD/cc.err"; then
    NP4=$(( CORES < 4 ? CORES : 4 ))
    run "mpirun -np $NP4 $TMPD/hola | sort -V"
    say "-- sobresuscripcion: P = cores+1 = $((CORES+1)) (sin flags):"
    if mpirun -np $((CORES+1)) "$TMPD/hola" >"$TMPD/ov.out" 2>"$TMPD/ov.err"; then
        say "OK sin flags"; OVERSUB="no hace falta"
    else
        say "FALLA sin flags: $(head -n 3 "$TMPD/ov.err" | tr '\n' ' ')"
        if mpirun --oversubscribe -np $((CORES+1)) "$TMPD/hola" >/dev/null 2>&1; then OVERSUB="requiere --oversubscribe"; else OVERSUB="falla tambien con --oversubscribe"; fi
        say "con --oversubscribe: $OVERSUB"
    fi
else
    say "NO COMPILA el programa MPI de prueba:"; cat "$TMPD/cc.err" | tee -a "$OUT"; OVERSUB="(no probado)"
fi

sec "9. MICRO-BENCHMARK CON EL SIMULADOR REAL (N=$N_BENCH, M=3, 3 repeticiones)"
BENCH_TXT="(no ejecutado)"
if [ -f src/monty_hall.c ] && mpicc -O2 -Wall -o "$TMPD/mh" src/monty_hall.c -lm 2>"$TMPD/mh.err"; then
    LISTA_P=""
    for p in 1 2 4 6 8 12 16 24 32 48 64 96; do [ "$p" -le "$CORES" ] && LISTA_P="$LISTA_P $p"; done
    [ -n "$P_MAX_ARG" ] || case " $LISTA_P " in *" $CORES "*) ;; *) LISTA_P="$LISTA_P $CORES";; esac
    say "P a probar:$LISTA_P"
    : > "$TMPD/t.txt"
    for r in 1 2 3; do for p in $LISTA_P; do
        t=$(mpirun -np "$p" "$TMPD/mh" "$N_BENCH" 3 2>>"$TMPD/mh.err" | tail -n 1 | cut -d, -f2)
        echo "$p ${t:-NA}" >> "$TMPD/t.txt"
    done; done
    : > "$TMPD/res.txt"
    for p in $LISTA_P; do
        v=$(awk -v p="$p" '$1==p && $2!="NA"{print $2}' "$TMPD/t.txt" | sort -n); n=$(echo "$v" | grep -c .)
        [ "$n" -eq 0 ] && continue
        echo "$p $(echo "$v" | sed -n "$(( (n+1)/2 ))p") $(echo "$v" | head -n 1) $(echo "$v" | tail -n 1)" >> "$TMPD/res.txt"
    done
    BENCH_TXT=$(awk -v N="$N_BENCH" 'NR==1{t1=$2; printf "ns/iteracion con P=1: %.2f\n", t1/N*1e9}
      {printf "P=%-3d mediana=%9.4f s  min=%9.4f  max=%9.4f  speedup=%6.2f  eficiencia=%5.2f  dispersion=%5.1f%%\n",$1,$2,$3,$4,t1/$2,t1/$2/$1,100*($4-$3)/$2}' "$TMPD/res.txt")
    say "$BENCH_TXT"
    [ -s "$TMPD/mh.err" ] && { say "-- stderr durante el benchmark (primeras lineas):"; head -n 5 "$TMPD/mh.err" | tee -a "$OUT"; }
else
    say "No se pudo compilar o falta src/monty_hall.c:"; cat "$TMPD/mh.err" 2>/dev/null | head -n 8 | tee -a "$OUT"
fi

sec "RESUMEN"
say "cores por nproc            : $NPROC"
say "cuota cgroup (cores)       : ${CUOTA:-sin cuota detectada}"
say "cores efectivos usados     : $CORES"
say "hilos por core (SMT)       : ${SMT:-?}"
say "MPI                        : $(mpirun --version 2>&1 | head -n 1)"
PLAN=$(which sbatch srun 2>/dev/null | tr '\n' ' ')
say "planificador (sbatch/srun) : ${PLAN:-no detectado}"
say "sobresuscripcion           : ${OVERSUB:-?}"
say "benchmark:"; echo "$BENCH_TXT" | sed 's/^/   /' | tee -a "$OUT"
rm -rf "$TMPD"
echo; echo ">> Listo. Subir el archivo: $OUT"