# abrir claude

Un atajo global (⌥C) abre una paleta que pregunta en qué carpeta abrir Claude Code. Al confirmar, abre una ventana nueva de Terminal, hace `cd` a esa carpeta y ejecuta `claude`.

## Uso

| Escribes | Se abre en |
|---|---|
| nada | tu carpeta de usuario |
| `proyectos/mi-app` | `~/proyectos/mi-app` |
| `~/proyectos/mi-app` | igual que lo anterior |
| `/Volumes/disco/obra` | esa ruta absoluta |
| una carpeta que no existe | Terminal muestra el error de `cd` y no arranca claude |

Teclas:
- **⌥C** abre la paleta. Con la paleta abierta, volver a pulsarlo equivale a Enter: **⌥C ⌥C** abre Claude directamente en tu carpeta de usuario.
- **↵** abre la carpeta escrita, o la fila elegida si has movido la selección con las flechas.
- **tab** completa con la fila elegida o con la primera sugerencia, y muestra las subcarpetas de esa carpeta.
- **↑ ↓** recorren las sugerencias. La lista solo se desplaza cuando hace falta, y dejando ver la fila siguiente. Pasado el último elemento se vuelve al campo de texto.
- **⌘A ⌘C ⌘V ⌘X ⌘Z** funcionan en el campo, gracias a un menú Edición que no se ve.
- **esc**, **⌘W** o un clic fuera cierran la paleta sin hacer nada.
- **⌘Q** con la paleta abierta cierra la app. Vuelve a arrancar al iniciar sesión o abriéndola desde Aplicaciones.

### Modelo, esfuerzo, permisos y sesión

Abajo hay una línea que dice, en este orden, con qué se lanza Claude: **Modelo · Esfuerzo · Permisos · Sesión**. Cada valor se pinta como lo pinta Claude Code. Al bajar con **↓** desde la última carpeta (o con **⌘↓**, o con un clic) se despliega en una fila por opción:

| Fila | Control | Opción de `claude` |
|---|---|---|
| Modelo | control segmentado a todo el ancho: Por defecto, Fable, Opus, Sonnet, Haiku, cada uno con su número (Opus 5.5). El número se lee del propio `claude` instalado, así que se actualiza solo cuando Claude Code se actualiza | `--model` con el alias (`opus`), que siempre lanza el último |
| Esfuerzo | una pastilla «auto» (usa el nivel de tu `settings.json`; la bola se queda hueca en ese nivel) y un carril con los cinco niveles reales, de Más rápido a Más listo: low, medium, high, xhigh y max. La bola lleva un punto del color del nivel y brilla en él; al arrastrar sigue al ratón y al soltar se coloca en el nivel más cercano | `--effort` |
| Permisos | «Por defecto» aparte (lo que diga tu configuración) y dos grupos: **Te pregunta** (Manual, Plan) y **No te pregunta** (Ediciones, Auto, No preguntar, Saltar). El elegido se tiñe de su color y debajo sale su símbolo y qué hace | `--permission-mode` |
| Sesión | control segmentado: Nueva, Continuar, Elegir | `--continue`, `--resume` |

Los colores salen de la tabla del tema oscuro que lleva dentro el propio `claude`:

| Valor | Color |
|---|---|
| esfuerzo low | `warning`, amarillo |
| esfuerzo medium | `success`, verde |
| esfuerzo high | `permission`, lavanda |
| esfuerzo xhigh | `autoAccept`, morado, con brillo animado |
| esfuerzo max | arcoíris animado |
| permisos Manual | gris, con `⏸` |
| permisos Plan | `planMode`, verde azulado, con `⏸` |
| permisos Aceptar ediciones | `autoAccept`, morado, con `⏵⏵` |
| permisos Auto | `warning`, amarillo, con `⏵⏵` |
| permisos No preguntar y Saltar permisos | `error`, rosa rojizo, con `⏵⏵` |

Teclas:
- **↑ ↓** cambian de fila, y **↑** desde la primera vuelve a las carpetas.
- **← →** cambian el valor; la pastilla del elegido se desliza. El slider se arrastra con el ratón: la bola sigue al puntero y al soltar se coloca en el nivel más cercano.
- **esc** pliega las opciones; un segundo **esc** cierra la ventana.
- **↵** o **⌥C** lanzan Claude.

"Por defecto" y "auto" no añaden nada al comando, así que se aplica tu configuración de Claude Code. En permisos, "Por defecto" muestra qué modo dice tu `~/.claude/settings.json`. Las elecciones se recuerdan para la próxima vez, guardadas por nombre, así que reordenar los valores no cambia lo elegido.

La ventana tiene un tamaño fijo y transparente, y la tarjeta crece y encoge dentro con animación, con su sombra dibujada en SwiftUI. Por eso abrir y plegar las opciones es fluido y no salta: al abrir, las filas entran una tras otra.

El atajo se fija en `App.swift` (`openClaudeShortcut`) y se vuelve a aplicar en cada arranque. Ojo: mientras la app está en marcha, ⌥C ya no escribe "©".

Abrir la app desde Spotlight o Finder también muestra la paleta. La lista muestra todas las subcarpetas. Tiene una barra de scroll propia, fina y sin carril, que aparece al desplazarse, y los bordes se difuminan cuando hay más contenido arriba o abajo. La parte de la ruta que ya has escrito sale atenuada.

## Aspecto

Por defecto replica la **entrada rápida de Claude** (⌥Espacio en la app de escritorio). Los valores se han sacado de su propia hoja de estilos (`quick-window.html` dentro de `app.asar`):
- panel transparente con sombra, de 606 px de ancho, centrado en la pantalla principal
- se arrastra y recuerda dónde lo dejaste
- barra de 56 px de alto con radio 16
- fondo en degradado de `#403F3E` (al 95 %) a `#292523`, con un borde de 0,5 px blanco al 20 %
- el destello oficial en `#D97757` a 18 px, en una celda de 56×56
- Anthropic Sans a 16 px en blanco, placeholder `#A6A39B` y cursor blanco
- sin borde de campo, sin aro de foco y sin fundido al aparecer

Las carpetas usan los tokens oscuros de Claude: texto `#C2C0B6`, iconos `#9C9A92`, y blanco al 9 % para la fila elegida.

Anthropic Sans se carga al arrancar desde `/Applications/Claude.app`; no se copia a este proyecto. Sin la app de Claude se usa la fuente del sistema.

El estilo **laaabs.** usa la misma barra en negro, con Outfit y el cursor cyan. Para cambiar de estilo:

```sh
defaults write com.aaangelmartin.abrir-claude theme laaabs   # o claude
pkill -x AbrirClaude; open ~/Applications/"Abrir Claude.app"
```

## Instalar en un Mac

Requisitos:
- macOS 14 o posterior y Xcode (Swift 6.2 o posterior)
- el kit de laaabs. en `~/Desktop/laaabs/marca/ui-swift`. Si está en otra ruta, cambia el `path:` de `Package.swift`
- `claude` en el PATH de una shell de login (`zsh -lic 'command -v claude'`)

Pasos:

```sh
cd ~/Developer/abrir-claude
./scripts/install.sh
```

El script hace todo esto:
1. Compila para arm64 y x86_64.
2. Monta `build/Abrir Claude.app` y genera el icono a partir de `Resources/claude.svg` (marca blanca sobre el naranja de Claude).
3. Firma con el primer certificado "Developer ID Application" válido del llavero. Con `SIGN_IDENTITY=-` firma ad hoc.
4. La instala en `~/Applications` y la abre.

En el primer arranque se añade sola a los elementos de inicio de sesión y muestra la paleta una vez.

## Permisos que pide macOS

- **Controlar Terminal** (Automatización): se pide la primera vez que abres una carpeta. Si lo rechazas, la paleta lo avisa y trae un botón a Ajustes del Sistema → Privacidad y seguridad → Automatización.
- **Elemento de inicio**: macOS avisa con una notificación de que se ha añadido. Se gestiona en Ajustes del Sistema → General → Elementos de inicio.

El atajo global no necesita permiso de Accesibilidad, porque usa `KeyboardShortcuts` (Carbon hotkeys).

## Estructura

```
Sources/AbrirClaude/
  App.swift            arranque, atajo global, elemento de inicio
  PalettePanel.swift   panel flotante que no activa la app, teclado, posición
  PaletteView.swift    la paleta en SwiftUI
  Theme.swift          los dos estilos (claude y laaabs.) y la carga de las fuentes de Claude
  PaletteModel.swift   texto, filas, selección, mensajes de estado
  FolderPath.swift     de lo escrito a ruta absoluta y orden de shell
  Suggestions.swift    autocompletado de carpetas y recientes
  Terminal.swift       AppleScript que abre la ventana de Terminal
  LaunchOptions.swift  modelo, esfuerzo, permisos y sesión, y las opciones de claude que añaden
  OptionsView.swift    la línea de resumen, las filas, el slider de esfuerzo y el texto animado
Resources/             Info.plist, entitlements, svg de claude
scripts/               install.sh, make-icon.swift
Tests/                 tests de rutas, sugerencias, selección y opciones (swift test)
                       SNAPSHOT_DIR=/ruta swift test --filter Snapshot dibuja la paleta en png sin abrirla
```

## Desinstalar

```sh
pkill -x AbrirClaude
rm -rf ~/Applications/"Abrir Claude.app"
```

Después, quítala de Ajustes del Sistema → General → Elementos de inicio si sigue apareciendo.
