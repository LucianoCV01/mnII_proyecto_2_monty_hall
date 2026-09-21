// Problema #4: Balanceo de carga sin reparto del resto.
//
// NO requiere MPI para demostrarse: es pura aritmetica de division entera, la misma que se
// usa despues para repartir trabajo entre procesos. 
//   gcc -Wall -o demo_balanceo demo_balanceo_carga.c
//   ./demo_balanceo
//
// SINTOMA: si se reparte N simulaciones entre P procesos con division
// entera simple (N/P) y se descarta el resto, la suma de lo que
// realmente ejecuta cada proceso es MENOR a N cada vez que N no es
// multiplo exacto de P -- se pierden hasta P-1 simulaciones en
// silencio, sin ningun error ni aviso.
//
// CAUSA RAIZ: 'int iteraciones_locales = n / p;' en cada proceso, sin
// distribuir el resto (n % p) entre ninguno de ellos.
//
// SOLUCION: los primeros (n % p) procesos reciben una iteracion extra
// (base + resto), tal como ya esta implementado en el simulador real
// desde la primera version (monty_hall_v1_naive.c en adelante) -- este
// archivo demuestra, de forma aislada, por que esa decision es
// necesaria y no un detalle cosmetico.

#include <stdio.h>

// Reparto INGENUO: descarta el resto (n % p)
void balanceo_ingenuo(long n, int p, long *total_ejecutado) {
    long por_proceso = n / p;
    *total_ejecutado = por_proceso * p;
}

// Reparto CORRECTO: base + resto distribuido entre los primeros procesos
// (la misma logica que ya usa el simulador real)
void balanceo_corregido(long n, int p, long *total_ejecutado) {
    long base = n / p;
    long resto = n % p;
    long total = 0;
    for (int rank = 0; rank < p; rank++) {
        long local = base + (rank < resto ? 1 : 0);
        total += local;
    }
    *total_ejecutado = total;
}

int main(void) {
    // Casos de prueba: se incluye a proposito un caso donde N es multiplo
    // exacto de P (no se pierde nada, para dejar claro que el bug depende
    // del resto y no aparece siempre), y casos con distintos ordenes de
    // magnitud de N, incluyendo el usado en el Paso D de la Bitacora.
    struct { long n; int p; } casos[] = {
        {17, 5},            // caso chico, para verificar a mano
        {100, 3},
        {1000000, 7},       // mismo P usado en el Paso B de la Bitacora
        {10000000, 8},      // caso "sin bug": N multiplo exacto de P
        {2200000000, 3},    // mismo N usado en el Paso D de la Bitacora
    };
    int n_casos = sizeof(casos) / sizeof(casos[0]);

    printf("%-14s %-4s %-18s %-18s %-10s\n",
           "N", "P", "Ingenuo (N/P*P)", "Corregido", "Perdidas");
    for (int i = 0; i < n_casos; i++) {
        long n = casos[i].n;
        int p = casos[i].p;
        long ing, cor;
        balanceo_ingenuo(n, p, &ing);
        balanceo_corregido(n, p, &cor);
        printf("%-14ld %-4d %-18ld %-18ld %-10ld\n", n, p, ing, cor, n - ing);
    }

    printf("\n'Perdidas' > 0 significa que esa cantidad de simulaciones\n");
    printf("nunca se hubiera ejecutado con el reparto ingenuo, en\n");
    printf("silencio y sin ningun mensaje de error.\n");

    return 0;
}