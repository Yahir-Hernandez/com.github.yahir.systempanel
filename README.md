# System Panel Plasmoid

Plasmoide para KDE Plasma 6 que agrupa en un solo panel desplegable un lanzador de aplicaciones, controles rápidos del sistema y una barra de estadísticas en tiempo real.

Nombre del paquete: com.github.yahir.systempanel

---

## Resumen

El widget aparece como un icono compacto en el panel de Plasma. Al abrirse muestra una superficie casi a pantalla completa con cuatro zonas:

1. Barra superior con usuario, batería, Wi-Fi, reloj y nombre del host.
2. Controles rápidos para Wi-Fi, Bluetooth, volumen, brillo, modo de presentación, notificaciones y perfil de energía.
3. Lanzador de aplicaciones con búsqueda en vivo y cuadrícula configurable.
4. Barra inferior con CPU, memoria, disco, temperatura y red.

La mayor parte de la lógica está en QML, con tres módulos JavaScript auxiliares para parsear aplicaciones y métricas del sistema.

---

## Funcionalidades

### Lanzador de aplicaciones

- Escanea archivos .desktop desde rutas XDG estándar.
- Filtra por nombre o descripción en tiempo real.
- Ordena los resultados alfabéticamente.
- Permite configurar el número de columnas entre 2 y 6.
- Abre la aplicación seleccionada y cierra el panel al hacer clic.

### Controles rápidos

- Wi-Fi: activar o desactivar la radio.
- Bluetooth: bloquear o desbloquear adaptadores.
- Volumen: lectura inicial y control con deslizador.
- Brillo: lectura inicial y control con deslizador.
- Presentación: mantiene la pantalla despierta con xdg-screensaver.
- Notificaciones: pausa y reanuda dunst con dunstctl.
- Perfil de energía: Performance, Balanced o Power Saver con powerprofilesctl.
- Accesos directos a configuración de pantalla, sonido, red y ajustes del sistema.

### Estadísticas del sistema

| Tarjeta | Métrica | Fuente |
|---|---|---|
| CPU | Uso porcentual | Diferencia de dos muestras de /proc/stat |
| RAM | Usada / total | /proc/meminfo con MemAvailable |
| Disco | Uso de / | df -k / |
| Temp | Temperatura del sensor | /sys/class/thermal/thermal_zone0/temp |
| Red | Subida / bajada | /proc/net/dev |

### Barra superior

- Usuario actual.
- Estado de batería si existe BAT0.
- SSID y señal de la Wi-Fi activa.
- Reloj actualizado cada segundo.
- Hostname corto.

---

## Requisitos

### Plataforma

| Componente | Versión esperada | Observaciones |
|---|---|---|
| KDE Plasma | 6.x | Diseñado para Plasma 6 |
| Qt | 6.x | Incluido con Plasma 6 |
| KDE Frameworks | 6.x | Usado por Kirigami y Plasma components |
| Sistema objetivo | KDE Neon 24.04 o similar | Base Ubuntu 24.04 LTS |

### Utilidades externas

| Herramienta | Uso |
|---|---|
| nmcli | Estado y control de Wi-Fi |
| rfkill | Control de Bluetooth |
| bluetoothctl | Conteo de dispositivos Bluetooth conectados |
| brightnessctl | Lectura y ajuste de brillo |
| amixer | Lectura y ajuste de volumen |
| powerprofilesctl | Cambio de perfil de energía |
| dunstctl | Pausa y reanudación de notificaciones |
| xdg-screensaver | Modo de presentación |
| kcmshell6 | Apertura de páginas de configuración |
| systemsettings6 | Apertura de Ajustes del sistema |

### Datos del kernel

La barra de estadísticas lee directamente de /proc y /sys, así que no requiere paquetes extra para CPU, RAM, disco o temperatura. La lectura de temperatura depende de que exista una zona térmica compatible en el sistema anfitrión.

---

## Estructura del proyecto

| Archivo | Responsabilidad |
|---|---|
| metadata.json | Metadatos del plasmoide, dependencias y punto de entrada |
| contents/ui/main.qml | Raíz del widget, composición general y layout |
| contents/ui/StatusBar.qml | Barra superior con usuario, batería, Wi-Fi, reloj y host |
| contents/ui/QuickSettings.qml | Controles rápidos y acciones del sistema |
| contents/ui/ApplicationLauncher.qml | Búsqueda, listado y lanzamiento de aplicaciones |
| contents/ui/SystemStats.qml | Métricas en vivo del sistema |
| contents/code/AppLauncher.js | Parser de archivos .desktop y deduplicación |
| contents/code/NetworkManager.js | Helpers para Wi-Fi y Bluetooth |
| contents/code/SystemMonitor.js | Parseo y cálculo de métricas de sistema |
| contents/config/config.qml | Página de configuración |
| contents/config/main.xml | Esquema de configuración KConfigXT |

---

## Cómo funciona

### Flujo general

1. main.qml crea el icono compacto y la representación completa.
2. StatusBar.qml y QuickSettings.qml cargan su estado inicial mediante comandos de shell.
3. ApplicationLauncher.qml ejecuta un find sobre directorios de aplicaciones y pasa los .desktop encontrados a AppLauncher.js.
4. AppLauncher.js lee cada archivo, extrae la sección [Desktop Entry], valida la entrada y la agrega al modelo.
5. SystemStats.qml recopila información periódica del sistema y usa SystemMonitor.js para parsearla.

### Launcher de aplicaciones

El lanzador usa dos pasos:

1. QML recopila rutas .desktop desde /usr/share/applications, /usr/local/share/applications y $HOME/.local/share/applications.
2. AppLauncher.js abre cada archivo con XMLHttpRequest, ignora entradas ocultas o no aplicables y elimina códigos de campo como %U o %f del comando Exec.

Esto evita duplicados entre instalaciones del sistema y sobrescrituras del usuario.

### Controles rápidos

QuickSettings.qml serializa la ejecución de comandos para evitar carreras y sincroniza los valores de interfaz con la salida del sistema. Los deslizadores de volumen y brillo tienen un retardo corto para no disparar comandos en cada movimiento.

### Estadísticas del sistema

SystemStats.qml toma dos muestras de CPU separadas por 500 ms para calcular el uso real. La red se calcula por delta entre lecturas de /proc/net/dev. El disco, la RAM y la temperatura se leen en cada refresco configurado.

---

## Instalación

### Opción 1: copia manual para desarrollo

```bash
git clone https://github.com/Yahir-Hernandez/com.github.yahir.systempanel.git
cd com.github.yahir.systempanel
cp -r . ~/.local/share/plasma/plasmoids/com.github.yahir.systempanel
kquitapp6 plasmashell && kstart plasmashell
```

### Opción 2: kpackagetool6

```bash
kpackagetool6 --type Plasma/Applet --install .
```

Para actualizar una instalación existente:

```bash
kpackagetool6 --type Plasma/Applet --upgrade .
```

### Añadir al panel

1. Clic derecho en un panel existente.
2. Selecciona Añadir widgets.
3. Busca System Panel.
4. Arrástralo al panel o haz doble clic.

---

## Configuración

Abre la configuración con clic derecho sobre el widget y luego Configurar System Panel.

| Ajuste | Valor por defecto | Rango |
|---|---|---|
| Intervalo de refresco | 2 s | 1 a 30 s |
| Animaciones | Activadas | Sí o no |
| Columnas del lanzador | 4 | 2 a 6 |

Los cambios se guardan mediante Plasmoid.configuration y se aplican sin reiniciar Plasma.

### Archivo de configuración

El esquema KConfigXT está definido en contents/config/main.xml. Plasma genera automáticamente las claves:

- refreshInterval
- showAnimations
- launcherColumns

---

## Interacción por teclado

| Tecla | Acción |
|---|---|
| Escape | Cierra el panel desplegable |
| Tab / Shift+Tab | Mueve el foco entre controles |
| Enter / Space | Activa la acción enfocada |
| Flechas | Navega por la cuadrícula de aplicaciones |
| Ctrl+F | Enfoca el buscador |

---

## Referencia de comandos usados

### Barra superior

- whoami
- cat /sys/class/power_supply/BAT0/capacity
- cat /sys/class/power_supply/BAT0/status
- nmcli -t -f active,ssid,signal dev wifi | grep '^yes'
- hostname -s

### Quick Settings

- nmcli radio wifi
- nmcli radio wifi on / off
- rfkill list bluetooth
- rfkill block bluetooth / unblock bluetooth
- bluetoothctl devices Connected | wc -l
- amixer sget Master
- amixer sset Master X%
- brightnessctl -m
- brightnessctl set X%
- powerprofilesctl get
- powerprofilesctl set performance / balanced / power-saver
- dunstctl set-paused true / false
- xdg-screensaver reset
- kcmshell6 kcm_kscreen
- kcmshell6 kcm_pulseaudio
- kcmshell6 kcm_networkmanagement
- systemsettings6

### Estadísticas

- awk sobre /proc/stat
- awk sobre /proc/meminfo
- df -k /
- cat /sys/class/thermal/thermal_zone0/temp
- awk sobre /proc/net/dev

---

## Resolución de problemas

### El widget no aparece después de instalarlo

Reinicia plasmashell para que Plasma detecte el paquete nuevo.

```bash
kquitapp6 plasmashell && kstart plasmashell
```

Si sigue sin aparecer, verifica que la carpeta instalada contenga metadata.json y contents.

### La barra de estadísticas muestra ceros

Comprueba que el plasmoide esté ejecutándose dentro de una sesión completa de Plasma y no en un entorno mínimo sin acceso normal a /proc o /sys.

### La temperatura siempre vale 0 °C

Es probable que thermal_zone0 no sea el sensor correcto en tu hardware. Revisa las zonas disponibles en /sys/class/thermal y ajusta cmdTemp en SystemStats.qml si hace falta.

### El brillo no cambia

brightnessctl puede requerir permisos sobre el dispositivo. En algunos equipos ayuda añadir el usuario al grupo video y volver a iniciar sesión.

### La velocidad de red tarda en aparecer

La primera lectura de red solo guarda la muestra inicial. Los valores reales aparecen tras la segunda lectura, cuando ya existe una diferencia de contadores.

### El perfil de energía no cambia

Comprueba que power-profiles-daemon esté instalado y activo.

```bash
sudo systemctl enable --now power-profiles-daemon
```

### Bluetooth o Wi-Fi no responden

Verifica que las utilidades nmcli y rfkill existan y que tu sesión tenga permisos para controlar esos dispositivos.

---

## Notas de diseño

- El panel usa Kirigami y Plasma Components para mantener la apariencia nativa de KDE.
- La barra completa usa fondo semitransparente y animaciones suaves si showAnimations está activado.
- La cuadrícula de aplicaciones evita bloqueos de la UI cargando iconos y archivos .desktop de forma asíncrona.

---

## Licencia

Este proyecto está licenciado bajo GNU Lesser General Public License v2.0 o posterior, es decir, LGPL-2.0-or-later.

Texto completo: https://www.gnu.org/licenses/old-licenses/lgpl-2.0.html
