#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <time.h>
#include <math.h>
#include <mpi.h>

#define SEED_MIX_CONST 2654435761u // Constante prima para hashing multiplicativo

// Paso 5 (V6): Cómputo local independiente
void simular_monty_hall(int64_t n_simulaciones, int id_proceso, int puertas,
                         unsigned int seed_base,
                         int64_t *victorias_cambiando, int64_t *victorias_manteniendo)
{
    int64_t v_cambiar = 0;
    int64_t v_mantener = 0;

    // Semilla única y descorrelacionada por proceso (Hashing multiplicativo)
    unsigned int seed = seed_base + ((unsigned int) id_proceso * SEED_MIX_CONST);

    for (int64_t i = 0; i < n_simulaciones; i++) {
        int premio   = rand_r(&seed) % puertas;
        int eleccion = rand_r(&seed) % puertas;

        // Lógica matemática V6: Cambiar equivale a haber fallado en la elección inicial
        if (eleccion != premio) {
            v_cambiar++;
        } else {
            v_mantener++;
        }
    }

    *victorias_cambiando   = v_cambiar;
    *victorias_manteniendo = v_mantener;
}

int main(int argc, char **argv) {
    int id_proceso, n_procesos;
    double t_inicio, t_fin, t_total;

    // Paso 1 (V6): Inicialización de MPI
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &id_proceso);
    MPI_Comm_size(MPI_COMM_WORLD, &n_procesos);

    // Paso 2 (V6): Lectura de parámetros
    // argv[1]: N, argv[2]: M (Puertas), argv[3]: Semilla base
    int64_t iteraciones_totales = (argc > 1) ? atoll(argv[1]) : 10000000;
    int      puertas_totales    = (argc > 2) ? atoi(argv[2])  : 3;
    unsigned int seed_base      = (argc > 3) ? (unsigned int) atoll(argv[3]) : (unsigned int) time(NULL);

    // Paso 3 (V6): Balanceo de carga (partición del trabajo)
    int64_t iteraciones_locales = iteraciones_totales / n_procesos;
    if (id_proceso < (iteraciones_totales % n_procesos)) {
        iteraciones_locales++;
    }

    // Paso 4 (V6): Sincronización previa a la medición
    MPI_Barrier(MPI_COMM_WORLD);
    t_inicio = MPI_Wtime();

    // Paso 5 (V6): Llamada al núcleo de la simulación
    int64_t victorias_cambiando_local = 0, victorias_manteniendo_local = 0;
    simular_monty_hall(iteraciones_locales, id_proceso, puertas_totales, seed_base,
                        &victorias_cambiando_local, &victorias_manteniendo_local);

    int64_t victorias_cambiando_global = 0, victorias_manteniendo_global = 0;

    // Paso 6 (V6): Reducción colectiva (MPI_INT64_T asegura 64 bits en todas las arquitecturas)
    MPI_Reduce(&victorias_cambiando_local, &victorias_cambiando_global, 1, MPI_INT64_T,
               MPI_SUM, 0, MPI_COMM_WORLD);
    MPI_Reduce(&victorias_manteniendo_local, &victorias_manteniendo_global, 1, MPI_INT64_T,
               MPI_SUM, 0, MPI_COMM_WORLD);

    // Paso 7 (V6): Sincronización y cierre de la medición
    MPI_Barrier(MPI_COMM_WORLD);
    t_fin = MPI_Wtime();
    t_total = t_fin - t_inicio;

    // Paso 8 (V6): Validación contra la teoría y exportación de resultados
    if (id_proceso == 0) {
        double p_cambiar_empirico = (double) victorias_cambiando_global / (double) iteraciones_totales;
        double p_cambiar_teorico  = (double) (puertas_totales - 1) / puertas_totales;
        double error_abs          = fabs(p_cambiar_empirico - p_cambiar_teorico);

        // Formato exacto CSV requerido por V6
        printf("%d,%f,%" PRId64 ",%d,%" PRId64 ",%" PRId64 ",%f,%f,%f\n",
               n_procesos, t_total, iteraciones_totales, puertas_totales,
               victorias_cambiando_global, victorias_manteniendo_global,
               p_cambiar_empirico, p_cambiar_teorico, error_abs);
    }

    // Paso 9 (V6): Finalización
    MPI_Finalize();
    return 0;
}