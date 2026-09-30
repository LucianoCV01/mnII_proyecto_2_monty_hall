// harness_sesgo.c -- Problema #5 (bitacora). Reproduce la logica de simular_monty_hall
// (dos llamadas consecutivas por iteracion: premio y eleccion, pares no solapados).
// modo 0: do_rand() de la libc BSD/macOS (Park-Miller, salida desplazada -1)
// modo 1: splitmix64 (generador propio del codigo final)
// Uso: gcc -O2 -o harness_sesgo harness_sesgo.c && ./harness_sesgo MODO N M SEMILLA
// Salida: modo M N semilla p_cambiar_empirico sesgo(p_emp - (M-1)/M)
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
// modo 0: do_rand de FreeBSD/macOS (Park-Miller con salida desplazada); modo 1: splitmix64
static unsigned long ctx;
static int do_rand(void){ long hi,lo,x; x=(ctx%0x7ffffffe)+1; hi=x/127773; lo=x%127773; x=16807*lo-2836*hi; if(x<0)x+=0x7fffffff; x--; ctx=x; return (int)x; }
static uint64_t sm;
static uint64_t next64(void){ uint64_t z=(sm+=0x9E3779B97F4A7C15ULL); z=(z^(z>>30))*0xBF58476D1CE4E5B9ULL; z=(z^(z>>27))*0x94D049BB133111EBULL; return z^(z>>31); }
static int unif(int M){ return (int)(((__uint128_t)next64()*(unsigned)M)>>64); }
int main(int argc,char**argv){
  int mode=atoi(argv[1]); long long N=atoll(argv[2]); int M=atoi(argv[3]); unsigned seed=(unsigned)atoll(argv[4]);
  long long sw=0;
  if(mode==0){ ctx=seed; for(long long i=0;i<N;i++){ int a=do_rand()%M, b=do_rand()%M; if(a!=b) sw++; } }
  else { sm=seed; for(long long i=0;i<N;i++){ int a=unif(M), b=unif(M); if(a!=b) sw++; } }
  double p=(double)sw/N; printf("%d %d %lld %u %.9f %.3e\n",mode,M,N,seed,p,p-(double)(M-1)/M); return 0; }