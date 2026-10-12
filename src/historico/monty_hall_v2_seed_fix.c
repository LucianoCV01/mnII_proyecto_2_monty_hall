#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <mpi.h>

// ============================================================
// VERSION 2 - CORRIGE PROBLEMA #2 (semilla por suma simple) de la version ingenua
//
// Diferencia respecto a monty_hall_v1_naive.c: la semilla de cada
// proceso ya NO se arma con una suma simple (seed_base + rank), sino
// con hashing multiplicativo (seed_base + rank * constante_prima),
// para evitar que procesos consecutivos arranquen con semillas
// numericamente cercanas.
//
// Compilacion normal (para medir tiempos, sin prints de diagnostico):
//   mpicc -O2 -Wall -o monty_v2 monty_hall_v2_seed_fix.c
//
// Compilacion de demostracion (Problema #2 observable, con -np chico):
//   mpicc -O2 -Wall -DDEBUG_SEEDS -o monty_v2_debug monty_hall_v2_seed_fix.c
//   mpirun -np 4 ./monty_v2_debug 1000
// ============================================================

// Constante prima grande para hashing multiplicativo de semillas
// (constante de Knuth, ~2^32/phi). Dispersa semillas de ranks
// consecutivos en todo el espacio de 32 bits en vez de dejarlas
// contiguas, como sucedia con la suma simple.
#define SEED_MIX_CONST 2654435761u

// Simulador: restringido a 3 puertas (Fase 1 del proyecto)
void simular_monty_hall(long n_simulaciones, int id_proceso, long *victorias_cambiando) {
    long v_cambiar = 0;
    unsigned int ahora = (unsigned int) time(NULL);

    // PROBLEMA #2 CORREGIDO: hashing multiplicativo en vez de suma simple.
    unsigned int seed = ahora + ((unsigned int) id_proceso * SEED_MIX_CONST);

#ifdef DEBUG_SEEDS
    // Demostracion del Problema #2: compila esta seccion solo si se pasa
    // -DDEBUG_SEEDS al compilador (ver instrucciones al final del archivo).
    // Calcula, SOLO PARA MOSTRAR, cual habria sido la semilla con la formula
    // vieja (suma simple) -- esa semilla NO se usa para simular nada.
    // Nota: para rank 0 ambas formulas dan el mismo valor (0 * cualquier
    // constante = 0), la diferencia se nota desde el rank 1 en adelante.
    unsigned int seed_naive_hipotetica = ahora + (unsigned int) id_proceso;
    fprintf(stderr,
        "[DEBUG][Problema #2] rank %d -> suma simple (NO USADA): %u | hash multiplicativo (USADA): %u\n",
        id_proceso, seed_naive_hipotetica, seed);
#endif

    for (long i = 0; i < n_simulaciones; i++) {
        int premio = rand_r(&seed) % 3;
        int eleccion = rand_r(&seed) % 3;

        // En el caso de 3 puertas, si te equivocas al inicio, ganas al cambiar
        if (eleccion != premio) {
            v_cambiar++;
        }
    }

    *victorias_cambiando = v_cambiar;
}

int main(int argc, char **argv) {
    int id_proceso, n_procesos;
    double t_inicio, t_fin, t_total;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &id_proceso);
    MPI_Comm_size(MPI_COMM_WORLD, &n_procesos);

    // FALLA INTENCIONAL #1
    long iteraciones_totales = (argc > 1) ? atol(argv[1]) : 10000000;

    if (id_proceso == 0) {
        fprintf(stderr, "[DEBUG] Argumento recibido: \"%s\" | N parseado: %ld\n",
                (argc > 1) ? argv[1] : "(default) 10000000", iteraciones_totales);
    }

    // Balanceo de carga (base + resto)
    long iteraciones_locales = iteraciones_totales / n_procesos;
    if (id_proceso < (iteraciones_totales % n_procesos)) {
        iteraciones_locales++;
    }

    MPI_Barrier(MPI_COMM_WORLD);
    t_inicio = MPI_Wtime();

    long victorias_cambiando_local = 0;
    simular_monty_hall(iteraciones_locales, id_proceso, &victorias_cambiando_local);

    long victorias_cambiando_global = 0;
    MPI_Reduce(&victorias_cambiando_local, &victorias_cambiando_global, 1, MPI_LONG,
               MPI_SUM, 0, MPI_COMM_WORLD);

    t_fin = MPI_Wtime();
    t_total = t_fin - t_inicio;

    if (id_proceso == 0) {
        double p_cambiar_empirico = (double) victorias_cambiando_global / (double) iteraciones_totales;
        double p_cambiar_teorico = 2.0 / 3.0; 

        fprintf(stderr, "\n--- VERSION 2 (Problema #2 corregido) ---\n");
        fprintf(stderr, "Simulaciones (N): %ld\n", iteraciones_totales);
        fprintf(stderr, "Victorias Cambiando: %ld\n", victorias_cambiando_global);
        fprintf(stderr, "Prob. Empirica: %f | Prob. Teorica: %f\n",
                p_cambiar_empirico, p_cambiar_teorico);
        fprintf(stderr, "Tiempo total: %f seg con %d procesos\n\n", t_total, n_procesos);

        // Linea CSV
        printf("%d,%f,%ld,%ld,%f,%f\n",
               n_procesos, t_total, iteraciones_totales,
               victorias_cambiando_global, p_cambiar_empirico, p_cambiar_teorico);
    }

    MPI_Finalize();
    return 0;
}