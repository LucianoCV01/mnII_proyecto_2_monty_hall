# Plan de Desarrollo: Proyecto 2 - Monty Hall (HPC)

> **Última actualización:** 03/10/2026. Se incorpora el Experimento 3 (fase B): barrido continuo de $P=1\dots28$ en el clúster, con un modelo del overhead de sincronización y su validación estocástica (Sección 6.3). Se cierran antes los resultados experimentales de Mac y clúster (Problemas #5 y #6), `-O2` vs. `-O3` y la corrida espejo. Ver Sección 13 (Registro de cambios). Queda como trabajo futuro, no bloqueante, la prueba con y sin `MPI_Barrier` (Sección 5.2).

## 1. Descripción General y Objetivos

El objetivo central del proyecto es utilizar la simulación masiva de eventos (método empírico de Monte Carlo) para verificar la frecuencia relativa de los resultados de la Paradoja de Monty Hall y validarlos contra la teoría probabilística. Se debe simular el concurso de puertas, evaluando el dilema matemático de si conviene mantener la elección inicial o cambiar de puerta luego de que el presentador abre una o más puertas incorrectas.

**Enfoque en dos fases:**
- **Fase 1 (obligatoria):** implementar y validar completamente el caso clásico de 3 puertas — es el foco principal exigido por la consigna.
- **Fase 2 (obligatoria, confirmada por la cátedra — ver Sección 12):** generalizar a $M$ puertas ($M = 3, 5, 10, 50$) y validar la frecuencia empírica contra la teoría $(M-1)/M$ para cada valor de $M$ (Sección 2).

**Sobre el proceso de desarrollo:** la cátedra evalúa explícitamente cómo se diagnostican y resuelven problemas de HPC, no solo la corrección del resultado final. Por eso el desarrollo se plantea deliberadamente por etapas: primero una versión simple del simulador, luego el registro honesto de los problemas reales que aparezcan (o que ya se anticiparon durante el diseño, ver Sección 5), y recién después las versiones corregidas — dejando esa evolución documentada en el repositorio en vez de entregar solo la versión final "prolija".

**Alcance de plataformas (actualizado):** los experimentos se realizan en **Mac M1** y en el **clúster de la Facultad**. La notebook Windows quedó fuera del alcance por razones logísticas del grupo; la evidencia de diagnóstico ya obtenida en ella (Problemas #1 y #3) se conserva en la bitácora, pero ya no condiciona el diseño del código final.

**Limitaciones que se reconocen de antemano** (ampliadas en la Sección 9):
- El método de Monte Carlo da una estimación con error estadístico de orden $O(1/\sqrt{N})$; no es un resultado exacto sino asintótico.
- La calidad del generador de números pseudoaleatorios utilizado condiciona la validez estadística de las simulaciones a gran escala. Esto dejó de ser una limitación teórica: se **confirmó** con datos propios (Problema #5, Sección 5.1) y motivó el reemplazo de `rand()` por un generador propio.
- El modelo generalizado a $M$ puertas depende de una regla específica sobre el comportamiento del presentador, que se explicita en la Sección 2.

## 2. Fundamento Matemático y Probabilístico del Problema

### 2.1 Caso clásico ($M = 3$)

Sea $P$ la puerta con el premio, $E$ la puerta elegida inicialmente por el jugador y $A$ la puerta que abre el presentador (siempre una puerta distinta de $E$ y sin premio). Por enumeración de los tres casos igualmente probables de elección inicial:

| Elección inicial | ¿Coincide con el premio? | Resultado si mantiene | Resultado si cambia |
|---|---|---|---|
| Puerta con el premio (prob. 1/3) | Sí | Gana | Pierde |
| Puerta sin premio, opción A (prob. 1/3) | No | Pierde | Gana |
| Puerta sin premio, opción B (prob. 1/3) | No | Pierde | Gana |

$$P(\text{ganar manteniendo}) = \frac{1}{3} \qquad P(\text{ganar cambiando}) = \frac{2}{3}$$

La clave del "truco" es que el presentador **nunca actúa al azar**: siempre elimina una puerta perdedora que el jugador no eligió, lo cual traslada la probabilidad inicial de "haber fallado" (2/3) íntegramente a la puerta alternativa.

### 2.2 Generalización a $M$ puertas (Fase 2)

Bajo el supuesto de que el presentador abre **todas las puertas incorrectas excepto una** (dejando siempre exactamente 2 puertas cerradas: la elegida y una alternativa), el mismo razonamiento por casos da:

$$P(\text{ganar cambiando}) = \frac{M-1}{M} \qquad P(\text{ganar manteniendo}) = \frac{1}{M}$$

**Nota sobre variantes:** existe una variante alternativa en la que el presentador abre **una sola** puerta incorrecta sin importar cuántas puertas totales haya $M$. Da una fórmula distinta y **no es la implementada en este proyecto**; queda documentada para evitar ambigüedad en la defensa oral (Lowery 2022, IB Maths Resources 2023). La generalización a $M$ puertas está confirmada (Sección 12); esta variante alternativa sigue fuera de alcance salvo indicación contraria de la cátedra.

**Valores teóricos y error esperado (Fase 2).** El criterio del simulador (`eleccion != premio` equivale a ganar cambiando) es válido para cualquier $M$ bajo el supuesto anterior, por lo que la Fase 2 **no requiere cambios en el núcleo**: solo se varía el parámetro $M$. Error estándar $SE=\sqrt{p(1-p)/N}$ con $N=10^9$:

| $M$ | $P(\text{cambiar})$ | $P(\text{mantener})$ | $SE$ ($N=10^9$) |
|---|---|---|---|
| 3 | 2/3 ≈ 0,6667 | 1/3 | $1{,}49\times10^{-5}$ |
| 5 | 4/5 = 0,8000 | 1/5 | $1{,}26\times10^{-5}$ |
| 10 | 9/10 = 0,9000 | 1/10 | $9{,}5\times10^{-6}$ |
| 50 | 49/50 = 0,9800 | 1/50 | $4{,}4\times10^{-6}$ |

## 3. Arquitectura de la Solución

Dado que el problema es "embarazosamente paralelo" (cada iteración es independiente de las demás), se dividirá el desarrollo en dos capas:

- **Núcleo Computacional (C + MPI):** genera los números aleatorios, juega las partidas distribuyendo la carga entre procesos ($P$), calcula la validación estadística contra la teoría, y registra los tiempos de ejecución. Es la única capa que participa de la medición de rendimiento.
- **Capa de Visualización (Python):** mediante `pandas` y `matplotlib`, procesa los CSV generados por el simulador para producir gráficos de barras (probabilidades empíricas vs. teóricas), curvas de escalabilidad (Speedup) y el análisis de convergencia del error. No participa de la medición de tiempos.

**Justificación de Diseño:** esta separación estricta evita un antipatrón común en la medición de rendimiento computacional: mezclar el tiempo de generación de gráficos o post-procesamiento de datos (operaciones I/O bound) dentro de la toma de tiempos del código paralelo, lo cual contaminaría y degradaría artificialmente el *speedup* reportado.

## 4. Características del Código y Estructura de Datos

- **Flexibilidad (Parametrización):** número de simulaciones ($N$), cantidad de puertas ($M$) y semilla base opcional se ingresan mediante argumentos de línea de comandos.
- **Estructura de Datos (Datos Sintéticos):** generados al vuelo en memoria local de cada proceso, sin I/O a disco.
- **Reproducibilidad:** con semilla explícita (`argv[3]`) una corrida se reproduce exactamente. Sin semilla, el rank 0 genera una de 64 bits a partir de la hora en nanosegundos y la difunde con `MPI_Bcast`; **la semilla se registra en el CSV** (columna `semilla`), de modo que toda corrida es reproducible a posteriori (Problema #6).
- **Balanceo de carga exacto:** reparto de base + resto entre procesos, evitando la pérdida silenciosa de iteraciones cuando $N$ no es múltiplo exacto de $P$ (Sección 5.1, Problema #4).
- **Independencia entre streams de proceso:** el estado inicial de cada rank se deriva mezclando la semilla base con el rank y pasándola por `splitmix64` (Problema #2, con la nota posterior). Con período $2^{64}$ el solapamiento entre streams es despreciable.
- **Tipos numéricos:** `int64_t` para los contadores (Problema #1). Se mantiene por ser gratuito: en los dos entornos finales (LP64) es el mismo tipo nativo de 64 bits, por lo que se descartó el experimento de costo (Sección 6.1).
- **Generador aleatorio propio:** `splitmix64` (período $2^{64}$), con `% M` sobre 64 bits (sesgo por módulo ≈ $5\times10^{-20}$), en vez de `rand()`/`srand()` de la libc. Motivo: `rand() % 3` sobre el generador de macOS tiene un sesgo sistemático de $-4\times10^{-5}$ (Problema #5). Da además exactamente los mismos resultados en Mac y clúster, sin depender de la libc de cada sistema.
- **Salida validada:** probabilidad empírica, probabilidad teórica y error absoluto calculados directamente en C.

### 4.1 Flujo de Ejecución del Simulador

1. **Inicialización de MPI:** cada proceso obtiene su rank y el tamaño del grupo (modelo SPMD).
2. **Lectura de parámetros y semilla:** cada proceso lee los mismos `argv` ($N$, $M$, semilla opcional). El rank 0 genera la semilla base si no se indicó una y la difunde (`MPI_Bcast`, fuera de la zona medida).
3. **Balanceo de carga:** división entera más resto ($\lfloor N/P \rfloor$ por proceso, resto distribuido entre los primeros procesos).
4. **Sincronización previa a la medición:** barrera antes de arrancar el cronómetro (queda fuera de la zona medida; justificación en la Sección 5.2).
5. **Cómputo local:** cada proceso sortea, para cada simulación local, la puerta premiada y la elegida; compara ambas para determinar victoria "cambiando" o "manteniendo".
6. **Reducción colectiva:** suma de los contadores locales de ambos tipos de victoria hacia el proceso raíz.
7. **Cierre de medición:** se detiene el cronómetro tras la reducción, sin barrera adicional (justificación en la Sección 5.2).
8. **Validación contra la teoría y exportación:** el proceso raíz calcula probabilidad empírica, teórica y error absoluto, y exporta una línea de resultados al CSV.
9. **Finalización:** cierre del entorno de MPI.

Solo hay comunicación en el paso 2 (difusión de la semilla, fuera de la medición), el paso 4 (una barrera) y el paso 6 (dos `MPI_Reduce` de un valor cada una), por lo que se espera overhead de comunicación marginal incluso a medida que crece $P$.

## 5. Bitácora de Diagnóstico y Decisiones de Diseño

La cátedra evalúa el proceso de diagnóstico tanto como el resultado. Esta sección se organiza en tres categorías, según el tipo de argumento que cada ítem aporta:

- **5.1 — Problemas Diagnosticados y Corregidos:** fallas reales (o de riesgo real) que existían en una versión del código y se corrigieron, con evidencia de antes/después.
- **5.2 — Decisiones de Diseño Justificadas:** elecciones de implementación que nunca fallaron en una versión anterior, pero que se justifican explícitamente en vez de darse por obvias.
- **5.3 — Propiedades Caracterizadas Empíricamente:** comportamientos inherentes del método (no del código) que no tienen solución, pero se miden con datos propios en vez de citarse solo en teoría.

### 5.1 Problemas Diagnosticados y Corregidos

#### Problema #1: Desbordamiento de enteros multiplataforma (Cross-Platform Overflow)

| Campo | Detalle |
|---|---|
| **Síntoma esperado** | Con $N \geq 2.15 \times 10^9$ simulaciones, los contadores se desbordarían a valores negativos, arruinando el CSV de resultados. |
| **Causa raíz** | El tipo `long` no tiene un tamaño fijo garantizado por el estándar de C: en Linux/macOS de 64 bits (modelo LP64) ocupa 64 bits, pero en Windows de 64 bits (modelo LLP64) ocupa 32 bits — sin importar si el compilador es gcc, porque el tamaño lo define el ABI del sistema operativo objetivo, no el compilador. |
| **Cómo se detectó** | Revisión de diseño al planificar la compilación en tres arquitecturas distintas (Mac M1, Windows, clúster), antes de escribir el código final. |
| **Solución aplicada** | Reemplazo de `long` por `int64_t` (`<stdint.h>`) en todos los contadores, `atol` por `atoll`, y `%ld` por el macro `PRId64` (`<inttypes.h>`) en las impresiones. En MPI, `MPI_LONG` se reemplaza por `MPI_INT64_T`. |
| **Cómo se verifica** | Protocolo de control cruzado: correr $N = 2.2\times10^9$, $P=1$ (aislando el balanceo de carga) en dos arquitecturas — Mac (control) y Windows (objetivo). |

**Resultado real obtenido — CONFIRMADO en ambas arquitecturas:**

- **Mac (control, LP64):** el valor parseado (2.200.000.000) coincidió exactamente con el tipeado, y la probabilidad convergió con normalidad — el Problema #1 **no se manifiesta** en esta arquitectura, tal como predice la causa raíz (`diagnostico/resultados/problema1_control_mac.txt`).
- **Windows (objetivo, LLP64):** se aisló la causa raíz con un chequeo mínimo sin MPI ni `rand_r` (`check_long_size.c`), evitando el bloqueo del Problema #3 en la misma máquina. Resultado: `sizeof(long) = 4 bytes (32 bits)` y `atol("2200000000") = -2094967296`.

  Esta corrupción coincide **exactamente** con la aritmética de desbordamiento de complemento a dos esperada: $2.200.000.000 - 2^{32} = 2.200.000.000 - 4.294.967.296 = -2.094.967.296$. No es un valor corrupto al azar — es el resultado determinístico y predecible de interpretar como entero de 32 bits con signo un valor que solo cabe en 33 bits sin signo. Esto confirma la causa raíz documentada arriba con precisión matemática, no solo cualitativamente (`diagnostico/resultados/problema1_windows.txt`).

Con ambas corridas, el Problema #1 queda **cerrado**: reproducido donde se predijo que fallaría, y confirmado como no aplicable donde se predijo que no fallaría.

**Estado final (alcance reducido):** al quedar Windows fuera del alcance, este problema no puede manifestarse en los dos entornos finales (Mac y clúster, ambos LP64). Se conserva `int64_t` porque no tiene costo (es el mismo tipo nativo de 64 bits) y se conserva la evidencia como parte del proceso de diagnóstico.

#### Problema #2: Correlación de semillas entre procesos (el "enemigo" de Monte Carlo)

| Campo | Detalle |
|---|---|
| **Síntoma esperado** | Si todos los procesos arrancan dentro del mismo segundo, sus semillas (`seed_base + id_proceso`) son números consecutivos (ej. 1000000, 1000001, 1000002...). En un generador congruencial lineal, semillas consecutivas pueden producir secuencias correlacionadas al inicio, sesgando la independencia estadística entre procesos. |
| **Causa raíz** | Combinar la semilla base y el rank mediante una simple suma preserva la cercanía numérica entre semillas de procesos vecinos. |
| **Cómo se detectó** | Revisión de diseño, al analizar la calidad estadística del generador de números aleatorios usado (`rand_r`) en un contexto paralelo. |
| **Solución aplicada** | Hashing multiplicativo: la semilla de cada proceso se calcula como `seed_base + (id_proceso * CONSTANTE_PRIMA_GRANDE)`, usando una constante cercana a $2^{32}/\varphi$ (constante de Knuth), que dispersa semillas consecutivas en todo el espacio de 32 bits en vez de dejarlas contiguas. |
| **Cómo se verifica** | Instrumentación con `-DDEBUG_SEEDS`: imprime, para cada rank, la semilla que habría dado la fórmula vieja junto a la que efectivamente usa la fórmula nueva. |

**Resultado real obtenido:** con $P=4$, la fórmula vieja produjo semillas consecutivas (1789939527, 1789939528, 1789939529, 1789939530), mientras que el hashing multiplicativo las dispersó por todo el rango de 32 bits (1789939527, 149407992, 2803843753, 1163312218) — el rank 0 coincide en ambas fórmulas porque el desplazamiento es matemáticamente nulo ($0 \times \text{constante} = 0$), caso esperado. Se confirma la corrección a nivel de la semilla en sí, sin necesidad de que la probabilidad final agregada cambie de forma visible — para una tarea tan simple (comparar dos números al azar entre 0 y $M-1$), esa probabilidad no sería un indicador confiable de esta mejora en particular (`diagnostico/resultados/problema2_mac.txt`).

#### Problema #3: Portabilidad de `rand_r` entre toolchains

> **Estado final:** superado. La causa (falta de `rand_r` en MinGW-w64/Windows) ya no aplica al alcance final, y la migración a `rand()` fue reemplazada a su vez por un generador propio (Problema #5). Se conserva como registro del diagnóstico.

| Campo | Detalle |
|---|---|
| **Síntoma esperado** | Error de compilación (`undefined reference` o `implicit declaration`) si el toolchain de gcc usado en la notebook Windows no provee `rand_r`, ya que es una función POSIX/BSD, no parte del estándar C ni siempre incluida en runtimes de Windows. |
| **Causa raíz** | `rand_r` depende de la biblioteca de tiempo de ejecución (libc) del sistema, no del compilador en sí — dos instalaciones de gcc en el mismo sistema operativo pueden diferir en esto según el runtime que usen por detrás. |
| **Cómo se detectó** | Anticipado durante la revisión de portabilidad multiplataforma, antes de intentar compilar en Windows. |
| **Solución aplicada** | Confirmada la falla real (ver abajo), se decide **migrar de `rand_r()` a `rand()`/`srand()`** en la versión final, en vez de trabajar alrededor del problema con WSL. Es una función 100% estándar de C, disponible en cualquier toolchain, y en este diseño es igualmente segura: cada proceso MPI tiene su propia memoria y su propio estado global — no hay hilos compartiendo el generador, como sí habría que cuidar con OpenMP. Esto resuelve el Problema #3 de raíz para las tres arquitecturas, en vez de dejarlo condicionado a usar WSL únicamente en Windows. |
| **Cómo se verifica** | Ejecutar `check_rand_r_toolchain.c` en la notebook Windows y registrar si compila o no, y con qué mensaje de error en caso de falla. |

**Resultado real obtenido — CONFIRMADO:** la compilación en la notebook Windows falló exactamente con el síntoma predicho:

```
check_rand_r_toolchain.c:29:17: warning: implicit declaration of function 'rand_r'
undefined reference to `rand_r'
collect2.exe: error: ld returned 1 exit status
```

(`diagnostico/resultados/problema3_windows.txt`). El toolchain identificado (MinGW-w64 vía Git Bash, a juzgar por `collect2.exe` y la ruta de archivos temporales de Windows) efectivamente no provee `rand_r`. La corrida de control en Mac (`diagnostico/resultados/problema3_control_mac.txt`) confirma que ahí sí está disponible — contraste que valida la causa raíz (dependencia de la libc del sistema, no del compilador).

**Nota posterior (Problemas #2 y #5):** el hashing de 32 bits fue diseñado para `rand_r`/`rand()`. Con ese generador todos los procesos recorren un único ciclo de $2^{31}-2$ valores y el hash solo mueve el punto de partida; con $N=10^9$ (93 % del ciclo) los streams de distintos ranks se solapan (≈1,3 a 1,5 llamadas por valor distinto para $P \ge 2$, por cobertura esperada con arranques aleatorios). En la versión final cada rank deriva su estado de 64 bits con `splitmix64` y el solapamiento deja de ser un riesgo práctico.

#### Problema #4: Balanceo de Carga sin Reparto de Resto

| Campo | Detalle |
|---|---|
| **Síntoma esperado** | Si se reparte $N$ simulaciones entre $P$ procesos con división entera simple ($N/P$), descartando el resto, la suma de lo que realmente ejecuta cada proceso resulta **menor a $N$** cada vez que $N$ no es múltiplo exacto de $P$ — se pierden hasta $P-1$ simulaciones en silencio, sin ningún aviso ni error. |
| **Causa raíz** | `iteraciones_locales = n / p;` en cada proceso, sin distribuir el resto (`n % p`) entre ninguno de ellos. |
| **Cómo se detectó** | Revisión de diseño, al plantear la lógica de reparto de trabajo antes de escribir el simulador completo — no requirió reproducirse con MPI real, ya que es un problema de aritmética pura. |
| **Solución aplicada** | Los primeros ($n \bmod p$) procesos reciben una iteración extra (`base + resto`), tal como ya está implementado en el simulador real desde la primera versión (`monty_hall_v1_naive.c` en adelante). |
| **Cómo se verifica** | Programa de demostración aislado (`demo_balanceo_carga.c`, sin MPI), que compara el reparto ingenuo contra el corregido para varios pares $(N, P)$. |

**Resultado real obtenido:**

| $N$ | $P$ | Ingenuo ($\lfloor N/P \rfloor \times P$) | Corregido | Perdidas |
|---|---|---|---|---|
| 17 | 5 | 15 | 17 | 2 |
| 100 | 3 | 99 | 100 | 1 |
| 1.000.000 | 7 | 999.999 | 1.000.000 | 1 |
| 10.000.000 | 8 | 10.000.000 | 10.000.000 | 0 |
| 2.200.000.000 | 3 | 2.199.999.999 | 2.200.000.000 | 1 |

Se incluyó a propósito el caso $N=10.000.000$, $P=8$, donde $N$ es múltiplo exacto de $P$: ahí no hay pérdida, confirmando que el bug depende exclusivamente del resto de la división y no aparece siempre. Para los tamaños de $N$ usados en el experimento real, la pérdida máxima posible es de $P-1$ simulaciones — estadísticamente insignificante frente a $N$ grande, pero corregirlo es una cuestión de exactitud algorítmica, no solo de impacto estadístico (`diagnostico/resultados/problema4_mac.txt`).

#### Problema #5: Sesgo sistemático de `rand() % puertas` (generador Park-Miller)

| Campo | Detalle |
|---|---|
| **Síntoma** | Con $N \ge 10^8$ el error absoluto deja de seguir $O(1/\sqrt{N})$ y se estanca en ≈ $4\times10^{-5}$. El error firmado es negativo en casi todas las corridas (con $N=10^9$: 100 de 100) y su media no depende de $P$. |
| **Causa raíz** | `rand()` de macOS es Park-Miller: $x' = 16807\,x \bmod (2^{31}-1)$. Escribiendo $x' = 16807\,x - k\,m$ con $k=\lfloor 16807\,x/m \rfloor \in [0,16806]$ y usando $16807\equiv 1$, $m\equiv 1 \pmod 3$, resulta $x'\equiv x-k \pmod 3$. Con $M=3$, `premio` y `eleccion` (dos llamadas consecutivas) coinciden cuando $k\equiv 0 \pmod 3$: 5603 de 16807 valores de $k$, es decir $1/3+2/50421$. Por lo tanto $P(\text{cambiar}) = 2/3 - 2/(3\cdot16807) = 0{,}6666627$: un sesgo de $-3{,}97\times10^{-5}$, constante (no depende de $N$, $P$ ni de la semilla). El desplazamiento de $-1$ que aplica la libc BSD a la salida no altera la comparación de residuos. |
| **Cómo se detectó** | Al analizar el CSV de la Mac (notebook): la mediana del error no bajaba de $\approx 4\times10^{-5}$ para $N=10^9$. Revisar el signo del error firmado por corrida mostró el sesgo, y la hipótesis anterior (agotamiento del período, Sección 5.3) quedó descartada. |
| **Solución aplicada** | Generador propio `splitmix64` (período $2^{64}$) con `% M` sobre 64 bits. Ver Sección 4. |
| **Cómo se verifica** | `diagnostico/harness_sesgo.c` (misma lógica del simulador, un proceso) con ≥ 8 semillas y $N=10^9$, comparando `do_rand` contra `splitmix64`; `diagnostico/ciclo_completo.c` para el recorrido exhaustivo del ciclo; y la corrida final v2 en Mac y clúster contra el CSV v1. |

**Resultado real obtenido:**

| Fuente ($N=10^9$, $M=3$) | Sesgo medio | Observación |
|---|---|---|
| Predicción analítica | $-3{,}97\times10^{-5}$ | $-2/(3\cdot16807)$ |
| Recorrido del ciclo completo (pares consecutivos) | $-3{,}966\times10^{-5}$ | `ciclo_completo.c` |
| CSV real v1, Mac (100 corridas, $P=1..8$) | $-4{,}06\times10^{-5}$ | 100 de 100 negativas, $t\approx-24$ |
| Harness con `do_rand` (8 semillas) | $-4{,}14\times10^{-5}$ | 8 de 8 negativas, $t\approx-27$ |
| Harness con `splitmix64` (8 semillas) | $+0{,}87\times10^{-5}$ | $t\approx+1{,}7$, compatible con 0 |
| Corrida final v2, Mac ($M=3,5,10,50$) | con $N=10^9$ (80 corridas por celda): $t=-0{,}11;\ 0{,}38;\ -0{,}11;\ 0{,}41$ | de 20 celdas $(M,N)$, 1 con $\lvert t\rvert>2$ (máx. 2,02; esperado ≈ 0,9) y ninguna $>3$; sin signo sistemático (11 de 20 medias positivas). Diferencias con $N=10^9$ (corridas combinadas): de $-1{,}8\times10^{-7}$ a $+5{,}3\times10^{-7}$; para $M=3$, IC 95 % $[-3{,}5;\,+3{,}1]\times10^{-6}$ (el sesgo anterior queda descartado por un factor ≈ 11) |
| Corrida final v2, clúster | con $N=10^9$ (40 corridas por celda): $t=-0{,}18;\ 0{,}78;\ -0{,}12;\ -0{,}59$ | 0 de 20 celdas con $\lvert t\rvert>2$ (máx. 1,55); sin signo sistemático (8 de 20 medias positivas); IC 95 % de $\bar z$ para $M=3$, $N=10^9$: $[-0{,}34;\,+0{,}28]$, frente a $\approx-2{,}7$ del sesgo anterior |

**Estado: cerrado.** Con el generador propio, la probabilidad empírica coincide con $(M-1)/M$ dentro del error estadístico para $M=3,5,10,50$ y hasta $N=10^9$, en la Mac y en el clúster (criterio $\lvert t\rvert<2$ cumplido en la celda más sensible, $M=3$ y $N=10^9$: $t=-0{,}11$ y $t=-0{,}18$). La única celda con $\lvert t\rvert>2$ (Mac, $M=3$, $N=10^8$, $t=+2{,}02$, signo opuesto al sesgo anterior) es compatible con el azar: $p\approx0{,}043$ y ≈ 59 % de probabilidad de observar al menos una así entre 20 celdas. Detalle en el notebook (Paso 6 y Paso 6.1b).

El sesgo también existe, mucho menor, para los otros valores de $M$ de la Fase 2 (recorrido del ciclo completo): $M=5$: $-4\times10^{-10}$; $M=10$: $-6{,}0\times10^{-6}$; $M=50$: $-1{,}2\times10^{-6}$. Es decir, el caso obligatorio $M=3$ era el más afectado. Salida guardada en `diagnostico/resultados/problema5_resultados.txt`. El CSV con el generador anterior se conserva como `resultados_mac_v1.csv` para documentar el antes y el después.

#### Problema #6: Semillas repetidas entre repeticiones (`time(NULL)`)

| Campo | Detalle |
|---|---|
| **Síntoma** | Las filas de una misma configuración $(N,P)$ a veces son idénticas. Resultados distintos sobre 80 filas por cada $N$: 15 ($10^5$), 16 ($10^6$), 19 ($10^7$), 47 ($10^8$), 80 ($10^9$). Las repeticiones cortas no aportan error independiente. |
| **Causa raíz** | La semilla base se obtenía con `time(NULL)` (resolución de 1 s), llamado por separado en cada rank y sin registrarse en el CSV. Las corridas que caen en el mismo segundo repiten la semilla, y ninguna corrida era reproducible. |
| **Cómo se detectó** | Análisis del CSV v1: cantidad de valores distintos de `victorias_cambiando` por celda $(N,P)$. |
| **Solución aplicada** | El rank 0 genera una semilla de 64 bits desde `clock_gettime` (nanosegundos), la difunde con `MPI_Bcast` y se imprime como columna `semilla`. |
| **Cómo se verifica** | En v2: 1600 semillas distintas en 1600 corridas (Mac) y 800 en 800 (clúster). **Cerrado.** |

#### Problema #7: Corridas superpuestas y sobresuscripción en el clúster

| Campo | Detalle |
|---|---|
| **Síntoma** | `run_experimento.sh` se lanzó dos veces en la misma terminal del clúster (PIDs 2738 y 16553) porque la primera parecía estancada. Las dos instancias corrían en paralelo y escribían en el mismo CSV. |
| **Causa raíz** | (1) El script no impedía instancias concurrentes: ambas competían por la cuota de 12 cores y falseaban los tiempos. (2) `nproc` informa 128 (nodo físico), no la cuota del contenedor (12), y Open MPI acepta $P$ mayor que la cuota sin advertencia (verificado con $P=13$); el riesgo de sobresuscripción solo se evitaba pasando `P_MAX` a mano. Parte de la lentitud percibida era esperable: con 30,1 ns por iteración en un core, una ronda completa lleva ≈ 6 min (≈ 1 h con 10 repeticiones). |
| **Cómo se detectó** | `pgrep`/`ps` y el script `diagnostico_cluster.sh`. Nota: durante cada corrida `ps` muestra un subproceso `bash` con el mismo comando que el script (la captura de salida con `$(...)`); no es una segunda instancia. |
| **Solución aplicada** | Lock de una sola corrida (`analisis/datos/.lock_corrida`, con verificación del PID); lectura de `cpu.max` del cgroup y tope de `P_MAX` (aborta si lo supera, salvo `PERMITIR_SOBRESUSCRIPCION=1`). Los datos de la corrida contaminada no se usan. |
| **Cómo se verifica** | Pruebas con MPI y cuota simulados: tope 128 → 12, rechazo de $P=13$, rechazo de una segunda instancia simultánea y liberación del lock. En el clúster real la corrida válida fue una única instancia y el CSV tiene las 800 filas esperadas (5 $N$ × 8 $P$ × 4 $M$ × 5 repeticiones); el lock no se ejercitó con una segunda instancia real, solo en simulación. |

### 5.2 Decisiones de Diseño Justificadas

Estas decisiones nunca partieron de una versión que fallara — se implementaron así desde el principio. Lo que corresponde documentar acá no es un diagnóstico, sino la justificación explícita de cada una.

#### Granularidad del registro (agregado vs. por simulación)

Se optó por una salida de datos agregada (una línea CSV por ejecución) en lugar de registrar cada simulación individualmente. El overflow del Problema #1 y la correlación del Problema #2 no dependen de ninguna simulación puntual — se observan comparando el valor de entrada/salida agregado contra lo esperado, no mirando fila por fila. Registrar miles de millones de iteraciones individuales generaría, además, un cuello de botella de E/S que contradice el diseño de datos sintéticos en memoria adoptado desde el inicio.

#### Barrera previa a la medición (`MPI_Barrier`)

**Decisión:** se mantiene una única `MPI_Barrier` inmediatamente antes de `t_inicio = MPI_Wtime()`. No hay barreras dentro del algoritmo: cada proceso simula de forma independiente y solo se comunica en los dos `MPI_Reduce` finales.

**Qué se mide y qué no (modelo de la cátedra, $T = T_{proc} + T_{com} + T_{idle}$):**
- La región cronometrada incluye $T_{proc}$ (bucle de simulación), $T_{com}$ (los dos `MPI_Reduce`) y $T_{idle}$: como `t_fin` se toma después de la reducción, el rank 0 espera al proceso más lento y esa espera queda dentro del tiempo medido.
- La barrera está **fuera** de esa región: su costo no se suma a $T_p$ y no oculta $T_{idle}$.
- Lo que se excluye es el lanzamiento de procesos, `MPI_Init` y el desfase de arranque entre ranks. Por lo tanto, el speedup reportado es el de la **región paralela**, no el del programa completo (tiempo de pared).

**Por qué se mantiene:** como solo el rank 0 reporta tiempo, sin barrera su cronómetro arrancaría antes o después que el de los demás según el orden de arranque, y el sesgo puede ir en **cualquier sentido**: si arranca primero, mide de más (speedup menor); si arranca último, mide de menos (speedup **optimista**). La barrera fija un origen común. El sesgo residual es la dispersión con que los ranks salen de la barrera (del orden de microsegundos), despreciable frente al cómputo salvo con $N=10^5$ ($T_p\approx0{,}3$ ms), valor que ya se descartó para juzgar escalabilidad.

**El overhead observado no proviene de la barrera ni de la comunicación.** Con los datos v1 de la Mac ($N=10^9$), el overhead $T_p - T_1/P$ va de 0,17 s ($P=2$) a 0,48 s ($P=8$), y con $P=8$ crece ≈ 8,5 veces al pasar de $N=10^8$ (0,056 s) a $N=10^9$ (0,476 s). Una barrera o una reducción cuestan microsegundos a milisegundos, independientes de $N$; un overhead que crece con el trabajo es compatible con $T_{idle}$ por heterogeneidad (el reparto equitativo de *iteraciones* no equivale a un reparto equitativo de *tiempo* entre P-cores y E-cores). No permite separar ese efecto de otros que también crecen con $N$ (frecuencia por núcleo, térmicos); para eso harían falta tiempos por rank. Con los datos v2 (Mac, $M=3$, $N=10^9$), el overhead pasa de 0,026 s con $P=4$ a 0,25 s con $P=8$, y con $P=8$ vuelve a crecer en proporción a $N$ (0,031 s con $N=10^8$ y 0,248 s con $N=10^9$, ≈ 7,9 veces), lo que confirma la conclusión. En el clúster (Experimento 3, Sección 6.3), con $P=28$ el overhead medido es de 43 a 57 µs para $N=10^4$ a $10^6$ y de 4,5 ms con $N=10^9$ (0,4 % de $T_p$), unas 55 veces menos que los 0,25 s de la Mac con $P=8$ y $N=10^9$: ni la barrera ni la reducción explican la meseta de la Mac.

**Verificación no realizada (requisito futuro, no bloqueante):** la prueba con y sin barrera **no se ejecutó**; esta justificación se apoya en el razonamiento y en los datos anteriores, no en una medición directa. Procedimiento previsto:
1. Condicionar la barrera con una variable de entorno (`if (getenv("MH_SIN_BARRERA") == NULL) MPI_Barrier(MPI_COMM_WORLD);`), correr en Mac con etiqueta `mac_sinbarrera` y comparar medianas **y dispersión** (IQR) del speedup. Expectativa, no medida: sin diferencia sistemática con $N$ grande y mayor dispersión sin barrera con $N$ chico.
2. Calcular el speedup con tiempo de pared (`/usr/bin/time -p mpirun ...`) para cuantificar el costo de lanzamiento que la región cronometrada excluye.

#### Eliminación de la barrera posterior a `MPI_Reduce`

El código mantiene la barrera previa al cómputo (necesaria para que todos los procesos arranquen el cronómetro desde el mismo punto de partida), pero elimina la barrera posterior a la reducción. Aunque `MPI_Reduce` no es, en sentido estricto del estándar, una operación de sincronización global garantizada, en la práctica el proceso raíz no puede salir de la reducción con el valor final correcto hasta recibir (directa o transitivamente) la contribución de todos los procesos. Como el tiempo se mide y reporta únicamente en el rank 0, y ese rank ya queda bloqueado dentro de `MPI_Reduce` esperando al proceso más lento, una barrera adicional después no cambia el número medido — solo agrega sincronización global redundante.

#### `MPI_Reduce` vs. `Send`/`Recv` manual

Para consolidar los contadores locales de victorias en el proceso raíz, se descartó implementar un bucle manual de `MPI_Send`/`MPI_Recv`. Esa alternativa obligaría al raíz a recibir los $P-1$ mensajes de forma secuencial (costo de comunicación $O(P)$), y agregaría superficie de error por posibles *deadlocks* si el orden de envío/recepción no coincide entre procesos. `MPI_Reduce` resuelve el mismo problema delegando en la implementación de MPI un patrón de comunicación jerárquico (típicamente en árbol, como el de la teoría de la cátedra), con complejidad $O(\log P)$ y sin riesgo de interbloqueo por diseño propio. Queda como verificación pendiente, opcional y no bloqueante, medir esta diferencia empíricamente en el clúster (donde $P$ grande la haría más perceptible) implementando una variante con `Send`/`Recv` manual solo a fines comparativos.

#### Bandera de optimización del compilador: `-O2` en vez de `-O3`

Se evaluó explícitamente si subir a `-O3` (que habilita además *loop unrolling* agresivo y *loop peeling*, según `gcc -Q --help=optimizers`) mejoraría el rendimiento del núcleo de la simulación, dado que se trata de un bucle numérico intensivo. Se midió directamente en vez de asumirlo: compilando el mismo bucle con `-O0`, `-O2` y `-O3`, el tiempo por iteración se mantuvo estable en las tres (~37-38 ns/iteración), sin diferencia significativa. La causa: el cuello de botella no es aritmética vectorizable, sino la llamada a `rand()` de la libc, que mantiene estado interno global y contiene ramas de control — el propio compilador reporta explícitamente `"couldn't vectorize loop: control flow in loop"` y `"statement clobbers memory: rand()"` al pedirle el detalle de vectorización (`-fopt-info-vec-all`). Ni `-O2` ni `-O3` pueden vectorizar ni desenrollar de forma útil una llamada a función opaca con efectos colaterales. Se mantiene `-O2` por ser el estándar razonable para este nivel de código, sin costo de rendimiento medible frente a `-O3` en este caso puntual.

**Nota posterior (generador propio):** esta medición se hizo con `rand()`, una llamada opaca con estado global. Con `splitmix64` (inline, sin llamadas opacas) esa justificación ya no aplica textualmente, por lo que la comparación `-O2` vs. `-O3` debe repetirse con el código final. **Resultado** (Mac, $M=3$, $N=10^9$, 10 repeticiones por $P$; `resultados_mac_v2.csv` para `-O2` y `resultados_mac_v2_O3.csv` para `-O3`): el cociente $T_p^{-O3}/T_p^{-O2}$ queda entre 0,983 y 1,014 (diferencia máxima 1,72 %), sin signo consistente (con $P=1$, `-O3` es 0,6 % más lento) y del orden de la dispersión entre repeticiones; las curvas de speedup se superponen (meseta de ≈ 3,7 a 3,9 para $P>4$ en ambos casos). **Conclusión: `-O3` no produce una mejora medible; se mantiene `-O2`.** Alcance: solo Mac. Hipótesis (no verificada): el `% puertas` con divisor variable y la bifurcación `eleccion != premio` impiden una vectorización útil. La cifra de ~37-38 ns/iteración de la medición original no coincide con los ≈ 14,3 ns/iteración del CSV v1 a $P=1$ ($N\ge10^7$) y no se pudo identificar qué configuración produjo cada una, por lo que no se cita. Valores vigentes con $P=1$ (v2): ≈ 1,79 ns/iteración en la Mac y ≈ 30,1 ns en el clúster.

### 5.3 Propiedades Caracterizadas Empíricamente

#### Convergencia $O(1/\sqrt{N})$ del error de Monte Carlo

A diferencia de los Problemas #1 a #4, el error estadístico de Monte Carlo **no tiene solución** — es una propiedad matemática del método, no un bug de la implementación. Ningún cambio de código lo elimina; solo aumentar $N$ lo reduce, sin hacerlo desaparecer nunca del todo. Por eso este ítem no tiene una fila de "solución aplicada": lo que se hace es caracterizarlo con datos propios, modelando el experimento como ensayos de Bernoulli independientes.

Para una probabilidad verdadera $p=2/3$, el error estándar teórico de la estimación es:

$$SE = \sqrt{\frac{p(1-p)}{N}} \approx \sqrt{\frac{0{,}2222}{N}}$$

**Muestreo base ($N=10^6$, 5 corridas):** el error absoluto promedio observado fue $0{,}000560$. Para una distribución aproximadamente normal de desvío $SE$, el valor esperado del error absoluto es $SE \cdot \sqrt{2/\pi} \approx 0{,}000376$. El valor observado es algo mayor al esperado, pero con solo 5 muestras esa diferencia es perfectamente compatible con el azar — no hay evidencia de sesgo sistemático en esta escala.

**Corridas de gran escala ($N=2{,}2\times10^9$, dos ejecuciones independientes del Paso D de control del Problema #1):**

| Corrida | Error absoluto | Error / $SE$ teórico ($0{,}0000101$) |
|---|---|---|
| 1ra ejecución | $0{,}0000408$ | $4{,}06$ |
| 2da ejecución | $0{,}0000397$ | $3{,}93$ |

Un desvío de más de $4\sigma$ tiene una probabilidad de ocurrir por azar de aproximadamente 1 en 16.000 — infrecuente, pero no imposible en una corrida aislada. Que se repita dos veces, en ejecuciones independientes, con una magnitud tan similar, ya deja de ser explicable como pura casualidad (la probabilidad de que ambas superen los $3{,}9\sigma$ por azar es muchísimo menor que la de una sola).

**Hipótesis revisada (actualización del 29/09/2026):** la hipótesis de correlación entre procesos (Problema #2) se descarta explícitamente: ambas corridas usan $P=1$. La segunda hipótesis, agotamiento del período de `rand()` ($2^{31}-2$), también se **descarta** tras analizar el CSV completo de la Mac (Problema #5):

- el desvío aparece igual con $P=1,\dots,8$ (donde cada proceso consume una fracción mucho menor del período), y ya es visible con $N=10^8$ (≈9 % del período);
- el error firmado tiene **siempre el mismo signo** y una media constante, lo que corresponde a un **sesgo**, no a ruido ni a agotamiento;
- el valor de ese sesgo coincide con el calculado analíticamente: $-2/(3\cdot16807)=-3{,}97\times10^{-5}$.

Con un sesgo constante $b$, el cociente error/$SE$ crece como $\sqrt{N}$ (porque $SE$ baja y $b$ no):

| $N$ | $SE$ | $\lvert b\rvert/SE$ esperado | Observado |
|---|---|---|---|
| $10^8$ | $4{,}7\times10^{-5}$ | 0,84 | error firmado medio $-3{,}3\times10^{-5}$ (0,69 $SE$, CSV v1, 47 valores distintos) |
| $10^9$ | $1{,}49\times10^{-5}$ | 2,66 | $-4{,}06\times10^{-5}$ (2,72 $SE$, CSV v1, 100 corridas) |
| $2{,}2\times10^9$ | $1{,}0\times10^{-5}$ | 3,95 | 4,06 y 3,93 $SE$ (las dos corridas de diagnóstico de arriba) |

La simulación de la versión anterior de este documento (que reimplementaba `do_rand()`) era correcta y por eso reproducía el fenómeno; lo que resultó incorrecto fue su interpretación: el crecimiento del error/$SE$ con $N$ **no** refleja la fracción del período consumida, sino el cociente entre un sesgo fijo y un $SE$ decreciente.

**Por qué esto sí afectaba al experimento real:** el sesgo no depende de $N/P$ ni del número de procesos, por lo que contaminaba todas las corridas con $N\ge10^8$ de la barrida completa, y no solo el caso extremo de $P=1$. La corrección (generador propio, Sección 4) se valida en la corrida v2.

**Conclusión:** los datos propios confirman $O(1/\sqrt{N})$ mientras $SE$ sea mucho mayor que el sesgo (aprox. $N\lesssim10^8$). Más allá, con el generador anterior el error se estanca en ≈ $4\times10^{-5}$: efecto del sesgo del generador (Problema #5), no propiedad del método. Con el generador propio, la corrida v2 en Mac lo confirma cualitativamente: la mediana del error sigue $0{,}6745\,SE$ hasta $N=10^9$ para $M=3,5,10,50$ (cociente empírico/teórico entre 0,88 y 1,14, compatible con el ruido de una mediana de 80 valores, ≈ 13 %). La cuantificación formal mediante el test de sesgo por $(M,N)$ (Problema #5) lo confirma en Mac y clúster: ninguna celda con $\lvert t\rvert>3$ y, con $N=10^9$, $t$ entre $-0{,}59$ y $0{,}78$. La pendiente log-log no se ajustó explícitamente: la comparación es contra la curva $0{,}6745\,SE$.

## 6. Plan de Pruebas y Hardware

| Entorno | Arquitectura | Objetivo de la Prueba |
|---|---|---|
| Mac M1 | ARM (Heterogénea P-cores / E-cores) | Observar caídas de rendimiento al usar núcleos de eficiencia. |
| Clúster de la Facultad | AMD EPYC 7B12 (x86; 2 sockets × 64 cores, SMT = 1); nodo único en contenedor; corrida espejo con cuota de 12 cores (garantía 6) y Experimento 3 con 48 cores (192 GB) | Contrastar con un entorno de núcleos homogéneos y correr los experimentos de mayor escala. Sin red entre nodos: Open MPI usa memoria compartida. |

La notebook Windows (x86) quedó fuera del alcance (Sección 1). No se realiza comparación con una arquitectura simétrica; la Ley de Amdahl se contrasta con la curva de cada uno de los dos entornos.

> **Hipótesis arquitectónicas esperadas (a contrastar empíricamente):**
> - **Mac M1 (ARM Heterogéneo):** se anticipaba una caída de eficiencia cuando $P$ supere la cantidad de P-cores y MPI comience a asignar carga a los E-cores. *Resultado (v2, $M=3,5,10,50$):* eficiencia 0,90 a 1,00 hasta $P=4$ y caída abrupta en $P=5$ (0,38 a 0,75 según $N$). Con $N=10^9$, $S_4\approx3{,}78$ y $S_8\approx3{,}80$ ($E\approx0{,}48$ con $P=8$): los E-cores no aportan ganancia medible, y con $N\le10^8$ usar 8 procesos es más lento que usar 4. **$P=4$ es el punto óptimo.** En la v1 (con `rand()`) los E-cores sí aportaban ($S_8\approx6{,}3$). *Hipótesis (no probada):* con reparto estático $N/P$ el proceso del núcleo más lento fija el tiempo, y el bucle v2 (corto, con mucho paralelismo a nivel de instrucciones) penaliza más a los E-cores que el bucle v1 (limitado por la latencia de `rand()`). Karp-Flatt ($N=10^9$): fracción serial efectiva ≈ 0,02 para $P\le4$ y de 0,09 ($P=5$) a 0,16 ($P=8$). La causa exacta (desbalance vs. comunicación) sigue sin aislar: faltan tiempos por rank.
> - **Clúster de la Facultad (nodo único, núcleos homogéneos):** se esperaba escalado casi ideal mientras $P$ no supere la cuota de CPU. *Resultado (corrida espejo, $M=3,5,10,50$, $P\le8$, 5 repeticiones):* speedup prácticamente lineal y eficiencia ≈ 0,998 con $N=10^9$ (entre 0,94 y 0,99 con $N=10^5$), sin codo; $T_1\approx30{,}1$ s con $N=10^9$ (≈ 30 ns por iteración). El diagnóstico previo (nodo casi ocioso) había mostrado $E\approx0{,}99$ hasta $P=12$. Esto contrasta con la Mac y respalda la hipótesis de P-cores y E-cores. La hipótesis original de overhead de red **no aplica** (un solo nodo). La corrida llegó a $P=8$, por encima de los 6 cores garantizados, sin degradación visible; la carga del nodo durante la corrida no se registró. El Experimento 3 (Sección 6.3) extendió el barrido hasta $P=28$ con $E_p\approx0{,}996$ para $N=10^9$.

En los dos entornos se compilará y ejecutará con **gcc** (`mpicc -O2`), mismo código fuente. **Mecanismo de lanzamiento en el clúster** (diagnóstico del 01/10/2026, `diagnostico_cluster.sh`): JupyterHub (VS Code web) sobre Kubernetes, sin gestor de colas (no hay `sbatch` ni `srun`); `mpirun` directo (Open MPI 4.1.6), `gcc` 13.3 y Python 3.13. Recurso elegido: 12 cores (`cpu.max` = 12, garantía 6, memoria 48 GiB); `nproc` informa 128 (nodo físico). Open MPI acepta $P$ mayor que la cuota sin advertencia (verificado con $P=13$), por lo que `P_MAX` es obligatorio: el script V2 ya lo limita (Problema #7). Para $P$ hasta 28 (Experimento 3) se usó una sesión de 192 GB y 48 cores, la opción mínima que lo permite; no se registraron `cpu.max` ni la garantía de cores de esa sesión.

**Comparación cruzada** (notebook, Pasos 6.2 y 6.3; $N=10^9$, $M=3$): $T_1\approx1{,}79$ s en la Mac frente a ≈ 30,1 s en el clúster (la Mac es ≈ 17 veces más rápida por núcleo con este código; causa no medida, hipótesis de las divisiones de 64 bits en Zen 2); eficiencia con $P=8$: ≈ 0,47 en la Mac frente a ≈ 0,998 en el clúster; $P$ óptimo: 4 en la Mac y al menos 28 en el clúster (Experimento 3, Sección 6.3).

**Variables experimentales a barrer:**
1. Número de procesos $P$ (escalado fuerte, variable principal). Mac y corrida espejo del clúster: $P=1\dots8$; Experimento 3 (clúster): $P=1\dots28$ (Sección 6.3).
2. Tamaño del problema $N$ — ajustado empíricamente, sin valores fijos predefinidos.
3. Cantidad de puertas $M$ (Fase 2, confirmada — Sección 12): $M = 3, 5, 10, 50$.

### 6.1 Experimento descartado: costo de `int64_t` en el clúster

Se había planteado comparar `int64_t` contra el tipo nativo en el clúster. Con el alcance reducido deja de tener sentido: en Linux de 64 bits (LP64) `int64_t` **es** `long`, y en macOS es `long long`, ambos de 64 bits, con el mismo código máquina. La necesidad de `int64_t` era exclusivamente de portabilidad hacia Windows. Se descarta el experimento y se mantiene una única versión del código.

### 6.2 Diseño del barrido de $M$ (Fase 2)

- Se ejecuta `run_experimento.sh` una vez por cada valor de $M$ (3, 5, 10, 50), con el mismo barrido de $N$ y $P$, acumulando todo en el mismo CSV (la columna `M` distingue los casos). En el clúster se puede acotar con la lista de $N$ y el paso de $P$ del script.
- El objetivo de la Fase 2 es la **validación estadística** frente a $(M-1)/M$; el análisis de speedup se hace con $M=3$ (se supone que el costo por iteración no cambia con $M$; **verificado** en la Mac v2: con $N=10^9$, $T_1$ difiere menos de 0,25 % entre $M=3,5,10,50$ (1,7894; 1,7893; 1,7917; 1,7938 s) y el speedup difiere menos de ≈ 5 %).
- Criterio de validación por $(N,M)$: $z=(\hat p-p)/SE$ por corrida; se espera media de $z$ compatible con 0 y ≈ 95 % de las corridas con $\lvert z\rvert<2$. Se grafica $\hat p$ vs. $p$ por $M$ (barras) y el error normalizado vs. $N$.
- Con el generador anterior el sesgo era mayor en $M=3$ que en $M=5,10,50$ (Problema #5); con el propio se espera ausencia de sesgo en los cuatro casos.

### 6.3 Experimento 3 (fase B): barrido continuo de $P=1\dots28$ en el clúster

**Diseño.** `scripts/run_amdahl.sh` en una sesión de 192 GB de RAM y 48 cores (la opción mínima que permite $P=28$; la RAM no interviene). $N\in\{10^4,\dots,10^9\}$ × $P=1\dots28$ sin huecos (requisito de cátedra) × 3 repeticiones, con $M=3$, `-O2` y el mismo `monty_hall.c`: 504 corridas. El script escribe `amdahl_<fecha>.csv` (renombrado a `resultados_amdahl.csv`), usa la repetición como bucle exterior y registra un log y el conteo de filas. No tiene lock ni tope por cuota de CPU (se lanzó una sola vez); si se reutiliza, conviene incorporar las protecciones de `run_experimento.sh`.

**Integridad.** 504 filas, 168 combinaciones $(N,P)$ con 3 repeticiones cada una, sin nulos, 504 semillas distintas y victorias que suman $N$. Tasa $\lvert z\rvert<2$: 95,44 %; $t$ por $N$ entre $-0{,}75$ y $1{,}59$ (ninguno $>2$): sin evidencia de sesgo.

**Resultados** (mediana de las repeticiones):

| $N$ | $P^*$ observado | $S_p^*$ | $E_p$ con $P=28$ | Karp-Flatt $e(28)$ | Overhead con $P=28$ |
|---|---|---|---|---|---|
| $10^4$ | ≈ 15 (orientativo) | 8,0 | 0,20 | 0,147 | 43 µs |
| $10^5$ | 27 (orientativo) | 20,0 | 0,68 | 0,017 | 50 µs |
| $10^6$ | 28 | 26,6 | 0,95 | 0,0020 | 57 µs |
| $10^7$ | 28 | 27,6 | 0,987 | 0,0005 | 142 µs |
| $10^8$ | 28 | 27,9 | 0,995 | 0,0002 | 550 µs |
| $10^9$ | 28 | 27,9 | 0,996 | 0,00015 | 4,5 ms |

**Modelo del overhead.** Con $N=10^4$ y $10^5$, el overhead $T_p-T_1/P$ es casi el mismo y crece aproximadamente de forma lineal con $P$: ≈ 6,0 µs + 1,54 µs·$P$ ($R^2=0{,}82$). Con $T_p\approx T_1/P+c_0+\alpha P$ el óptimo es $P^*\approx\sqrt{T_1/\alpha}$: ≈ 14 para $N=10^4$ (observado: 15), ≈ 44 para $N=10^5$ y ≈ 140 para $N=10^6$ (estos dos, fuera del barrido). El modelo predice $S(28)$ de 5,06 frente a 5,63 observado ($-10\,\%$, $N=10^4$), 19,27 frente a 19,12 ($+0{,}8\,\%$, $N=10^5$) y 26,78 frente a 26,59 ($+0{,}7\,\%$, $N=10^6$, fuera de la muestra de ajuste).

**Lectura.** La parte no paralelizable es un costo de sincronización y reducción casi independiente de $N$ y creciente con $P$, y no una fracción fija del programa. Por eso la fracción secuencial efectiva se diluye al crecer $N$ ($e(28)$ de 0,147 a 0,00015), como predice Amdahl para una parte serial de tiempo aproximadamente fijo. Para $N\ge10^7$ el overhead es de 0,1 a 0,6 % de $T_p$ y no crece con $P$. En contraste con la Mac, donde con $P=8$ y $N=10^9$ el overhead fue de 0,25 s (Sección 5.2), el clúster escala casi linealmente hasta $P=28$ con el mismo código.

**Uso de recursos.** El tiempo de cómputo medido suma ≈ 6,6 min (≈ 0,78 core-horas); la reserva fue de 48 cores durante la sesión.

**Limitaciones.** (1) 3 repeticiones por punto y reloj de 1 µs: los $P^*$ de $N\le10^5$ son orientativos (con $N=10^4$ los tiempos son de 32 a 60 µs). (2) Con $N=10^6$ y $P$ bajos, el overhead queda tapado por la dispersión entre repeticiones y solo se mide con $P$ alto. (3) No se registraron `cpu.max`, la garantía de cores de esa sesión ni la carga del nodo; por analogía con la sesión de 12 cores (garantía 6) sería 24, no verificado, y con $P=28$ no hubo degradación visible. (4) El overhead agrupa la barrera, la reducción y el desfase de arranque de los procesos, que no se pueden separar. (5) El modelo es una hipótesis ajustada a medianas.

## 7. Verificación de Toolchain

Se compiló y ejecutó un programa mínimo que solo llama a `rand_r` (Problema #3): falla en la notebook Windows (MinGW-w64 vía Git Bash), funciona en Mac. **Estado final:** el simulador ya no usa `rand_r()` ni `rand()`, sino un generador propio en C estándar (Sección 4), por lo que no hay dependencia del toolchain para la generación de números aleatorios. Esta verificación queda como registro histórico.

## 8. Metodología de Medición y Validación Estadística

- **Escalado Fuerte (Strong Scaling — Ley de Amdahl):** prueba principal, $N$ fijo, variando $P$.
- **Escalado Débil (Weak Scaling — Ley de Gustafson):** prueba opcional.
- **Toma de Tiempos:** exclusivamente alrededor del bucle de cómputo y las reducciones (pasos 4 a 7 de la Sección 4.1).
- **Repeticiones y Mediana:** 10 corridas como mínimo por configuración. Para el cálculo del *speedup* ($S_p = T_1/T_p$), se utilizará estrictamente la **mediana estadística** de las ejecuciones, descartando picos de retraso anómalos atribuibles a factores externos del sistema operativo (ruido de fondo, *throttling* térmico, latencia de red).
- **Validación contra la teoría:** probabilidad empírica $\hat{p}_{cambiar} = \text{victorias\_cambiando}/N$, probabilidad teórica $(M-1)/M$, y error absoluto entre ambas, calculados en C y exportados al CSV. Ver Sección 5.3 para la caracterización empírica de cómo converge este error con $N$.
- **Independencia y registro de semillas:** cada corrida usa una semilla distinta, registrada en el CSV (Problema #6). Las repeticiones son, por lo tanto, estadísticamente independientes.
- **Versiones de datos:** `resultados_mac_v1.csv` (generador anterior, 9 columnas) se conserva como evidencia del Problema #5; la versión final (10 columnas, con `semilla`) se guarda en `resultados_mac_v2.csv` (`-O2`) y `resultados_mac_v2_O3.csv` (`-O3`). El script V2 aborta si el encabezado de un archivo existente no coincide, por lo que no se mezclan versiones. El notebook debe agrupar por $(M,N,P)$ y no suponer $M$ único.
- **Repeticiones:** Mac, 10 por $(M,N,P)$; clúster, 5 (dispersión < 1 % en el diagnóstico). Las medianas son comparables, pero los datos del clúster tienen menos muestras para el error.
- **Test de sesgo:** para cada $(N,M)$, media del error firmado sobre las repeticiones distintas y estadístico $t=\bar e\,\sqrt{n}/SE$ (aproximado, pues comparten generador).

## 9. Limitaciones Identificadas

- **Error estadístico del método de Monte Carlo:** converge con error de orden $O(1/\sqrt{N})$ — caracterizado con datos propios en la Sección 5.3.
- **Generador de números aleatorios:** `splitmix64` es un generador de propósito general, no criptográfico, sin garantías estadísticas tan estudiadas como otros (p. ej. `xoshiro256**` o Random123, Salmon et al. 2011, en la bibliografía); se valida empíricamente (Problema #5, corrida v2). El generador anterior (`rand()` de la libc) se descartó por su sesgo.
- **Sesgo de módulo:** con `% M` sobre 64 bits es ≈ $5\times10^{-20}$, despreciable para los valores de $M$ usados.
- **Comparación de tiempos entre arquitecturas:** solo tiene sentido comparar la forma de la curva de speedup por sistema, no los tiempos absolutos entre sistemas distintos.
- **Alcance de plataformas:** solo Mac M1 y clúster. El clúster (homogéneo, un solo nodo) sirve de contraste con la Mac heterogénea, pero no se mide comunicación entre nodos.
- **Origen del codo en $P=5$ (Mac):** sin tiempos por rank no se puede atribuir con certeza a desbalance por E-cores frente a costo de comunicación; los datos v2 (speedup plano entre $P=4$ y $P=8$ y overhead proporcional a $N$) son consistentes con desbalance. La explicación por paralelismo a nivel de instrucciones es una hipótesis no probada.
- **Costo por iteración en el clúster:** 30,1 ns con un core (diagnóstico, $N=10^8$) frente a 1,79 ns en la Mac v2 (≈ 17 veces). Hipótesis, no medida: las dos divisiones de 64 bits de `% puertas` son lentas en Zen 2 y rápidas en el M1. Prueba opcional, sin tocar el experimento: una variante sin divisiones y comparar $T_1$.
- **Cuota de CPU del clúster:** garantía de 6 cores y tope de 12. Las medidas del diagnóstico se tomaron con el nodo casi ocioso (carga 0,16) y en la corrida espejo no se registró la carga; con $P\le8$ no hubo degradación visible. Conviene registrar `uptime` al iniciar cada corrida. En el Experimento 3 (48 cores) no se registró la garantía de cores ni la carga del nodo; con $P=28$ no hubo degradación visible.
- **Orden de las corridas:** en la v1 las repeticiones de cada configuración eran consecutivas y $P=1$ abría cada bloque de $N$, lo que podía asociar el estado térmico y de frecuencia a una sola configuración. El script V2 pone la repetición como bucle exterior, lo que mitiga este efecto (no se verificó empíricamente).
- **Barrera previa sin verificación empírica:** la decisión de mantener `MPI_Barrier` antes del cronómetro se justifica por razonamiento y por los datos v1 (Sección 5.2), pero la prueba con y sin barrera no se ejecutó. El speedup reportado es el de la región paralela y excluye el lanzamiento de procesos.
- **Potencia del test de sesgo:** con $n=80$ (Mac) y $n=40$ (clúster) corridas por celda $(M,N)$, el test no descarta sesgos menores que ≈ $3\times10^{-6}$ (Mac, $M=3$, $N=10^9$, IC 95 %); sí descarta el sesgo del generador anterior ($-4\times10^{-5}$) por un factor ≈ 11. En el clúster detecta $\bar z\gtrsim0{,}5$. Además, con 20 celdas por plataforma es esperable ≈ 1 resultado con $\lvert t\rvert>2$ por azar.
- **Experimento 3:** 3 repeticiones por punto y reloj de 1 µs; los $P^*$ de $N\le10^5$ son orientativos y el modelo del overhead está ajustado a medianas con $R^2=0{,}82$ (Sección 6.3).
- **Supuesto sobre la regla del presentador:** válido para la variante "abre todas las puertas salvo una"; la variante alternativa queda fuera de alcance salvo indicación contraria de la cátedra (Sección 12).

## 10. Próximos Pasos (orden de prioridad, por etapas)

**Etapa de diagnóstico — cerrada:**

1. ✅ Consultar con la cátedra los puntos pendientes de la Sección 12.
2. ✅ Verificación de toolchain (Sección 7) — falla confirmada en Windows, `rand_r` no disponible.
3. ✅ Implementar la versión ingenua del simulador (`monty_hall_v1_naive.c`).
4. ✅ Reproducir el Problema #1 (overflow) en la notebook Windows — confirmado con `check_long_size.c`.
5. ✅ Corregir y observar el Problema #2 (semillas) en `monty_hall_v2_seed_fix.c`.
6. ✅ Diagnosticar y corregir el Problema #4 (balanceo de carga), con `demo_balanceo_carga.c`.
7. ✅ Confirmar la falla del Problema #3 (`rand_r`) en Windows y decidir la migración a `rand()`/`srand()`.
8. ✅ Verificar a mano, con $N$ chico, que el resultado sea consistente con $M=3 \Rightarrow p \approx 2/3$.

**Etapa de versión final y experimento — en curso:**

9. ✅ Versión 1 del simulador con las cuatro correcciones iniciales (`int64_t`, hashing de semilla, `rand()`, balanceo con resto), compilada con `-O2`. Sus datos (`resultados_mac_v1.csv`) se conservan como evidencia.
10. ✅ Script de automatización `run_experimento.sh`: barrido de $N$ y de $P$ (todos los enteros de 1 al máximo de núcleos), 10 repeticiones por combinación.
11. ✅ Escalado fuerte v1 corrido en Mac M1 y analizado (notebook). **Windows: fuera del alcance.**
12. ✅ **Versión final (v2) del simulador** (`src/monty_hall.c`): `splitmix64` en vez de `rand()` (Problema #5), semilla de 64 bits difundida y registrada (Problema #6), salida con 10 decimales; compilada con `mpicc -O2` por el script. La prueba corta previa ($P=1,4$, $N=10^6$, $M=3,5$) no se ejecutó como paso separado; la verificación equivalente se hizo en el notebook: 1600 semillas distintas en 1600 corridas (Mac) y 800 en 800 (clúster).
13. ✅ (ya no necesario) Mover el CSV de la v1: el script V2 escribe en `resultados_mac_v2.csv` (y `_O3`), no toca la v1 y aborta ante un encabezado distinto. Renombrar la v1 a `resultados_mac_v1.csv` queda solo por claridad.
14. ✅ **Ejecutado en Mac:** `bash scripts/run_experimento.sh "" 3,5,10,50` ($M=3,5,10,50$, barrido completo de $N$ y $P$, salida `resultados_mac_v2.csv`) y `bash scripts/run_experimento.sh "" 3 10 1 "" -O3` ($M=3$, salida `resultados_mac_v2_O3.csv`). ✅ **Analizado en el notebook (Mac v2):** escalado fuerte, $T_1$ por $M$ (supuesto de la Sección 6.2 verificado) y convergencia del error. ✅ **Completado:** test formal de sesgo por $(M,N)$ (Problema #5), barras empírico vs. teórico con $N=10^9$, `-O2` vs. `-O3` (sin mejora; Sección 5.2) y comparación v1 vs. v2.
14 bis. ⏳ **(Futuro, no bloqueante)** Prueba con y sin `MPI_Barrier` y comparación con tiempo de pared: no ejecutada; justificación y procedimiento en la Sección 5.2.
15. ✅ Acceso y mecanismo de lanzamiento documentados (Sección 6). Script adaptado (lock de instancia única y tope por cuota; Problema #7). ✅ Corrida espejo ($M=3,5,10,50$, $P\le8$, 5 repeticiones, 800 filas) ejecutada, analizada y validada (Sección 6, Problemas #5 y #6). ✅ La fase B se realizó como Experimento 3 (Sección 6.3): barrido continuo $P=1\dots28$ y $N=10^4\dots10^9$. Opcionales no realizados: grilla reducida para $M\ne3$ y $N$ mayores que $10^9$.
16. ✅ Notebook completado: agrupa por $(M,N,P)$, incluye `semilla`, speedup, eficiencia y convergencia, test de sesgo por $(M,N)$ para Mac y clúster, comparación `-O2` vs. `-O3`, Amdahl y Karp-Flatt (M = 3), comparación v1 vs. v2 y comparación Mac vs. clúster; se eliminaron las salidas viejas y se corrigieron las interpretaciones. Experimento 3 incorporado (Pasos A1 a A6): speedup, eficiencia, modelo del overhead, Karp-Flatt y validación estocástica del barrido.
17. ✅ Campos pendientes de los Problemas #5, #6 y #7 y de la Sección 5.3 completados con los resultados de la Mac y del clúster.
18. Redactar conclusiones y recomendaciones de mejora, incluyendo la Bitácora. Mejora futura documentada: generador con saltos garantizados sin solapamiento (`xoshiro256**` con `jump`, Random123). Mejora futura adicional: reparto ponderado o dinámico entre núcleos heterogéneos; con $S_8\approx3{,}8$ y reparto estático, un reparto proporcional a la velocidad de cada núcleo podría acercar $S_8$ a ≈ 5,9 (**estimación**, supone un E-core ≈ 2,1 veces más lento).
19. Subir código (incluyendo la versión ingenua junto a la corregida y la carpeta `diagnostico/`), scripts (`run_experimento.sh`, `run_amdahl.sh`, `diagnostico_cluster.sh`), datos v1, v2 y `resultados_amdahl.csv`, gráficos y README al repositorio.
20. (Opcional) Armar un PDF del proyecto a partir del README y la documentación generada.

**Cronograma sugerido (7 días):**

| Día | Actividad |
|---|---|
| 1 | Ítems 12 a 14: código final, prueba corta y barrido $M=3$ en Mac. |
| 2 | Fase 2 en Mac ($M=5,10,50$) y actualización del notebook (ítem 16). |
| 3 a 4 | Clúster: acceso, adaptación del script y corridas (ítem 15). |
| 5 | Análisis y gráficos finales (✅ completado). |
| 6 | Informe, README y repositorio. |
| 7 | Margen. |

## 11. Bibliografía

- Salmon, J. K.; Moraes, M. A.; Dror, R. O.; Shaw, D. E. (2011). *Parallel Random Numbers: As Easy as 1, 2, 3*. SC11 (Best Paper). https://www.thesalmons.org/john/random123/papers/random123sc11.pdf
- Lowery, B. (2022). *The Monty Hall problem and its generalisations (Part 2)*. STOR-i, Lancaster University. https://www.lancaster.ac.uk/stor-i-student-sites/ben-lowery/2022/04/the-monty-hall-problem-and-its-generalisations-part-2/
- IB Maths Resources (2023). *The Monty Hall Problem – Extended*. https://ibmathsresources.com/2023/11/01/the-monty-hall-problem-extended/
- Gropp, W.; Lusk, E.; Skjellum, A. *Using MPI: Portable Parallel Programming with the Message-Passing Interface*. MIT Press.
- Grama, A.; Gupta, A.; Karypis, G.; Kumar, V. *Introduction to Parallel Computing*. Addison-Wesley.
- MPI Tutorial (Wes Kendall). https://mpitutorial.com/tutorials/
- LLNL HPC Tutorials — Message Passing Interface (MPI). https://hpc-tutorials.llnl.gov/mpi/

## 12. Puntos Pendientes de Confirmación con la Cátedra

- ✅ **Alcance de la generalización:** la generalización a $M$ puertas (Fase 2, Sección 2.2) fue **confirmada** como parte del trabajo; se barren $M=3,5,10,50$ (Sección 6.2).
- ❓ **Variante del presentador que abre una sola puerta:** sin confirmación; se mantiene fuera de alcance (Sección 2.2).
- ❓ **Plataformas:** confirmar que Mac M1 + clúster son suficientes (la notebook Windows quedó fuera por razones logísticas del grupo) y que la evidencia de Windows (Problemas #1 y #3) puede presentarse como diagnóstico.
- ✅ **Acceso al clúster de la Facultad:** acceso obtenido. Falta documentar el mecanismo de lanzamiento (Sección 6).

## 13. Registro de cambios

| Fecha | Cambio |
|---|---|
| 03/10/2026 | Experimento 3 (fase B) incorporado (Sección 6.3): barrido continuo $P=1\dots28$ en el clúster (504 corridas, 192 GB / 48 cores), $E_p\approx0{,}996$ con $N=10^9$, modelo del overhead (≈ 6 µs + 1,54 µs·$P$, $R^2=0{,}82$) y validación estocástica sin sesgo. Se actualizan las Secciones 5.2, 6, 9 y 10 (ítems 15, 16 y 19). |
| 03/10/2026 | Resultados experimentales cerrados: test de sesgo por $(M,N)$ en Mac y clúster (Problema #5 cerrado; $t=-0{,}11$ y $-0{,}18$ con $M=3$, $N=10^9$), semillas únicas (Problema #6 cerrado), `-O3` sin mejora (se mantiene `-O2`; Sección 5.2), corrida espejo del clúster (eficiencia ≈ 0,998; $T_1\approx30{,}1$ s) y comparación cruzada (Sección 6). Se actualizan las Secciones 5.1, 5.2, 5.3, 6, 9 y 10 (ítems 14 a 17 completados). Se retira de la Sección 5.2 la cifra de 37-38 ns/iteración, no reproducible. |
| 03/10/2026 | Resultados de la Mac v2 incorporados: escalado fuerte ($P=4$ óptimo, $S_4\approx S_8$ con $N=10^9$), convergencia del error sin plateau (Problema #5 y Sección 5.3), $T_1$ por $M$ verificado (Sección 6.2) y evidencia v2 del overhead (Sección 5.2). Diagnóstico del clúster documentado (nodo único, cuota 12 / garantía 6, EPYC 7B12; Sección 6) y nuevo Problema #7 (corridas superpuestas y sobresuscripción). Se actualizan las Secciones 8, 9 y 10 (ítems 14 a 18). |
| 30/09/2026 | Ítems 12 a 14 de la Sección 10 actualizados (corridas $M=3,5,10,50$ y `-O3` ejecutadas en Mac; análisis pendiente). Agregada la justificación de `MPI_Barrier` (Sección 5.2) con la prueba con y sin barrera como requisito futuro no ejecutado; corregida la descripción de las limitaciones (orden de corridas, barrera) y los nombres de los CSV de la v2. |
| 29/09/2026 | Fase 2 confirmada (Secciones 1, 2.2, 6.2, 12). Alcance reducido a Mac M1 + clúster: se descarta el experimento de la Sección 6.1 y se marcan como superados los Problemas #1 y #3. Nuevo Problema #5 (sesgo de `rand() % M`) y Problema #6 (semillas repetidas); se corrige la Sección 5.3, cuya conclusión anterior (agotamiento del período) queda reemplazada. Se reemplaza `rand()` por `splitmix64` y se actualizan Secciones 4, 5.2, 6 a 10 y 12. Se corrige la descripción del flujo (Sección 4.1): no hay segunda barrera y hay dos `MPI_Reduce`. |