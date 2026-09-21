# Plan de Desarrollo: Proyecto 2 - Monty Hall (HPC)

## 1. Descripción General y Objetivos

El objetivo central del proyecto es utilizar la simulación masiva de eventos (método empírico de Monte Carlo) para verificar la frecuencia relativa de los resultados de la Paradoja de Monty Hall y validarlos contra la teoría probabilística. Se debe simular el concurso de puertas, evaluando el dilema matemático de si conviene mantener la elección inicial o cambiar de puerta luego de que el presentador abre una o más puertas incorrectas.

**Enfoque en dos fases:**
- **Fase 1 (obligatoria):** implementar y validar completamente el caso clásico de 3 puertas — es el foco principal exigido por la consigna.
- **Fase 2 (valor agregado, sujeto a confirmación con la cátedra — ver Sección 12):** generalizar a $M$ puertas, para enriquecer la validación estadística y demostrar la comprensión matemática del problema (Sección 2).

**Sobre el proceso de desarrollo:** la cátedra evalúa explícitamente cómo se diagnostican y resuelven problemas de HPC, no solo la corrección del resultado final. Por eso el desarrollo se plantea deliberadamente por etapas: primero una versión simple del simulador, luego el registro honesto de los problemas reales que aparezcan (o que ya se anticiparon durante el diseño, ver Sección 5), y recién después las versiones corregidas — dejando esa evolución documentada en el repositorio en vez de entregar solo la versión final "prolija".

**Limitaciones que se reconocen de antemano** (ampliadas en la Sección 9):
- El método de Monte Carlo da una estimación con error estadístico de orden $O(1/\sqrt{N})$; no es un resultado exacto sino asintótico.
- La calidad del generador de números pseudoaleatorios utilizado condiciona la validez estadística de las simulaciones a gran escala.
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

**Nota sobre variantes:** existe una variante alternativa en la que el presentador abre **una sola** puerta incorrecta sin importar cuántas puertas totales haya $M$. Da una fórmula distinta y **no es la implementada en este proyecto**; queda documentada para evitar ambigüedad en la defensa oral (Lowery 2022, IB Maths Resources 2023). Tanto el alcance de la generalización como esta variante quedan sujetos a lo que confirme la cátedra (Sección 12).

## 3. Arquitectura de la Solución

Dado que el problema es "embarazosamente paralelo" (cada iteración es independiente de las demás), se dividirá el desarrollo en dos capas:

- **Núcleo Computacional (C + MPI):** genera los números aleatorios, juega las partidas distribuyendo la carga entre procesos ($P$), calcula la validación estadística contra la teoría, y registra los tiempos de ejecución. Es la única capa que participa de la medición de rendimiento.
- **Capa de Visualización (Python):** mediante `pandas` y `matplotlib`, procesa los CSV generados por el simulador para producir gráficos de barras (probabilidades empíricas vs. teóricas), curvas de escalabilidad (Speedup) y el análisis de convergencia del error. No participa de la medición de tiempos.

**Justificación de Diseño:** esta separación estricta evita un antipatrón común en la medición de rendimiento computacional: mezclar el tiempo de generación de gráficos o post-procesamiento de datos (operaciones I/O bound) dentro de la toma de tiempos del código paralelo, lo cual contaminaría y degradaría artificialmente el *speedup* reportado.

## 4. Características del Código y Estructura de Datos

- **Flexibilidad (Parametrización):** número de simulaciones ($N$), cantidad de puertas ($M$) y semilla base opcional se ingresan mediante argumentos de línea de comandos.
- **Estructura de Datos (Datos Sintéticos):** generados al vuelo en memoria local de cada proceso, sin I/O a disco.
- **Reproducibilidad:** sin semilla especificada se usa la hora del sistema; con semilla fija se puede reproducir exactamente una corrida para depurar.
- **Balanceo de carga exacto:** reparto de base + resto entre procesos, evitando la pérdida silenciosa de iteraciones cuando $N$ no es múltiplo exacto de $P$ (Sección 5.1, Problema #4).
- **Independencia entre streams de proceso:** hashing multiplicativo de la semilla con el rank (Sección 5.1, Problema #2).
- **Portabilidad de tipos numéricos:** `int64_t` en vez de `long` (Sección 5.1, Problema #1) — con la salvedad de que su costo de rendimiento en el clúster se trata como hipótesis a verificar, no como un hecho (Sección 6.1).
- **Salida validada:** probabilidad empírica, probabilidad teórica y error absoluto calculados directamente en C.

### 4.1 Flujo de Ejecución del Simulador

1. **Inicialización de MPI:** cada proceso obtiene su rank y el tamaño del grupo (modelo SPMD).
2. **Lectura de parámetros:** cada proceso lee los mismos `argv` ($N$, $M$, semilla opcional).
3. **Balanceo de carga:** división entera más resto ($\lfloor N/P \rfloor$ por proceso, resto distribuido entre los primeros procesos).
4. **Sincronización previa a la medición:** barrera antes de arrancar el cronómetro.
5. **Cómputo local:** cada proceso sortea, para cada simulación local, la puerta premiada y la elegida; compara ambas para determinar victoria "cambiando" o "manteniendo".
6. **Reducción colectiva:** suma de los contadores locales de ambos tipos de victoria hacia el proceso raíz.
7. **Sincronización y cierre de medición:** segunda barrera, luego se detiene el cronómetro.
8. **Validación contra la teoría y exportación:** el proceso raíz calcula probabilidad empírica, teórica y error absoluto, y exporta una línea de resultados al CSV.
9. **Finalización:** cierre del entorno de MPI.

Solo hay comunicación en los pasos 4, 6 y 7 (dos barreras y una reducción de un valor), por lo que se espera overhead de comunicación marginal incluso a medida que crece $P$.

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

**Resultado real obtenido:** en Mac (arquitectura LP64, `long` de 64 bits), el valor parseado (2.200.000.000) coincidió exactamente con el tipeado, y la probabilidad convergió con normalidad — confirmando que en esta arquitectura el Problema #1 **no se manifiesta**, tal como predice la causa raíz. La corrida equivalente en la notebook Windows (Paso C) queda **pendiente**, a cargo del integrante del grupo con esa arquitectura; se documentará acá apenas esté disponible.

#### Problema #2: Correlación de semillas entre procesos (el "enemigo" de Monte Carlo)

| Campo | Detalle |
|---|---|
| **Síntoma esperado** | Si todos los procesos arrancan dentro del mismo segundo, sus semillas (`seed_base + id_proceso`) son números consecutivos (ej. 1000000, 1000001, 1000002...). En un generador congruencial lineal, semillas consecutivas pueden producir secuencias correlacionadas al inicio, sesgando la independencia estadística entre procesos. |
| **Causa raíz** | Combinar la semilla base y el rank mediante una simple suma preserva la cercanía numérica entre semillas de procesos vecinos. |
| **Cómo se detectó** | Revisión de diseño, al analizar la calidad estadística del generador de números aleatorios usado (`rand_r`) en un contexto paralelo. |
| **Solución aplicada** | Hashing multiplicativo: la semilla de cada proceso se calcula como `seed_base + (id_proceso * CONSTANTE_PRIMA_GRANDE)`, usando una constante cercana a $2^{32}/\varphi$ (constante de Knuth), que dispersa semillas consecutivas en todo el espacio de 32 bits en vez de dejarlas contiguas. |
| **Cómo se verifica** | Instrumentación con `-DDEBUG_SEEDS`: imprime, para cada rank, la semilla que habría dado la fórmula vieja junto a la que efectivamente usa la fórmula nueva. |

**Resultado real obtenido:** con $P=4$, la fórmula vieja produjo semillas consecutivas (1789939527, 1789939528, 1789939529, 1789939530), mientras que el hashing multiplicativo las dispersó por todo el rango de 32 bits (1789939527, 149407992, 2803843753, 1163312218) — el rank 0 coincide en ambas fórmulas porque el desplazamiento es matemáticamente nulo ($0 \times \text{constante} = 0$), caso esperado. Se confirma la corrección a nivel de la semilla en sí, sin necesidad de que la probabilidad final agregada cambie de forma visible — para una tarea tan simple (comparar dos números al azar entre 0 y $M-1$), esa probabilidad no sería un indicador confiable de esta mejora en particular.

#### Problema #3: Portabilidad de `rand_r` entre toolchains

| Campo | Detalle |
|---|---|
| **Síntoma esperado** | Error de compilación (`undefined reference` o `implicit declaration`) si el toolchain de gcc usado en la notebook Windows no provee `rand_r`, ya que es una función POSIX/BSD, no parte del estándar C ni siempre incluida en runtimes de Windows. |
| **Causa raíz** | `rand_r` depende de la biblioteca de tiempo de ejecución (libc) del sistema, no del compilador en sí — dos instalaciones de gcc en el mismo sistema operativo pueden diferir en esto según el runtime que usen por detrás. |
| **Cómo se detectó** | Anticipado durante la revisión de portabilidad multiplataforma, antes de intentar compilar en Windows. |
| **Solución aplicada** | Paso de verificación de toolchain (Sección 7): compilar un programa mínimo (`check_rand_r_toolchain.c`) que solo llama a `rand_r`, sin MPI, antes de invertir tiempo en el experimento completo. Si falla en Windows, la alternativa es correr esa parte sobre WSL. |
| **Cómo se verifica** | Ejecutar `check_rand_r_toolchain.c` en la notebook Windows y registrar si compila o no, y con qué mensaje de error en caso de falla. |

**Resultado real obtenido:** pendiente, a cargo del mismo integrante del grupo que completará el Problema #1.

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

Se incluyó a propósito el caso $N=10.000.000$, $P=8$, donde $N$ es múltiplo exacto de $P$: ahí no hay pérdida, confirmando que el bug depende exclusivamente del resto de la división y no aparece siempre. Para los tamaños de $N$ usados en el experimento real, la pérdida máxima posible es de $P-1$ simulaciones — estadísticamente insignificante frente a $N$ grande, pero corregirlo es una cuestión de exactitud algorítmica, no solo de impacto estadístico.

### 5.2 Decisiones de Diseño Justificadas

Estas tres decisiones nunca partieron de una versión que fallara — se implementaron así desde el principio. Lo que corresponde documentar acá no es un diagnóstico, sino la justificación explícita de cada una.

#### Granularidad del registro (agregado vs. por simulación)

Se optó por una salida de datos agregada (una línea CSV por ejecución) en lugar de registrar cada simulación individualmente. El overflow del Problema #1 y la correlación del Problema #2 no dependen de ninguna simulación puntual — se observan comparando el valor de entrada/salida agregado contra lo esperado, no mirando fila por fila. Registrar miles de millones de iteraciones individuales generaría, además, un cuello de botella de E/S que contradice el diseño de datos sintéticos en memoria adoptado desde el inicio.

#### Eliminación de la barrera posterior a `MPI_Reduce`

El código mantiene la barrera previa al cómputo (necesaria para que todos los procesos arranquen el cronómetro desde el mismo punto de partida), pero elimina la barrera posterior a la reducción. Aunque `MPI_Reduce` no es, en sentido estricto del estándar, una operación de sincronización global garantizada, en la práctica el proceso raíz no puede salir de la reducción con el valor final correcto hasta recibir (directa o transitivamente) la contribución de todos los procesos. Como el tiempo se mide y reporta únicamente en el rank 0, y ese rank ya queda bloqueado dentro de `MPI_Reduce` esperando al proceso más lento, una barrera adicional después no cambia el número medido — solo agrega sincronización global redundante.

#### `MPI_Reduce` vs. `Send`/`Recv` manual

Para consolidar los contadores locales de victorias en el proceso raíz, se descartó implementar un bucle manual de `MPI_Send`/`MPI_Recv`. Esa alternativa obligaría al raíz a recibir los $P-1$ mensajes de forma secuencial (costo de comunicación $O(P)$), y agregaría superficie de error por posibles *deadlocks* si el orden de envío/recepción no coincide entre procesos. `MPI_Reduce` resuelve el mismo problema delegando en la implementación de MPI un patrón de comunicación jerárquico (típicamente en árbol, como el de la teoría de la cátedra), con complejidad $O(\log P)$ y sin riesgo de interbloqueo por diseño propio. Queda como verificación pendiente, opcional y no bloqueante, medir esta diferencia empíricamente en el clúster (donde $P$ grande la haría más perceptible) implementando una variante con `Send`/`Recv` manual solo a fines comparativos.

### 5.3 Propiedades Caracterizadas Empíricamente

#### Convergencia $O(1/\sqrt{N})$ del error de Monte Carlo

A diferencia de los Problemas #1 a #4, el error estadístico de Monte Carlo **no tiene solución** — es una propiedad matemática del método, no un bug de la implementación. Ningún cambio de código lo elimina; solo aumentar $N$ lo reduce, sin hacerlo desaparecer nunca del todo. Por eso este ítem no tiene una fila de "solución aplicada": lo que se hace es caracterizarlo con datos propios, modelando el experimento como ensayos de Bernoulli independientes.

Para una probabilidad verdadera $p=2/3$, el error estándar teórico de la estimación es:

$$SE = \sqrt{\frac{p(1-p)}{N}} \approx \sqrt{\frac{0{,}2222}{N}}$$

**Muestreo base ($N=10^6$, 5 corridas):** el error absoluto promedio observado fue $0{,}000560$. Para una distribución aproximadamente normal de desvío $SE$, el valor esperado del error absoluto es $SE \cdot \sqrt{2/\pi} \approx 0{,}000376$. El valor observado es algo mayor al esperado, pero con solo 5 muestras esa diferencia es perfectamente compatible con el azar — no hay evidencia de sesgo sistemático en esta escala.

**Corrida de gran escala ($N=2{,}2\times10^9$, Paso D de control del Problema #1):** el error absoluto observado fue $0{,}0000408$, equivalente a $4{,}06$ veces el $SE$ teórico ($0{,}0000101$). Un desvío de más de $4\sigma$ tiene una probabilidad de ocurrir por azar de aproximadamente 1 en 16.000 — infrecuente, aunque no imposible en una sola corrida.

**Hallazgo abierto, no concluyente:** esta corrida se realizó con `monty_hall_v1_naive.c`, que en ese momento todavía usaba la semilla sin corregir (Problema #2). Con $P=1$ en esa corrida puntual no hay múltiples procesos combinándose, por lo que la hipótesis de correlación entre procesos (Salmon et al., 2011) no aplica directamente a este caso — pero tampoco corresponde descartarla sin más evidencia. **Próximo paso sugerido, no bloqueante:** repetir esta misma corrida con la versión final (semilla corregida e `int64_t`) un par de veces más, para confirmar si el error vuelve al rango esperable o si se mantiene sistemáticamente alto.

**Conclusión:** los datos propios confirman la tendencia general de $O(1/\sqrt{N})$ — al aumentar $N$ en un factor ~2200, el error se redujo en un orden de magnitud comparable a $\sqrt{2200}\approx47$. La única observación que amerita seguimiento es el error puntualmente alto de la corrida de $2{,}2\times10^9$, documentado arriba como hallazgo abierto.

## 6. Plan de Pruebas y Hardware

| Entorno | Arquitectura | Objetivo de la Prueba |
|---|---|---|
| Mac M1 | ARM (Heterogénea P-cores / E-cores) | Observar caídas de rendimiento al usar núcleos de eficiencia. |
| Notebook Windows | x86 | Curva de speedup en arquitectura simétrica; además, entorno donde se reproduce el Problema #1 (Sección 5.1). |
| Clúster de la Facultad | Nodos distribuidos | Medir el costo real de comunicación en red; entorno final donde correrán los experimentos de mayor escala. |

> **Hipótesis arquitectónicas esperadas (a contrastar empíricamente):**
> - **Mac M1 (ARM Heterogéneo):** se anticipa una caída de eficiencia o "efecto convoy" cuando $P$ supere la cantidad de núcleos de alto rendimiento (P-cores) y MPI comience a asignar carga a los núcleos de eficiencia (E-cores).
> - **Notebook Windows (x86 Simétrico):** se espera una curva de escalado más regular, dictada por la Ley de Amdahl, sostenida por memoria compartida.
> - **Clúster de la Facultad (Memoria Distribuida):** se espera que el overhead de red en las primitivas de comunicación de MPI se vuelva perceptible a medida que $P$ escale, a diferencia de los entornos locales.

En los tres entornos se compilará y ejecutará con **gcc**, mismo código fuente y mismo `Makefile`. La cátedra explicará el mecanismo de acceso al clúster; hasta entonces se avanza con Mac M1 y notebook Windows.

**Variables experimentales a barrer:**
1. Número de procesos $P$ (escalado fuerte, variable principal).
2. Tamaño del problema $N$ — ajustado empíricamente, sin valores fijos predefinidos.
3. Cantidad de puertas $M$ (Fase 2, sujeta a confirmación — Sección 12): $M = 3, 5, 10, 50$.

### 6.1 Experimento adicional: ¿tiene costo real la portabilidad de tipos en el clúster?

Dado que el volumen de datos grande se va a correr específicamente en el clúster, surge la duda de si `int64_t` introduce algún costo de rendimiento frente a usar el tipo nativo del sistema en esa arquitectura puntual. En vez de asumir una respuesta, se lo trata como una hipótesis a verificar con datos:

- **Hipótesis de partida:** en Linux de 64 bits (modelo LP64, el esperable en el clúster), `int64_t` y `long` son, en la práctica, el mismo tipo de 64 bits nativo de la CPU — por lo que no debería haber diferencia de rendimiento medible. La necesidad de `int64_t` es exclusivamente un tema de **portabilidad** hacia Windows, no de rendimiento en el clúster.
- **Diseño del experimento:** compilar dos variantes del núcleo de simulación, idénticas salvo un `typedef` del tipo de los contadores (`int64_t` vs. el entero nativo de 64 bits del sistema), y correr el mismo $N$ grande con el mismo $P$ en el clúster, repitiendo las 10 corridas mínimas de la Sección 8 para cada variante, comparando las medianas de tiempo.
- **Refinamiento adicional a probar:** dado que el contador local de cada proceso opera sobre $N/P$ (que con $P$ grande puede entrar cómodo en 32 bits, aunque $N$ total no), se probará también una variante que use un tipo de 32 bits solo para el acumulador local del bucle caliente, reservando 64 bits únicamente para el total global tras la reducción.
- **Resultado esperado según la hipótesis:** si se confirma que no hay diferencia medible, se mantiene una única versión portable (`int64_t` en todos lados). Si aparece una diferencia real, se documenta el caso puntual y se justifica mantener una variante "cluster-only", dejando explícito el trade-off entre portabilidad y rendimiento.

## 7. Verificación de Toolchain

Antes de lanzar las corridas de medición, se compilará y ejecutará un programa mínimo en cada sistema que solo llame a `rand_r` (Problema #3, Sección 5.1), para confirmar que el toolchain de gcc de esa máquina lo soporta sin errores de enlazado. Si falla en la notebook Windows, la alternativa es correr esa parte del experimento sobre WSL.

## 8. Metodología de Medición y Validación Estadística

- **Escalado Fuerte (Strong Scaling — Ley de Amdahl):** prueba principal, $N$ fijo, variando $P$.
- **Escalado Débil (Weak Scaling — Ley de Gustafson):** prueba opcional.
- **Toma de Tiempos:** exclusivamente alrededor del bucle de cómputo y las reducciones (pasos 4 a 7 de la Sección 4.1).
- **Repeticiones y Mediana:** 10 corridas como mínimo por configuración. Para el cálculo del *speedup* ($S_p = T_1/T_p$), se utilizará estrictamente la **mediana estadística** de las ejecuciones, descartando picos de retraso anómalos atribuibles a factores externos del sistema operativo (ruido de fondo, *throttling* térmico, latencia de red).
- **Validación contra la teoría:** probabilidad empírica $\hat{p}_{cambiar} = \text{victorias\_cambiando}/N$, probabilidad teórica $(M-1)/M$, y error absoluto entre ambas, calculados en C y exportados al CSV. Ver Sección 5.3 para la caracterización empírica de cómo converge este error con $N$.

## 9. Limitaciones Identificadas

- **Error estadístico del método de Monte Carlo:** converge con error de orden $O(1/\sqrt{N})$ — caracterizado con datos propios en la Sección 5.3.
- **Generador de números aleatorios:** correlación entre semillas mitigada, no eliminada por completo (Problema #2, Sección 5.1).
- **Sesgo de módulo:** despreciable para los valores de $M$ usados.
- **Comparación de tiempos entre arquitecturas:** solo tiene sentido comparar la forma de la curva de speedup por sistema, no los tiempos absolutos entre sistemas distintos.
- **Costo de rendimiento de `int64_t` en el clúster:** tratado como hipótesis pendiente de verificación empírica (Sección 6.1), no como un hecho asumido.
- **Supuesto sobre la regla del presentador:** válido para la variante "abre todas las puertas salvo una"; la variante alternativa queda fuera de alcance salvo indicación contraria de la cátedra (Sección 12).

## 10. Próximos Pasos (orden de prioridad, por etapas)

1. ✅ Consultar con la cátedra los puntos pendientes de la Sección 12.
2. ✅ Preparar la verificación de toolchain (Sección 7) — ejecución en Windows pendiente (Problema #3).
3. ✅ Implementar la versión ingenua del simulador (`monty_hall_v1_naive.c`).
4. ⏳ Reproducir el Problema #1 (overflow) en la notebook Windows — pendiente, a cargo del compañero de grupo.
5. ✅ Corregir y observar el Problema #2 (semillas) en `monty_hall_v2_seed_fix.c`; el Problema #1 se integra a la versión final recién cuando se confirme el punto 4.
6. ✅ Diagnosticar y corregir el Problema #4 (balanceo de carga), con `demo_balanceo_carga.c`.
7. ✅ Verificar a mano, con $N$ chico, que el resultado sea consistente con $M=3 \Rightarrow p \approx 2/3$.
8. Escribir el script de automatización en bash para ejecutar el programa 10 veces (mínimo) por configuración de $P$.
9. Ejecutar el escalado fuerte en Mac M1 y notebook Windows; sumar el clúster en cuanto la cátedra confirme el acceso.
10. En el clúster, correr el experimento de la Sección 6.1 (`int64_t` vs. tipo nativo) antes de dar por cerrada la versión final del código.
11. **Fase 2 (según lo confirmado en la Sección 12):** correr el barrido de $M$ (3, 5, 10, 50).
12. Escribir el notebook de Python: medianas, speedup por sistema, comparación empírico vs. teórico.
13. Redactar conclusiones y recomendaciones de mejora, incluyendo lo aprendido en la Bitácora de Diagnóstico.
14. Subir código (incluyendo la versión ingenua junto a la corregida, como evidencia del proceso), datos, gráficos y README al repositorio.
15. (Opcional) Armar un PDF del proyecto a partir del README y la documentación generada.

## 11. Bibliografía

- Salmon, J. K.; Moraes, M. A.; Dror, R. O.; Shaw, D. E. (2011). *Parallel Random Numbers: As Easy as 1, 2, 3*. SC11 (Best Paper). https://www.thesalmons.org/john/random123/papers/random123sc11.pdf
- Lowery, B. (2022). *The Monty Hall problem and its generalisations (Part 2)*. STOR-i, Lancaster University. https://www.lancaster.ac.uk/stor-i-student-sites/ben-lowery/2022/04/the-monty-hall-problem-and-its-generalisations-part-2/
- IB Maths Resources (2023). *The Monty Hall Problem – Extended*. https://ibmathsresources.com/2023/11/01/the-monty-hall-problem-extended/
- Gropp, W.; Lusk, E.; Skjellum, A. *Using MPI: Portable Parallel Programming with the Message-Passing Interface*. MIT Press.
- Grama, A.; Gupta, A.; Karypis, G.; Kumar, V. *Introduction to Parallel Computing*. Addison-Wesley.
- MPI Tutorial (Wes Kendall). https://mpitutorial.com/tutorials/
- LLNL HPC Tutorials — Message Passing Interface (MPI). https://hpc-tutorials.llnl.gov/mpi/

## 12. Puntos Pendientes de Confirmación con la Cátedra

- **Alcance de la generalización:** ¿la generalización a $M$ puertas (Fase 2, Sección 2.2) se espera como parte del análisis o es un plus opcional? ¿Conviene también implementar la variante donde el presentador abre una sola puerta?
- **Acceso al clúster de la Facultad:** pendiente de confirmación (credenciales, login directo vs. gestor de colas).