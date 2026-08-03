# Sistema visual — CCE Home

Fuente de verdad en código: `lib/theme/cce_tokens.dart`. Este documento explica
el *porqué*; el código manda sobre los valores.

## Dirección

**Instrumento cálido de casa.**

Quien usa esto está en su casa, de noche, con poca luz, y mira la pantalla
pocos segundos para saber cómo está todo o cambiar una cosa. No está
analizando datos ni administrando infraestructura.

De ahí sale todo lo demás:

- **Cálido, no frío.** El hue base es 30°. Una casa de noche es ámbar; el azul
  de dashboard pertenece a otro producto.
- **Quieto.** Nada rebota, nada pulsa sin motivo, nada brilla por adorno.
- **Un acento.** Ámbar `#FFB46B` — el color de una luz encendida, que es de lo
  que la app trata.

## Profundidad: UNA estrategia

**Escalones de superficie + hairline + material.**

Una card tiene cuerpo, y ese cuerpo sale de tres cosas que trabajan juntas —
ninguna alcanza sola y de a una son imperceptibles:

1. `CceGradients.cardSurface`: canto de luz en el 6% superior, caída suave
   hacia la base. Rango total ~5 puntos de lightness.
2. `CceShadows.raised`: sombra de contacto corta + difusa larga.
3. `stroke`: hairline que cierra el canto.

La diferencia con el neumorfismo que se retiró: la luz viene **de arriba y
nada más**. El par direccional (highlight arriba-izquierda + sombra
abajo-derecha) es lo que convertía cada superficie en plástico, y el mismo par
aplicado a texto e íconos era lo que los ensuciaba.

Nunca: emboss de texto o de íconos, sombras internas, gradientes que simulen
volumen en un control.

| Nivel | Token | Uso |
|---|---|---|
| L0 | `bg` `#121110` | Lienzo. **Todas** las pantallas. |
| L1 | `surface` `#1A1817` | Cards, sheets, barras. |
| L2 | `surfaceHigh` `#232120` | Inputs, chips, hover. |
| L3 | `surfaceTop` `#2C2A27` | Menús, popovers. |
| — | `surfaceSunken` `#0D0C0B` | Huecos: tracks de slider, switch apagado. |

Hairlines: `strokeSoft` (divisores) → `stroke` (cards) → `strokeStrong` (foco).

Sombras: sólo `raised` (card sobre lienzo) y `floating` (sheet/diálogo). Son
ambientales — caen hacia abajo, sin luz direccional simulada.

**Prohibido:** relieve neumórfico, emboss de texto o de íconos, sombras
internas, gradientes que simulen volumen. Todo eso se retiró en el rebranding;
los tokens `neo*` siguen existiendo sólo como alias de compatibilidad.

## Color

**Un acento** (`accent`) para todo lo activo: switch encendido, card
seleccionada, ícono prendido, filtro elegido.

**Semánticos sólo para estado**, nunca para decorar: `ok`, `danger`, `info`,
`motion` (presencia), `contact` (apertura).

**Marcas de terceros** (JBL, Samsung, el arcoíris de Hue): sólo dentro del
detalle del dispositivo. En listas y en la home, todo dispositivo usa el ícono
y el acento del sistema — si cada marca trae su color, nada destaca.

**El color real de una luz** aparece en su tile y en el detalle, donde es la
información principal. **No** en la lista de habitaciones: ahí lo que importa
es si algo está prendido, no de qué color.

## Espaciado

Base 4: `CceSpace.xs/sm/md/lg/xl/xxl/xxxl` = 4/8/12/16/24/32/48.

Padding **simétrico** siempre. Única excepción justificada: `SectionHeader`,
que respira `xl` arriba y `md` abajo porque el encabezado pertenece a lo que
viene debajo.

## Radios

`sm` 10 (chips) · `control` 16 (tiles, botones) · `card` 22 · `sheet` 28 ·
`pill` 999.

## Tipografía

Fuente del sistema. Seis pasos, **sin medios puntos**:

`display` 32 · `title` 20 · `headline` 17 · `body` 15 · `caption`/`label` 13 ·
`section` 11 (mayúsculas, tracking +1.1).

Los **datos** (`data`, `dataLarge`) usan cifras tabulares: una temperatura que
pasa de 23.9 a 24.0 no debe mover el layout.

## Reglas de componentes

- **Filas de lista: altura uniforme.** `RoomCard.kHeight` = 88, con slider o
  sin él. Un salto de altura según haya o no brillo hace que la lista salte.
- **Un control apagado debe verse.** El switch OFF lleva hairline: sin él se
  funde con la card y parece que no hay control. El estado se lee además por
  valor (thumb gris → claro), no sólo por color.
- **No decir lo mismo dos veces.** Si un dot ya lleva el color del estado, el
  texto de al lado va en `textSecondary`. Si un borde de acento ya marca
  "activo", no va además un check.
- **Animación:** deceleración (`easeOutCubic`), 180–220 ms. Nunca `bounceOut`
  ni `elasticOut`.
- **Un marcador de selección muestra lo que elegís, no lo señala.** En el
  selector de color el centro del círculo ES el punto: adentro se ve el color
  que se va a aplicar. Un pin de mapa (cabeza arriba, punta abajo) resuelve el
  problema contrario — señalar sin tapar — y deja el color elegido lejos del
  dedo.
- **Gestos largos, horizontales.** La barra de brillo va a todo el ancho: un
  gesto vertical contra el borde de la pantalla pelea con el scroll y con el
  swipe-back de iOS, y desperdicia recorrido.
- **La transición ES el feedback.** Un cambio de estado visible (una luz que
  enciende) se anima: 260 ms `easeOutCubic` interpolando borde, halo, ícono y
  texto. No se le encima un pulso — `PulseOnUpdate` es sólo para eventos que
  NO cambian nada en pantalla (sensores). Encimar las dos cosas produce un
  corte seco seguido de un fantasma que llega tarde.
- **Un control tiene que mostrar su recorrido completo.** El track de un
  slider va en `surfaceHigh`, no en `surfaceSunken`: sobre un lienzo casi
  negro, un hueco más oscuro es invisible y la barra se lee cortada en vez de
  llena hasta el valor. Y siempre lleva un asa en el extremo del relleno —
  sin ella, al 100% se ve como un bloque de color, no como algo arrastrable.

## Deuda conocida

- **Tres sets de íconos** conviven: Material (~134), Lucide SVG (~64), MDI
  (~16). El objetivo es Lucide (`CceIcons`) solo. Migrar por pantalla.
- **Logo**: `CceLogo` es una silueta panorámica (≈8.8:1). A 22 px de alto en
  el header se aplana y no se lee como marca.
- **Nombres bilingües** ("Bedroom", "Go to sleep"): vienen del bridge Hue, no
  del código. Se arreglan renombrando en Hue.
