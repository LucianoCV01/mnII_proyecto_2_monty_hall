#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <mpi.h>

// ============================================================
// VERSION 1 - INGENUA (Base de Diagnostico)
// Contiene DOS fallas intencionales que se van a reproducir y
// documentar antes de escribir la version corregida:
//   - FALLA #1: uso de 'long'/'atol' (riesgo de overflow en Windows,
//     donde 'long' es de 32 bits aunque el compilador sea gcc)
//   - FALLA #2: semilla por suma simple (riesgo de correlacion entre
//     procesos si arrancan dentro del mismo segundo de reloj)
// ============================================================

// Simulador ingenuo: restringido a 3 puertas
void simular_monty_hall_ingenuo(long n_simulaciones, int id_proceso, long *victorias_cambiando) {
    long v_cambiar = 0;

    // FALLA INTENCIONAL #2: Semilla por suma simple (riesgo de correlacion
    // entre procesos si arrancan dentro del mismo segundo de reloj)
    unsigned int seed = time(NULL) + id_proceso;

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

    // FALLA INTENCIONAL #1: Uso de 'long' y 'atol' (riesgo de desbordamiento
    // en Windows, donde 'long' es de 32 bits aunque el compilador sea gcc)
    long iteraciones_totales = (argc > 1) ? atol(argv[1]) : 10000000;

    // Chequeo de diagnostico rapido: compara lo que se tipeo por linea de
    // comandos contra lo que realmente quedo guardado en 'iteraciones_totales'
    // tras el parseo. Si difieren (o el valor parseado es negativo/absurdo),
    // ya alcanza para confirmar la Falla #1 sin esperar a que termine toda
    // la simulacion.
    if (id_proceso == 0) {
        fprintf(stderr, "[DEBUG] Argumento recibido: \"%s\" | N parseado: %ld\n",
                (argc > 1) ? argv[1] : "(default) 10000000", iteraciones_totales);
    }

    // Balanceo de carga (base + resto)
    long iteraciones_locales = iteraciones_totales / n_procesos;
    if (id_proceso < (iteraciones_totales % n_procesos)) {
        iteraciones_locales++;
    }

    // Barrera PREVIA: se mantiene. Asegura que todos los procesos arranquen
    // el cronometro desde el mismo punto de partida, sin importar si el SO
    // tardo mas en lanzar a algunos procesos que a otros.
    MPI_Barrier(MPI_COMM_WORLD);
    t_inicio = MPI_Wtime();

    long victorias_cambiando_local = 0;

    // Ejecucion del computo local
    simular_monty_hall_ingenuo(iteraciones_locales, id_proceso, &victorias_cambiando_local);

    long victorias_cambiando_global = 0;

    // Reduccion usando MPI_LONG (consistente con la Falla #1: sigue siendo
    // 'long', no MPI_INT64_T, a proposito en esta version)
    MPI_Reduce(&victorias_cambiando_local, &victorias_cambiando_global, 1, MPI_LONG,
               MPI_SUM, 0, MPI_COMM_WORLD);

    t_fin = MPI_Wtime();
    t_total = t_fin - t_inicio;

    if (id_proceso == 0) {
        double p_cambiar_empirico = (double) victorias_cambiando_global / (double) iteraciones_totales;
        double p_cambiar_teorico = 2.0 / 3.0; 

        // Reporte legible
        fprintf(stderr, "\n--- VERSION INGENUA (Base de Diagnostico) ---\n");
        fprintf(stderr, "Simulaciones (N): %ld\n", iteraciones_totales);
        fprintf(stderr, "Victorias Cambiando: %ld\n", victorias_cambiando_global);
        fprintf(stderr, "Prob. Empirica: %f | Prob. Teorica: %f\n",
                p_cambiar_empirico, p_cambiar_teorico);
        fprintf(stderr, "Tiempo total: %f seg con %d procesos\n\n", t_total, n_procesos);

        // Linea CSV redirigir con: ./monty_naive N >> resultados.csv
        // Formato: n_procesos,tiempo,N,victorias_cambiando,p_empirico,p_teorico
        printf("%d,%f,%ld,%ld,%f,%f\n",
               n_procesos, t_total, iteraciones_totales,
               victorias_cambiando_global, p_cambiar_empirico, p_cambiar_teorico);
    }

    MPI_Finalize();
    return 0;
}