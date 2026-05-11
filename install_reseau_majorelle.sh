#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Réseau Louis Majorelle — Script d'installation
#  Compatible : toutes versions Ubuntu · Fedora · Arch · openSUSE…
# ═══════════════════════════════════════════════════════════════════

VERSION="0.16.1"   # ← changer uniquement ici pour toute la version

set -e

# ── Logging ─────────────────────────────────────────────────────────
# Dossier de logs dans Téléchargements (ou Downloads selon la langue)
DOWNLOADS_DIR="$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Téléchargements")"
LOG_DIR="$DOWNLOADS_DIR/majorelle-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/majorelle_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "══════════════════════════════════════════════"
echo "  Log démarré le $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Distro  : $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"')"
echo "  Python : $(python3 --version 2>&1)"
echo "══════════════════════════════════════════════"

# Capturer les erreurs avec leur contexte
trap 'echo ""; echo "❌ ERREUR ligne $LINENO — commande : $BASH_COMMAND"; echo "   → Voir le log complet : $LOG_FILE"' ERR

PROXY_HOST="172.19.255.254"
PROXY_PORT="3128"
APP_ID="reseau-majorelle"
INSTALL_DIR="$HOME/.local/share/$APP_ID"
DESKTOP_DIR="$HOME/.local/share/applications"
CONFIG_DIR="$HOME/.config/$APP_ID"
CERT_DIR="$CONFIG_DIR/certs"
APP_FILE="$INSTALL_DIR/majorelle.py"
ICON_NAME="reseau-majorelle"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"

# ── Chemins système (icône dock Ubuntu + intégration GNOME) ─────────
SYS_ICON_DIR_SVG="/usr/share/icons/hicolor/scalable/apps"
SYS_ICON_DIR_48="/usr/share/icons/hicolor/48x48/apps"
SYS_ICON_DIR_256="/usr/share/icons/hicolor/256x256/apps"
SYS_DESKTOP_DIR="/usr/share/applications"
BIN_DIR="/usr/local/bin"
LAUNCHER="$BIN_DIR/$APP_ID"

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║   Réseau Louis Majorelle — Installation v$VERSION   ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# ── 1. Détection du gestionnaire de paquets ─────────────────────────
echo "→ Détection du système..."

if   command -v apt-get &>/dev/null; then PKG_MGR="apt"
elif command -v dnf     &>/dev/null; then PKG_MGR="dnf"
elif command -v pacman  &>/dev/null; then PKG_MGR="pacman"
elif command -v zypper  &>/dev/null; then PKG_MGR="zypper"
else                                       PKG_MGR="unknown"
fi
echo "  Gestionnaire de paquets : $PKG_MGR"

pkg_install() {
    case "$PKG_MGR" in
        apt)    sudo apt-get install -y "$@" -qq 2>&1 ;;
        dnf)    sudo dnf install -y "$@" -q  2>&1 ;;
        pacman) sudo pacman -S --noconfirm --needed "$@" 2>&1 ;;
        zypper) sudo zypper install -y "$@" 2>&1 ;;
        *)      echo "  ⚠️  Gestionnaire inconnu. Installe manuellement : $*"; return 1 ;;
    esac
}

# ── 1b. Dépendances — vérification par import Python ────────────────
# Plus fiable que de deviner les noms de paquets selon la version
echo "→ Vérification des dépendances (test import Python)..."

_try_import() {
    python3 -c "$1" &>/dev/null
}

# ── GTK / GObject Introspection ──
if ! _try_import "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk"; then
    echo "  ✗ GTK3/gi manquant — tentative d'installation..."
    case "$PKG_MGR" in
        apt)
            # Essaie les deux noms selon la version Ubuntu
            pkg_install python3-gi python3-gi-cairo gir1.2-gtk-3.0 2>/dev/null || \
            pkg_install python3-gobject python3-gobject-cairo        2>/dev/null || true
            ;;
        dnf)    pkg_install python3-gobject gtk3 ;;
        pacman) pkg_install python-gobject gtk3  ;;
        zypper) pkg_install python3-gobject typelib-1_0-Gtk-3_0 ;;
    esac
    if _try_import "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk"; then
        echo "  ✅ GTK3/gi installé"
    else
        echo "  ❌ GTK3/gi toujours manquant — l'app ne peut pas démarrer"
        echo "     Installe manuellement : python3-gi gir1.2-gtk-3.0"
        exit 1
    fi
else
    echo "  ✅ GTK3/gi présent"
fi

# ── VTE (terminal intégré — optionnel) ──
if ! _try_import "import gi; gi.require_version('Vte','2.91'); from gi.repository import Vte"; then
    echo "  → VTE absent — tentative d'installation..."
    case "$PKG_MGR" in
        apt)
            pkg_install gir1.2-vte-2.91 2>/dev/null || \
            pkg_install gir1.2-vte-3.91 2>/dev/null || true
            ;;
        dnf)    pkg_install vte291 2>/dev/null || true ;;
        pacman) pkg_install vte3   2>/dev/null || true ;;
        zypper) pkg_install typelib-1_0-Vte-2_91 2>/dev/null || true ;;
    esac
    if _try_import "import gi; gi.require_version('Vte','2.91'); from gi.repository import Vte"; then
        echo "  ✅ VTE installé"
    else
        echo "  ⚠️  VTE indisponible — terminal simplifié activé (fonctionnel)"
    fi
else
    echo "  ✅ VTE présent"
fi

# ── AppIndicator (icône barre des tâches — optionnel) ──
_INDICATOR_OK=false
for _mod in \
    "gi.require_version('AyatanaAppIndicator3','0.1'); from gi.repository import AyatanaAppIndicator3" \
    "gi.require_version('AppIndicator3','0.1'); from gi.repository import AppIndicator3"; do
    _try_import "import gi; $_mod" && { _INDICATOR_OK=true; break; }
done
if ! $_INDICATOR_OK; then
    echo "  → Icône barre des tâches (AppIndicator)..."
    case "$PKG_MGR" in
        apt)
            pkg_install gir1.2-ayatanaappindicator3-0.1 2>/dev/null || \
            pkg_install gir1.2-appindicator3-0.1        2>/dev/null || true ;;
        dnf)    pkg_install libayatana-appindicator-gtk3 2>/dev/null || true ;;
        pacman) pkg_install libayatana-appindicator      2>/dev/null || true ;;
        zypper) pkg_install typelib-1_0-AyatanaAppIndicator3-0_1 2>/dev/null || true ;;
    esac
    _INDICATOR_OK=false
    for _mod in \
        "gi.require_version('AyatanaAppIndicator3','0.1'); from gi.repository import AyatanaAppIndicator3" \
        "gi.require_version('AppIndicator3','0.1'); from gi.repository import AppIndicator3"; do
        _try_import "import gi; $_mod" && { _INDICATOR_OK=true; break; }
    done
    $_INDICATOR_OK && echo "  ✅ AppIndicator installé" \
                   || echo "  ⚠️  AppIndicator indisponible — icône tray basique (Gtk.StatusIcon)"
else
    echo "  ✅ AppIndicator présent"
fi

# ── 2. Dossiers ─────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR" "$DESKTOP_DIR" "$CONFIG_DIR" "$CERT_DIR"

# ── Icône dans le thème système (requis pour dock Ubuntu/GNOME) ──────
ICON_FILE="$INSTALL_DIR/majorelle.svg"

# ── 3. Détection du proxy ───────────────────────────────────────────
if ip -4 addr | grep -q "172.19."; then
    echo "  ✅ Réseau lycée détecté : $PROXY_HOST:$PROXY_PORT"
else
    echo "  ⚠️  Réseau lycée non détecté."
    read -p "  IP du proxy (défaut: $PROXY_HOST) : " INPUT_HOST
    read -p "  Port     (défaut: $PROXY_PORT)   : " INPUT_PORT
    PROXY_HOST="${INPUT_HOST:-$PROXY_HOST}"
    PROXY_PORT="${INPUT_PORT:-$PROXY_PORT}"
fi
PROXY_URL="http://$PROXY_HOST:$PROXY_PORT"

# ── 4. Icône SVG ────────────────────────────────────────────────────
cat > "$ICON_FILE" <<'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#0a1628"/>
      <stop offset="100%" style="stop-color:#162040"/>
    </linearGradient>
    <linearGradient id="g1" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#7b8fe8"/>
      <stop offset="100%" style="stop-color:#c084fc"/>
    </linearGradient>
    <linearGradient id="g2" x1="100%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#38bdf8"/>
      <stop offset="100%" style="stop-color:#7b8fe8"/>
    </linearGradient>
    <filter id="glow">
      <feGaussianBlur stdDeviation="1.5" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <!-- Fond arrondi -->
  <rect width="100" height="100" rx="22" fill="url(#bg)"/>
  <!-- Cercle central — nœud réseau -->
  <circle cx="50" cy="47" r="9" fill="url(#g1)" filter="url(#glow)"/>
  <circle cx="50" cy="47" r="5.5" fill="#0a1628"/>
  <circle cx="50" cy="47" r="2.5" fill="url(#g1)"/>
  <!-- Nœuds satellites -->
  <circle cx="22" cy="30" r="4.5" fill="url(#g2)" filter="url(#glow)"/>
  <circle cx="78" cy="30" r="4.5" fill="url(#g2)" filter="url(#glow)"/>
  <circle cx="18" cy="64" r="3.5" fill="url(#g1)" opacity="0.8"/>
  <circle cx="82" cy="64" r="3.5" fill="url(#g1)" opacity="0.8"/>
  <circle cx="50" cy="76" r="4"   fill="url(#g2)" filter="url(#glow)"/>
  <!-- Liaisons réseau -->
  <g stroke="url(#g1)" stroke-width="1.8" fill="none" opacity="0.7" stroke-linecap="round">
    <line x1="50" y1="38" x2="22" y2="34"/>
    <line x1="50" y1="38" x2="78" y2="34"/>
    <line x1="50" y1="56" x2="18" y2="61"/>
    <line x1="50" y1="56" x2="82" y2="61"/>
    <line x1="50" y1="56" x2="50" y2="72"/>
    <line x1="22" y1="34" x2="18" y2="61"/>
    <line x1="78" y1="34" x2="82" y2="61"/>
  </g>
  <!-- Arc signal (wifi stylisé) en haut -->
  <g stroke="url(#g2)" stroke-width="2.2" fill="none" stroke-linecap="round" opacity="0.5">
    <path d="M36 20 Q50 12 64 20"/>
    <path d="M42 14 Q50 9  58 14"/>
  </g>
  <!-- Label M discret -->
  <text x="50" y="92" text-anchor="middle" font-family="'Cantarell','Ubuntu',sans-serif"
        font-size="7" font-weight="700" fill="#7b8fe8" opacity="0.6" letter-spacing="1">MAJORELLE</text>
</svg>
SVGEOF

# Installer l'icône système (dock Ubuntu, GNOME Shell, Alt+Tab…)
mkdir -p "$ICON_DIR"
cp "$ICON_FILE" "$ICON_DIR/$ICON_NAME.svg"

# Installer dans /usr/share (requis pour apparaître dans le dock comme une vraie app)
sudo mkdir -p "$SYS_ICON_DIR_SVG" "$SYS_ICON_DIR_48" "$SYS_ICON_DIR_256"
sudo cp "$ICON_FILE" "$SYS_ICON_DIR_SVG/$ICON_NAME.svg"

# Convertir le SVG en PNG 48x48 et 256x256 si rsvg-convert ou inkscape disponible
if command -v rsvg-convert &>/dev/null; then
    rsvg-convert -w 48  -h 48  "$ICON_FILE" | sudo tee "$SYS_ICON_DIR_48/$ICON_NAME.png"  >/dev/null
    rsvg-convert -w 256 -h 256 "$ICON_FILE" | sudo tee "$SYS_ICON_DIR_256/$ICON_NAME.png" >/dev/null
elif command -v inkscape &>/dev/null; then
    inkscape "$ICON_FILE" -w 48  -h 48  -o /tmp/majorelle_48.png  2>/dev/null && sudo mv /tmp/majorelle_48.png  "$SYS_ICON_DIR_48/$ICON_NAME.png"
    inkscape "$ICON_FILE" -w 256 -h 256 -o /tmp/majorelle_256.png 2>/dev/null && sudo mv /tmp/majorelle_256.png "$SYS_ICON_DIR_256/$ICON_NAME.png"
elif command -v convert &>/dev/null; then
    convert -background none "$ICON_FILE" -resize 48x48   /tmp/majorelle_48.png  2>/dev/null && sudo mv /tmp/majorelle_48.png  "$SYS_ICON_DIR_48/$ICON_NAME.png"
    convert -background none "$ICON_FILE" -resize 256x256 /tmp/majorelle_256.png 2>/dev/null && sudo mv /tmp/majorelle_256.png "$SYS_ICON_DIR_256/$ICON_NAME.png"
fi

# Mettre à jour le cache d'icônes système
sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
echo "  ✅ Icône installée (système + utilisateur)"

# ── 5. Application Python ────────────────────────────────────────────
echo "→ Génération de l'application..."
cat > "$APP_FILE" <<PYEOF
#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════
#  Réseau Louis Majorelle v0.16.1
# ═══════════════════════════════════════════════════════════════════

import gi
gi.require_version('Gtk', '3.0')

# VTE optionnel (terminal intégré)
HAS_VTE = False
try:
    gi.require_version('Vte', '2.91')
    HAS_VTE = True
except Exception:
    pass

# AppIndicator optionnel (icône barre des tâches système)
HAS_INDICATOR = False
_AppIndicator = None
for _ns, _ver in [('AyatanaAppIndicator3','0.1'), ('AppIndicator3','0.1')]:
    try:
        gi.require_version(_ns, _ver)
        from gi.repository import AyatanaAppIndicator3 as _AI
        _AppIndicator = _AI; HAS_INDICATOR = True; break
    except Exception:
        pass
if not HAS_INDICATOR:
    try:
        from gi.repository import AppIndicator3 as _AI
        _AppIndicator = _AI; HAS_INDICATOR = True
    except Exception:
        pass

from gi.repository import Gtk, Gdk, GLib, GdkPixbuf
if HAS_VTE:
    from gi.repository import Vte

import subprocess, os, re, json, shutil, glob, time, math, urllib.request, threading
try:
    import cairo as _cairo_mod
    HAS_CAIRO = True
except ImportError:
    HAS_CAIRO = False

# ── Config ────────────────────────────────────────────────────────────────────
_DEFAULT_PROXY_HOST = "$PROXY_HOST"
_DEFAULT_PROXY_PORT = $PROXY_PORT

INSTALL_DIR = os.path.expanduser("~/.local/share/$APP_ID")
CONFIG_DIR  = os.path.expanduser("~/.config/$APP_ID")
APP_VERSION = "$VERSION"
CERT_DIR    = os.path.join(CONFIG_DIR, "certs")
os.makedirs(CERT_DIR, exist_ok=True)
CONFIG_FILE    = os.path.join(CONFIG_DIR, "config.json")
PROFILES_FILE  = os.path.join(CONFIG_DIR, "profiles.json")
LOCAL_APPS     = os.path.expanduser("~/.local/share/applications")
AUTOSTART_FILE = os.path.expanduser("~/.config/autostart/$APP_ID.desktop")
os.makedirs(CONFIG_DIR, exist_ok=True)

DEFAULT_CFG = {
    "theme":           "dark",
    "accent":          "#7b8fe8",
    "font_size":       10,
    "font_family":     "Cantarell",
    "border_radius":   12,
    "sidebar_opacity": 100,
    "nav_style":       "pill",
    "tray_icon":       "default",
    "custom_apps":     [],
    "proxy_host":      _DEFAULT_PROXY_HOST,
    "proxy_port":      _DEFAULT_PROXY_PORT,
    "autostart":       False,
    "tray_on_close":   True,
    "start_minimized": False,
    "active_profile":  "lycee",
}

# ── Profils réseau ────────────────────────────────────────────────────────────
DEFAULT_PROFILES = {
    "lycee": {
        "label":       "Lycée",
        "emoji":       "🏫",
        "proxy_host":  _DEFAULT_PROXY_HOST,
        "proxy_port":  _DEFAULT_PROXY_PORT,
        "proxy_on":    True,
        "services": {
            "apt": True, "snap": True, "flatpak": True,
            "git": True, "pip":  True, "npm":     True,
            "wget": True, "docker": True,
        },
        "builtin": True,
    },
    "maison": {
        "label":      "Maison",
        "emoji":      "🏠",
        "proxy_host": "",
        "proxy_port": 0,
        "proxy_on":   False,
        "services": {
            "apt": False, "snap": False, "flatpak": False,
            "git": False, "pip":  False, "npm":     False,
            "wget": False, "docker": False,
        },
        "builtin": True,
    },
    "mobile": {
        "label":      "Partage mobile",
        "emoji":      "📱",
        "proxy_host": "",
        "proxy_port": 0,
        "proxy_on":   False,
        "services": {
            "apt": False, "snap": False, "flatpak": False,
            "git": False, "pip":  False, "npm":     False,
            "wget": False, "docker": False,
        },
        "builtin": True,
    },
}

def load_profiles():
    try:
        with open(PROFILES_FILE) as f:
            data = json.load(f)
        # S'assurer que les profils builtins existent toujours
        for pid, pdata in DEFAULT_PROFILES.items():
            data.setdefault(pid, dict(pdata))
        return data
    except Exception:
        return dict(DEFAULT_PROFILES)

def save_profiles(profiles):
    with open(PROFILES_FILE, "w") as f:
        json.dump(profiles, f, indent=2)

PROFILES = load_profiles()

def apply_profile(profile_id):
    """Applique un profil : met à jour proxy + services + CFG."""
    global PROFILES
    PROFILES = load_profiles()
    prof = PROFILES.get(profile_id)
    if not prof:
        return False

    # Mettre à jour le proxy
    if prof["proxy_on"] and prof["proxy_host"]:
        CFG["proxy_host"] = prof["proxy_host"]
        CFG["proxy_port"] = prof["proxy_port"]
        set_system_proxy(True)
    else:
        set_system_proxy(False)

    _rebuild_proxy()

    # Appliquer les services
    svc_map = {
        "apt":    write_apt_proxy,
        "snap":   write_snap_proxy,
        "flatpak":write_flatpak_proxy,
        "git":    write_git_proxy,
        "pip":    write_pip_proxy,
        "npm":    write_npm_proxy,
        "wget":   lambda e: (write_wget_proxy(e), write_curl_proxy(e)),
        "docker": write_docker_proxy,
    }
    for svc, fn in svc_map.items():
        try:
            fn(prof["services"].get(svc, False))
        except Exception:
            pass

    CFG["active_profile"] = profile_id
    save_cfg(CFG)
    log(f"Profil appliqué : {prof['label']}")
    return True

def load_cfg():
    try:
        with open(CONFIG_FILE) as f:
            c = json.load(f)
        for k, v in DEFAULT_CFG.items():
            c.setdefault(k, v)
        return c
    except:
        return dict(DEFAULT_CFG)

def save_cfg(c):
    with open(CONFIG_FILE, "w") as f:
        json.dump(c, f, indent=2)

CFG = load_cfg()

# Proxy dynamique — modifiable depuis l'UI
PROXY_HOST = CFG["proxy_host"]
PROXY_PORT = CFG["proxy_port"]
PROXY_URL  = f"http://{PROXY_HOST}:{PROXY_PORT}"
PROXY_ENV  = (f"HTTPS_PROXY={PROXY_URL} HTTP_PROXY={PROXY_URL} "
              f"http_proxy={PROXY_URL} https_proxy={PROXY_URL}")

def _rebuild_proxy():
    global PROXY_HOST, PROXY_PORT, PROXY_URL, PROXY_ENV
    PROXY_HOST = CFG["proxy_host"]
    PROXY_PORT = CFG["proxy_port"]
    PROXY_URL  = f"http://{PROXY_HOST}:{PROXY_PORT}"
    PROXY_ENV  = (f"HTTPS_PROXY={PROXY_URL} HTTP_PROXY={PROXY_URL} "
                  f"http_proxy={PROXY_URL} https_proxy={PROXY_URL}")

# ── Palettes de couleurs ──────────────────────────────────────────────────────
# Chaque palette : WIN, SIDE, MAIN, CARD, HOVER, BORDER, FG, FG2, SEP
COLOR_PALETTES = {
    # ── Sombres ──
    "dark":        ("#0b1120","#0d1530","#0f1a38","#152040","#1c2b50","#1e2e55","#e2e8f8","#7a8ab0","#182045"),
    "minuit":      ("#09090f","#0f0f1a","#111120","#181828","#20203a","#252540","#dcdcf0","#7070a0","#141428"),
    "foret":       ("#091510","#0c1c12","#0e2016","#12291a","#193826","#1a3d28","#d4edd8","#6a9870","#102014"),
    "bordeaux":    ("#130a0a","#1c0c0c","#200e0e","#2a1010","#3a1515","#421818","#f0d8d8","#aa7070","#1a0c0c"),
    "ocean":       ("#060e18","#081525","#0a1a30","#0d2240","#102c55","#123060","#d0e8ff","#5a90c0","#081020"),
    "charbon":     ("#111111","#181818","#1c1c1c","#242424","#2e2e2e","#333333","#e8e8e8","#888888","#1a1a1a"),
    "violet_nuit": ("#0e0818","#140c22","#180e28","#1e1232","#281845","#2c1c4e","#e8d8ff","#9070c0","#100a1c"),
    "cafe":        ("#110d08","#1a1208","#1e160a","#271a0c","#352312","#3c2815","#eeddc8","#9a7858","#180f08"),
    # ── Clairs ──
    "light":       ("#f0f2fa","#e4e8f6","#f5f7ff","#ffffff","#dce1f5","#c8ceea","#111827","#4a5568","#d0d6ec"),
    "creme":       ("#f8f4ec","#efe8d8","#faf7f0","#ffffff","#e8dfcc","#d8ceba","#2a2015","#7a6848","#e0d8c8"),
    "rosé":        ("#fdf2f4","#f5e0e4","#fef5f7","#ffffff","#f0d0d8","#e8b8c4","#3a1020","#9a5868","#f0d8dc"),
    "sage":        ("#f2f6f2","#e2ece2","#f5faf5","#ffffff","#d4e8d4","#c0d8c0","#1a2e1a","#507050","#d8ecd8"),
}

PALETTE_LABELS = {
    "dark":        "Nuit (défaut)",
    "minuit":      "Minuit",
    "foret":       "Forêt",
    "bordeaux":    "Bordeaux",
    "ocean":       "Océan",
    "charbon":     "Charbon",
    "violet_nuit": "Violet nuit",
    "cafe":        "Café",
    "light":       "Lumière",
    "creme":       "Crème",
    "rosé":        "Rosé",
    "sage":        "Sauge",
}

def _hex_to_rgba(h, a):
    h = h.lstrip('#')
    r,g,b = int(h[0:2],16), int(h[2:4],16), int(h[4:6],16)
    return f"rgba({r},{g},{b},{a:.2f})"

# ── CSS ───────────────────────────────────────────────────────────────────────
def build_css(cfg):
    acc  = cfg.get("accent", "#7b8fe8")
    theme = cfg.get("theme", "dark")
    fs   = cfg.get("font_size", 10)
    fs_s = fs - 1      # small
    fs_l = fs + 4      # page title
    ff   = cfg.get("font_family", "Cantarell")
    br   = cfg.get("border_radius", 12)       # border-radius cards
    br_s = max(4, br - 4)                     # border-radius buttons
    op   = cfg.get("sidebar_opacity", 100) / 100.0
    nav  = cfg.get("nav_style", "pill")       # pill | underline | square

    palette = COLOR_PALETTES.get(theme, COLOR_PALETTES["dark"])
    WIN, SIDE, MAIN, CARD, HOVER, BORDER, FG, FG2, SEP = palette
    SIDE_BG = _hex_to_rgba(SIDE, op) if op < 1.0 else SIDE

    # Nav button style variants
    if nav == "pill":
        NAV_ACTIVE_EXTRA = f"border-radius: {br_s}px; background-color: {HOVER};"
        NAV_HOVER_EXTRA  = f"border-radius: {br_s}px;"
    elif nav == "underline":
        NAV_ACTIVE_EXTRA = f"border-radius: 0; background-color: transparent; border-bottom: 2px solid {acc}; padding-bottom: 7px;"
        NAV_HOVER_EXTRA  = "border-radius: 0; background-color: transparent;"
    else:  # square
        NAV_ACTIVE_EXTRA = f"border-radius: 4px; background-color: {HOVER};"
        NAV_HOVER_EXTRA  = "border-radius: 4px;"

    return f"""
* {{ outline: none; }}
window {{
    background-color: {WIN};
    color: {FG};
    font-family: '{ff}', 'Ubuntu', sans-serif;
    font-size: {fs}pt;
}}
#sidebar {{
    background-color: {SIDE_BG};
    border-right: none;
    min-width: 210px;
}}
#sidebar-header {{
    padding: 22px 16px 14px 16px;
    border-bottom: 1px solid {SEP};
}}
#app-name {{
    font-size: {fs+1}pt;
    font-weight: 700;
    color: {FG};
}}
#app-sub {{
    font-size: {fs_s}pt;
    color: {FG2};
}}
.nav-btn {{
    background-color: transparent;
    border: none;
    border-radius: {br_s}px;
    color: {FG2};
    padding: 9px 14px;
    margin: 1px 10px;
    font-size: {fs}pt;
}}
.nav-btn:hover {{
    {NAV_HOVER_EXTRA}
    background-color: {HOVER};
    color: {FG};
}}
.nav-btn-active {{
    {NAV_ACTIVE_EXTRA}
    color: {acc};
    font-weight: 600;
}}
#sidebar-footer {{
    border-top: 1px solid {SEP};
    padding: 14px 16px;
}}
#content {{
    background-color: {MAIN};
}}
.page-title {{
    font-size: {fs_l}pt;
    font-weight: 700;
    color: {FG};
}}
.page-sub {{
    font-size: {fs_s}pt;
    color: {FG2};
}}
.card {{
    background-color: {CARD};
    border-radius: {br}px;
    border: 1px solid {BORDER};
    padding: 14px 16px;
    min-width: 0;
}}
.card-title {{
    font-size: {fs}pt;
    font-weight: 600;
    color: {FG};
}}
.card-sub {{
    font-size: {fs_s}pt;
    color: {FG2};
}}
switch {{
    background-color: {HOVER};
    border-radius: 14px;
    min-height: 22px;
    min-width: 42px;
}}
switch:checked {{
    background-color: {acc};
}}
switch slider {{
    background-color: white;
    border-radius: 50%;
    min-height: 16px;
    min-width: 16px;
    margin: 2px;
}}
.badge-on {{
    background-color: alpha(#34d399, 0.14);
    color: #34d399;
    border-radius: 20px;
    padding: 2px 10px;
    font-size: {fs_s}pt;
    font-weight: 600;
}}
.badge-off {{
    background-color: {HOVER};
    color: {FG2};
    border-radius: 20px;
    padding: 2px 10px;
    font-size: {fs_s}pt;
}}
.badge-na {{
    background-color: alpha(#fb923c, 0.12);
    color: #fb923c;
    border-radius: 20px;
    padding: 2px 10px;
    font-size: {fs_s}pt;
}}
.btn-accent {{
    background-color: {acc};
    color: white;
    border-radius: {br_s}px;
    padding: 7px 16px;
    font-weight: 600;
    font-size: {fs}pt;
}}
.btn-accent:hover {{
    background-color: {HOVER};
    color: {acc};
    outline: 1px solid {acc};
}}
.btn-ghost {{
    background-color: {HOVER};
    color: {FG};
    border-radius: {br_s}px;
    padding: 6px 14px;
    font-size: {fs}pt;
}}
.btn-ghost:hover {{ background-color: {BORDER}; }}
.btn-danger {{
    background-color: alpha(#ef4444, 0.10);
    color: #ef4444;
    border-radius: {br_s}px;
    padding: 6px 12px;
    font-size: {fs}pt;
}}
.btn-danger:hover {{ background-color: alpha(#ef4444, 0.20); }}
#statusbar {{
    background-color: {SIDE_BG};
    padding: 6px 16px;
}}
separator {{ background-color: {SEP}; min-height: 1px; margin: 4px 0; }}
entry {{
    background-color: {CARD};
    border-radius: {br_s}px;
    color: {FG};
    padding: 6px 10px;
    font-size: {fs}pt;
}}
entry:focus {{ outline-color: {acc}; }}
scrollbar {{ background-color: transparent; min-width: 5px; }}
scrollbar slider {{
    background-color: {BORDER};
    border-radius: 3px;
    min-width: 5px;
    min-height: 28px;
}}
scrollbar slider:hover {{ background-color: {FG2}; }}
.section-label {{
    font-size: {fs_s}pt;
    font-weight: 700;
    color: {FG2};
    margin-bottom: 4px;
    margin-top: 8px;
}}
.info-key {{
    font-size: {fs}pt;
    color: {FG2};
    min-width: 80px;
}}
.info-val {{
    font-size: {fs}pt;
    color: {FG};
    font-family: 'Ubuntu Mono', monospace;
}}
.swatch {{
    border-radius: 50%;
    min-width: 26px;
    min-height: 26px;
    border: 2px solid transparent;
    padding: 0;
}}
.swatch-active {{ outline: 2px solid {FG}; outline-offset: 1px; }}
.term-toolbar {{
    background-color: {SIDE_BG};
    border-bottom: 1px solid {BORDER};
    padding: 6px 12px;
}}
.quick-btn {{
    background-color: {CARD};
    color: {FG2};
    border: 1px solid {BORDER};
    border-radius: {br_s}px;
    padding: 4px 10px;
    font-size: {fs_s}pt;
    font-family: 'Ubuntu Mono', monospace;
}}
.quick-btn:hover {{
    background-color: {HOVER};
    color: {FG};
}}
scale trough {{
    background-color: {HOVER};
    border-radius: 4px;
    min-height: 4px;
}}
scale highlight {{
    background-color: {acc};
    border-radius: 4px;
}}
scale slider {{
    background-color: {acc};
    border-radius: 50%;
    min-width: 16px;
    min-height: 16px;
    border: none;
}}
"""

_css_prov = None
def apply_css(cfg):
    global _css_prov
    if _css_prov:
        Gtk.StyleContext.remove_provider_for_screen(Gdk.Screen.get_default(), _css_prov)
    _css_prov = Gtk.CssProvider()
    _css_prov.load_from_data(build_css(cfg).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), _css_prov,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

# ── Logique proxy système ─────────────────────────────────────────────────────
def runcmd(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)

def get_proxy_mode():
    r = runcmd(["gsettings","get","org.gnome.system.proxy","mode"], text=True)
    return r.stdout.strip().strip("'")

def has_snap():    return os.path.exists("/usr/bin/snap")
def has_flatpak(): return os.path.exists("/usr/bin/flatpak")
def has_rpm():     return os.path.exists("/usr/bin/rpm") or os.path.exists("/usr/bin/dnf")
def has_npm():     return runcmd(["which","npm"]).returncode == 0
def has_git():     return runcmd(["which","git"]).returncode == 0
def has_docker():  return os.path.exists("/usr/bin/docker") or os.path.exists("/usr/local/bin/docker")

# ── Proxy global (GNOME) ──────────────────────────────────────────────────────
def set_system_proxy(enable):
    if enable:
        runcmd(["gsettings","set","org.gnome.system.proxy","mode","manual"])
        for p in ("http","https"):
            runcmd(["gsettings","set",f"org.gnome.system.proxy.{p}","host",PROXY_HOST])
            runcmd(["gsettings","set",f"org.gnome.system.proxy.{p}","port",str(PROXY_PORT)])
        runcmd(["gsettings","set","org.gnome.system.proxy","ignore-hosts",
                "['localhost','127.0.0.0/8','::1','10.0.0.0/8','192.168.0.0/16','172.16.0.0/12']"])
    else:
        runcmd(["gsettings","set","org.gnome.system.proxy","mode","none"])

# ── APT ───────────────────────────────────────────────────────────────────────
def write_apt_proxy(enable):
    path = "/etc/apt/apt.conf.d/99-proxy-majorelle"
    if enable:
        content = (f'Acquire::http::Proxy "{PROXY_URL}";\n'
                   f'Acquire::https::Proxy "{PROXY_URL}";\n'
                   f'Acquire::ftp::Proxy "{PROXY_URL}";\n')
        subprocess.run(["sudo","tee",path], input=content.encode(), capture_output=True)
    else:
        subprocess.run(["sudo","rm","-f",path], capture_output=True)

def apt_proxy_active():
    return os.path.exists("/etc/apt/apt.conf.d/99-proxy-majorelle")

# ── Snap ──────────────────────────────────────────────────────────────────────
def write_snap_proxy(enable):
    if not has_snap(): return
    if enable:
        subprocess.run(["sudo","snap","set","system",f"proxy.http={PROXY_URL}"],  capture_output=True)
        subprocess.run(["sudo","snap","set","system",f"proxy.https={PROXY_URL}"], capture_output=True)
    else:
        subprocess.run(["sudo","snap","unset","system","proxy.http"],  capture_output=True)
        subprocess.run(["sudo","snap","unset","system","proxy.https"], capture_output=True)

def snap_proxy_active():
    if not has_snap(): return False
    r = subprocess.run(["snap","get","system","proxy.http"], capture_output=True, text=True)
    return bool(r.stdout.strip())

# ── Flatpak ───────────────────────────────────────────────────────────────────
def write_flatpak_proxy(enable):
    if not has_flatpak(): return
    if enable:
        subprocess.run(["sudo","flatpak","config","--system","--set","http-proxy",PROXY_URL], capture_output=True)
    else:
        subprocess.run(["sudo","flatpak","config","--system","--unset","http-proxy"], capture_output=True)

def flatpak_proxy_active():
    if not has_flatpak(): return False
    r = subprocess.run(["flatpak","config","--system","http-proxy"], capture_output=True, text=True)
    return PROXY_HOST in r.stdout

# ── Git ───────────────────────────────────────────────────────────────────────
def write_git_proxy(enable):
    if not has_git(): return
    if enable:
        subprocess.run(["git","config","--global","http.proxy", PROXY_URL],  capture_output=True)
        subprocess.run(["git","config","--global","https.proxy",PROXY_URL],  capture_output=True)
    else:
        subprocess.run(["git","config","--global","--unset","http.proxy"],   capture_output=True)
        subprocess.run(["git","config","--global","--unset","https.proxy"],  capture_output=True)

def git_proxy_active():
    if not has_git(): return False
    r = subprocess.run(["git","config","--global","http.proxy"], capture_output=True, text=True)
    return bool(r.stdout.strip())

# ── Pip ───────────────────────────────────────────────────────────────────────
def write_pip_proxy(enable):
    pip_conf = os.path.expanduser("~/.config/pip/pip.conf")
    os.makedirs(os.path.dirname(pip_conf), exist_ok=True)
    try:
        import configparser
        cfg = configparser.ConfigParser()
        if os.path.exists(pip_conf): cfg.read(pip_conf)
        if not cfg.has_section("global"): cfg.add_section("global")
        if enable: cfg.set("global","proxy",PROXY_URL)
        else:      cfg.remove_option("global","proxy")
        with open(pip_conf,"w") as f: cfg.write(f)
    except Exception: pass

def pip_proxy_active():
    pip_conf = os.path.expanduser("~/.config/pip/pip.conf")
    try:
        import configparser
        cfg = configparser.ConfigParser()
        cfg.read(pip_conf)
        return cfg.has_option("global","proxy")
    except Exception: return False

# ── npm ───────────────────────────────────────────────────────────────────────
def write_npm_proxy(enable):
    if not has_npm(): return
    if enable:
        subprocess.run(["npm","config","set","proxy",       PROXY_URL], capture_output=True)
        subprocess.run(["npm","config","set","https-proxy", PROXY_URL], capture_output=True)
    else:
        subprocess.run(["npm","config","delete","proxy"],        capture_output=True)
        subprocess.run(["npm","config","delete","https-proxy"],  capture_output=True)

def npm_proxy_active():
    if not has_npm(): return False
    r = subprocess.run(["npm","config","get","proxy"], capture_output=True, text=True)
    v = r.stdout.strip()
    return v not in ("","undefined","null")

# ── wget ──────────────────────────────────────────────────────────────────────
def write_wget_proxy(enable):
    wgetrc = os.path.expanduser("~/.wgetrc")
    proxy_keys = ["http_proxy","https_proxy","ftp_proxy","use_proxy"]
    try:
        lines = open(wgetrc).readlines() if os.path.exists(wgetrc) else []
        lines = [l for l in lines if not any(l.startswith(k+"=") for k in proxy_keys)]
        if enable:
            lines += [f"http_proxy={PROXY_URL}\n",f"https_proxy={PROXY_URL}\n","use_proxy=on\n"]
        with open(wgetrc,"w") as f: f.writelines(lines)
    except Exception: pass

def wget_proxy_active():
    wgetrc = os.path.expanduser("~/.wgetrc")
    try: return "http_proxy" in open(wgetrc).read()
    except Exception: return False

# ── curl ──────────────────────────────────────────────────────────────────────
def write_curl_proxy(enable):
    curlrc = os.path.expanduser("~/.curlrc")
    try:
        lines = open(curlrc).readlines() if os.path.exists(curlrc) else []
        lines = [l for l in lines if not l.startswith("proxy=") and not l.startswith("noproxy=")]
        if enable: lines += [f"proxy={PROXY_URL}\n","noproxy=localhost,127.0.0.1,::1\n"]
        with open(curlrc,"w") as f: f.writelines(lines)
    except Exception: pass

def curl_proxy_active():
    curlrc = os.path.expanduser("~/.curlrc")
    try: return "proxy=" in open(curlrc).read()
    except Exception: return False

# ── Docker daemon ─────────────────────────────────────────────────────────────
def write_docker_proxy(enable):
    if not has_docker(): return
    conf_dir  = "/etc/systemd/system/docker.service.d"
    conf_path = f"{conf_dir}/proxy-majorelle.conf"
    no_proxy  = "localhost,127.0.0.0/8,::1,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12"
    if enable:
        content = (f'[Service]\nEnvironment="HTTP_PROXY={PROXY_URL}"\n'
                   f'Environment="HTTPS_PROXY={PROXY_URL}"\n'
                   f'Environment="NO_PROXY={no_proxy}"\n')
        subprocess.run(["sudo","mkdir","-p",conf_dir], capture_output=True)
        subprocess.run(["sudo","tee",conf_path], input=content.encode(), capture_output=True)
    else:
        subprocess.run(["sudo","rm","-f",conf_path], capture_output=True)
    subprocess.run(["sudo","systemctl","daemon-reload"],    capture_output=True)
    subprocess.run(["sudo","systemctl","restart","docker"], capture_output=True)

def docker_proxy_active():
    return os.path.exists("/etc/systemd/system/docker.service.d/proxy-majorelle.conf")

# ── Certificat 802.1X ─────────────────────────────────────────────────────────
def cert_installed():
    return os.path.exists(os.path.join(CERT_DIR, "certificate.pkcs12"))

def cert_cn():
    try:
        return open(os.path.join(CERT_DIR, "cn.txt")).read().strip() or "Inconnu"
    except Exception:
        return "Aucun certificat"

def cert_expiry():
    try:
        return open(os.path.join(CERT_DIR, "expiry.txt")).read().strip() or "Inconnue"
    except Exception:
        return "Inconnue"

def cert_find_password(p12_path, candidate=None):
    """
    Essaie de trouver le mot de passe d'un .pkcs12.
    Si candidate est fourni, l'essaie en premier.
    Retourne le mot de passe trouvé ou None.
    """
    candidates = []
    if candidate:
        candidates.append(candidate)
    # Mots de passe courants lycée / onboarding
    candidates += [
        "",           # sans mot de passe
        "changeit",   # défaut Java / Cisco ISE
        "password",
        "Password1",
        "cisco",
        "admin",
        "reseau",
        "lycee",
        "majorelle",
    ]
    for pwd in candidates:
        r = subprocess.run(
            ["openssl","pkcs12","-in",p12_path,"-nokeys","-noout",
             "-passin",f"pass:{pwd}"],
            capture_output=True)
        if r.returncode == 0:
            return pwd
    return None

def cert_strip_password(p12_path, password):
    """
    Crée une copie du .pkcs12 sans mot de passe.
    Retourne le chemin du nouveau fichier ou None si échec.
    """
    out_path = p12_path + ".nopass.p12"
    try:
        # Extraire tous les contenus puis recréer sans mot de passe
        r = subprocess.run(
            ["openssl","pkcs12","-in",p12_path,
             "-passin",f"pass:{password}",
             "-passout","pass:",
             "-out",out_path],
            capture_output=True)
        if r.returncode == 0 and os.path.exists(out_path):
            return out_path
    except Exception:
        pass
    return None

def cert_import(p12_path, password=None):
    """Importe un certificat PKCS#12. Retourne (True, msg) ou (False, erreur)."""
    try:
        import shutil

        # Trouver le mot de passe automatiquement si non fourni ou si invalide
        found_pwd = cert_find_password(p12_path, candidate=password)
        if found_pwd is None:
            return False, "Mot de passe introuvable — essayez de le saisir manuellement"
        password = found_pwd

        # Si un mot de passe a été trouvé, créer une version sans mot de passe
        stripped = cert_strip_password(p12_path, password)
        src = stripped if stripped else p12_path
        src_pwd = "" if stripped else password

        # Copier le .pkcs12 sans mot de passe dans le dossier de config
        dest_p12 = os.path.join(CERT_DIR, "certificate.pkcs12")
        shutil.copy(src, dest_p12)
        os.chmod(dest_p12, 0o600)

        # Extraire CA
        subprocess.run(["openssl","pkcs12","-in",dest_p12,"-nokeys","-cacerts",
            "-passin","pass:","-passout","pass:",
            "-out",os.path.join(CERT_DIR,"ca.crt")],
            capture_output=True)

        # Extraire cert client
        subprocess.run(["openssl","pkcs12","-in",dest_p12,"-nokeys","-clcerts",
            "-passin","pass:","-passout","pass:",
            "-out",os.path.join(CERT_DIR,"client.crt")],
            capture_output=True)

        # Extraire clé privée (sans chiffrement)
        subprocess.run(["openssl","pkcs12","-in",dest_p12,"-nocerts","-nodes",
            "-passin","pass:",
            "-out",os.path.join(CERT_DIR,"client.key")],
            capture_output=True)
        os.chmod(os.path.join(CERT_DIR, "client.key"), 0o600)

        # Nettoyer le fichier temporaire
        if stripped and os.path.exists(stripped):
            os.remove(stripped)

        # Lire CN
        r_cert = subprocess.run(
            ["openssl","pkcs12","-in",dest_p12,"-nokeys","-clcerts",
             "-passin","pass:","-passout","pass:"],
            capture_output=True, text=True)
        r_cn = subprocess.run(
            ["openssl","x509","-noout","-subject"],
            input=r_cert.stdout, capture_output=True, text=True)
        cn = r_cn.stdout.strip().split("CN")[-1].lstrip(" =").split(",")[0].strip()
        with open(os.path.join(CERT_DIR,"cn.txt"),"w") as f:
            f.write(cn or "Inconnu")

        # Lire expiry
        r_exp = subprocess.run(
            ["openssl","x509","-noout","-enddate"],
            input=r_cert.stdout, capture_output=True, text=True)
        expiry = r_exp.stdout.strip().replace("notAfter=","")
        with open(os.path.join(CERT_DIR,"expiry.txt"),"w") as f:
            f.write(expiry or "Inconnue")

        # Importer dans NSS (Chrome/Chromium)
        nssdb = os.path.expanduser("~/.pki/nssdb")
        if subprocess.run(["which","certutil"],capture_output=True).returncode == 0:
            os.makedirs(nssdb, exist_ok=True)
            subprocess.run(["certutil","-d",f"sql:{nssdb}","-N","--empty-password"],
                capture_output=True)
            subprocess.run(["certutil","-d",f"sql:{nssdb}","-A","-n","Majorelle-CA",
                "-t","CT,,","-i",os.path.join(CERT_DIR,"ca.crt")],
                capture_output=True)
            subprocess.run(["pk12util","-d",f"sql:{nssdb}","-i",dest_p12,"-W",""],
                capture_output=True)

        # Configurer NetworkManager 802.1X
        _cert_configure_nm()

        pwd_msg = "sans mot de passe" if found_pwd == "" else "mot de passe retiré automatiquement"
        return True, f"Certificat importé ({pwd_msg})\nIdentité : {cn}\nExpiration : {expiry}"
    except Exception as e:
        return False, str(e)

def cert_remove():
    """Supprime le certificat installé."""
    import shutil
    for f in ["certificate.pkcs12","ca.crt","client.crt","client.key","cn.txt","expiry.txt"]:
        try: os.remove(os.path.join(CERT_DIR, f))
        except Exception: pass
    # Supprimer de NM
    try:
        r = subprocess.run(["nmcli","-t","-f","NAME,TYPE","connection","show","--active"],
            capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if "802-3-ethernet" in line:
                con = line.split(":")[0]
                subprocess.run(["nmcli","connection","modify",con,
                    "802-1x.eap","","802-1x.ca-cert","",
                    "802-1x.client-cert","","802-1x.private-key",""],
                    capture_output=True)
    except Exception:
        pass

def _cert_configure_nm():
    """Injecte le certificat dans la connexion 'Etablissement' existante."""
    try:
        r = subprocess.run(
            ["nmcli","-t","-f","NAME,TYPE","connection","show"],
            capture_output=True, text=True)
        etab_con = None
        for line in r.stdout.splitlines():
            if "etablissement" in line.lower() or "Etablissement" in line:
                etab_con = line.split(":")[0]
                break
        if not etab_con:
            log("NM : connexion 'Etablissement' introuvable")
            return
        cn = cert_cn()
        subprocess.run([
            "nmcli","connection","modify", etab_con,
            "wifi-sec.key-mgmt","wpa-eap",
            "802-1x.eap","tls",
            "802-1x.identity", cn,
            "802-1x.ca-cert",     os.path.join(CERT_DIR,"ca.crt"),
            "802-1x.client-cert", os.path.join(CERT_DIR,"client.crt"),
            "802-1x.private-key", os.path.join(CERT_DIR,"client.key"),
            "802-1x.private-key-password","",
            "connection.autoconnect","yes",
        ], capture_output=True)
        log(f"NM : certificat injecté dans '{etab_con}'")
    except Exception as e:
        log(f"NM 802.1X config error: {e}")

# ── Logique .desktop ──────────────────────────────────────────────────────────
def find_desktop(paths):
    for p in paths:
        if os.path.exists(p): return p
    return None

def desktop_has_proxy(local):
    if not local or not os.path.exists(local): return False
    with open(local) as f: return "HTTPS_PROXY" in f.read()

def set_desktop_proxy(src_paths, local, enable, extra=""):
    src = find_desktop(src_paths)
    if src is None: return "Fichier .desktop introuvable."
    if src != local: shutil.copy(src, local)
    with open(local) as f: lines = f.readlines()
    out = []
    for line in lines:
        if line.startswith("Exec="):
            line = line.rstrip("\n")
            line = re.sub(r'env\s+((?:[A-Za-z_]+=\S+\s+)+)', '', line)
            line = re.sub(r'\s*-http-proxy\s+\S+', '', line)
            if enable:
                line = line.replace("Exec=", f"Exec=env {PROXY_ENV} ", 1)
                if extra:
                    line = (line.replace("%U", f"{extra} %U") if "%U" in line
                            else line.rstrip() + f" {extra}")
            line += "\n"
        out.append(line)
    with open(local, "w") as f: f.writelines(out)
    subprocess.run(["update-desktop-database", LOCAL_APPS], capture_output=True)
    return None

# ── Apps intégrées ────────────────────────────────────────────────────────────
APPS_BUILTIN = [
    {"id":"discord","label":"Discord","color":"#5865f2",
     "desc":"Client de discussion (Electron)",
     "paths":[f"{LOCAL_APPS}/discord.desktop",
              "/usr/share/applications/discord.desktop",
              "/usr/local/share/applications/discord.desktop",
              "/var/lib/snapd/desktop/applications/discord_discord.desktop"],
     "local":f"{LOCAL_APPS}/discord.desktop","extra":""},
    {"id":"steam","label":"Steam","color":"#1b2838",
     "desc":"Plateforme de jeux Valve",
     "paths":[f"{LOCAL_APPS}/steam.desktop",
              "/usr/share/applications/steam.desktop",
              "/var/lib/snapd/desktop/applications/steam_steam.desktop"],
     "local":f"{LOCAL_APPS}/steam.desktop","extra":f"-http-proxy {PROXY_URL}"},
    {"id":"spotify","label":"Spotify","color":"#1db954",
     "desc":"Streaming musical (Electron)",
     "paths":[f"{LOCAL_APPS}/spotify.desktop",
              "/usr/share/applications/spotify.desktop",
              "/var/lib/snapd/desktop/applications/spotify_spotify.desktop"],
     "local":f"{LOCAL_APPS}/spotify.desktop","extra":""},
    {"id":"vscode","label":"VS Code","color":"#007acc",
     "desc":"Éditeur de code (Electron)",
     "paths":[f"{LOCAL_APPS}/code.desktop",
              "/usr/share/applications/code.desktop",
              "/var/lib/snapd/desktop/applications/code_code.desktop"],
     "local":f"{LOCAL_APPS}/code.desktop","extra":""},
    {"id":"arduino","label":"Arduino IDE","color":"#00979d",
     "desc":"preferences.txt + arduino-cli.yaml",
     "paths":None,"local":None,"extra":""},
    {"id":"sober","label":"Sober (Roblox)","color":"#e8192c",
     "desc":"Flatpak override --user --env",
     "paths":None,"local":None,"extra":""},
]

# Arduino
ARDUINO1 = os.path.expanduser("~/.arduino15/preferences.txt")
ARDUINO2 = os.path.expanduser("~/.arduino15/arduino-cli.yaml")
def _upref(path,key,val):
    if not os.path.exists(path): return
    with open(path) as f: lines=f.readlines()
    found,out=[],[]
    for l in lines:
        if l.startswith(key+"="): out.append(f"{key}={val}\n"); found=True
        else: out.append(l)
    if not found: out.append(f"{key}={val}\n")
    with open(path,"w") as f: f.writelines(out)
def _rmref(path,key):
    if not os.path.exists(path): return
    with open(path) as f: lines=f.readlines()
    with open(path,"w") as f: [f.write(l) for l in lines if not l.startswith(key+"=")]
def arduino_installed(): return os.path.exists(ARDUINO1) or os.path.exists(ARDUINO2)
def arduino_status():
    if os.path.exists(ARDUINO1):
        with open(ARDUINO1) as f:
            if f"proxy.manual.http={PROXY_HOST}" in f.read(): return True
    if os.path.exists(ARDUINO2):
        with open(ARDUINO2) as f:
            if PROXY_HOST in f.read(): return True
    return False
def set_arduino(enable):
    if os.path.exists(ARDUINO1):
        if enable:
            for k,v in [("proxy.manual.http",PROXY_HOST),
                        ("proxy.manual.http_port",str(PROXY_PORT)),
                        ("proxy.manual.https",PROXY_HOST),
                        ("proxy.manual.https_port",str(PROXY_PORT)),
                        ("proxy.type","MANUAL")]:
                _upref(ARDUINO1,k,v)
        else:
            for k in ("proxy.manual.http","proxy.manual.http_port",
                      "proxy.manual.https","proxy.manual.https_port"):
                _rmref(ARDUINO1,k)
            _upref(ARDUINO1,"proxy.type","NONE")
    os.makedirs(os.path.dirname(ARDUINO2),exist_ok=True)
    _proxy_val = PROXY_URL if enable else ""
    with open(ARDUINO2,"w") as f:
        f.write(f'network:\n  proxy: "{_proxy_val}"\n')
    return None

# Sober
SOBER_ID = "org.vinegarhq.Sober"
def sober_installed():
    if not has_flatpak(): return False
    r=runcmd(["flatpak","list","--app","--columns=application"],text=True)
    return SOBER_ID in r.stdout
def sober_status():
    if not sober_installed(): return False
    r=runcmd(["flatpak","override","--user","--show",SOBER_ID],text=True)
    return "HTTPS_PROXY" in r.stdout
def set_sober(enable):
    if not sober_installed(): return "Sober introuvable — installe-le depuis Flathub."
    for v in ("HTTPS_PROXY","HTTP_PROXY","https_proxy","http_proxy"):
        if enable: subprocess.run(["flatpak","override","--user",f"--env={v}={PROXY_URL}",SOBER_ID],capture_output=True)
        else:       subprocess.run(["flatpak","override","--user",f"--unset-env={v}",SOBER_ID],capture_output=True)
    return None

def app_installed(app):
    if app["id"]=="arduino": return arduino_installed()
    if app["id"]=="sober":   return sober_installed()
    return find_desktop(app["paths"]) is not None
def app_status(app):
    if app["id"]=="arduino": return arduino_status()
    if app["id"]=="sober":   return sober_status()
    return desktop_has_proxy(app["local"])
def app_set(app,enable):
    if app["id"]=="arduino": return set_arduino(enable)
    if app["id"]=="sober":   return set_sober(enable)
    return set_desktop_proxy(app["paths"],app["local"],enable,app["extra"])

# ── Apps personnalisées ───────────────────────────────────────────────────────
def get_custom_apps():
    return CFG.get("custom_apps", [])

def save_custom_apps(lst):
    CFG["custom_apps"] = lst
    save_cfg(CFG)

def custom_status(app):
    return desktop_has_proxy(app.get("local",""))

def custom_set(app, enable):
    src  = app.get("src","")
    local = app.get("local","")
    if not src or not os.path.exists(src):
        return f"Fichier .desktop introuvable :\n{src}"
    return set_desktop_proxy([src], local, enable, "")

# ── Scan des .desktop système ─────────────────────────────────────────────────
def scan_system_desktops():
    results = []
    dirs = ["/usr/share/applications","/usr/local/share/applications",
            LOCAL_APPS, "/var/lib/snapd/desktop/applications",
            "/var/lib/flatpak/exports/share/applications"]
    seen = set()
    for d in dirs:
        if not os.path.isdir(d): continue
        for path in sorted(glob.glob(os.path.join(d,"*.desktop"))):
            name = os.path.basename(path)
            if name in seen: continue
            seen.add(name)
            try:
                with open(path, errors="ignore") as f:
                    content = f.read()
                label = ""
                for line in content.splitlines():
                    if line.startswith("Name=") and not line.startswith("Name["):
                        label = line[5:].strip(); break
                if label:
                    results.append({"path": path, "name": name, "label": label})
            except: pass
    return results

# ═══════════════════════════════════════════════════════════════════
#  VÉRIFICATION DE VERSION GitHub
# ═══════════════════════════════════════════════════════════════════
def check_version_github():
    """Vérifier s'il y a une nouvelle version disponible sur GitHub"""
    try:
        # Récupère les dernières releases depuis l'API GitHub
        url = "https://api.github.com/repos/proxylycee/proxy-du-lyc-e-louis-majorelle/releases/latest"
        req = urllib.request.Request(url, headers={'Accept': 'application/vnd.github.v3+json'})
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
            latest_version = data.get('tag_name', '').lstrip('v')  # Récupère et nettoie le tag
            
            if latest_version and latest_version != APP_VERSION:
                log(f"Nouvelle version disponible: v{latest_version} (actuelle: v{APP_VERSION})")
                return latest_version
    except Exception as e:
        log(f"Impossible de vérifier la version GitHub: {e}", "debug")
    return None

def show_update_dialog(parent, latest_version):
    """Affiche une boîte de dialogue pour notifier une nouvelle version"""
    dialog = Gtk.MessageDialog(
        parent=parent,
        flags=Gtk.DialogFlags.MODAL,
        message_type=Gtk.MessageType.INFO,
        buttons=Gtk.ButtonsType.OK_CANCEL,
        text="Nouvelle version disponible"
    )
    dialog.format_secondary_text(
        f"Une nouvelle version (v{latest_version}) est disponible.\n\n"
        f"Version actuelle: v{APP_VERSION}\n\n"
        "Vous pouvez la télécharger depuis:\n"
        "https://github.com/proxylycee/proxy-du-lyc-e-louis-majorelle/releases"
    )
    dialog.set_title("Mise à jour disponible")
    response = dialog.run()
    if response == Gtk.ResponseType.OK:
        # Optionnel: ouvrir le lien
        try:
            subprocess.Popen(['xdg-open', 'https://github.com/proxylycee/proxy-du-lyc-e-louis-majorelle/releases'])
        except: pass
    dialog.destroy()

# ═══════════════════════════════════════════════════════════════════
#  INTERFACE
# ═══════════════════════════════════════════════════════════════════
class App(Gtk.Window):
    def __init__(self):
        super().__init__(title="Réseau Louis Majorelle")
        self.set_default_size(860, 580)
        self.set_resizable(True)
        self.set_border_width(0)
        # WM_CLASS doit correspondre exactement au StartupWMClass du .desktop
        # pour que GNOME regroupe les fenêtres dans le dock correctement
        self.set_wmclass("reseau-majorelle", "reseau-majorelle")
        # Icône de la fenêtre (Alt+Tab, barre des tâches)
        try:
            icon_path = os.path.join(INSTALL_DIR, "majorelle.svg")
            icon_pb = GdkPixbuf.Pixbuf.new_from_file_at_size(icon_path, 256, 256)
            self.set_icon(icon_pb)
        except Exception:
            self.set_icon_name("reseau-majorelle")
        # Fermer = masquer dans le tray si activé, sinon quitter
        self.connect("delete-event", self._on_delete)
        apply_css(CFG)

        # Vérifier les mises à jour en arrière-plan au démarrage
        def check_update_bg():
            latest = check_version_github()
            if latest:
                GLib.idle_add(lambda: show_update_dialog(self, latest) if self.get_visible() else None)
        
        update_thread = threading.Thread(target=check_update_bg, daemon=True)
        update_thread.start()

        self._nav_btns = {}
        self._custom_box = None
        self._term_widget = None
        self._sidebar_visible = True

        root = Gtk.Box()
        self.add(root)
        self._sidebar_widget = self._mk_sidebar()
        root.pack_start(self._sidebar_widget, False, False, 0)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        right.set_name("content")
        right.set_hexpand(True)
        right.set_vexpand(True)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_transition_duration(130)
        self.stack.set_hexpand(True)
        self.stack.set_vexpand(True)

        self.stack.add_named(self._page_tableau(),      "tableau")
        self.stack.add_named(self._page_profils(),      "profils")
        self.stack.add_named(self._page_services(),     "services")
        self.stack.add_named(self._page_applications(), "applications")
        self.stack.add_named(self._page_terminal(),     "terminal")
        self.stack.add_named(self._page_apparence(),    "apparence")
        self.stack.add_named(self._page_parametres(),   "parametres")

        right.pack_start(self.stack, True, True, 0)
        right.pack_start(self._mk_statusbar(), False, False, 0)
        root.pack_start(right, True, True, 0)

        self._mk_tray()

        if CFG.get("start_minimized") and HAS_INDICATOR:
            pass  # ne pas appeler show_all
        else:
            self.show_all()
        self._nav_go("tableau")

    def _on_delete(self, win, event):
        if CFG.get("tray_on_close", True) and (HAS_INDICATOR or hasattr(self, "_status_icon")):
            self.hide()
            return True  # empêche la destruction
        Gtk.main_quit()
        return False

    def _toggle_window(self, *_):
        if self.get_visible():
            self.hide()
        else:
            self.show_all()
            self.present()

    # ── Tray icon ─────────────────────────────────────────────────────────────
    def _mk_tray(self):
        icon_path = os.path.join(INSTALL_DIR, "majorelle.svg")
        tray_icon  = CFG.get("tray_icon", "default")
        # Build alternate tray SVG if needed
        self._write_tray_svg(tray_icon)
        if HAS_INDICATOR and _AppIndicator:
            self._indicator = _AppIndicator.Indicator.new(
                "reseau-majorelle",
                "reseau-majorelle",
                _AppIndicator.IndicatorCategory.APPLICATION_STATUS)
            self._indicator.set_status(_AppIndicator.IndicatorStatus.ACTIVE)
            if not os.path.exists(os.path.expanduser(
                    "~/.local/share/icons/hicolor/scalable/apps/reseau-majorelle.svg")):
                self._indicator.set_icon_full(icon_path, "Réseau Majorelle")
            self._indicator.set_menu(self._mk_tray_menu())
        else:
            # Fallback Gtk.StatusIcon (deprecated mais universel)
            self._status_icon = Gtk.StatusIcon()
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_size(icon_path, 22, 22)
                self._status_icon.set_from_pixbuf(pb)
            except Exception:
                self._status_icon.set_from_icon_name("network-proxy")
            self._status_icon.set_tooltip_text("Réseau Louis Majorelle")
            self._status_icon.set_visible(True)
            self._status_icon.connect("activate", self._toggle_window)
            self._status_icon.connect("popup-menu", self._on_tray_popup)

    def _write_tray_svg(self, style):
        """Regenerate the main SVG + hicolor copy according to chosen tray style."""
        icon_path = os.path.join(INSTALL_DIR, "majorelle.svg")
        hicolor   = os.path.expanduser("~/.local/share/icons/hicolor/scalable/apps/reseau-majorelle.svg")
        acc = CFG.get("accent", "#7b8fe8")

        def svg_default(a):
            return (
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n'
                '  <defs>\n'
                '    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">\n'
                '      <stop offset="0%" style="stop-color:#0a1628"/>\n'
                '      <stop offset="100%" style="stop-color:#162040"/>\n'
                '    </linearGradient>\n'
                '    <linearGradient id="g1" x1="0%" y1="0%" x2="100%" y2="100%">\n'
                f'      <stop offset="0%" style="stop-color:{a}"/>\n'
                '      <stop offset="100%" style="stop-color:#c084fc"/>\n'
                '    </linearGradient>\n'
                '    <linearGradient id="g2" x1="100%" y1="0%" x2="0%" y2="100%">\n'
                '      <stop offset="0%" style="stop-color:#38bdf8"/>\n'
                f'      <stop offset="100%" style="stop-color:{a}"/>\n'
                '    </linearGradient>\n'
                '  </defs>\n'
                '  <rect width="100" height="100" rx="22" fill="url(#bg)"/>\n'
                f'  <circle cx="50" cy="47" r="9" fill="url(#g1)" opacity="0.9"/>\n'
                '  <circle cx="50" cy="47" r="5.5" fill="#0a1628"/>\n'
                f'  <circle cx="50" cy="47" r="2.5" fill="url(#g1)"/>\n'
                f'  <circle cx="22" cy="30" r="4.5" fill="url(#g2)" opacity="0.9"/>\n'
                f'  <circle cx="78" cy="30" r="4.5" fill="url(#g2)" opacity="0.9"/>\n'
                f'  <circle cx="18" cy="64" r="3.5" fill="{a}" opacity="0.7"/>\n'
                f'  <circle cx="82" cy="64" r="3.5" fill="{a}" opacity="0.7"/>\n'
                f'  <circle cx="50" cy="76" r="4"   fill="url(#g2)" opacity="0.9"/>\n'
                f'  <g stroke="{a}" stroke-width="1.8" fill="none" opacity="0.6" stroke-linecap="round">\n'
                '    <line x1="50" y1="38" x2="22" y2="34"/>\n'
                '    <line x1="50" y1="38" x2="78" y2="34"/>\n'
                '    <line x1="50" y1="56" x2="18" y2="61"/>\n'
                '    <line x1="50" y1="56" x2="82" y2="61"/>\n'
                '    <line x1="50" y1="56" x2="50" y2="72"/>\n'
                '    <line x1="22" y1="34" x2="18" y2="61"/>\n'
                '    <line x1="78" y1="34" x2="82" y2="61"/>\n'
                '  </g>\n'
                '  <g stroke="#38bdf8" stroke-width="2.2" fill="none" stroke-linecap="round" opacity="0.45">\n'
                '    <path d="M36 20 Q50 12 64 20"/>\n'
                '    <path d="M42 14 Q50 9  58 14"/>\n'
                '  </g>\n'
                '  <text x="50" y="92" text-anchor="middle" font-family="sans-serif"\n'
                f'        font-size="7" font-weight="700" fill="{a}" opacity="0.55" letter-spacing="1">MAJORELLE</text>\n'
                '</svg>'
            )

        def svg_minimal(a):
            return (
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n'
                '  <rect width="100" height="100" rx="18" fill="#0a1628"/>\n'
                '  <text x="50" y="64" text-anchor="middle" font-family="sans-serif"\n'
                f'        font-size="52" font-weight="900" fill="{a}">M</text>\n'
                '</svg>'
            )

        def svg_wifi(a):
            return (
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n'
                '  <defs>\n'
                '    <linearGradient id="bg2" x1="0%" y1="0%" x2="100%" y2="100%">\n'
                '      <stop offset="0%" style="stop-color:#0d1b3e"/>\n'
                '      <stop offset="100%" style="stop-color:#1a2a5e"/>\n'
                '    </linearGradient>\n'
                '  </defs>\n'
                '  <rect width="100" height="100" rx="22" fill="url(#bg2)"/>\n'
                f'  <g stroke="{a}" stroke-width="4" fill="none" stroke-linecap="round">\n'
                '    <path d="M16 46 Q50 18 84 46"/>\n'
                '    <path d="M26 58 Q50 35 74 58"/>\n'
                '    <path d="M36 70 Q50 52 64 70"/>\n'
                f'    <circle cx="50" cy="80" r="5" fill="{a}" stroke="none"/>\n'
                '  </g>\n'
                '</svg>'
            )

        def svg_shield(a):
            return (
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\n'
                '  <rect width="100" height="100" rx="22" fill="#0a1628"/>\n'
                f'  <path d="M50 15 L78 26 L78 50 Q78 70 50 85 Q22 70 22 50 L22 26 Z"\n'
                f'        fill="none" stroke="{a}" stroke-width="3.5" stroke-linejoin="round"/>\n'
                f'  <path d="M38 50 L46 58 L62 42" stroke="{a}" stroke-width="4"\n'
                '        fill="none" stroke-linecap="round" stroke-linejoin="round"/>\n'
                '</svg>'
            )

        builders = {
            "default": svg_default,
            "minimal": svg_minimal,
            "wifi":    svg_wifi,
            "shield":  svg_shield,
        }
        svg_text = builders.get(style, svg_default)(acc)
        with open(icon_path, "w") as f:
            f.write(svg_text)
        os.makedirs(os.path.dirname(hicolor), exist_ok=True)
        import shutil as _sh
        _sh.copy(icon_path, hicolor)
        subprocess.run(["gtk-update-icon-cache", "-f", "-t",
                        os.path.expanduser("~/.local/share/icons/hicolor")],
                       capture_output=True)

    def _mk_tray_menu(self):
        menu = Gtk.Menu()
        on = get_proxy_mode() == "manual"

        # Profil actif
        active_id   = CFG.get("active_profile","lycee")
        active_prof = load_profiles().get(active_id, {})
        item_prof = Gtk.MenuItem(
            label=f"{active_prof.get('emoji','🔌')} {active_prof.get('label','Lycée')}")
        item_prof.set_sensitive(False)
        menu.append(item_prof)

        # Sous-menu changer de profil
        prof_menu = Gtk.Menu()
        for pid, prof in load_profiles().items():
            it = Gtk.MenuItem(
                label=f"{'✓ ' if pid==active_id else '   '}{prof.get('emoji','')} {prof.get('label','')}")
            it.connect("activate", lambda _, p=pid: (
                apply_profile(p),
                GLib.idle_add(self._refresh_sys)))
            prof_menu.append(it)
        prof_menu.show_all()
        item_switch = Gtk.MenuItem(label="Changer de profil…")
        item_switch.set_submenu(prof_menu)
        menu.append(item_switch)

        menu.append(Gtk.SeparatorMenuItem())

        item_toggle = Gtk.MenuItem(label="✅ Proxy actif" if on else "⚫ Proxy inactif")
        item_toggle.connect("activate", lambda _: (
            set_system_proxy(not (get_proxy_mode() == "manual")),
            write_apt_proxy(not (get_proxy_mode() == "manual")),
            GLib.idle_add(self._refresh_sys)))
        menu.append(item_toggle)
        menu.append(Gtk.SeparatorMenuItem())

        item_open = Gtk.MenuItem(label="Ouvrir")
        item_open.connect("activate", lambda _: (self.show_all(), self.present()))
        menu.append(item_open)

        item_quit = Gtk.MenuItem(label="Quitter")
        item_quit.connect("activate", lambda _: Gtk.main_quit())
        menu.append(item_quit)

        menu.show_all()
        return menu

    def _on_tray_popup(self, icon, button, time):
        menu = self._mk_tray_menu()
        menu.popup(None, None, Gtk.StatusIcon.position_menu, icon, button, time)

    # ── Sidebar ───────────────────────────────────────────────────────────────
    def _mk_sidebar(self):
        sb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        sb.set_name("sidebar")

        hdr = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        hdr.set_name("sidebar-header")
        icon_p = os.path.join(INSTALL_DIR, "majorelle.svg")
        if os.path.exists(icon_p):
            try:
                pb  = GdkPixbuf.Pixbuf.new_from_file_at_size(icon_p, 34, 34)
                img = Gtk.Image.new_from_pixbuf(pb)
                img.set_halign(Gtk.Align.START)
                img.set_margin_bottom(8)
                hdr.pack_start(img, False, False, 0)
            except: pass
        n = Gtk.Label(label="Louis Majorelle")
        n.set_name("app-name"); n.set_halign(Gtk.Align.START)
        hdr.pack_start(n, False, False, 0)
        s = Gtk.Label(label="Réseau & Proxy")
        s.set_name("app-sub"); s.set_halign(Gtk.Align.START)
        hdr.pack_start(s, False, False, 0)

        # Badge profil actif
        prof_id = CFG.get("active_profile", "lycee")
        prof    = PROFILES.get(prof_id, DEFAULT_PROFILES.get("lycee", {}))
        self._sidebar_profile_lbl = Gtk.Label(
            label=f"{prof.get('emoji','🔌')}  {prof.get('label','Lycée')}")
        self._sidebar_profile_lbl.get_style_context().add_class(
            "badge-on" if prof.get("proxy_on") else "badge-off")
        self._sidebar_profile_lbl.set_halign(Gtk.Align.START)
        self._sidebar_profile_lbl.set_margin_top(6)
        hdr.pack_start(self._sidebar_profile_lbl, False, False, 0)

        sb.pack_start(hdr, False, False, 0)

        nav = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        nav.set_margin_top(10)
        pages = [
            ("tableau",      "  Tableau de bord"),
            ("profils",      "  Profils réseau"),
            ("services",     "  Services proxy"),
            ("applications", "  Applications"),
            ("terminal",     "  Terminal"),
            ("apparence",    "  Apparence"),
            ("parametres",   "  Paramètres"),
        ]
        for pid, label in pages:
            btn = Gtk.Button(label=label)
            btn.set_relief(Gtk.ReliefStyle.NONE)
            btn.get_style_context().add_class("nav-btn")
            btn.connect("clicked", lambda b, p=pid: self._nav_go(p))
            nav.pack_start(btn, False, False, 0)
            self._nav_btns[pid] = btn
        sb.pack_start(nav, False, False, 0)
        sb.pack_end(self._mk_sidebar_footer(), False, False, 0)
        return sb

    def _mk_sidebar_footer(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.set_name("sidebar-footer")
        row = Gtk.Box(spacing=10)
        self._dot = Gtk.Label()
        row.pack_start(self._dot, False, False, 0)
        col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        col.set_hexpand(True)
        lbl = Gtk.Label(label="Proxy global")
        lbl.get_style_context().add_class("card-title")
        lbl.set_halign(Gtk.Align.START)
        self._sys_sub = Gtk.Label()
        self._sys_sub.get_style_context().add_class("card-sub")
        self._sys_sub.set_halign(Gtk.Align.START)
        col.pack_start(lbl, False, False, 0)
        col.pack_start(self._sys_sub, False, False, 0)
        row.pack_start(col, True, True, 0)
        self._sys_sw = Gtk.Switch()
        self._sys_sw.connect("notify::active", self._on_sys_toggle)
        row.pack_start(self._sys_sw, False, False, 0)
        box.pack_start(row, False, False, 0)
        self._refresh_sys()
        return box

    def _refresh_sys(self):
        on = get_proxy_mode() == "manual"
        self._sys_sw.handler_block_by_func(self._on_sys_toggle)
        self._sys_sw.set_active(on)
        self._sys_sw.handler_unblock_by_func(self._on_sys_toggle)
        _dot_col = "#34d399" if on else "#7a8ab0"
        self._dot.set_markup(f'<span foreground="{_dot_col}" font="14">●</span>')
        self._sys_sub.set_text("Actif" if on else "Inactif")
        if hasattr(self,"_sb_lbl"):
            if on:
                self._sb_lbl.set_markup(
                    f'<span foreground="#34d399">●  Proxy actif</span>'
                    f'<span foreground="#7a8ab0">  —  {PROXY_URL}</span>')
            else:
                self._sb_lbl.set_markup('<span foreground="#7a8ab0">●  Connexion directe</span>')
        if hasattr(self,"_dash"): self._refresh_dash()

    def _on_sys_toggle(self, sw, _):
        set_system_proxy(sw.get_active())
        self._refresh_sys()

    def _mk_statusbar(self):
        bar = Gtk.Box(spacing=8)
        bar.set_name("statusbar")

        # Bouton toggle sidebar ☰
        self._toggle_sb_btn = Gtk.Button(label="☰")
        self._toggle_sb_btn.set_relief(Gtk.ReliefStyle.NONE)
        self._toggle_sb_btn.set_tooltip_text("Afficher/masquer la barre latérale  (Ctrl+B)")
        self._toggle_sb_btn.get_style_context().add_class("btn-ghost")
        self._toggle_sb_btn.connect("clicked", lambda _: self._toggle_sidebar())
        sp_tb = Gtk.CssProvider()
        sp_tb.load_from_data(b".toggle-sb{padding:2px 8px;font-size:13pt;border-radius:6px;}")
        self._toggle_sb_btn.get_style_context().add_provider(sp_tb, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self._toggle_sb_btn.get_style_context().add_class("toggle-sb")
        bar.pack_start(self._toggle_sb_btn, False, False, 0)

        self._sb_lbl = Gtk.Label()
        self._sb_lbl.set_halign(Gtk.Align.START)
        self._sb_lbl.set_hexpand(True)
        bar.pack_start(self._sb_lbl, True, True, 0)
        ver = Gtk.Label(label="v$VERSION")
        ver.get_style_context().add_class("card-sub")
        bar.pack_end(ver, False, False, 0)
        self._refresh_sys()

        # Raccourci clavier Ctrl+B
        accel = Gtk.AccelGroup()
        accel.connect(ord('b'), Gdk.ModifierType.CONTROL_MASK, 0,
                      lambda *_: self._toggle_sidebar())
        self.add_accel_group(accel)

        return bar

    def _toggle_sidebar(self):
        self._sidebar_visible = not self._sidebar_visible
        if self._sidebar_visible:
            self._sidebar_widget.show()
        else:
            self._sidebar_widget.hide()
        return bar

    def _nav_go(self, pid):
        self.stack.set_visible_child_name(pid)
        for p, btn in self._nav_btns.items():
            ctx = btn.get_style_context()
            ctx.add_class("nav-btn-active") if p==pid else ctx.remove_class("nav-btn-active")

    # ── Helpers ───────────────────────────────────────────────────────────────
    def _scrolled(self, child):
        sc = Gtk.ScrolledWindow()
        sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sc.set_hexpand(True)
        sc.set_vexpand(True)
        # Viewport permet au child de s'étirer horizontalement avec la fenêtre
        vp = Gtk.Viewport()
        vp.set_hexpand(True)
        vp.set_vexpand(True)
        vp.add(child)
        sc.add(vp)
        return sc

    def _page_header(self, title, sub):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_bottom(20)
        t = Gtk.Label(label=title)
        t.get_style_context().add_class("page-title")
        t.set_halign(Gtk.Align.START)
        s = Gtk.Label(label=sub)
        s.get_style_context().add_class("page-sub")
        s.set_halign(Gtk.Align.START)
        box.pack_start(t, False, False, 0)
        box.pack_start(s, False, False, 0)
        return box

    def _section(self, text):
        l = Gtk.Label(label=text.upper())
        l.get_style_context().add_class("section-label")
        l.set_halign(Gtk.Align.START)
        return l

    def _color_bar(self, color, app_id):
        b = Gtk.Box()
        b.set_size_request(4, -1)
        p = Gtk.CssProvider()
        p.load_from_data(f".cbar-{app_id}{{background-color:{color};border-radius:2px;}}".encode())
        b.get_style_context().add_provider(p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        b.get_style_context().add_class(f"cbar-{app_id}")
        return b

    def _err_dialog(self, msg):
        d = Gtk.MessageDialog(transient_for=self,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK, text=msg)
        d.run(); d.destroy()

    # ── Trafic réseau : lecture /proc/net/dev ────────────────────────────────
    def _net_read_bytes(self):
        """Retourne (rx_bytes, tx_bytes) cumulés sur toutes les interfaces actives."""
        rx = tx = 0
        try:
            with open("/proc/net/dev") as f:
                for line in f:
                    line = line.strip()
                    if ":" not in line: continue
                    iface, rest = line.split(":", 1)
                    iface = iface.strip()
                    if iface in ("lo",): continue
                    cols = rest.split()
                    if len(cols) >= 9:
                        rx += int(cols[0])
                        tx += int(cols[8])
        except Exception:
            pass
        return rx, tx

    def _net_init(self):
        """Initialise les données du moniteur réseau."""
        HISTORY = 60
        self._net_rx_hist = [0.0] * HISTORY
        self._net_tx_hist = [0.0] * HISTORY
        self._net_prev_rx, self._net_prev_tx = self._net_read_bytes()
        self._net_prev_time = time.monotonic()
        self._net_rx_now = 0.0
        self._net_tx_now = 0.0
        # Labels mis à jour
        self._net_rx_lbl = None
        self._net_tx_lbl = None
        self._net_total_rx_lbl = None
        self._net_total_tx_lbl = None
        self._net_canvas = None
        self._net_timer_id = GLib.timeout_add(1000, self._net_tick)

    def _net_tick(self):
        """Appelé toutes les secondes — met à jour l'historique et redessine."""
        rx, tx = self._net_read_bytes()
        now = time.monotonic()
        dt = max(now - self._net_prev_time, 0.001)
        rx_rate = (rx - self._net_prev_rx) / dt
        tx_rate = (tx - self._net_prev_tx) / dt
        self._net_prev_rx, self._net_prev_tx = rx, tx
        self._net_prev_time = now
        self._net_rx_now = max(rx_rate, 0)
        self._net_tx_now = max(tx_rate, 0)
        self._net_rx_hist.append(self._net_rx_now)
        self._net_tx_hist.append(self._net_tx_now)
        self._net_rx_hist = self._net_rx_hist[-60:]
        self._net_tx_hist = self._net_tx_hist[-60:]

        def _fmt(b):
            if b >= 1_048_576: return f"{b/1_048_576:.1f} Mio/s"
            if b >= 1024:      return f"{b/1024:.0f} Kio/s"
            return f"{b:.0f} o/s"

        def _fmt_total(b):
            if b >= 1_073_741_824: return f"{b/1_073_741_824:.1f} Gio"
            if b >= 1_048_576:     return f"{b/1_048_576:.1f} Mio"
            if b >= 1024:          return f"{b/1024:.0f} Kio"
            return f"{b} o"

        if self._net_rx_lbl:
            self._net_rx_lbl.set_text(_fmt(self._net_rx_now))
        if self._net_tx_lbl:
            self._net_tx_lbl.set_text(_fmt(self._net_tx_now))
        if self._net_total_rx_lbl:
            self._net_total_rx_lbl.set_text(_fmt_total(rx))
        if self._net_total_tx_lbl:
            self._net_total_tx_lbl.set_text(_fmt_total(tx))
        if self._net_canvas:
            self._net_canvas.queue_draw()
        return True  # répéter

    def _net_draw(self, widget, cr):
        """Dessine les courbes RX (bleu) et TX (orange) à la Cairo."""
        w = widget.get_allocated_width()
        h = widget.get_allocated_height()
        N = len(self._net_rx_hist)

        # Fond
        cr.set_source_rgba(0.06, 0.09, 0.18, 0.0)
        cr.paint()

        # Grille horizontale
        cr.set_source_rgba(1, 1, 1, 0.06)
        cr.set_line_width(1)
        for pct in (0.25, 0.5, 0.75):
            y = h - pct * h
            cr.move_to(0, y); cr.line_to(w, y)
            cr.stroke()

        if N < 2:
            return

        # Calcul du max pour l'échelle (plancher 512 Ko/s)
        peak = max(max(self._net_rx_hist), max(self._net_tx_hist), 524288)

        def _draw_curve(hist, r, g, b):
            step = w / (N - 1)
            # Zone remplie
            cr.set_source_rgba(r, g, b, 0.18)
            cr.move_to(0, h)
            for i, v in enumerate(hist):
                x = i * step
                y = h - (v / peak) * (h - 4)
                cr.line_to(x, y)
            cr.line_to((N - 1) * step, h)
            cr.close_path(); cr.fill()
            # Ligne
            cr.set_source_rgba(r, g, b, 0.9)
            cr.set_line_width(1.8)
            cr.move_to(0, h - (hist[0] / peak) * (h - 4))
            for i, v in enumerate(hist[1:], 1):
                x = i * step
                y = h - (v / peak) * (h - 4)
                cr.line_to(x, y)
            cr.stroke()

        # RX = bleu, TX = orange
        _draw_curve(self._net_rx_hist, 0.36, 0.68, 0.97)
        _draw_curve(self._net_tx_hist, 1.00, 0.60, 0.22)

    def _mk_net_card(self):
        """Construit la carte 'Trafic réseau' pour le tableau de bord."""
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        card.get_style_context().add_class("card")
        card.set_margin_top(12)

        # Titre
        title = Gtk.Label(label="Trafic réseau")
        title.get_style_context().add_class("card-title")
        title.set_halign(Gtk.Align.START)
        card.pack_start(title, False, False, 0)

        # Zone de dessin du graphique
        canvas = Gtk.DrawingArea()
        canvas.set_size_request(-1, 80)
        canvas.set_hexpand(True)
        canvas.set_vexpand(False)
        canvas.connect("draw", self._net_draw)
        self._net_canvas = canvas
        card.pack_start(canvas, True, True, 0)

        # Légende RX / TX
        leg = Gtk.Box(spacing=24)
        leg.set_margin_top(6)

        # RX
        rx_box = Gtk.Box(spacing=8)
        rx_dot = Gtk.Label()
        rx_dot.set_markup('<span foreground="#5cadF8" font="14">▼</span>')
        rx_box.pack_start(rx_dot, False, False, 0)
        rx_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        rx_head = Gtk.Box(spacing=8)
        rx_label = Gtk.Label(label="Réception")
        rx_label.get_style_context().add_class("card-sub")
        rx_label.set_halign(Gtk.Align.START)
        self._net_rx_lbl = Gtk.Label(label="0 o/s")
        self._net_rx_lbl.get_style_context().add_class("info-val")
        rx_head.pack_start(rx_label, False, False, 0)
        rx_head.pack_start(self._net_rx_lbl, False, False, 0)
        rx_total_row = Gtk.Box(spacing=4)
        rx_total_label = Gtk.Label(label="Total reçu")
        rx_total_label.get_style_context().add_class("card-sub")
        self._net_total_rx_lbl = Gtk.Label(label="—")
        self._net_total_rx_lbl.get_style_context().add_class("card-sub")
        rx_total_row.pack_start(rx_total_label, False, False, 0)
        rx_total_row.pack_start(self._net_total_rx_lbl, False, False, 0)
        rx_col.pack_start(rx_head, False, False, 0)
        rx_col.pack_start(rx_total_row, False, False, 0)
        rx_box.pack_start(rx_col, False, False, 0)
        leg.pack_start(rx_box, False, False, 0)

        # TX
        tx_box = Gtk.Box(spacing=8)
        tx_dot = Gtk.Label()
        tx_dot.set_markup('<span foreground="#ff9933" font="14">▲</span>')
        tx_box.pack_start(tx_dot, False, False, 0)
        tx_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        tx_head = Gtk.Box(spacing=8)
        tx_label = Gtk.Label(label="Envoi")
        tx_label.get_style_context().add_class("card-sub")
        tx_label.set_halign(Gtk.Align.START)
        self._net_tx_lbl = Gtk.Label(label="0 o/s")
        self._net_tx_lbl.get_style_context().add_class("info-val")
        tx_head.pack_start(tx_label, False, False, 0)
        tx_head.pack_start(self._net_tx_lbl, False, False, 0)
        tx_total_row = Gtk.Box(spacing=4)
        tx_total_label = Gtk.Label(label="Total envoyé")
        tx_total_label.get_style_context().add_class("card-sub")
        self._net_total_tx_lbl = Gtk.Label(label="—")
        self._net_total_tx_lbl.get_style_context().add_class("card-sub")
        tx_total_row.pack_start(tx_total_label, False, False, 0)
        tx_total_row.pack_start(self._net_total_tx_lbl, False, False, 0)
        tx_col.pack_start(tx_head, False, False, 0)
        tx_col.pack_start(tx_total_row, False, False, 0)
        tx_box.pack_start(tx_col, False, False, 0)
        leg.pack_start(tx_box, False, False, 0)

        card.pack_start(leg, False, False, 0)
        return card

    # ── PAGE : TABLEAU ────────────────────────────────────────────────────────
    def _page_tableau(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_hexpand(True)
        outer.set_margin_start(28)
        outer.set_margin_end(28)
        outer.set_margin_top(20)
        outer.set_margin_bottom(20)
        outer.pack_start(self._page_header("Tableau de bord","État du réseau et des services proxy"), False, False, 0)

        grid = Gtk.Grid()
        grid.set_column_spacing(12)
        grid.set_row_spacing(12)
        grid.set_margin_bottom(20)
        grid.set_hexpand(True)
        grid.set_column_homogeneous(True)
        self._dash = {}
        for i,(cid,title,desc) in enumerate([
            ("sys","Proxy système","GNOME, navigateurs"),
            ("apt","APT","Gestionnaire de paquets"),
            ("snap","Snap","Ubuntu Store"),
            ("flatpak","Flatpak","Flathub"),
            ("wifi","802.1X Wi-Fi","Connexion auto Etablissement"),
        ]):
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            card.get_style_context().add_class("card")
            card.set_hexpand(True)
            top = Gtk.Box(spacing=8)
            tl = Gtk.Label(label=title)
            tl.get_style_context().add_class("card-title")
            tl.set_halign(Gtk.Align.START); tl.set_hexpand(True)
            badge = Gtk.Label()
            top.pack_start(tl,True,True,0); top.pack_start(badge,False,False,0)
            card.pack_start(top,False,False,0)
            dl = Gtk.Label(label=desc)
            dl.get_style_context().add_class("card-sub"); dl.set_halign(Gtk.Align.START)
            card.pack_start(dl,False,False,0)
            self._dash[cid] = badge
            grid.attach(card, i%2, i//2, 1, 1)
        outer.pack_start(grid, False, False, 0)

        outer.pack_start(self._section("Informations réseau"), False, False, 0)
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        info.get_style_context().add_class("card"); info.set_margin_top(6)
        for k,v in [("Hôte",PROXY_HOST),("Port",str(PROXY_PORT)),("URL",PROXY_URL)]:
            row = Gtk.Box(spacing=16)
            kl = Gtk.Label(label=k); kl.get_style_context().add_class("info-key"); kl.set_halign(Gtk.Align.START)
            vl = Gtk.Label(label=v); vl.get_style_context().add_class("info-val"); vl.set_selectable(True); vl.set_halign(Gtk.Align.START)
            row.pack_start(kl,False,False,0); row.pack_start(vl,False,False,0)
            info.pack_start(row,False,False,0)
        outer.pack_start(info,False,False,0)

        # ── Graphique trafic réseau ──
        outer.pack_start(self._section("Trafic réseau"), False, False, 0)
        self._net_init()
        outer.pack_start(self._mk_net_card(), False, False, 0)

        self._refresh_dash()
        return self._scrolled(outer)

    def _refresh_dash(self):
        if not hasattr(self,"_dash"): return
        states = {
            "sys":     (get_proxy_mode()=="manual", True),
            "apt":     (os.path.exists("/etc/apt/apt.conf.d/99-proxy-majorelle"), True),
            "snap":    (snap_proxy_active(), has_snap()),
            "flatpak": (flatpak_proxy_active(), has_flatpak()),
            "wifi":    (cert_installed(), True),
        }
        for cid,(on,available) in states.items():
            badge = self._dash.get(cid)
            if not badge: continue
            ctx = badge.get_style_context()
            for cl in ("badge-on","badge-off","badge-na"): ctx.remove_class(cl)
            if not available:
                badge.set_text("Non installé"); ctx.add_class("badge-na")
            elif on:
                badge.set_text("Actif"); ctx.add_class("badge-on")
            else:
                badge.set_text("Inactif"); ctx.add_class("badge-off")

    # ── PAGE : PROFILS RÉSEAU ─────────────────────────────────────────────────
    def _page_profils(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_hexpand(True)
        outer.set_margin_start(28); outer.set_margin_end(28)
        outer.set_margin_top(20);   outer.set_margin_bottom(20)
        outer.pack_start(self._page_header(
            "Profils réseau",
            "Passez d'un contexte réseau à l'autre en un clic"), False, False, 0)

        self._profile_cards = {}

        outer.pack_start(self._section("Profils disponibles"), False, False, 0)
        self._profiles_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._profiles_list.set_margin_top(6)
        self._profiles_list.set_margin_bottom(16)
        self._profiles_list.set_hexpand(True)
        outer.pack_start(self._profiles_list, False, False, 0)
        self._rebuild_profile_cards()

        # ── Créer un profil personnalisé ──
        outer.pack_start(self._section("Nouveau profil"), False, False, 0)
        new_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        new_card.get_style_context().add_class("card")
        new_card.set_margin_top(6)
        new_card.set_hexpand(True)

        # Nom
        row_name = Gtk.Box(spacing=10)
        lbl_name = Gtk.Label(label="Nom")
        lbl_name.get_style_context().add_class("info-key")
        lbl_name.set_halign(Gtk.Align.START)
        self._new_prof_name = Gtk.Entry()
        self._new_prof_name.set_hexpand(True)
        self._new_prof_name.set_placeholder_text("ex: VPN maison, Partage iPhone…")
        row_name.pack_start(lbl_name, False, False, 0)
        row_name.pack_start(self._new_prof_name, True, True, 0)
        new_card.pack_start(row_name, False, False, 0)

        # Proxy host
        row_host = Gtk.Box(spacing=10)
        lbl_host = Gtk.Label(label="Hôte proxy")
        lbl_host.get_style_context().add_class("info-key")
        lbl_host.set_halign(Gtk.Align.START)
        self._new_prof_host = Gtk.Entry()
        self._new_prof_host.set_hexpand(True)
        self._new_prof_host.set_placeholder_text("ex: 172.19.255.254  (vide = sans proxy)")
        row_host.pack_start(lbl_host, False, False, 0)
        row_host.pack_start(self._new_prof_host, True, True, 0)
        new_card.pack_start(row_host, False, False, 0)

        # Proxy port
        row_port = Gtk.Box(spacing=10)
        lbl_port = Gtk.Label(label="Port")
        lbl_port.get_style_context().add_class("info-key")
        lbl_port.set_halign(Gtk.Align.START)
        self._new_prof_port = Gtk.Entry()
        self._new_prof_port.set_text("3128")
        self._new_prof_port.set_width_chars(8)
        row_port.pack_start(lbl_port, False, False, 0)
        row_port.pack_start(self._new_prof_port, False, False, 0)
        new_card.pack_start(row_port, False, False, 0)

        # Emoji
        row_emoji = Gtk.Box(spacing=10)
        lbl_emoji = Gtk.Label(label="Icône")
        lbl_emoji.get_style_context().add_class("info-key")
        lbl_emoji.set_halign(Gtk.Align.START)
        self._new_prof_emoji = Gtk.Entry()
        self._new_prof_emoji.set_text("🌐")
        self._new_prof_emoji.set_width_chars(4)
        row_emoji.pack_start(lbl_emoji, False, False, 0)
        row_emoji.pack_start(self._new_prof_emoji, False, False, 0)
        new_card.pack_start(row_emoji, False, False, 0)

        btn_create = Gtk.Button(label="➕  Créer le profil")
        btn_create.get_style_context().add_class("btn-accent")
        btn_create.set_halign(Gtk.Align.START)
        btn_create.connect("clicked", self._prof_create)
        new_card.pack_start(btn_create, False, False, 0)

        outer.pack_start(new_card, False, False, 0)
        return self._scrolled(outer)

    def _rebuild_profile_cards(self):
        for ch in self._profiles_list.get_children():
            self._profiles_list.remove(ch)
        self._profile_cards = {}

        active_id = CFG.get("active_profile", "lycee")
        profiles  = load_profiles()

        for pid, prof in profiles.items():
            is_active = (pid == active_id)

            card = Gtk.Box(spacing=14)
            card.get_style_context().add_class("card")
            card.set_hexpand(True)

            # Emoji
            em = Gtk.Label(label=prof.get("emoji","🌐"))
            sp_em = Gtk.CssProvider()
            sp_em.load_from_data(b".prof-em{font-size:22pt;}")
            em.get_style_context().add_provider(sp_em, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            em.get_style_context().add_class("prof-em")
            card.pack_start(em, False, False, 0)

            # Info
            info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            info.set_hexpand(True)

            lbl_title = Gtk.Label(label=prof.get("label","Profil"))
            lbl_title.get_style_context().add_class("card-title")
            lbl_title.set_halign(Gtk.Align.START)
            info.pack_start(lbl_title, False, False, 0)

            host = prof.get("proxy_host","")
            port = prof.get("proxy_port", 0)
            if prof.get("proxy_on") and host:
                desc = f"Proxy : {host}:{port}"
            else:
                desc = "Sans proxy"
            lbl_desc = Gtk.Label(label=desc)
            lbl_desc.get_style_context().add_class("card-sub")
            lbl_desc.set_halign(Gtk.Align.START)
            info.pack_start(lbl_desc, False, False, 0)

            card.pack_start(info, True, True, 0)

            # Badge actif
            if is_active:
                badge = Gtk.Label(label="Actif")
                badge.get_style_context().add_class("badge-on")
                card.pack_start(badge, False, False, 0)

            # Bouton activer
            btn_apply = Gtk.Button(label="Activer")
            btn_apply.get_style_context().add_class(
                "btn-accent" if not is_active else "btn-ghost")
            btn_apply.set_sensitive(not is_active)
            btn_apply.connect("clicked", self._mk_prof_apply(pid))
            card.pack_start(btn_apply, False, False, 0)

            # Bouton supprimer (seulement profils non-builtins)
            if not prof.get("builtin", False):
                btn_del = Gtk.Button(label="🗑")
                btn_del.get_style_context().add_class("btn-danger")
                btn_del.connect("clicked", self._mk_prof_delete(pid))
                card.pack_start(btn_del, False, False, 0)

            self._profiles_list.pack_start(card, False, False, 0)
            self._profile_cards[pid] = card

        self._profiles_list.show_all()

    def _mk_prof_apply(self, pid):
        def h(_):
            ok = apply_profile(pid)
            if ok:
                self._rebuild_profile_cards()
                # Mettre à jour le badge sidebar
                prof = load_profiles().get(pid, {})
                self._sidebar_profile_lbl.set_text(
                    f"{prof.get('emoji','🔌')}  {prof.get('label','')}")
                ctx = self._sidebar_profile_lbl.get_style_context()
                ctx.remove_class("badge-on"); ctx.remove_class("badge-off")
                ctx.add_class("badge-on" if prof.get("proxy_on") else "badge-off")
                # Rafraîchir le tableau de bord
                if hasattr(self, "_dash"): self._refresh_dash()
                self._refresh_sys()
        return h

    def _mk_prof_delete(self, pid):
        def h(_):
            dlg = Gtk.MessageDialog(
                transient_for=self, modal=True,
                message_type=Gtk.MessageType.WARNING,
                buttons=Gtk.ButtonsType.OK_CANCEL,
                text=f"Supprimer le profil ?")
            if dlg.run() == Gtk.ResponseType.OK:
                profs = load_profiles()
                profs.pop(pid, None)
                save_profiles(profs)
                self._rebuild_profile_cards()
            dlg.destroy()
        return h

    def _prof_create(self, _):
        name  = self._new_prof_name.get_text().strip()
        host  = self._new_prof_host.get_text().strip()
        port_s= self._new_prof_port.get_text().strip()
        emoji = self._new_prof_emoji.get_text().strip() or "🌐"

        if not name:
            self._new_prof_name.grab_focus(); return

        port = int(port_s) if port_s.isdigit() else 0
        pid  = name.lower().replace(" ","_")[:20]

        profs = load_profiles()
        profs[pid] = {
            "label":      name,
            "emoji":      emoji,
            "proxy_host": host,
            "proxy_port": port,
            "proxy_on":   bool(host),
            "services": {
                "apt": bool(host), "snap": bool(host), "flatpak": bool(host),
                "git": bool(host), "pip":  bool(host), "npm":     bool(host),
                "wget": bool(host), "docker": bool(host),
            },
            "builtin": False,
        }
        save_profiles(profs)
        self._new_prof_name.set_text("")
        self._new_prof_host.set_text("")
        self._new_prof_port.set_text("3128")
        self._new_prof_emoji.set_text("🌐")
        self._rebuild_profile_cards()

    # ── PAGE : SERVICES PROXY ─────────────────────────────────────────────────
    def _page_services(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_hexpand(True)
        outer.set_margin_start(28)
        outer.set_margin_end(28)
        outer.set_margin_top(20)
        outer.set_margin_bottom(20)
        outer.pack_start(self._page_header(
            "Services proxy",
            "Activez ou désactivez le proxy service par service"), False, False, 0)

        # Définition des services
        # (id, label, description, has_fn, active_fn, write_fn)
        self._svc_switches = {}
        services = [
            ("apt",     "APT",           "Gestionnaire de paquets (apt install, apt update…)",
             lambda: True,       apt_proxy_active,    write_apt_proxy),
            ("snap",    "Snap",          "Ubuntu Store — paquets Snap",
             has_snap,           snap_proxy_active,   write_snap_proxy),
            ("flatpak", "Flatpak",       "Flathub — paquets Flatpak",
             has_flatpak,        flatpak_proxy_active,write_flatpak_proxy),
            ("git",     "Git",           "Clones, fetch, push via HTTP/HTTPS",
             has_git,            git_proxy_active,    write_git_proxy),
            ("pip",     "Pip / PyPI",    "Installation de paquets Python",
             lambda: True,       pip_proxy_active,    write_pip_proxy),
            ("npm",     "npm",           "Installation de paquets Node.js",
             has_npm,            npm_proxy_active,    write_npm_proxy),
            ("wget",    "wget / curl",   "Téléchargements en ligne de commande",
             lambda: True,       wget_proxy_active,   self._write_wget_curl),
            ("docker",  "Docker daemon", "Pull d'images Docker et builds",
             has_docker,         docker_proxy_active, write_docker_proxy),
        ]

        outer.pack_start(self._section("Services système"), False, False, 6)

        for svc_id, label, desc, has_fn, active_fn, write_fn in services:
            available = has_fn()
            card = Gtk.Box(spacing=12)
            card.get_style_context().add_class("card")
            card.set_hexpand(True)
            card.set_margin_bottom(2)

            # Indicateur coloré
            dot = Gtk.Label()
            _dot_col = "#34d399" if available else "#555566"
            dot.set_markup(f'<span foreground="{_dot_col}" font="12">●</span>')
            card.pack_start(dot, False, False, 0)

            # Info
            info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            info.set_hexpand(True)
            lbl_title = Gtk.Label(label=label)
            lbl_title.get_style_context().add_class("card-title")
            lbl_title.set_halign(Gtk.Align.START)
            lbl_desc = Gtk.Label(label=desc if available else f"{desc}  —  non installé")
            lbl_desc.get_style_context().add_class("card-sub")
            lbl_desc.set_halign(Gtk.Align.START)
            info.pack_start(lbl_title, False, False, 0)
            info.pack_start(lbl_desc,  False, False, 0)
            card.pack_start(info, True, True, 0)

            # Switch
            sw = Gtk.Switch()
            sw.set_sensitive(available)
            sw.set_active(active_fn() if available else False)
            h = self._mk_svc_handler(write_fn, active_fn, dot, available)
            sig_id = sw.connect("notify::active", h)
            card.pack_start(sw, False, False, 0)

            self._svc_switches[svc_id] = (sw, active_fn, dot, available, sig_id)
            outer.pack_start(card, False, False, 0)

        # Boutons tout activer / tout désactiver
        outer.pack_start(Gtk.Separator(), False, False, 14)
        btn_row = Gtk.Box(spacing=10)
        btn_all_on  = Gtk.Button(label="✅  Tout activer")
        btn_all_on.get_style_context().add_class("btn-accent")
        btn_all_on.connect("clicked", lambda _: self._svc_all(True))
        btn_all_off = Gtk.Button(label="⛔  Tout désactiver")
        btn_all_off.get_style_context().add_class("btn-ghost")
        btn_all_off.connect("clicked", lambda _: self._svc_all(False))
        btn_row.pack_start(btn_all_on,  False, False, 0)
        btn_row.pack_start(btn_all_off, False, False, 0)
        outer.pack_start(btn_row, False, False, 0)

        return self._scrolled(outer)

    def _write_wget_curl(self, enable):
        write_wget_proxy(enable)
        write_curl_proxy(enable)

    def _mk_svc_handler(self, write_fn, active_fn, dot, available):
        def h(sw, _):
            write_fn(sw.get_active())
            on = active_fn() if available else False
            _dot_col = "#34d399" if on else "#7a8ab0"
            dot.set_markup(f'<span foreground="{_dot_col}" font="12">●</span>')
        return h

    def _svc_all(self, enable):
        fns = [write_apt_proxy, write_snap_proxy, write_flatpak_proxy,
               write_git_proxy, write_pip_proxy,  write_npm_proxy,
               self._write_wget_curl, write_docker_proxy]
        for fn in fns:
            try: fn(enable)
            except Exception: pass
        # Mettre à jour les switches sans déclencher leurs handlers
        for svc_id, (sw, active_fn, dot, available, sig_id) in self._svc_switches.items():
            if not available: continue
            sw.handler_block(sig_id)
            try:
                sw.set_active(enable)
                on = active_fn()
                _dot_col = "#34d399" if on else "#7a8ab0"
                dot.set_markup(f'<span foreground="{_dot_col}" font="12">●</span>')
            except Exception: pass
            finally:
                sw.handler_unblock(sig_id)

    # ── PAGE : APPLICATIONS ───────────────────────────────────────────────────
    def _page_applications(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_hexpand(True)
        outer.set_margin_start(28)
        outer.set_margin_end(28)
        outer.set_margin_top(20)
        outer.set_margin_bottom(20)
        outer.pack_start(self._page_header("Applications",
            "Proxy par application — relancez l'appli après chaque changement"), False, False, 0)

        # Apps intégrées
        outer.pack_start(self._section("Applications intégrées"), False, False, 0)
        blt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        blt.set_margin_top(6)
        for app in APPS_BUILTIN:
            blt.pack_start(self._mk_app_row(app, builtin=True), False, False, 0)
        outer.pack_start(blt, False, False, 0)

        outer.pack_start(Gtk.Separator(), False, False, 10)

        # Apps personnalisées
        hdr_row = Gtk.Box(spacing=10)
        hdr_row.set_margin_top(4)
        sec = self._section("Applications personnalisées")
        sec.set_hexpand(True)
        hdr_row.pack_start(sec, True, True, 0)

        add_btn = Gtk.Button(label="+ Ajouter")
        add_btn.get_style_context().add_class("btn-accent")
        add_btn.connect("clicked", self._show_add_dialog)
        hdr_row.pack_start(add_btn, False, False, 0)
        outer.pack_start(hdr_row, False, False, 0)

        self._custom_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self._custom_box.set_margin_top(6)
        outer.pack_start(self._custom_box, False, False, 0)
        self._rebuild_custom()

        return self._scrolled(outer)

    def _mk_app_row(self, app, builtin=True):
        card = Gtk.Box(spacing=12)
        card.get_style_context().add_class("card")
        card.set_margin_bottom(0)
        card.pack_start(self._color_bar(app["color"], app["id"]), False, False, 0)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        info.set_hexpand(True)
        tl = Gtk.Label(label=app["label"])
        tl.get_style_context().add_class("card-title"); tl.set_halign(Gtk.Align.START)
        dl = Gtk.Label(label=app["desc"])
        dl.get_style_context().add_class("card-sub"); dl.set_halign(Gtk.Align.START)
        info.pack_start(tl,False,False,0); info.pack_start(dl,False,False,0)
        card.pack_start(info,True,True,0)

        if builtin:
            installed = app_installed(app)
            if not installed:
                b = Gtk.Label(label="Non installé")
                b.get_style_context().add_class("badge-na")
                card.pack_start(b,False,False,0)
            else:
                sw = Gtk.Switch()
                sw.set_active(app_status(app))
                sw.connect("notify::active", self._mk_handler(app))
                card.pack_start(sw,False,False,0)
        return card

    def _mk_handler(self, app):
        def h(sw, _):
            err = app_set(app, sw.get_active())
            if err:
                self._err_dialog(err)
                sw.handler_block_by_func(h)
                sw.set_active(not sw.get_active())
                sw.handler_unblock_by_func(h)
        return h

    def _rebuild_custom(self):
        if not self._custom_box: return
        for c in self._custom_box.get_children():
            self._custom_box.remove(c)
        apps = get_custom_apps()
        if not apps:
            ph = Gtk.Label()
            ph.set_markup('<span foreground="#7a8ab0"><i>Aucune application ajoutée.\nCliquez sur "+ Ajouter" pour en configurer une.</i></span>')
            ph.set_halign(Gtk.Align.CENTER); ph.set_margin_top(14)
            self._custom_box.pack_start(ph, False, False, 0)
        else:
            for app in apps:
                self._custom_box.pack_start(self._mk_custom_row(app), False, False, 0)
        self._custom_box.show_all()

    def _mk_custom_row(self, app):
        card = Gtk.Box(spacing=12)
        card.get_style_context().add_class("card")
        card.pack_start(self._color_bar(app.get("color","#7b8fe8"), app["id"]), False, False, 0)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        info.set_hexpand(True)
        tl = Gtk.Label(label=app["label"])
        tl.get_style_context().add_class("card-title"); tl.set_halign(Gtk.Align.START)
        dl = Gtk.Label(label=app.get("desc",""))
        dl.get_style_context().add_class("card-sub"); dl.set_halign(Gtk.Align.START)
        info.pack_start(tl,False,False,0); info.pack_start(dl,False,False,0)
        card.pack_start(info,True,True,0)

        sw = Gtk.Switch()
        sw.set_active(custom_status(app))
        sw.connect("notify::active", lambda s, _, a=app: (
            self._err_dialog(e) if (e := custom_set(a, s.get_active())) else None))
        card.pack_start(sw,False,False,0)

        del_btn = Gtk.Button(label="✕")
        del_btn.get_style_context().add_class("btn-danger")
        del_btn.connect("clicked", lambda _, a=app: self._delete_custom(a))
        card.pack_start(del_btn,False,False,0)
        return card

    def _delete_custom(self, app):
        apps = [a for a in get_custom_apps() if a["id"] != app["id"]]
        save_custom_apps(apps)
        self._rebuild_custom()

    def _show_add_dialog(self, *_):
        # Scanner les .desktop disponibles
        all_desktops = scan_system_desktops()
        builtin_ids  = {os.path.basename(a["local"] or "") for a in APPS_BUILTIN if a["local"]}
        custom_srcs  = {a.get("src","") for a in get_custom_apps()}
        available    = [d for d in all_desktops
                        if os.path.basename(d["path"]) not in builtin_ids
                        and d["path"] not in custom_srcs]

        dlg = Gtk.Dialog(title="Ajouter une application",
                         transient_for=self, modal=True)
        dlg.set_default_size(500, 420)
        dlg.add_buttons("Annuler", Gtk.ResponseType.CANCEL,
                        "Ajouter", Gtk.ResponseType.OK)
        dlg.get_widget_for_response(Gtk.ResponseType.OK).get_style_context().add_class("btn-accent")

        area = dlg.get_content_area()
        area.set_border_width(20)
        area.set_spacing(14)

        # Champ de recherche
        search_lbl = Gtk.Label(label="Rechercher une application installée :")
        search_lbl.set_halign(Gtk.Align.START)
        area.pack_start(search_lbl, False, False, 0)

        search_entry = Gtk.SearchEntry()
        search_entry.set_placeholder_text("Nom de l'application…")
        area.pack_start(search_entry, False, False, 0)

        # Liste scrollable
        sw_list = Gtk.ScrolledWindow()
        sw_list.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw_list.set_min_content_height(160)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)

        def populate(query=""):
            for c in listbox.get_children(): listbox.remove(c)
            q = query.lower()
            for d in available:
                if q and q not in d["label"].lower() and q not in d["name"].lower(): continue
                row = Gtk.ListBoxRow()
                row_box = Gtk.Box(spacing=10)
                row_box.set_border_width(8)
                lbl_r = Gtk.Label(label=d["label"])
                lbl_r.set_halign(Gtk.Align.START); lbl_r.set_hexpand(True)
                lbl_p = Gtk.Label(label=d["name"])
                lbl_p.get_style_context().add_class("card-sub")
                row_box.pack_start(lbl_r,True,True,0)
                row_box.pack_start(lbl_p,False,False,0)
                row.add(row_box)
                row._desktop = d
                listbox.add(row)
            listbox.show_all()

        populate()
        search_entry.connect("changed", lambda e: populate(e.get_text()))
        sw_list.add(listbox)
        area.pack_start(sw_list, True, True, 0)

        # Séparateur
        area.pack_start(Gtk.Separator(), False, False, 0)

        # Ou .desktop manuel
        area.pack_start(Gtk.Label(label="Ou choisir un fichier .desktop manuellement :"), False, False, 0)
        fc_row = Gtk.Box(spacing=8)
        self._fc_label = Gtk.Label(label="Aucun fichier sélectionné")
        self._fc_label.get_style_context().add_class("card-sub")
        self._fc_label.set_halign(Gtk.Align.START); self._fc_label.set_hexpand(True)
        self._fc_path = None
        fc_btn = Gtk.Button(label="Parcourir…")
        fc_btn.get_style_context().add_class("btn-ghost")
        def pick_file(_):
            fc = Gtk.FileChooserDialog(title="Choisir un .desktop",
                                       transient_for=dlg,
                                       action=Gtk.FileChooserAction.OPEN)
            fc.add_buttons("Annuler",Gtk.ResponseType.CANCEL,"Ouvrir",Gtk.ResponseType.OK)
            ff = Gtk.FileFilter(); ff.set_name(".desktop"); ff.add_pattern("*.desktop"); fc.add_filter(ff)
            for d in ["/usr/share/applications", LOCAL_APPS]:
                if os.path.exists(d): fc.set_current_folder(d); break
            if fc.run() == Gtk.ResponseType.OK:
                self._fc_path = fc.get_filename()
                self._fc_label.set_text(os.path.basename(self._fc_path))
                listbox.unselect_all()
            fc.destroy()
        fc_btn.connect("clicked", pick_file)
        fc_row.pack_start(self._fc_label,True,True,0)
        fc_row.pack_start(fc_btn,False,False,0)
        area.pack_start(fc_row, False, False, 0)

        area.show_all()
        resp = dlg.run()

        if resp == Gtk.ResponseType.OK:
            selected_row = listbox.get_selected_row()
            if selected_row:
                d = selected_row._desktop
                src_path = d["path"]
                label    = d["label"]
            elif self._fc_path:
                src_path = self._fc_path
                try:
                    with open(src_path, errors="ignore") as f:
                        label = next((l[5:].strip() for l in f if l.startswith("Name=") and not l.startswith("Name[")), os.path.basename(src_path))
                except: label = os.path.basename(src_path)
            else:
                dlg.destroy(); return

            local = os.path.join(LOCAL_APPS, os.path.basename(src_path))
            safe_id = re.sub(r'[^a-z0-9]', '_', label.lower())
            new_app = {
                "id":    f"custom_{safe_id}_{len(get_custom_apps())}",
                "label": label,
                "desc":  os.path.basename(src_path),
                "color": "#7b8fe8",
                "src":   src_path,
                "local": local,
            }
            apps = get_custom_apps()
            apps.append(new_app)
            save_custom_apps(apps)
            self._rebuild_custom()

        dlg.destroy()

    # ── PAGE : TERMINAL ───────────────────────────────────────────────────────
    def _page_terminal(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_hexpand(True)
        outer.set_vexpand(True)

        # Barre d'outils terminal
        toolbar = Gtk.Box(spacing=8)
        toolbar.get_style_context().add_class("term-toolbar")
        toolbar.set_border_width(0)

        title_lbl = Gtk.Label(label="Terminal")
        title_lbl.get_style_context().add_class("card-title")
        title_lbl.set_halign(Gtk.Align.START)
        toolbar.pack_start(title_lbl, False, False, 0)

        # Raccourcis rapides
        quick_cmds = [
            ("apt install",    "sudo apt install "),
            ("snap install",   "sudo snap install "),
            ("flatpak install","flatpak install flathub "),
            ("pip install",    "pip3 install "),
            ("npm install",    "sudo npm install -g "),
        ]
        if has_rpm():
            quick_cmds.insert(2, ("dnf install", "sudo dnf install "))

        sep_v = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        toolbar.pack_start(sep_v, False, False, 4)

        for label, cmd in quick_cmds:
            btn = Gtk.Button(label=label)
            btn.get_style_context().add_class("quick-btn")
            btn.connect("clicked", lambda b, c=cmd: self._term_send(c))
            toolbar.pack_start(btn, False, False, 0)

        outer.pack_start(toolbar, False, False, 0)

        # Terminal VTE ou fallback
        term_area = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        term_area.set_vexpand(True)

        if HAS_VTE:
            self._vte = Vte.Terminal()
            self._vte.set_scrollback_lines(5000)
            self._vte.set_mouse_autohide(True)
            self._vte.set_hexpand(True)
            self._vte.set_vexpand(True)
            # Couleurs terminal
            fg = Gdk.RGBA(); fg.parse("#c8d3f5")
            bg = Gdk.RGBA(); bg.parse("#060d1a")
            self._vte.set_colors(fg, bg, [])
            # Lancer le shell avec proxy dans l'env
            env = os.environ.copy()
            for k,v in [("HTTP_PROXY",PROXY_URL),("HTTPS_PROXY",PROXY_URL),
                        ("http_proxy",PROXY_URL),("https_proxy",PROXY_URL)]:
                env[k] = v
            shell = os.environ.get("SHELL","/bin/bash")
            self._vte.spawn_async(
                Vte.PtyFlags.DEFAULT,
                os.path.expanduser("~"),
                [shell],
                [f"{k}={v}" for k,v in env.items()],
                GLib.SpawnFlags.DO_NOT_REAP_CHILD,
                None, None, -1, None, None)
            sc = Gtk.ScrolledWindow()
            sc.add(self._vte)
            sc.set_hexpand(True); sc.set_vexpand(True)
            term_area.pack_start(sc, True, True, 0)
        else:
            self._vte = None
            # Fallback : zone de sortie + saisie
            fallback = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            fallback.set_vexpand(True)

            warn_bar = Gtk.Box()
            warn_bar.set_border_width(10)
            warn_lbl = Gtk.Label()
            warn_lbl.set_markup(
                '<span foreground="#fb923c">⚠  gir1.2-vte-2.91 non installé — terminal simplifié</span>'
                '  <span foreground="#7a8ab0">(sudo apt install gir1.2-vte-2.91 puis relancer)</span>')
            warn_lbl.set_halign(Gtk.Align.START)
            warn_bar.pack_start(warn_lbl, False, False, 0)
            fallback.pack_start(warn_bar, False, False, 0)

            self._term_out = Gtk.TextView()
            self._term_out.set_editable(False)
            self._term_out.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
            self._term_out.override_background_color(
                Gtk.StateFlags.NORMAL, Gdk.RGBA(0.024, 0.051, 0.102, 1))
            self._term_out.override_color(
                Gtk.StateFlags.NORMAL, Gdk.RGBA(0.784, 0.827, 0.961, 1))
            sw_out = Gtk.ScrolledWindow()
            sw_out.add(self._term_out)
            sw_out.set_vexpand(True)
            fallback.pack_start(sw_out, True, True, 0)

            cmd_row = Gtk.Box(spacing=6)
            cmd_row.set_border_width(8)
            self._cmd_entry = Gtk.Entry()
            self._cmd_entry.set_placeholder_text("$ commande…")
            self._cmd_entry.set_hexpand(True)
            self._cmd_entry.connect("activate", self._run_fallback)
            cmd_row.pack_start(self._cmd_entry, True, True, 0)
            run_btn = Gtk.Button(label="Exécuter")
            run_btn.get_style_context().add_class("btn-accent")
            run_btn.connect("clicked", self._run_fallback)
            cmd_row.pack_start(run_btn, False, False, 0)
            fallback.pack_start(cmd_row, False, False, 0)
            term_area.pack_start(fallback, True, True, 0)

        outer.pack_start(term_area, True, True, 0)
        return outer

    def _term_send(self, text):
        if HAS_VTE and self._vte:
            try:
                self._vte.feed_child(text.encode())       # VTE < 0.70
            except TypeError:
                self._vte.feed_child(text.encode(), -1)   # VTE >= 0.70
            self._vte.grab_focus()
        elif hasattr(self,"_cmd_entry"):
            self._cmd_entry.set_text(text)
            self._cmd_entry.grab_focus()
            self._cmd_entry.set_position(-1)

    def _run_fallback(self, *_):
        cmd = self._cmd_entry.get_text().strip()
        if not cmd: return
        buf = self._term_out.get_buffer()
        buf.insert(buf.get_end_iter(), f"\n$ {cmd}\n")
        env = os.environ.copy()
        env.update({"HTTP_PROXY":PROXY_URL,"HTTPS_PROXY":PROXY_URL,
                    "http_proxy":PROXY_URL,"https_proxy":PROXY_URL})
        try:
            r = subprocess.run(cmd, shell=True, text=True,
                               capture_output=True, env=env, timeout=120)
            buf.insert(buf.get_end_iter(), r.stdout + r.stderr or "(pas de sortie)\n")
        except subprocess.TimeoutExpired:
            buf.insert(buf.get_end_iter(), "(timeout)\n")
        except Exception as e:
            buf.insert(buf.get_end_iter(), f"Erreur : {e}\n")
        self._cmd_entry.set_text("")
        # Auto-scroll
        adj = self._term_out.get_parent().get_vadjustment()
        GLib.idle_add(lambda: adj.set_value(adj.get_upper()))

    # ── PAGE : APPARENCE ──────────────────────────────────────────────────────
    def _page_apparence(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_hexpand(True)
        outer.set_margin_start(28)
        outer.set_margin_end(28)
        outer.set_margin_top(20)
        outer.set_margin_bottom(20)
        outer.pack_start(self._page_header("Apparence","Personnalisez l'interface à votre goût"), False, False, 0)

        # ── Palette de couleurs ──
        outer.pack_start(self._section("Palette de couleurs"), False, False, 0)

        # Grille de tuiles : 4 colonnes
        palette_grid = Gtk.Grid()
        palette_grid.set_column_spacing(10)
        palette_grid.set_row_spacing(10)
        palette_grid.set_margin_top(6)
        palette_grid.set_margin_bottom(16)
        palette_grid.set_hexpand(True)
        palette_grid.set_column_homogeneous(True)
        self._palette_btns = {}
        cur_theme = CFG.get("theme", "dark")

        dark_palettes  = ["dark","minuit","foret","bordeaux","ocean","charbon","violet_nuit","cafe"]
        light_palettes = ["light","creme","rosé","sage"]
        all_palettes   = dark_palettes + light_palettes

        for idx, pid in enumerate(all_palettes):
            pal   = COLOR_PALETTES[pid]
            label = PALETTE_LABELS[pid]
            win_c, side_c, main_c, card_c, hover_c, border_c, fg_c, fg2_c, sep_c = pal

            # Conteneur bouton
            btn_box = Gtk.Button()
            btn_box.set_relief(Gtk.ReliefStyle.NONE)
            btn_box.set_focus_on_click(False)
            btn_box.connect("clicked", self._mk_palette_handler(pid))

            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            inner.set_border_width(2)

            # Miniature de prévisualisation (SVG-like via CSS)
            preview = Gtk.Box(spacing=0)
            preview.set_size_request(120, 60)

            # Bande sidebar
            side_strip = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            side_strip.set_size_request(30, 60)
            sp_side = Gtk.CssProvider()
            sp_side.load_from_data(f".side-{pid}{{background-color:{side_c};border-radius:6px 0 0 6px;}}".encode())
            side_strip.get_style_context().add_provider(sp_side, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            side_strip.get_style_context().add_class(f"side-{pid}")

            # Mini nav dots dans la sidebar
            for dot_color in [fg_c, fg2_c, fg2_c]:
                dot = Gtk.Label(label="●")
                dot.set_margin_start(6); dot.set_margin_top(4)
                sp_dot = Gtk.CssProvider()
                sp_dot.load_from_data(f".dot-{pid}-{dot_color[1:]}{{color:{dot_color};font-size:5pt;}}".encode())
                dot.get_style_context().add_provider(sp_dot, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
                dot.get_style_context().add_class(f"dot-{pid}-{dot_color[1:]}")
                side_strip.pack_start(dot, False, False, 0)
            preview.pack_start(side_strip, False, False, 0)

            # Zone contenu principale
            main_area = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            main_area.set_border_width(5)
            main_area.set_hexpand(True)
            sp_main = Gtk.CssProvider()
            sp_main.load_from_data(f".main-{pid}{{background-color:{main_c};border-radius:0 6px 6px 0;}}".encode())
            main_area.get_style_context().add_provider(sp_main, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            main_area.get_style_context().add_class(f"main-{pid}")

            # Mini cards
            for card_h in [18, 14]:
                mini_card = Gtk.Box()
                mini_card.set_size_request(-1, card_h)
                sp_c = Gtk.CssProvider()
                sp_c.load_from_data(f".mc-{pid}-{card_h}{{background-color:{card_c};border-radius:3px;border:1px solid {border_c};}}".encode())
                mini_card.get_style_context().add_provider(sp_c, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
                mini_card.get_style_context().add_class(f"mc-{pid}-{card_h}")
                main_area.pack_start(mini_card, False, True, 0)
            preview.pack_start(main_area, True, True, 0)

            inner.pack_start(preview, False, False, 0)

            # Nom du thème
            lbl = Gtk.Label(label=label)
            sp_lbl = Gtk.CssProvider()
            sp_lbl.load_from_data(f".pl-{pid}{{font-size:8pt;color:{fg_c if pid==cur_theme else '#888888'};font-weight:{'700' if pid==cur_theme else '400'};padding-top:4px;padding-bottom:2px;}}".encode())
            lbl.get_style_context().add_provider(sp_lbl, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            lbl.get_style_context().add_class(f"pl-{pid}")
            inner.pack_start(lbl, False, False, 0)

            btn_box.add(inner)

            # Bordure active
            sp_btn = Gtk.CssProvider()
            active_border = f"border:2px solid {CFG.get('accent','#7b8fe8')};" if pid == cur_theme else "border:2px solid transparent;"
            sp_btn.load_from_data(f".pb-{pid}{{border-radius:10px;padding:3px;{active_border}}}".encode())
            btn_box.get_style_context().add_provider(sp_btn, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            btn_box.get_style_context().add_class(f"pb-{pid}")
            self._palette_btns[pid] = (btn_box, sp_btn, lbl, sp_lbl)

            col = idx % 4
            row = idx // 4
            palette_grid.attach(btn_box, col, row, 1, 1)

        outer.pack_start(palette_grid, False, False, 0)

        # ── Couleur d'accent ──
        outer.pack_start(self._section("Couleur d'accent"), False, False, 0)
        accent_card = Gtk.Box(spacing=10)
        accent_card.get_style_context().add_class("card")
        accent_card.set_margin_top(6); accent_card.set_margin_bottom(16)

        self._swatches = {}
        presets = [("#7b8fe8","Majorelle"),("#a78bfa","Violet"),
                   ("#34d399","Vert"),("#f59e0b","Ambre"),
                   ("#f87171","Rouge"),("#38bdf8","Cyan"),("#f472b6","Rose"),
                   ("#fb923c","Orange"),("#4ade80","Lime"),("#e879f9","Fuchsia")]
        cur = CFG.get("accent","#7b8fe8")
        for color, tip in presets:
            btn = Gtk.Button()
            btn.set_tooltip_text(tip)
            btn.set_size_request(26,26)
            btn.get_style_context().add_class("swatch")
            if color == cur: btn.get_style_context().add_class("swatch-active")
            sp = Gtk.CssProvider()
            sp.load_from_data(f".sw{color[1:]}{{background-color:{color};border-radius:50%;}}".encode())
            btn.get_style_context().add_provider(sp, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            btn.get_style_context().add_class(f"sw{color[1:]}")
            btn.connect("clicked", self._mk_accent(color))
            accent_card.pack_start(btn,False,False,0)
            self._swatches[color] = btn
        cb = Gtk.ColorButton()
        r = Gdk.RGBA(); r.parse(cur); cb.set_rgba(r)
        cb.set_tooltip_text("Couleur personnalisée")
        cb.connect("color-set", self._on_custom_accent)
        accent_card.pack_start(cb,False,False,0)
        outer.pack_start(accent_card,False,False,0)

        # ── Police de caractères ──
        outer.pack_start(self._section("Police de caractères"), False, False, 0)
        font_fam_card = Gtk.Box(spacing=12)
        font_fam_card.get_style_context().add_class("card")
        font_fam_card.set_margin_top(6); font_fam_card.set_margin_bottom(16)
        self._r_fonts = {}
        fonts = [("Cantarell","Cantarell"),("Ubuntu","Ubuntu"),("Noto Sans","Noto"),
                 ("Liberation Sans","Liberation"),("DejaVu Sans","DejaVu")]
        cur_ff = CFG.get("font_family","Cantarell")
        first_rb = None
        for ff, label in fonts:
            if first_rb is None:
                rb = Gtk.RadioButton(label=f"  {label}")
                first_rb = rb
            else:
                rb = Gtk.RadioButton(group=first_rb, label=f"  {label}")
            if ff == cur_ff: rb.set_active(True)
            rb.connect("toggled", self._mk_font_family(ff))
            font_fam_card.pack_start(rb,False,False,0)
            self._r_fonts[ff] = rb
        outer.pack_start(font_fam_card,False,False,0)

        # ── Taille de police ──
        outer.pack_start(self._section("Taille du texte"), False, False, 0)
        font_card = Gtk.Box(spacing=12)
        font_card.get_style_context().add_class("card")
        font_card.set_margin_top(6); font_card.set_margin_bottom(16)
        font_card.pack_start(Gtk.Label(label="A"), False, False, 0)
        self._font_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 8, 14, 1)
        self._font_scale.set_value(CFG.get("font_size",10))
        self._font_scale.set_hexpand(True)
        self._font_scale.set_draw_value(True)
        self._font_scale.connect("value-changed", self._on_font_change)
        font_card.pack_start(self._font_scale,True,True,0)
        al = Gtk.Label()
        al.set_markup('<span font="14">A</span>')
        font_card.pack_start(al, False, False, 0)
        outer.pack_start(font_card,False,False,0)

        # ── Rayon des coins ──
        outer.pack_start(self._section("Arrondi des coins"), False, False, 0)
        radius_card = Gtk.Box(spacing=12)
        radius_card.get_style_context().add_class("card")
        radius_card.set_margin_top(6); radius_card.set_margin_bottom(16)
        lbl_sq = Gtk.Label(label="□")
        lbl_sq.set_markup('<span font="14">□</span>')
        radius_card.pack_start(lbl_sq, False, False, 0)
        self._radius_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 20, 2)
        self._radius_scale.set_value(CFG.get("border_radius", 12))
        self._radius_scale.set_hexpand(True)
        self._radius_scale.set_draw_value(True)
        self._radius_scale.connect("value-changed", self._on_radius_change)
        radius_card.pack_start(self._radius_scale, True, True, 0)
        lbl_rd = Gtk.Label()
        lbl_rd.set_markup('<span font="14">◯</span>')
        radius_card.pack_start(lbl_rd, False, False, 0)
        outer.pack_start(radius_card, False, False, 0)

        # ── Opacité de la sidebar ──
        outer.pack_start(self._section("Opacité de la barre latérale"), False, False, 0)
        op_card = Gtk.Box(spacing=12)
        op_card.get_style_context().add_class("card")
        op_card.set_margin_top(6); op_card.set_margin_bottom(16)
        lbl_op0 = Gtk.Label(label="Transparent")
        lbl_op0.get_style_context().add_class("card-sub")
        op_card.pack_start(lbl_op0, False, False, 0)
        self._opacity_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 40, 100, 5)
        self._opacity_scale.set_value(CFG.get("sidebar_opacity", 100))
        self._opacity_scale.set_hexpand(True)
        self._opacity_scale.set_draw_value(True)
        self._opacity_scale.connect("value-changed", self._on_opacity_change)
        op_card.pack_start(self._opacity_scale, True, True, 0)
        lbl_op1 = Gtk.Label(label="Opaque")
        lbl_op1.get_style_context().add_class("card-sub")
        op_card.pack_start(lbl_op1, False, False, 0)
        outer.pack_start(op_card, False, False, 0)

        # ── Style de navigation ──
        outer.pack_start(self._section("Style de la navigation"), False, False, 0)
        nav_card = Gtk.Box(spacing=16)
        nav_card.get_style_context().add_class("card")
        nav_card.set_margin_top(6); nav_card.set_margin_bottom(16)
        self._r_nav = {}
        nav_styles = [("pill","  Pilule"),("underline","  Souligné"),("square","  Carré")]
        cur_nav = CFG.get("nav_style","pill")
        first_nr = None
        for ns, nl in nav_styles:
            if first_nr is None:
                nr = Gtk.RadioButton(label=nl)
                first_nr = nr
            else:
                nr = Gtk.RadioButton(group=first_nr, label=nl)
            if ns == cur_nav: nr.set_active(True)
            nr.connect("toggled", self._mk_nav_style(ns))
            nav_card.pack_start(nr, False, False, 0)
            self._r_nav[ns] = nr
        outer.pack_start(nav_card, False, False, 0)

        # ── Icône dans la barre des tâches ──
        outer.pack_start(self._section("Icône dans la barre des tâches"), False, False, 0)
        tray_card = Gtk.Box(spacing=16)
        tray_card.get_style_context().add_class("card")
        tray_card.set_margin_top(6); tray_card.set_margin_bottom(16)
        self._r_tray = {}
        tray_icons = [
            ("default",  "  Réseau (défaut)"),
            ("minimal",  "  Minimaliste (M)"),
            ("wifi",     "  Signal WiFi"),
            ("shield",   "  Bouclier"),
        ]
        cur_ti = CFG.get("tray_icon","default")
        first_tr = None
        for ti, tl in tray_icons:
            if first_tr is None:
                tr = Gtk.RadioButton(label=tl)
                first_tr = tr
            else:
                tr = Gtk.RadioButton(group=first_tr, label=tl)
            if ti == cur_ti: tr.set_active(True)
            tr.connect("toggled", self._mk_tray_icon_style(ti))
            tray_card.pack_start(tr, False, False, 0)
            self._r_tray[ti] = tr
        outer.pack_start(tray_card, False, False, 0)

        # ── Reset ──
        rst = Gtk.Button(label="Réinitialiser l'apparence")
        rst.get_style_context().add_class("btn-ghost")
        rst.set_halign(Gtk.Align.START)
        rst.connect("clicked", self._reset_appearance)
        outer.pack_start(rst,False,False,0)

        return self._scrolled(outer)

    def _mk_palette_handler(self, pid):
        def h(_):
            CFG["theme"] = pid
            save_cfg(CFG)
            apply_css(CFG)
            # Update visual selection state
            acc = CFG.get("accent", "#7b8fe8")
            for tid, (btn, sp_btn, lbl, sp_lbl) in self._palette_btns.items():
                pal = COLOR_PALETTES[tid]
                fg_c = pal[6]
                active = (tid == pid)
                border = f"border:2px solid {acc};" if active else "border:2px solid transparent;"
                sp_btn.load_from_data(f".pb-{tid}{{border-radius:10px;padding:3px;{border}}}".encode())
                fw = "700" if active else "400"
                col = fg_c if active else "#888888"
                sp_lbl.load_from_data(f".pl-{tid}{{font-size:8pt;color:{col};font-weight:{fw};padding-top:4px;padding-bottom:2px;}}".encode())
        return h

    def _set_theme(self, t):
        CFG["theme"] = t; save_cfg(CFG); apply_css(CFG)

    def _mk_accent(self, color):
        def h(_):
            CFG["accent"] = color; save_cfg(CFG); apply_css(CFG)
            for c,btn in self._swatches.items():
                ctx = btn.get_style_context()
                ctx.add_class("swatch-active") if c==color else ctx.remove_class("swatch-active")
            # Rafraîchir la bordure de la palette active
            if hasattr(self, "_palette_btns"):
                cur = CFG.get("theme","dark")
                for tid, (pb, sp_btn, lbl, sp_lbl) in self._palette_btns.items():
                    active = (tid == cur)
                    border = f"border:2px solid {color};" if active else "border:2px solid transparent;"
                    sp_btn.load_from_data(f".pb-{tid}{{border-radius:10px;padding:3px;{border}}}".encode())
            # Mettre à jour l'icône tray avec la nouvelle couleur d'accent
            self._write_tray_svg(CFG.get("tray_icon","default"))
        return h

    def _on_custom_accent(self, btn):
        rgba = btn.get_rgba()
        c = f"#{int(rgba.red*255):02x}{int(rgba.green*255):02x}{int(rgba.blue*255):02x}"
        CFG["accent"] = c; save_cfg(CFG); apply_css(CFG)
        self._write_tray_svg(CFG.get("tray_icon","default"))

    def _on_font_change(self, scale):
        CFG["font_size"] = int(scale.get_value()); save_cfg(CFG); apply_css(CFG)

    def _mk_font_family(self, ff):
        def h(rb):
            if rb.get_active():
                CFG["font_family"] = ff; save_cfg(CFG); apply_css(CFG)
        return h

    def _on_radius_change(self, scale):
        CFG["border_radius"] = int(scale.get_value()); save_cfg(CFG); apply_css(CFG)

    def _on_opacity_change(self, scale):
        CFG["sidebar_opacity"] = int(scale.get_value()); save_cfg(CFG); apply_css(CFG)

    def _mk_nav_style(self, ns):
        def h(rb):
            if rb.get_active():
                CFG["nav_style"] = ns; save_cfg(CFG); apply_css(CFG)
        return h

    def _mk_tray_icon_style(self, ti):
        def h(rb):
            if rb.get_active():
                CFG["tray_icon"] = ti; save_cfg(CFG)
                self._write_tray_svg(ti)
                # Rafraîchir l'icône dans le tray si possible
                icon_path = os.path.join(INSTALL_DIR, "majorelle.svg")
                if HAS_INDICATOR and hasattr(self, "_indicator"):
                    try:
                        self._indicator.set_icon_full(icon_path, "Réseau Majorelle")
                    except Exception:
                        pass
                elif hasattr(self, "_status_icon"):
                    try:
                        pb = GdkPixbuf.Pixbuf.new_from_file_at_size(icon_path, 22, 22)
                        self._status_icon.set_from_pixbuf(pb)
                    except Exception:
                        pass
        return h

    def _reset_appearance(self, *_):
        for k in ("theme","accent","font_size","font_family","border_radius","sidebar_opacity","nav_style","tray_icon"):
            CFG[k] = DEFAULT_CFG[k]
        save_cfg(CFG); apply_css(CFG)
        if hasattr(self,"_font_scale"):
            self._font_scale.set_value(DEFAULT_CFG["font_size"])
        if hasattr(self,"_radius_scale"):
            self._radius_scale.set_value(DEFAULT_CFG["border_radius"])
        if hasattr(self,"_opacity_scale"):
            self._opacity_scale.set_value(DEFAULT_CFG["sidebar_opacity"])
        # Rafraîchir la sélection de palette
        if hasattr(self, "_palette_btns"):
            acc = CFG.get("accent", "#7b8fe8")
            for tid, (btn, sp_btn, lbl, sp_lbl) in self._palette_btns.items():
                pal = COLOR_PALETTES[tid]
                fg_c = pal[6]
                active = (tid == DEFAULT_CFG["theme"])
                border = f"border:2px solid {acc};" if active else "border:2px solid transparent;"
                sp_btn.load_from_data(f".pb-{tid}{{border-radius:10px;padding:3px;{border}}}".encode())
                fw = "700" if active else "400"
                col = fg_c if active else "#888888"
                sp_lbl.load_from_data(f".pl-{tid}{{font-size:8pt;color:{col};font-weight:{fw};padding-top:4px;padding-bottom:2px;}}".encode())
        self._write_tray_svg(DEFAULT_CFG["tray_icon"])

    # ── PAGE : PARAMÈTRES ─────────────────────────────────────────────────────
    def _page_parametres(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_hexpand(True)
        outer.set_margin_start(28)
        outer.set_margin_end(28)
        outer.set_margin_top(20)
        outer.set_margin_bottom(20)
        outer.pack_start(self._page_header("Paramètres", "Configuration du proxy et du comportement"), False, False, 0)

        # ── Proxy ──
        outer.pack_start(self._section("Adresse du proxy"), False, False, 0)
        proxy_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        proxy_card.get_style_context().add_class("card")
        proxy_card.set_margin_top(6); proxy_card.set_margin_bottom(16)

        row_host = Gtk.Box(spacing=12)
        lbl_host = Gtk.Label(label="Hôte")
        lbl_host.get_style_context().add_class("info-key")
        lbl_host.set_halign(Gtk.Align.START)
        self._entry_host = Gtk.Entry()
        self._entry_host.set_text(CFG.get("proxy_host", _DEFAULT_PROXY_HOST))
        self._entry_host.set_hexpand(True)
        self._entry_host.set_placeholder_text("ex : 172.19.255.254")
        row_host.pack_start(lbl_host, False, False, 0)
        row_host.pack_start(self._entry_host, True, True, 0)
        proxy_card.pack_start(row_host, False, False, 0)

        row_port = Gtk.Box(spacing=12)
        lbl_port = Gtk.Label(label="Port")
        lbl_port.get_style_context().add_class("info-key")
        lbl_port.set_halign(Gtk.Align.START)
        self._entry_port = Gtk.Entry()
        self._entry_port.set_text(str(CFG.get("proxy_port", _DEFAULT_PROXY_PORT)))
        self._entry_port.set_width_chars(8)
        self._entry_port.set_placeholder_text("ex : 3128")
        row_port.pack_start(lbl_port, False, False, 0)
        row_port.pack_start(self._entry_port, False, False, 0)
        proxy_card.pack_start(row_port, False, False, 0)

        btn_save_proxy = Gtk.Button(label="Appliquer le proxy")
        btn_save_proxy.get_style_context().add_class("btn-accent")
        btn_save_proxy.set_halign(Gtk.Align.START)
        btn_save_proxy.connect("clicked", self._save_proxy)
        proxy_card.pack_start(btn_save_proxy, False, False, 0)
        outer.pack_start(proxy_card, False, False, 0)

        # ── Comportement ──
        outer.pack_start(self._section("Comportement"), False, False, 0)
        behav_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        behav_card.get_style_context().add_class("card")
        behav_card.set_margin_top(6); behav_card.set_margin_bottom(16)

        for key, label, tip in [
            ("autostart",      "Démarrage automatique",          "Lance l'app au démarrage de session"),
            ("tray_on_close",  "Réduire dans le tray à la fermeture", "Masque la fenêtre au lieu de quitter"),
            ("start_minimized","Démarrer minimisé dans le tray", "Démarre sans fenêtre, icône tray seulement"),
        ]:
            row = Gtk.Box(spacing=12)
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            col.set_hexpand(True)
            lbl = Gtk.Label(label=label)
            lbl.get_style_context().add_class("card-title")
            lbl.set_halign(Gtk.Align.START)
            sub = Gtk.Label(label=tip)
            sub.get_style_context().add_class("card-sub")
            sub.set_halign(Gtk.Align.START)
            col.pack_start(lbl, False, False, 0)
            col.pack_start(sub, False, False, 0)
            row.pack_start(col, True, True, 0)
            sw = Gtk.Switch()
            sw.set_active(CFG.get(key, DEFAULT_CFG.get(key, False)))
            sw.connect("notify::active", self._mk_behav_toggle(key))
            row.pack_start(sw, False, False, 0)
            behav_card.pack_start(row, False, False, 0)

        outer.pack_start(behav_card, False, False, 0)

        # ── Réinitialiser le proxy ──
        rst = Gtk.Button(label="Remettre le proxy par défaut du lycée")
        rst.get_style_context().add_class("btn-ghost")
        rst.set_halign(Gtk.Align.START)
        rst.connect("clicked", self._reset_proxy)
        outer.pack_start(rst, False, False, 0)

        return self._scrolled(outer)

    def _save_proxy(self, *_):
        host = self._entry_host.get_text().strip()
        port_s = self._entry_port.get_text().strip()
        if not host or not port_s.isdigit():
            dlg = Gtk.MessageDialog(transient_for=self, modal=True,
                message_type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.OK,
                text="Hôte ou port invalide.")
            dlg.run(); dlg.destroy(); return
        CFG["proxy_host"] = host
        CFG["proxy_port"] = int(port_s)
        save_cfg(CFG)
        _rebuild_proxy()
        self._refresh_sys()
        dlg = Gtk.MessageDialog(transient_for=self, modal=True,
            message_type=Gtk.MessageType.INFO, buttons=Gtk.ButtonsType.OK,
            text=f"Proxy mis à jour : http://{host}:{port_s}")
        dlg.run(); dlg.destroy()

    def _reset_proxy(self, *_):
        CFG["proxy_host"] = _DEFAULT_PROXY_HOST
        CFG["proxy_port"] = _DEFAULT_PROXY_PORT
        save_cfg(CFG); _rebuild_proxy()
        self._entry_host.set_text(_DEFAULT_PROXY_HOST)
        self._entry_port.set_text(str(_DEFAULT_PROXY_PORT))
        self._refresh_sys()

    def _mk_behav_toggle(self, key):
        def handler(sw, _):
            CFG[key] = sw.get_active()
            save_cfg(CFG)
            if key == "autostart":
                self._set_autostart(sw.get_active())
        return handler

    def _set_autostart(self, enable):
        os.makedirs(os.path.dirname(AUTOSTART_FILE), exist_ok=True)
        app_file = os.path.join(INSTALL_DIR, "majorelle.py")
        if enable:
            with open(AUTOSTART_FILE, "w") as f:
                f.write(f"""[Desktop Entry]
Name=Réseau Louis Majorelle
Exec=python3 {app_file}
Icon=reseau-majorelle
Type=Application
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=false
Comment=Démarrage automatique proxy lycée
""")
        else:
            try: os.remove(AUTOSTART_FILE)
            except FileNotFoundError: pass

# ── Main ──────────────────────────────────────────────────────────────────────
import sys, traceback, logging

LOG_PY = os.path.join(
    os.path.expanduser(
        subprocess.run(["xdg-user-dir","DOWNLOAD"], capture_output=True, text=True).stdout.strip()
        or os.path.expanduser("~/Téléchargements")
    ),
    "majorelle-logs", "majorelle_app.log"
)
os.makedirs(os.path.dirname(LOG_PY), exist_ok=True)
logging.basicConfig(
    filename=LOG_PY, level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S")

def log(msg, level="info"):
    getattr(logging, level)(msg)
    print(msg)

if __name__ == "__main__":
    log(f"=== Démarrage Majorelle v$VERSION ===")
    log(f"Python  : {sys.version}")
    log(f"GTK     : {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}")
    log(f"HAS_VTE       : {HAS_VTE}")
    log(f"HAS_INDICATOR : {HAS_INDICATOR}")
    try:
        Gtk.init([])
        log("Gtk.init() OK")
        App()
        log("App() créée")
        Gtk.main()
    except Exception:
        tb = traceback.format_exc()
        log(f"CRASH:\n{tb}", "error")
        sys.exit(1)
    log("Fin normale")
PYEOF

chmod +x "$APP_FILE"

# ── 6. Lanceur binaire + .desktop système ───────────────────────────
echo "→ Installation comme logiciel système..."

# Créer un vrai lanceur exécutable dans /usr/local/bin
sudo tee "$LAUNCHER" > /dev/null <<LAUNCHEOF
#!/usr/bin/env bash
# Lanceur Réseau Louis Majorelle v$VERSION
exec python3 "$APP_FILE" "\$@"
LAUNCHEOF
sudo chmod +x "$LAUNCHER"
echo "  ✅ Lanceur créé : $LAUNCHER"

# .desktop utilisateur (compatibilité)
cat > "$DESKTOP_DIR/$APP_ID.desktop" <<DEOF
[Desktop Entry]
Name=Réseau Louis Majorelle
GenericName=Gestionnaire de proxy
Comment=Proxy réseau lycée Louis Majorelle
Exec=$LAUNCHER %u
Icon=$ICON_NAME
Terminal=false
Type=Application
Categories=Network;Settings;System;
Keywords=proxy;réseau;lycée;majorelle;wifi;
StartupNotify=true
StartupWMClass=reseau-majorelle
X-GNOME-SingleWindow=true
DEOF
chmod +x "$DESKTOP_DIR/$APP_ID.desktop"

# .desktop SYSTÈME — c'est lui qui fait apparaître l'icône dans le dock Ubuntu
sudo tee "$SYS_DESKTOP_DIR/$APP_ID.desktop" > /dev/null <<SDEOF
[Desktop Entry]
Name=Réseau Louis Majorelle
GenericName=Gestionnaire de proxy
Comment=Proxy réseau lycée Louis Majorelle
Exec=$LAUNCHER %u
Icon=$ICON_NAME
Terminal=false
Type=Application
Categories=Network;Settings;System;
Keywords=proxy;réseau;lycée;majorelle;wifi;
StartupNotify=true
StartupWMClass=reseau-majorelle
X-GNOME-SingleWindow=true
SDEOF
sudo chmod +x "$SYS_DESKTOP_DIR/$APP_ID.desktop"

# Mettre à jour les bases de données système
sudo update-desktop-database "$SYS_DESKTOP_DIR" 2>/dev/null || true
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

# Enregistrer via xdg (méthode officielle)
xdg-desktop-menu install --novendor "$SYS_DESKTOP_DIR/$APP_ID.desktop" 2>/dev/null || true
xdg-icon-resource install --novendor --context apps --size scalable \
    "$ICON_FILE" "$ICON_NAME" 2>/dev/null || true

# Forcer GNOME Shell à relire les icônes immédiatement
sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true

# Notification bureau
if command -v notify-send &>/dev/null; then
    notify-send --icon="$ICON_NAME" \
        "Réseau Louis Majorelle v$VERSION" \
        "Installé — cherchez 'Majorelle' dans les applications" \
        2>/dev/null || true
fi

echo "  ✅ Logiciel installé : cherchez 'Majorelle' dans les applications"
echo "  ✅ Raccourci dock    : clic droit → Épingler au dock"

# ── 7. Certificat 802.1X & connexion automatique ────────────────────
echo "→ Configuration 802.1X (wpa_supplicant + NetworkManager)..."

_setup_8021x() {
    local P12="$1"
    local PASS="$2"
    local CA_PEM_SRC="$3"   # optionnel : chemin vers un ca-cert.pem séparé

    # ── Copier le .p12 tel quel (NM l'utilise directement comme GNOME le fait) ──
    cp "$P12" "$CERT_DIR/certificate.p12"
    chmod 600 "$CERT_DIR/certificate.p12"

    # ── CA cert : préférer le fichier PEM séparé, sinon extraire du .p12 ──
    if [ -f "$CA_PEM_SRC" ]; then
        cp "$CA_PEM_SRC" "$CERT_DIR/ca-cert.pem"
        echo "  ✅ CA cert copié depuis : $(basename "$CA_PEM_SRC")"
    else
        openssl pkcs12 -in "$P12" -nokeys -cacerts \
            -passin "pass:$PASS" -passout pass: \
            -out "$CERT_DIR/ca-cert.pem" 2>/dev/null || true
        echo "  ✅ CA cert extrait du .p12"
    fi
    chmod 644 "$CERT_DIR/ca-cert.pem"

    # ── Extraire client.crt / client.key pour wpa_supplicant uniquement ──
    openssl pkcs12 -in "$P12" -nokeys -clcerts \
        -passin "pass:$PASS" -passout pass: \
        -out "$CERT_DIR/client.crt" 2>/dev/null || true
    openssl pkcs12 -in "$P12" -nocerts -nodes \
        -passin "pass:$PASS" \
        -out "$CERT_DIR/client.key" 2>/dev/null || true
    chmod 600 "$CERT_DIR/client.key"

    # ── CN et expiry ──
    CN=$(openssl pkcs12 -in "$P12" -nokeys -clcerts \
            -passin "pass:$PASS" -passout pass: 2>/dev/null \
         | openssl x509 -noout -subject 2>/dev/null \
         | sed 's/.*CN\s*=\s*//' | cut -d',' -f1 | tr -d ' ')
    echo "$CN" > "$CERT_DIR/cn.txt"
    openssl pkcs12 -in "$P12" -nokeys -clcerts \
        -passin "pass:$PASS" -passout pass: 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | sed 's/notAfter=//' > "$CERT_DIR/expiry.txt"
    echo "  ✅ Certificat prêt — identité : $CN"

    # ── wpa_supplicant ────────────────────────────────────────────────
    sudo mkdir -p /etc/wpa_supplicant
    cat > /tmp/majorelle_wpa.conf <<WPAEOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="Etablissement"
    key_mgmt=WPA-EAP
    eap=TLS
    identity="$CN"
    ca_cert="$CERT_DIR/ca-cert.pem"
    client_cert="$CERT_DIR/client.crt"
    private_key="$CERT_DIR/client.key"
    phase1="peapver=0"
    priority=10
}
WPAEOF
    sudo cp /tmp/majorelle_wpa.conf /etc/wpa_supplicant/wpa_supplicant-majorelle.conf
    sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant-majorelle.conf
    rm -f /tmp/majorelle_wpa.conf
    echo "  ✅ wpa_supplicant configuré pour SSID Etablissement"

    # ── NetworkManager ─────────────────────────────────────────────────
    # Correspond exactement à la config GNOME (capture écran) :
    #   CA cert    → ca-cert.pem
    #   User cert  → certificate.p12
    #   Private key→ certificate.p12  (même fichier)
    #   Password   → mot de passe du .p12
    if command -v nmcli &>/dev/null; then

        _nm_apply() {
            local CON_NAME="$1"
            nmcli connection modify "$CON_NAME" \
                wifi-sec.key-mgmt wpa-eap \
                802-1x.eap tls \
                802-1x.identity "$CN" \
                802-1x.ca-cert "$CERT_DIR/ca-cert.pem" \
                802-1x.client-cert "$CERT_DIR/certificate.p12" \
                802-1x.private-key "$CERT_DIR/certificate.p12" \
                802-1x.private-key-password "1234" \
                connection.autoconnect yes \
                ipv4.method auto 2>/dev/null
        }

        # Chercher la connexion "Etablissement" existante
        ETAB_CON=$(nmcli -t -f NAME,TYPE connection show \
            | grep -i "etablissement" | head -1 | cut -d: -f1)

        if [ -n "$ETAB_CON" ]; then
            echo "  🔧 Connexion trouvée : $ETAB_CON — application du certificat..."
            if _nm_apply "$ETAB_CON"; then
                echo "  ✅ Certificat configuré dans : $ETAB_CON"
            else
                echo "  ❌ Échec configuration NM pour : $ETAB_CON"
            fi
        else
            # Créer la connexion Wi-Fi WPA-EAP/TLS si elle n'existe pas
            echo "  ℹ️  Connexion 'Etablissement' absente — création..."
            nmcli connection add \
                type wifi \
                con-name "Etablissement" \
                ssid "Etablissement" \
                wifi-sec.key-mgmt wpa-eap \
                802-1x.eap tls \
                802-1x.identity "$CN" \
                802-1x.ca-cert "$CERT_DIR/ca-cert.pem" \
                802-1x.client-cert "$CERT_DIR/certificate.p12" \
                802-1x.private-key "$CERT_DIR/certificate.p12" \
                802-1x.private-key-password "1234" \
                connection.autoconnect yes \
                ipv4.method auto 2>/dev/null \
            && echo "  ✅ Connexion 'Etablissement' créée et configurée" \
            || echo "  ❌ Impossible de créer la connexion NM"
            ETAB_CON="Etablissement"
        fi

        nmcli connection up "$ETAB_CON" 2>/dev/null \
            && echo "  ✅ Connexion activée : $ETAB_CON" \
            || echo "  ℹ️  Activation différée (normal si hors portée Wi-Fi)"

        # Connexion filaire — même logique
        ETH_ETAB=$(nmcli -t -f NAME,TYPE connection show \
            | grep "802-3-ethernet" | head -1 | cut -d: -f1)
        if [ -n "$ETH_ETAB" ]; then
            nmcli connection modify "$ETH_ETAB" \
                802-1x.eap tls \
                802-1x.identity "$CN" \
                802-1x.ca-cert "$CERT_DIR/ca-cert.pem" \
                802-1x.client-cert "$CERT_DIR/certificate.p12" \
                802-1x.private-key "$CERT_DIR/certificate.p12" \
                802-1x.private-key-password "1234" \
                connection.autoconnect yes 2>/dev/null \
            && echo "  ✅ Certificat injecté dans connexion filaire : $ETH_ETAB" || true
        fi
    fi

    # ── NSS (Chrome/Chromium) ──────────────────────────────────────────
    if command -v certutil &>/dev/null; then
        NSSDB="$HOME/.pki/nssdb"
        mkdir -p "$NSSDB"
        certutil -d "sql:$NSSDB" -N --empty-password 2>/dev/null || true
        certutil -d "sql:$NSSDB" -A -n "Majorelle-CA" \
            -t "CT,," -i "$CERT_DIR/ca-cert.pem" 2>/dev/null && \
            echo "  ✅ CA importé dans NSS (Chrome/Chromium)" || true
    fi
}

# Chercher le .p12 et le ca-cert.pem
FOUND_CERT=$(find "$HOME/Téléchargements" "$HOME" -maxdepth 3 \
    \( -name "*.pkcs12" -o -name "*.p12" \) 2>/dev/null | head -1)
FOUND_CA=$(find "$HOME/Téléchargements" "$HOME" -maxdepth 3 \
    -name "ca-cert.pem" 2>/dev/null | head -1)

if [ -f "$CERT_DIR/certificate.p12" ]; then
    echo "  ✅ Certificat déjà installé — connexion auto active"
elif [ -n "$FOUND_CERT" ]; then
    echo "  🔐 Certificat trouvé : $(basename "$FOUND_CERT")"
    [ -n "$FOUND_CA" ] && echo "  🔐 CA cert trouvé  : $(basename "$FOUND_CA")"
    CERT_PASS=""
    for _TRY in "" "changeit" "password" "Password1" "cisco" "admin" "reseau" "lycee" "majorelle"; do
        if openssl pkcs12 -in "$FOUND_CERT" -nokeys -noout \
                -passin "pass:$_TRY" 2>/dev/null; then
            CERT_PASS="$_TRY"; break
        fi
    done
    if openssl pkcs12 -in "$FOUND_CERT" -nokeys -noout \
            -passin "pass:$CERT_PASS" 2>/dev/null; then
        _setup_8021x "$FOUND_CERT" "$CERT_PASS" "$FOUND_CA"
    else
        read -s -p "  Mot de passe du certificat : " CERT_PASS; echo ""
        if openssl pkcs12 -in "$FOUND_CERT" -nokeys -noout \
                -passin "pass:$CERT_PASS" 2>/dev/null; then
            _setup_8021x "$FOUND_CERT" "$CERT_PASS" "$FOUND_CA"
        else
            echo "  ⚠️  Mot de passe incorrect — connexion auto non configurée"
            echo "     Relancez le script avec le bon certificat dans ~/Téléchargements"
        fi
    fi
    unset CERT_PASS
else
    echo "  ℹ️  Aucun certificat trouvé dans ~/Téléchargements"
    echo "     Téléchargez-le depuis le portail du lycée et relancez le script"
fi

# ── 8. Proxy gestionnaire de paquets ────────────────────────────────
echo "→ Configuration proxy système de paquets..."
case "$PKG_MGR" in
    apt)
        sudo tee /etc/apt/apt.conf.d/99-proxy-majorelle > /dev/null <<EOF
Acquire::http::Proxy "$PROXY_URL";
Acquire::https::Proxy "$PROXY_URL";
EOF
        echo "  ✅ apt configuré"
        ;;
    dnf)
        DNF_CONF="/etc/dnf/dnf.conf"
        if sudo grep -q "^proxy=" "$DNF_CONF" 2>/dev/null; then
            sudo sed -i "s|^proxy=.*|proxy=$PROXY_URL|" "$DNF_CONF"
        else
            echo "proxy=$PROXY_URL" | sudo tee -a "$DNF_CONF" > /dev/null
        fi
        echo "  ✅ dnf configuré"
        ;;
    pacman)
        echo "  ℹ️  pacman utilise les variables d'env HTTP_PROXY/HTTPS_PROXY (déjà configurées)"
        ;;
    zypper)
        sudo zypper modifyrepo --all --proxy "$PROXY_URL" 2>/dev/null || true
        echo "  ✅ zypper configuré"
        ;;
    *)
        echo "  ⚠️  Configuration apt ignorée (gestionnaire non apt)"
        ;;
esac

# ── 9. Git & GitHub via proxy ────────────────────────────────────────
echo "→ Configuration Git (proxy réseau lycée)..."

# Config globale git
git config --global http.proxy  "$PROXY_URL"
git config --global https.proxy "$PROXY_URL"
# Pas de proxy pour localhost/intranet
git config --global no_proxy    "localhost,127.0.0.1,172.19.0.0/16,192.168.0.0/16"
echo "  ✅ git config --global http(s).proxy configuré"

# Variables d'environnement persistantes dans le profil shell
# (utiles pour les sous-processus comme git appelé depuis un script sudo)
for _RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$_RC" ] || continue
    # Ne pas dupliquer
    if ! grep -q "majorelle-git-proxy" "$_RC" 2>/dev/null; then
        cat >> "$_RC" <<RCEOF

# ── Réseau Majorelle — proxy Git ── majorelle-git-proxy
export GIT_PROXY_COMMAND=""
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export no_proxy="localhost,127.0.0.1,172.19.0.0/16,192.168.0.0/16"
export NO_PROXY="\$no_proxy"
RCEOF
        echo "  ✅ Variables proxy ajoutées dans : $_RC"
    else
        echo "  ℹ️  Proxy déjà présent dans : $_RC"
    fi
done

# Proxy également pour git lancé en sudo (git clone dans des scripts d'install)
SUDOERS_GIT="/etc/sudoers.d/majorelle-git-proxy"
if [ ! -f "$SUDOERS_GIT" ]; then
    echo 'Defaults env_keep += "http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY GIT_CONFIG_NOSYSTEM"' \
        | sudo tee "$SUDOERS_GIT" > /dev/null
    sudo chmod 440 "$SUDOERS_GIT"
    echo "  ✅ sudo préservation proxy configurée (sudoers.d)"
fi

# ── 10. Snap ─────────────────────────────────────────────────────────
if command -v snap &>/dev/null; then
    sudo snap set system proxy.http="$PROXY_URL"
    sudo snap set system proxy.https="$PROXY_URL"
    echo "  ✅ snap configuré"
fi

# ── 11. Flatpak ──────────────────────────────────────────────────────
if command -v flatpak &>/dev/null; then
    # flatpak config --set http-proxy supprimé dans flatpak 1.15+
    # On passe par override --env qui fonctionne sur toutes les versions
    for VAR in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
        flatpak override --system --env="$VAR=$PROXY_URL" 2>/dev/null || \
        flatpak override --user  --env="$VAR=$PROXY_URL" 2>/dev/null || true
    done
    echo "  ✅ flatpak configuré"
fi

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║   ✅  Installation v$VERSION terminée !            ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "  Lance depuis GNOME : 'Réseau Louis Majorelle'"
echo "  ou : python3 $APP_FILE"
echo "  Logs : $LOG_DIR/"
echo "    ├── majorelle_install.log  (ce script)"
echo "    └── majorelle_app.log      (erreurs de l'app)"
echo ""
