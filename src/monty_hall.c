#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <time.h>
#include <math.h>
#include <mpi.h>

// Generador propio (splitmix64, periodo 2^64). Reemplaza rand()/srand():
// rand() % 3 sobre el Park-Miller de macOS tiene un sesgo exacto de
// -2/(3*16807) ~ -4e-5 en P(cambiar) (ver Problema #5 de la bitacora).
static inline uint64_t splitmix64(uint64_t *s) {
    uint64_t z = (*s += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

void simular_monty_hall(int64_t n_simulaciones, int id_proceso, int puertas,
                        uint64_t seed_base,
                        int64_t *victorias_cambiando, int64_t *victorias_manteniendo)
{
    int64_t v_cambiar = 0, v_mantener = 0;

    // Stream propio por proceso: la semilla base se mezcla con el rank
    uint64_t t  = seed_base ^ ((uint64_t)(id_proceso + 1) * 0xD1B54A32D192ED03ULL);
    uint64_t st = splitmix64(&t);

    for (int64_t i = 0; i < n_simulaciones; i++) {
        int premio   = (int)(splitmix64(&st) % (uint64_t)puertas);
        int eleccion = (int)(splitmix64(&st) % (uint64_t)puertas);
        if (eleccion != premio) v_cambiar++; else v_mantener++;
    }
    *victorias_cambiando   = v_cambiar;
    *victorias_manteniendo = v_mantener;
}

int main(int argc, char **argv) {
    int id_proceso, n_procesos;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &id_proceso);
    MPI_Comm_size(MPI_COMM_WORLD, &n_procesos);

    // argv[1]: N, argv[2]: M (puertas), argv[3]: semilla base (opcional)
    int64_t iteraciones_totales = (argc > 1) ? atoll(argv[1]) : 10000000;
    int     puertas_totales     = (argc > 2) ? atoi(argv[2])  : 3;
    uint64_t seed_base;
    if (argc > 3) {
        seed_base = (uint64_t)strtoull(argv[3], NULL, 10);
    } else {
        // Sin semilla: nanosegundos del rank 0, difundidos a todos los ranks
        // (time(NULL) repetia la semilla en corridas dentro del mismo segundo)
        struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
        seed_base = ((uint64_t)ts.tv_sec << 30) ^ (uint64_t)ts.tv_nsec;
    }
    MPI_Bcast(&seed_base, 1, MPI_UINT64_T, 0, MPI_COMM_WORLD);

    // Balanceo de carga: base + resto
    int64_t iteraciones_locales = iteraciones_totales / n_procesos;
    if (id_proceso < (iteraciones_totales % n_procesos)) iteraciones_locales++;

    #ifndef SIN_BARRERA
    MPI_Barrier(MPI_COMM_WORLD);
    #endif

    double t_inicio = MPI_Wtime();

    int64_t vc_local = 0, vm_local = 0, vc_global = 0, vm_global = 0;
    simular_monty_hall(iteraciones_locales, id_proceso, puertas_totales, seed_base,
                       &vc_local, &vm_local);
    MPI_Reduce(&vc_local, &vc_global, 1, MPI_INT64_T, MPI_SUM, 0, MPI_COMM_WORLD);
    MPI_Reduce(&vm_local, &vm_global, 1, MPI_INT64_T, MPI_SUM, 0, MPI_COMM_WORLD);

    double t_total = MPI_Wtime() - t_inicio;

    if (id_proceso == 0) {
        double p_emp = (double)vc_global / (double)iteraciones_totales;
        double p_teo = (double)(puertas_totales - 1) / puertas_totales;
        // CSV: n_procesos,tiempo,N,M,victorias_cambiando,victorias_manteniendo,p_emp,p_teo,error_abs,semilla
        printf("%d,%f,%" PRId64 ",%d,%" PRId64 ",%" PRId64 ",%.10f,%.10f,%.10f,%" PRIu64 "\n",
               n_procesos, t_total, iteraciones_totales, puertas_totales,
               vc_global, vm_global, p_emp, p_teo, fabs(p_emp - p_teo), seed_base);
    }
    MPI_Finalize();
    return 0;
}