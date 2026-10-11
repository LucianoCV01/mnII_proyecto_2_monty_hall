// monty_hall_serial.c: version SERIAL (sin MPI) del simulador de Monty Hall.
// Sirve de linea base para comparar con la version paralela (incluso con P=1).
// Usa el mismo generador (SplitMix64), la misma derivacion de semilla del
// proceso 0 y el mismo bucle que monty_hall.c: con la misma semilla, N y M da
// exactamente las mismas victorias que la version MPI con P=1.
//
// Uso: ./monty_hall_serial N [M] [semilla]
// Salida (una linea CSV, mismas columnas que la version paralela;
//   n_procesos = 0 indica "serial"):
//   0,tiempo,N,M,victorias_cambiando,victorias_manteniendo,p_empirico,p_teorico,error_abs,semilla
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <time.h>
#include <math.h>

static inline uint64_t splitmix64(uint64_t *s) {
    uint64_t z = (*s += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

static double ahora(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    int64_t N = (argc > 1) ? atoll(argv[1]) : 10000000;
    int     M = (argc > 2) ? atoi(argv[2])  : 3;
    uint64_t seed;
    if (argc > 3) {
        seed = (uint64_t) strtoull(argv[3], NULL, 10);
    } else {
        struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
        seed = ((uint64_t) ts.tv_sec << 30) ^ (uint64_t) ts.tv_nsec;
    }

    // Estado inicial: igual al del proceso 0 de la version paralela
    uint64_t t  = seed ^ ((uint64_t) 1 * 0xD1B54A32D192ED03ULL);
    uint64_t st = splitmix64(&t);

    int64_t v_cambiar = 0, v_mantener = 0;
    double t0 = ahora();
    for (int64_t i = 0; i < N; i++) {
        int premio   = (int) (splitmix64(&st) % (uint64_t) M);
        int eleccion = (int) (splitmix64(&st) % (uint64_t) M);
        if (eleccion != premio) v_cambiar++; else v_mantener++;
    }
    double tiempo = ahora() - t0;

    double p_emp = (double) v_cambiar / (double) N;
    double p_teo = (double) (M - 1) / M;
    printf("0,%f,%" PRId64 ",%d,%" PRId64 ",%" PRId64 ",%.10f,%.10f,%.10f,%" PRIu64 "\n",
           tiempo, N, M, v_cambiar, v_mantener, p_emp, p_teo, fabs(p_emp - p_teo), seed);
    return 0;
}