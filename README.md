# Proyecto 2 — Simulación de Probabilidad Colectiva (Monty Hall)

**Métodos Numéricos II - Computación Científica** — FACET, UNT
**Evaluación Parcial 1 (HPC)**

Este repositorio contiene la implementación en **C y MPI** de una simulación de Monte Carlo para la Paradoja de Monty Hall. El proyecto demuestra el uso de Computación de Alta Performance (HPC) evaluando el rendimiento concurrente (Speedup) y resolviendo desafíos de portabilidad multiplataforma.

## 🗂️ Estructura del Proyecto

- `/src`: Contiene el código fuente final y optimizado (`monty_hall.c`).
- `/diagnostico`: Contiene las versiones previas del código (`/src`) utilizadas para evidenciar y aislar errores comunes en HPC (overflow de enteros y correlación de semillas), junto con sus resultados (`/resultados`). Las explicaciones de las fallas están documentadas como comentarios dentro del mismo código.
- `/docs`: Documentación principal, incluyendo el Plan de Desarrollo y la Bitácora de Resolución de Problemas.
- `/analysis`: Notebook de Python para la generación de gráficos empíricos vs teóricos y curvas de escalabilidad.

## 🚀 Inicio Rápido (Compilación y Ejecución)

### Requisitos
- Compilador de C (GCC)
- Entorno MPI instalado (OpenMPI o MPICH)

### 1. Compilar la versión final
Para obtener el máximo rendimiento computacional, compilamos aplicando la bandera de optimización `-O3`:

```bash
mpicc -O3 -Wall -o monty_hall src/monty_hall.c