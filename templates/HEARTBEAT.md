> ## Índice de Documentación
> Consultá el índice completo en: https://docs.openclaw.ai/llms.txt
> Usalo para descubrir todas las páginas antes de explorar más a fondo.

# HEARTBEAT.md — Checklist Periódico

> Dejá este archivo **vacío** (o solo con comentarios) para saltear las llamadas de heartbeat y ahorrar tokens.
> Agregá tareas cuando quieras que el agente revise algo periódicamente.

**Cuándo usar este archivo vs cron:**
- **Acá:** tareas que se benefician de batcheo, timing flexible (~30 min), contexto conversacional.
- **Cron:** tareas con timing exacto, aisladas, one-shot, o que entregan a un canal sin pasar por la sesión principal.

Ver `AGENTS.md` §8 para la guía completa.

### Control de inyección al system prompt

Este archivo se inyecta al system prompt **solo cuando los heartbeats están habilitados** para el agente default. Podés forzar el comportamiento con la flag:

- `agents.defaults.heartbeat.includeSystemPromptSection: true` → siempre inyectar
- `agents.defaults.heartbeat.includeSystemPromptSection: false` → nunca inyectar (ahorra tokens en runs normales)

En corridas de heartbeat propiamente dichas, el archivo siempre se usa como guía para los checks. Vaciarlo desactiva efectivamente el heartbeat.

---

## Plantilla de Tareas

<!-- Descomentá y adaptá. Borrá lo que no uses. Cuanto más corto, menos tokens. -->

<!--
### 📬 Email
- Revisá la bandeja de entrada en busca de urgencias sin leer.
- Si hay algo con "urgente", "importante" o de contactos VIP, mencionalo.
- Frecuencia: cada ~2h durante horas laborales.

### 📅 Calendario
- Chequeá eventos en las próximas 2h.
- Si hay alguno que requiera preparación, avisá con tiempo.
- Frecuencia: cada 1h durante el día.

### 🌐 Menciones y notificaciones sociales
- Revisá menciones en Twitter/Mastodon/Bluesky.
- Solo alertá si algo pide respuesta rápida.
- Frecuencia: 3-4 veces al día.

### 🌤️ Clima
- Si se planea actividad al aire libre hoy (ver calendario), chequeá el clima.
- Alertá si hay cambio significativo (lluvia, frío extremo).
- Frecuencia: 1 vez a la mañana, 1 vez a la tarde.

### 💻 Proyectos activos
- Ejecutá `git status` en cada repo dentro de `projects/`.
- Si hay cambios sin commitear por más de 24h, notalo en el log diario.
- Si hay PRs pendientes de review, recordalos.
- Frecuencia: 2 veces al día.

### 🧠 Mantenimiento de memoria
- Cada 3-4 días, revisá `memory/YYYY-MM-DD.md` recientes.
- Destilá lo valioso a `MEMORY.md`.
- Marcá para archivar lo que sea obsoleto.

### 📰 Feeds / newsletters
- Chequeá RSS/newsletters configurados.
- Resumí los 3 items más relevantes si hay algo nuevo.
- Frecuencia: 1 vez al día (a la mañana).
-->

---

## Estado de los Chequeos

El archivo `memory/heartbeat-state.json` trackea cuándo fue el último check de cada tarea. Estructura esperada:

```json
{
  "lastChecks": {
    "email": 1703275200,
    "calendar": 1703260800,
    "weather": null,
    "projects": 1703260000,
    "memory_review": 1703100000
  }
}
```

Antes de chequear algo, mirá el timestamp. Si chequeaste hace menos de 30 minutos, es probable que debas responder `HEARTBEAT_OK` sin hacer nada.

---

## Anti-patrones

- ❌ Checklists largos con 20+ items — el agente se va a distraer
- ❌ Tareas que deberían ser cron jobs (timing exacto, aisladas)
- ❌ Olvidarse de actualizar `heartbeat-state.json` — termina en chequeos redundantes
- ❌ Alertar por cualquier cosa — filtrá, que la señal importa más que el volumen
