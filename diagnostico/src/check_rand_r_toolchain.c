// Problema #3 
// Objetivo: confirmar que el compilador/runtime de esta maquina provee
// rand_r() ANTES de invertir tiempo compilando y corriendo el simulador
// completo (que sí necesita MPI).
//
// Compilar con: gcc -Wall -o check_rand_r check_rand_r_toolchain.c
// Correr con:   ./check_rand_r
//
// Resultado esperado si el toolchain esta OK:
//   Se imprime un valor y el mensaje de exito -> el Problema #3 NO SE
//   REPRODUCE en esta maquina, se puede seguir usando gcc "tal cual"
//   para el simulador.
//
// Resultado esperado si el toolchain NO provee rand_r:
//   Error de COMPILACION (no de ejecucion), algo como:
//     "implicit declaration of function 'rand_r'"
//   o, al enlazar:
//     "undefined reference to `rand_r'"
//   En ese caso: copiar el mensaje de error exacto tal cual aparece en
//   la terminal (para la Bitacora) y usar WSL como alternativa, en vez
//   de intentar arreglarlo dentro de MinGW.

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(void) {
    unsigned int seed = (unsigned int) time(NULL);
    int valor = rand_r(&seed);

    printf("[CHECK] rand_r() compilo y corrio correctamente.\n");
    printf("[CHECK] Valor generado de ejemplo: %d\n", valor);
    printf("[CHECK] Conclusion: el toolchain de esta maquina SI provee rand_r.\n");
    printf("[CHECK] Problema #3 (Bitacora): NO se reproduce aqui.\n");

    return 0;
}