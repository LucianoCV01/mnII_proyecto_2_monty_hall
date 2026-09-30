// ciclo_completo.c -- Problema #5. Recorre el ciclo completo de Park-Miller (2^31-2 valores)
// y calcula, para pares consecutivos (x, x2), P(x%M != x2%M) y su desvio respecto de (M-1)/M.
// Uso: gcc -O2 -o ciclo_completo ciclo_completo.c && ./ciclo_completo
#include <stdio.h>
#include <stdint.h>
int main(){ const uint64_t m=2147483647ULL; int Ms[4]={3,5,10,50}; uint64_t eq[4]={0}; uint64_t x=1,n=m-1;
 for(uint64_t i=0;i<n;i++){ uint64_t y=(x*16807ULL)%m; for(int k=0;k<4;k++) if(x%Ms[k]==y%Ms[k]) eq[k]++; x=y; }
 for(int k=0;k<4;k++){ double pe=(double)eq[k]/n; printf("M=%d P_switch_ciclo=%.10f teorico=%.10f sesgo=%.3e\n",Ms[k],1-pe,1-1.0/Ms[k],(1-pe)-(1-1.0/Ms[k])); }
 return 0; }