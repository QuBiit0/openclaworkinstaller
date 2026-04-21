> ## Índice de Documentación
> Consultá el índice completo en: https://docs.openclaw.ai/llms.txt
> Usalo para descubrir todas las páginas antes de explorar más a fondo.

# BOOT.md — Hook de Arranque

Este archivo contiene **instrucciones cortas y explícitas** que OpenClaw ejecuta cuando se reinicia el gateway (no al inicio de cada sesión de chat).

**Requisito:** tené habilitado `hooks.internal.enabled` en la configuración.

> **Diferencia clave vs otros archivos del workspace:** `BOOT.md` **NO se inyecta** al system prompt como Project Context en cada turno. Es un **hook de startup** que ejecuta una tarea única al arrancar el gateway. Usalo para chequeos de salud, sincronización inicial, notificaciones urgentes — no para instrucciones permanentes (esas van en `AGENTS.md`).

---

## Cómo funciona

- Si la tarea **envía un mensaje**, usá la tool `message` y luego respondé con el token silencioso **exacto**: `NO_REPLY` o `no_reply`.
- Si la tarea **no necesita mensaje externo**, simplemente ejecutá las instrucciones y terminá la respuesta con `NO_REPLY`.
- Mantené este archivo **corto**. Cada tarea consume tokens en cada arranque.

---

## Tareas al Arranque

<!-- Descomentá y adaptá lo que necesites. Borrá lo que no uses. -->

<!--
### 1. Verificación del workspace
- Leé `memory/YYYY-MM-DD.md` de hoy. Si no existe, creá uno vacío.
- Chequeá que `MEMORY.md` sigue intacta y con formato válido.

### 2. Sincronización de proyectos activos
- Ejecutá `git status` en cada repo dentro de `projects/`.
- Si hay cambios sin commitear por más de 24h, agregá una nota al log diario.

### 3. Notificaciones prioritarias
- Revisá emails marcados como urgentes desde el último arranque.
- Si hay alguno, enviá un resumen al canal principal vía `message`.
- Si no hay nada, `NO_REPLY`.

### 4. Chequeo de cron jobs
- Listá crons pendientes para hoy con `openclaw cron list --today`.
- Si hay alguno crítico, recordalo.

### 5. Autocuración
- Si detectás archivos huérfanos en `memory/` con fecha > 60 días, sugerí archivarlos.
-->

---

## Ejemplo: Arranque silencioso

```markdown
# Leé el log de ayer para tener contexto reciente.
# Chequeá si hay mensajes sin leer en los canales activos.
# No respondas a nadie salvo que haya algo urgente.
# Terminá con NO_REPLY.
```

---

## Ejemplo: Arranque con notificación

```markdown
# Si hay un evento de calendario en las próximas 2h:
#   - Enviá un mensaje al canal principal con el detalle.
#   - Respondé con el token: no_reply
# Si no hay nada relevante, respondé directamente: NO_REPLY
```

---

## Anti-patrones

- ❌ Instrucciones ambiguas ("chequeá cosas importantes")
- ❌ Tareas largas que deberían ser cron jobs
- ❌ Loops o recursión implícita
- ❌ Olvidarse del token `NO_REPLY` — genera ruido en los canales
