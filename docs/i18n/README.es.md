<div align="center">

<img src="../../Dusty/Dusty/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" height="96" alt="">

# Dusty

**Libera espacio en el disco de tu Mac y mira cada archivo antes de que se borre.**

Una alternativa gratuita y de código abierto a CleanMyMac que vive en tu barra de menús.

[![Release](https://img.shields.io/github/v/release/yagcioglutoprak/dusty?color=3b82f6&label=Release)](https://github.com/yagcioglutoprak/dusty/releases/latest)
[![CI](https://github.com/yagcioglutoprak/dusty/actions/workflows/ci.yml/badge.svg)](https://github.com/yagcioglutoprak/dusty/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/github/license/yagcioglutoprak/dusty?color=6366f1)](../../LICENSE)
[![Stars](https://img.shields.io/github/stars/yagcioglutoprak/dusty?label=Stars&color=38bdf8)](https://github.com/yagcioglutoprak/dusty/stargazers)

[English](../../README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · **Español** · [Français](README.fr.md) · [Русский](README.ru.md)

[**Descargar**](https://github.com/yagcioglutoprak/dusty/releases/latest) ·
[Instalación](#instalación) ·
[Qué limpia](#qué-limpia) ·
[Por qué es seguro](#por-qué-puedes-confiar-en-dusty) ·
[Línea de comandos](#línea-de-comandos-y-atajos) ·
[Preguntas frecuentes](#preguntas-frecuentes)

<br>

<img src="../screenshots/demo.gif?v=4" width="480" alt="La bienvenida de Dusty al abrirlo por primera vez, un análisis en curso, el espacio recuperable por nivel, una limpieza segura con su temporizador para deshacer y, después, el nivel Desarrollo elemento por elemento">

<sub>Si Dusty te ahorra espacio, una estrella en GitHub ayuda a que más usuarios de Mac encuentren un limpiador más seguro.</sub>

</div>

> Esta página es una traducción. El [README en inglés](../../README.md) siempre es el más actualizado.

## De un vistazo

- **Enseña lo que hace.** Cada ruta y su tamaño aparecen en pantalla antes de
  borrar nada. Analizar nunca borra.
- **Solo puede tocar archivos basura.** Solo borra lo que figura en una lista de
  permitidos fija y legible de cachés y archivos sobrantes. Tus documentos, fotos
  y correo quedan fuera de su alcance por diseño.
- **Cada limpieza se puede deshacer.** Los elementos pasan por la Papelera, con
  un botón Deshacer disponible durante unos segundos, y cada borrado queda
  anotado en un registro.
- **Conoce la basura de desarrollo.** DerivedData de Xcode, simuladores, cachés
  de npm, Cargo y pip, y los `node_modules` de proyectos olvidados.
- **Es rápido.** Un análisis completo de un equipo de desarrollo en uso (M3, unos
  18 GB repartidos en 866 rutas) tarda unos 5 segundos.
- **No estorba.** El espacio libre aparece en la barra de menús, un análisis en
  segundo plano mantiene al día la cifra «por limpiar» y la app se actualiza sola.
- **No cuesta nada.** Gratis, con licencia MIT, sin cuenta y sin telemetría.

## Instalación

```bash
brew install --cask yagcioglutoprak/tap/dusty
```

O descarga `Dusty.dmg` desde la
[última versión](https://github.com/yagcioglutoprak/dusty/releases/latest),
arrástralo a Aplicaciones y ábrelo. En ambos casos, la app está firmada y
notarizada por Apple.

Dusty aparece en la barra de menús como un icono de disco con tu espacio libre al
lado. Necesita macOS 13 Ventura o posterior y se mantiene actualizado solo
(puedes desactivarlo en Ajustes).

El panel también habla español. Sigue el idioma de tu Mac, o puedes
elegirlo en **Ajustes > General**.

## Cómo funciona

1. **Analiza.** Haz clic en el icono del disco y lanza un análisis. Dusty mide
   cada objetivo de limpieza y reparte lo que encuentra en tres niveles, de mayor
   a menor.
2. **Revisa.** Un clic limpia el nivel Seguro. O abre cualquier nivel y desmarca
   lo que quieras conservar, elemento por elemento. La barra inferior siempre
   muestra lo que se llevaría una limpieza.
3. **Limpia, con opción de volver atrás.** Una confirmación muestra cada ruta y
   tu espacio libre antes y después. Tras la limpieza tienes unos segundos para
   cambiar de opinión: haz clic en Deshacer (o usa ⌘Z) y los elementos limpiados
   vuelven a su sitio.

<p align="center">
<img src="../screenshots/overview.png" alt="El panel de Dusty: la pantalla de inicio con una barra de almacenamiento y la limpieza segura de un clic, el nivel Desarrollo elemento por elemento, la ventana de confirmación y Ajustes">
</p>

## Qué limpia

Tres niveles, de «hazlo cuando quieras» a «mira bien antes de saltar».

| Nivel | Qué elimina | Por qué es seguro |
| --- | --- | --- |
| 🟢 **Seguro** | Cachés de usuario, registros de apps, Papelera, cachés de navegadores (Safari, Chrome, Firefox, Edge, Brave, Arc) y cachés de apps (Slack, Discord, Notion, Spotify, VS Code, Cursor, Signal, Obsidian, Microsoft Teams, instaladores de actualización de Zoom, caché multimedia de Telegram) | Se regenera solo, sin ningún impacto funcional |
| 🟣 **Desarrollo** | DerivedData de Xcode, DeviceSupport antiguos, simuladores no disponibles, cachés de gestores de paquetes (npm, yarn, pnpm, pip, uv, Bun, Deno, Cargo, Go, Homebrew, Composer, Gradle, CocoaPods, SwiftPM, pub de Dart/Flutter), caché de binarios de Cypress, cachés de herramientas de desarrollo en `~/.cache`, cachés de JetBrains y Unity, repositorio local de Maven (si lo activas), `docker system prune` opcional | Se reconstruye o se vuelve a descargar la próxima vez que lo necesites |
| 🟠 **Profundo** | Instaladores `.dmg` / `.pkg` antiguos en Descargas, archivos de Xcode, simuladores sin usar, instantáneas locales de Time Machine, registros de diagnóstico antiguos, modelos de Ollama (si los activas), artefactos de proyectos abandonados | No se selecciona nada hasta que lo marques |

**Proyectos olvidados.** El nivel Profundo también mira dentro de tus proyectos.
Encuentra los `node_modules`, la carpeta `target` de Cargo o el virtualenv de un
proyecto que no has tocado en un mes. El manifiesto de la herramienta tiene que
estar justo al lado del artefacto, la actividad se mide por tus propios archivos
y tu historial de git, y si tocas un proyecto entre el análisis y la limpieza,
sus artefactos se rechazan.

**Observaciones.** Tras un análisis, Dusty señala lo que notaría una persona:
12 GB de DerivedData cuando ya no tienes Xcode instalado, una caché en la que nada
ha escrito desde la primavera, un disco que va camino de llenarse en tres
semanas. Las observaciones solo señalan, nunca seleccionan ni borran nada.

**Modo automático.** Un análisis en segundo plano (activado por omisión, cada
4 horas) mantiene al día la cifra de la barra de menús y nunca borra nada. La
limpieza automática (desactivada por omisión) se ejecuta según un calendario, o
cuando el espacio libre baja de un umbral que tú eliges, y sigue las mismas
reglas que el panel.

## Por qué puedes confiar en Dusty

«Limpiador para Mac» suele significar «app que borra cosas que no puedes ver».
Dusty está diseñado justo al revés. La lógica de borrado es un paquete Swift
independiente y totalmente probado (`CleanerEngine`), sin interfaz, y solo un
componente, `SafetyValidator`, puede autorizar un borrado. Aplica estas reglas:

- **Solo lista de permitidos.** Una ruta solo se puede borrar si está dentro de
  un objetivo explícito de [`CleanupTargetRegistry`](../../CleanerEngine/Sources/CleanerEngine/CleanupTargetRegistry.swift).
  No hay lógica de «borrar todo excepto» en ninguna parte del código.
- **Las carpetas protegidas quedan fuera de alcance.** Documentos, Escritorio,
  Imágenes, la fototeca de Fotos, Música, Películas, Mail, iCloud Drive, Llaveros
  y Application Support se rechazan incluso como prefijos (salvo las subcarpetas
  de caché concretas que nombran los objetivos registrados).
- **Sin escapes por enlaces simbólicos.** Los enlaces simbólicos nunca se siguen,
  tampoco cuando la carpeta superior es un enlace simbólico.
- **Sin root.** Dusty nunca se ejecuta como root ni usa `sudo`, y no toca nada
  protegido por SIP.
- **Deshacer en todos los niveles.** Las limpiezas dejan primero los elementos en
  la Papelera, y las restauraciones se comprueban igual que los borrados.
- **Simulación.** Un solo interruptor hace que cada limpieza indique lo que
  borraría, sin borrar nada.
- **Todo queda por escrito.** Cada acción (hora, ruta, bytes) se añade a
  `~/Library/Application Support/Dusty/deletion-log.jsonl`.

La explicación completa del diseño, con código:
[Cómo está hecho Dusty para no borrar lo que no debe](https://toprak.sh/dusty/safety/) (en inglés).
Si encuentras una forma de hacer que borre algo fuera de la lista de permitidos,
comunícalo en privado: consulta [SECURITY.md](../../.github/SECURITY.md).

## Línea de comandos y Atajos

El mismo motor, la misma lista de permitidos y las mismas reglas de seguridad,
para usar en scripts. La CLI `dusty` viene dentro de la app, y el cask de
Homebrew la añade a tu `PATH`:

```bash
dusty scan                                    # mide los tres niveles, no borra nada
dusty scan --json                             # lo mismo, en formato legible por máquina
dusty clean                                   # muestra el plan de borrado del nivel Seguro
dusty clean --yes                             # lo borra de verdad
dusty clean --level developer --trash --yes   # deja las cachés de desarrollo en la Papelera
dusty targets                                 # muestra la lista de permitidos completa
```

`clean` no toca nada sin `--yes`, solo borra los elementos que la app
seleccionaría por sí misma y omite cualquier objetivo cuya app esté abierta. Dos
acciones de Atajos, **Limpiar los elementos seguros** y **Obtener el espacio
recuperable**, te permiten usar Dusty en cualquier automatización de macOS.

## Preguntas frecuentes

**¿De verdad es gratis?**
Sí. Licencia MIT, sin periodo de prueba, sin extras de pago y sin cuenta.

**¿Puede borrar mis proyectos o documentos?**
No. El validador rechaza esas carpetas antes de tocar nada, y solo entran en
juego las rutas de cachés y artefactos que están en la lista de permitidos.
Incluso en un proyecto olvidado, solo se ofrecen sus artefactos de compilación,
nunca tu código.

**¿Y si limpio algo que necesitaba?**
Haz clic en Deshacer (o usa ⌘Z) en los segundos siguientes a la limpieza y los
elementos vuelven a su sitio. La única excepción es vaciar la Papelera, que es
definitivo, igual que en el Finder.

**¿Por qué no está en el Mac App Store?**
El App Store exige que las apps usen sandbox, y una app en sandbox no puede
llegar a las cachés que limpia Dusty.

Hay más respuestas (Acceso total al disco, actualizaciones, compilar desde el
código fuente) en el [README en inglés](../../README.md).

## Cómo contribuir

Se aceptan pull requests, sobre todo con nuevos objetivos de limpieza y
traducciones. Consulta [CONTRIBUTING.md](../../CONTRIBUTING.md) y el
[issue sobre traducciones](https://github.com/yagcioglutoprak/dusty/issues/33).

## Licencia

MIT. Consulta [LICENSE](../../LICENSE).

---

<div align="center">
creado por <a href="https://toprak.sh">toprak.sh</a>
</div>
