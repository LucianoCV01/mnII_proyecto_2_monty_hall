# Proyecto 2 — Simulación de Monty Hall con MPI

**Métodos Numéricos II – Computación Científica** — FACET, UNT
**Evaluación Parcial 1 (HPC)** — Año [2026]

> ### El informe está en la carpeta [`docs/`](docs/)
> **[Informe_Monty_Hall.pdf](docs/Informe_Monty_Hall.pdf)** es el documento principal del trabajo: contiene la teoría, los métodos, los resultados y las conclusiones.
> El resto del repositorio contiene el código y los datos que permiten reproducir lo que dice el informe.

## ¿Qué es este proyecto?

Una simulación de Monte Carlo de la Paradoja de Monty Hall (con 3, 5, 10 y 50 puertas), escrita en **C con MPI**. Se la usó para comparar la frecuencia obtenida con la teoría y para medir el rendimiento (speedup y eficiencia) en distintos sistemas.

Resultados principales (detalles en el informe):

- Con mil millones de partidas, cambiar de puerta ganó en 0,666666 de los casos con 3 puertas (teoría: 0,666667).
- En un nodo del clúster dado por la Facultad, el programa fue unas 28 veces más rápido con 28 procesos.

## Cómo compilar y ejecutar

### Requisitos

- Compilador de C (`gcc`)
- MPI instalado (Open MPI o MPICH): comandos `mpicc` y `mpirun`
- Python 3 

### Compilar

```bash
mkdir -p bin
mpicc -O2 -Wall -o bin/monty_hall src/monty_hall.c -lm
```

### Ejecutar

```bash
mpirun -np 4 bin/monty_hall 100000000 3 12345
```

Los argumentos son, en orden: cantidad de partidas **N**, cantidad de puertas **M** y una **semilla** (opcional; si se omite, se genera una a partir del reloj). Con la misma semilla y el mismo número de procesos, el resultado se repite exactamente.

El programa imprime una línea con los campos:

`n_procesos, tiempo, N, M, victorias_cambiando, victorias_manteniendo, p_empirico, p_teorico, error_abs, semilla`
