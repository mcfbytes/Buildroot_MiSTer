"""Root Kun art generator: MiSTer Kun as the site foreman who builds the whole OS from source.

Same pipeline as the Tasty, Seedy and ItsAlive art: MiSTer Kun's paths from the upstream remaster,
hand-written SVG props on top, inkscape for PNGs.
Run: python3 art-src/gen.py  (writes ../art and ../art/icons)
upstream/mister_kun_fullcolor.svg is vendored from baxysquare/mister_kun at KUN_COMMIT and hash-checked,
because the path extraction below depends on its exact path order.
"""
import hashlib, re, subprocess, os

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "art")
ICONS = os.path.join(ART, "icons")
KUN_SRC = os.environ.get("KUN_SVG", os.path.join(HERE, "upstream", "mister_kun_fullcolor.svg"))
KUN_COMMIT = "97df77b74f15e767e698293e04be559c7e8b788b"
KUN_SHA256 = "03a820c50a06fb7cb477bcd3004f3146e638f629503539128c357e13ff68bd80"

raw = open(KUN_SRC, "rb").read()
if hashlib.sha256(raw).hexdigest() != KUN_SHA256:
    exit(f"{KUN_SRC}: sha256 mismatch, expected mister_kun_fullcolor.svg from baxysquare/mister_kun@{KUN_COMMIT}")
src = raw.decode()
PATHS = [p for p in re.findall(r'<path [^>]*/>', src) if 'm-81.806' not in p]
OUTLINE, FILL, FACE = PATHS[0], PATHS[1], PATHS[2:]
FILL_D = re.search(r'd="([^"]*)"', FILL).group(1)

PINK = "#e88cb8"; WHITE = "#efefef"; GREY = "#b3b3b3"
ACCENT = "#ffb81c"   # hard-hat yellow: the Buildroot accent
ACCENT_D = "#d9920a"; ACCENT_L = "#ffe08a"
VEST = "#ff7a1a"; VEST_D = "#d65a06"; REFLECT = "#e8eef2"
STEEL = "#9aa3ad"; STEEL_D = "#646d78"; STEEL_L = "#d4dae0"
BLUE = "#2f6fd6"; BLUE_D = "#1f4c99"; BLUE_L = "#cfe0ff"
WOOD = "#8a5a36"; RED = "#d9463b"; GREEN = "#5bbf4a"; PAPER = "#fbfbf6"
CARD = "#2b2b3a"; TERM = "#14181f"; CORN = "#ffd23f"; CORN_D = "#e6a817"
S = 'stroke="#000" stroke-width="16" stroke-linejoin="round" stroke-linecap="round"'
S10 = 'stroke="#000" stroke-width="10" stroke-linejoin="round" stroke-linecap="round"'
FONT = 'font-family="Open Sans" font-weight="800" font-style="italic"'
MONO = 'font-family="DejaVu Sans Mono" font-weight="bold"'
JP = 'font-family="Noto Sans JP Thin" font-weight="800"'

DEFS = f'<defs><clipPath id="body"><path d="{FILL_D}"/></clipPath></defs>'


# --- the foreman ----------------------------------------------------------------------------------

def hardhat(tilt=-5):
    """A yellow hard hat between the ears, with a root prompt on the front."""
    out = f'<g transform="rotate({tilt} 500 170)">'
    # dome, then a ridge down the middle, then the brim on top so its edge reads in front
    out += f'<path d="M318 176 C318 70 400 18 500 18 C600 18 682 70 682 176 Z" fill="{ACCENT}" {S}/>'
    out += f'<path d="M454 26 C446 70 446 130 452 172 L548 172 C554 130 554 70 546 26" fill="{ACCENT_L}" {S10}/>'
    out += f'<path d="M370 120 C380 80 400 60 420 50" fill="none" stroke="#fff" stroke-width="14" stroke-linecap="round" opacity="0.8"/>'
    out += f'<path d="M262 186 C300 154 700 154 738 186 C752 204 722 214 690 206 C600 186 400 186 310 206 C278 214 248 204 262 186 Z" fill="{ACCENT_D}" {S}/>'
    out += f'<text x="500" y="146" {MONO} font-size="64" text-anchor="middle" fill="#000">#</text>'
    return out + '</g>'


def vest():
    """Hi-vis vest over the lower body: orange panels, two reflective bands, open at the front."""
    body = f'<path d="M0 690 L380 690 L460 1010 L0 1010 Z M1000 690 L620 690 L540 1010 L1000 1010 Z" fill="{VEST}" {S}/>'
    body += f'<rect x="0" y="690" width="150" height="320" fill="{VEST_D}" opacity="0.5"/>'
    body += f'<rect x="850" y="690" width="150" height="320" fill="{VEST_D}" opacity="0.5"/>'
    for y in (790, 900):
        for d in (f"M-20 {y} L{392 + (y - 690) * 0.25:.0f} {y} L{400 + (y - 690) * 0.25 + 10:.0f} {y + 44} L-20 {y + 44} Z",
                  f"M1020 {y} L{608 - (y - 690) * 0.25:.0f} {y} L{600 - (y - 690) * 0.25 - 10:.0f} {y + 44} L1020 {y + 44} Z"):
            body += f'<path d="{d}" fill="{REFLECT}" stroke="#000" stroke-width="10" stroke-linejoin="round"/>'
    # a pocket with a pencil and a little MiSTer badge on the other side
    body += f'<path d="M200 950 L320 950 L320 1010 L200 1010 Z" fill="{VEST_D}" stroke="#000" stroke-width="9"/>'
    body += f'<path d="M286 958 L304 880" stroke="#000" stroke-width="24" stroke-linecap="round"/>'
    body += f'<path d="M286 958 L304 880" stroke="{CORN}" stroke-width="12" stroke-linecap="round"/>'
    out = f'<g clip-path="url(#body)">{body}</g>'
    out += (f'<g transform="translate(760 738) rotate(8)"><rect x="-58" y="-24" width="116" height="48" rx="8" fill="{PAPER}" {S10}/>'
            f'<text x="0" y="12" {MONO} font-size="28" text-anchor="middle" fill="#000">root</text></g>')
    out += f'<path d="{FILL_D}" fill="none" stroke="#000" stroke-width="3"/>'
    return out


def pencil_ear():
    """A carpenter's pencil tucked behind the right ear."""
    return (f'<g transform="translate(770 210) rotate(-56)">'
            f'<rect x="-110" y="-16" width="200" height="32" fill="{CORN}" {S10}/>'
            f'<path d="M90 -16 L136 0 L90 16 Z" fill="#f0d2a8" {S10}/>'
            f'<path d="M122 -5 L136 0 L122 5 Z" fill="#000"/>'
            f'<rect x="-110" y="-16" width="26" height="32" fill="{PINK}" {S10}/></g>')


def kun():
    face = "".join(FACE)
    return f'<g id="kun">{OUTLINE}{FILL}{vest()}{face}{pencil_ear()}{hardhat()}</g>'


# --- props (centred on 0,0, about +-150) ------------------------------------------------------------

PROP = {}

PROP["crane"] = f'''<g>
   <path d="M-100 160 L-100 -150 M-60 160 L-60 -150" stroke="#000" stroke-width="22" stroke-linecap="round"/>
   <path d="M-100 160 L-100 -150 M-60 160 L-60 -150" stroke="{ACCENT}" stroke-width="10" stroke-linecap="round"/>
   {"".join(f'<path d="M-100 {y} L-60 {y - 40}" stroke="#000" stroke-width="8"/>' for y in (150, 100, 50, 0, -50, -100))}
   <path d="M-150 -150 L160 -150" stroke="#000" stroke-width="30" stroke-linecap="round"/>
   <path d="M-150 -150 L160 -150" stroke="{ACCENT}" stroke-width="16" stroke-linecap="round"/>
   <rect x="-170" y="-170" width="50" height="60" fill="{STEEL_D}" {S10}/>
   <path d="M110 -150 L110 -36" stroke="#000" stroke-width="6"/>
   <path d="M96 -40 L124 -40 L110 -24 Z" fill="{STEEL}" stroke="#000" stroke-width="6"/>
   <rect x="20" y="-24" width="180" height="96" rx="8" fill="{BLUE}" {S}/>
   <text x="110" y="38" {MONO} font-size="28" text-anchor="middle" fill="#fff">rootfs</text>
 </g>'''

PROP["blueprint"] = f'''<g transform="rotate(-8)">
   <rect x="-160" y="-120" width="320" height="230" fill="{BLUE}" {S}/>
   <path d="M-160 -60 L160 -60 M-160 0 L160 0 M-160 60 L160 60 M-100 -120 L-100 110 M0 -120 L0 110 M100 -120 L100 110" stroke="{BLUE_L}" stroke-width="2" opacity="0.5"/>
   <text x="-136" y="-74" {MONO} font-size="26" fill="#fff">defconfig</text>
   <text x="-136" y="-30" {MONO} font-size="22" fill="{BLUE_L}">BR2_arm=y</text>
   <text x="-136" y="2" {MONO} font-size="22" fill="{BLUE_L}">BR2_LINUX_</text>
   <text x="-136" y="30" {MONO} font-size="22" fill="{BLUE_L}"> KERNEL=y</text>
   <rect x="40" y="40" width="96" height="50" fill="none" stroke="#fff" stroke-width="5"/>
   <path d="M40 40 L136 90 M136 40 L40 90" stroke="#fff" stroke-width="3"/>
   <circle cx="-160" cy="110" r="34" fill="{BLUE_D}" {S10}/>
   <circle cx="-160" cy="110" r="14" fill="{BLUE}" stroke="#000" stroke-width="6"/>
 </g>'''

PROP["kernel"] = f'''<g transform="rotate(10)">
   <path d="M0 -150 C90 -150 130 -60 120 20 C110 100 50 150 0 150 C-50 150 -110 100 -120 20 C-130 -60 -90 -150 0 -150 Z" fill="{CORN}" {S}/>
   <path d="M-40 -110 C-60 -60 -70 0 -60 60" fill="none" stroke="#fff" stroke-width="16" stroke-linecap="round" opacity="0.8"/>
   <path d="M-120 90 C-60 60 60 60 120 90 C110 120 60 150 0 150 C-50 150 -100 124 -120 90 Z" fill="{CORN_D}" {S10}/>
   <text x="8" y="30" {FONT} font-size="64" text-anchor="middle" fill="#000">LTS</text>
 </g>'''

PROP["tarball"] = f'''<g transform="rotate(-6)">
   <path d="M-150 -60 L0 -120 L150 -60 L0 0 Z" fill="#e2bd8a" {S}/>
   <path d="M-150 -60 L0 0 L0 160 L-150 100 Z" fill="#c99a5e" {S}/>
   <path d="M150 -60 L0 0 L0 160 L150 100 Z" fill="#b5844a" {S}/>
   <path d="M-75 -90 L75 -30 L75 40" fill="none" stroke="#a46d36" stroke-width="22"/>
   <text x="-76" y="76" {MONO} font-size="34" text-anchor="middle" fill="#000" transform="skewY(22) translate(0 30)">.tar</text>
   <g transform="translate(96 70) rotate(-14)">
     <rect x="-74" y="-40" width="148" height="80" rx="10" fill="{GREEN}" {S10}/>
     <text x="0" y="-4" {MONO} font-size="24" text-anchor="middle" fill="#000">sha256</text>
     <path d="M-22 14 L-6 28 L24 2" fill="none" stroke="#000" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>
   </g>
 </g>'''

PROP["stopwatch"] = f'''<g>
   <rect x="-26" y="-170" width="52" height="34" rx="8" fill="{ACCENT}" {S10}/>
   <path d="M-6 -136 L-6 -120 M6 -136 L6 -120" stroke="#000" stroke-width="10"/>
   <path d="M96 -98 L122 -124" stroke="#000" stroke-width="22" stroke-linecap="round"/>
   <circle r="130" fill="#fff" {S}/>
   <circle r="110" fill="none" stroke="{RED}" stroke-width="10"/>
   {"".join(f'<path d="M0 -100 L0 -80" stroke="#000" stroke-width="10" stroke-linecap="round" transform="rotate({a})"/>' for a in range(0, 360, 45))}
   <path d="M0 0 L0 -86" stroke="{RED}" stroke-width="12" stroke-linecap="round" transform="rotate(40)"/>
   <circle r="12" fill="#000"/>
   <text x="0" y="62" {MONO} font-size="38" text-anchor="middle" fill="#000">RT</text>
 </g>'''

PROP["sdcard"] = f'''<g transform="rotate(12)">
   <path d="M-110 -150 L60 -150 L110 -100 L110 150 L-110 150 Z" fill="{CARD}" {S}/>
   {"".join(f'<rect x="{x}" y="-136" width="20" height="54" rx="4" fill="{CORN}" stroke="#000" stroke-width="6"/>' for x in (-90, -60, -30, 0, 30))}
   <rect x="-86" y="-50" width="172" height="150" rx="8" fill="{PAPER}" {S10}/>
   <text x="0" y="0" {FONT} font-size="40" text-anchor="middle" fill="#000">MiSTer</text>
   <text x="0" y="62" {FONT} font-size="46" text-anchor="middle" fill="{VEST_D}">FRESH</text>
 </g>'''

PROP["patches"] = f'''<g>
   <rect x="-120" y="-160" width="240" height="300" fill="{PAPER}" {S} transform="rotate(10) translate(30 10)"/>
   <rect x="-120" y="-160" width="240" height="300" fill="{PAPER}" {S} transform="rotate(4) translate(14 4)"/>
   <g transform="rotate(-4)">
     <rect x="-120" y="-160" width="240" height="300" fill="{PAPER}" {S}/>
     <text x="-96" y="-116" {MONO} font-size="24" fill="#000">0001.patch</text>
     {"".join(f'<rect x="-96" y="{y}" width="{w}" height="18" fill="{c}"/>' for y, w, c in ((-90, 170, "#f2b8b5"), (-62, 130, "#f2b8b5"), (-34, 186, "#b9e3b0"), (-6, 150, "#b9e3b0"), (22, 176, "#b9e3b0")))}
     <text x="-104" y="-74" {MONO} font-size="22" fill="{RED}">-</text>
     <text x="-104" y="-46" {MONO} font-size="22" fill="{RED}">-</text>
     <text x="-104" y="-18" {MONO} font-size="22" fill="#2a7a1e">+</text>
     <text x="-104" y="10" {MONO} font-size="22" fill="#2a7a1e">+</text>
     <text x="-104" y="38" {MONO} font-size="22" fill="#2a7a1e">+</text>
     <path d="M-90 80 L90 80 M-90 108 L40 108" stroke="{GREY}" stroke-width="10" stroke-linecap="round"/>
   </g>
 </g>'''

PROP["wrench"] = f'''<g transform="rotate(-40)">
   <path d="M-26 -60 L26 -60 L26 150 C26 172 -26 172 -26 150 Z" fill="{STEEL}" {S}/>
   <path d="M-10 -40 L-10 140" stroke="{STEEL_L}" stroke-width="8" stroke-linecap="round"/>
   <path d="M-74 -150 L-74 -84 C-74 -40 -40 -24 0 -24 C40 -24 74 -40 74 -84 L74 -150 L30 -150 L30 -96 L-30 -96 L-30 -150 Z" fill="{STEEL}" {S}/>
 </g>'''

PROP["terminal"] = f'''<g transform="rotate(-5)">
   <rect x="-170" y="-130" width="340" height="250" rx="16" fill="{STEEL}" {S}/>
   <rect x="-148" y="-96" width="296" height="196" rx="8" fill="{TERM}" {S10}/>
   <circle cx="-140" cy="-114" r="7" fill="{RED}"/><circle cx="-116" cy="-114" r="7" fill="{ACCENT}"/><circle cx="-92" cy="-114" r="7" fill="{GREEN}"/>
   <text x="-130" y="-52" {MONO} font-size="30" fill="{ACCENT}"># make</text>
   <text x="-130" y="-12" {MONO} font-size="22" fill="{GREY}">&gt;&gt;&gt; linux</text>
   <text x="-130" y="18" {MONO} font-size="22" fill="{GREY}">&gt;&gt;&gt; busybox</text>
   <text x="-130" y="60" {MONO} font-size="28" fill="{GREEN}">BUILD OK</text>
   <rect x="20" y="40" width="18" height="26" fill="{GREEN}"/>
 </g>'''

ICON_ONLY = {
    "hardhat": f'<g transform="translate(-500 -110)">{hardhat(0)}</g>',
    "cone": f'''<g>
       <path d="M-30 -150 L30 -150 L110 120 L-110 120 Z" fill="{VEST}" {S}/>
       <path d="M-48 -80 L48 -80 L66 -20 L-66 -20 Z M-84 30 L84 30 L100 84 L-100 84 Z" fill="{REFLECT}" stroke="#000" stroke-width="10" stroke-linejoin="round"/>
       <rect x="-160" y="110" width="320" height="44" rx="10" fill="{VEST_D}" {S}/></g>''',
    "brick": f'''<g>{"".join(f'<rect x="{x}" y="{y}" width="150" height="70" rx="6" fill="#c8553d" {S10}/>' for x, y in ((-160, 40), (-4, 40), (-82, -36), (-160, -112), (-4, -112)))}</g>''',
}


def with_prop(name, x=880, y=830, s=1.25):
    return DEFS + kun() + f'<g transform="translate({x} {y}) scale({s})">{PROP[name]}</g>'


def built():
    """The build went green: a terminal reading BUILD OK."""
    return with_prop("terminal", 900, 830, 1.2)


# --- output helpers (same as the Tasty, Seedy and ItsAlive pipeline) --------------------------------

def svg(w, h, body, vb=None, bg=None):
    vb = vb or f"0 0 {w} {h}"
    b = f'<rect x="-10000" y="-10000" width="20000" height="20000" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{vb}">{b}{body}</svg>'


def write(name, text, d=ART):
    p = os.path.join(d, name + ".svg")
    open(p, "w").write(text)
    return p


def png(svgp, w, pngname=None, d=ART):
    pn = os.path.join(d, (pngname or os.path.basename(svgp)[:-4]) + ".png")
    subprocess.run(["inkscape", svgp, "--export-type=png", f"--export-filename={pn}", f"--export-width={w}"],
                   check=True, capture_output=True)
    return pn


def nested(inner, x, y, size, vb="0 0 1000 1000"):
    return f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="{vb}">{inner}</svg>'


def wordmark(x, y, scale=1.0, jp=True, dark=False):
    ink = "#f0efef" if dark else "#000"
    t = f'<g transform="translate({x} {y}) scale({scale})">'
    t += f'<text x="0" y="0" {FONT} font-size="120" fill="{ink}" letter-spacing="-2">MiSTer</text>'
    t += (f'<text x="0" y="150" {FONT} font-size="150" fill="{ACCENT}" stroke="{ink}" stroke-width="10" '
          f'paint-order="stroke" letter-spacing="2">BUILDROOT</text>')
    if jp:
        t += f'<text x="8" y="235" {JP} font-size="62" fill="{ink}">ミスター・ビルドルート</text>'
    return t + '</g>'


def hazard(x, y, w, h):
    """A yellow-and-black hazard stripe."""
    out = f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><rect width="{w}" height="{h}" fill="{ACCENT}"/>'
    out += "".join(f'<path d="M{i} {h} L{i + h} 0 L{i + h + 24} 0 L{i + 24} {h} Z" fill="#000"/>' for i in range(-h, w + h, 48))
    return out + '</svg>'


def props_row(x, y, size, gap, names):
    out = ""
    for i, n in enumerate(names):
        out += f'<g transform="translate({x + i * (size + gap) + size / 2} {y + size / 2}) scale({size / 340})">{PROP[n]}</g>'
    return out


TAGLINE = "The whole MiSTer OS, from source."
VARIANTS = ["crane", "blueprint", "kernel", "tarball", "stopwatch", "sdcard", "patches", "wrench"]
VB = "-130 -20 1260 1120"   # room for the prop
SITE = "#1b1f27"


def main():
    os.makedirs(ICONS, exist_ok=True)
    made = []
    p = write("root-kun", svg(1000, 1000, DEFS + kun(), vb="-130 -70 1260 1260")); made.append(png(p, 512))
    p = write("root-kun-built", svg(1080, 1080, built(), vb=VB)); made.append(png(p, 512))
    for v in VARIANTS:
        p = write(f"root-kun-{v}", svg(1080, 1080, with_prop(v), vb=VB)); made.append(png(p, 512))

    # social preview 1280x640
    body = nested(built(), 30, 40, 540, vb=VB)
    body += wordmark(600, 210, 0.7)
    body += f'<text x="606" y="490" {FONT} font-size="34" fill="#000">{TAGLINE}</text>'
    body += hazard(0, 600, 1280, 40)
    p = write("social-preview", svg(1280, 640, body, bg="#ffffff")); made.append(png(p, 1280))

    # README banner 1280x420, dark
    body = nested(DEFS + kun(), 30, 30, 360, vb="-130 -70 1260 1260")
    body += wordmark(420, 150, 0.6, jp=False, dark=True)
    body += f'<text x="426" y="316" {JP} font-size="36" fill="#f0efef">ミスター・ビルドルート</text>'
    body += props_row(930, 90, 56, 12, ["crane", "blueprint", "kernel", "patches", "stopwatch"])
    body += f'<text x="932" y="236" {FONT} font-size="30" fill="#f0efef">Kernel, rootfs and</text>'
    body += f'<text x="932" y="278" {FONT} font-size="30" fill="#f0efef">SD card, built</text>'
    body += f'<text x="932" y="320" {FONT} font-size="30" fill="{ACCENT}">from source.</text>'
    body += hazard(0, 396, 1280, 24)
    p = write("banner", svg(1280, 420, body, bg=SITE)); made.append(png(p, 1280))

    # heading icons
    tmp = os.path.join(HERE, "out-scratch")
    os.makedirs(tmp, exist_ok=True)
    icons = dict(PROP)
    icons.update(ICON_ONLY)
    for name, g in icons.items():
        sc = {"hardhat": 0.95, "brick": 1.2}.get(name, 1.3)
        body = DEFS + f'<g transform="translate(250 270) scale({sc})">{g}</g>'
        p = write(f"icon-{name}", svg(500, 540, body), d=tmp)
        made.append(png(p, 48, f"{name}-48", d=ICONS))
    print("\n".join(made))


# --- 8-bit Root Kun: the upstream 32x32 pixel Kun, repainted by hand -------------------------------

KUN8 = """\
.........K............K.........
........KWK..........KWK........
.......KWKWK........KWKWK.......
......KWKGKWK......KWKGKWK......
.....KWKKKKKWKKKKKKWKKKKKWK.....
....KWWWWWWWWWWWWWWWWWWWWWWK....
....KWWWWWWWWWWWWWWWWWWWWWWK....
...KWWWWWWWWWWWWWWWWWWWWWWWWK...
...KWWWWWWWWWWWWWWWWWWWWWWWWK...
...KWWWWWWWWWWWWWWWWWWWWWWWWK...
...KWWWWWWWWWWWWWWWWWWWWWWWWK...
...KWWWWWWWWWKWWWWKWWWWWWWWWK...
...KWKKKKKKKKKKKKKKKKKKKKKKWK...
...KWKWWWKKKKWKPPKWKKKKWWWKWK...
..KKWKWWWWKKWWKPPKWWKKWWWWKWKK..
.KWWWKWWWWWWWWKKKKWWWWWWWWKWWWK.
.KWWWWKWWWWWWKKRRKKWWWWWWKWWWWK.
KWWWWWWKKKKKKPPKKPPKKKKKKWWWWWWK
KWWWWWWWWWWKPPPPPPPPKWWWWWWWWWWK
KWWWWWWWWWWWKPPKKPPKWWWWWWWWWWWK
.KWWWWWWWWWKWKKPPKKWKWWWWWWWWWK.
.KWWWWWWWWWKWWWKKWWWKWWWWWWWWWK.
..KKWWWWWWWWWWWWWWWWWWWWWWWWKK..
...KWWWWWWWWWWWWWWWWWWWWWWWWK...
...KWWWWWWWWWWWWWWWWWWWWWWWWK...
...KWWWWWWWWWWWWWWWWWWWWWWWWK...
..KWWWWWWWWWWWKKKKWWWWWWWWWWWK..
.KWWWWWWWWWWWK....KWWWWWWWWWWWK.
.KWWWWWWWWWWK......KWWWWWWWWWWK.
..KWWWWWWWWWK......KWWWWWWWWWK..
...KKKKKKKKK........KKKKKKKKK...
"""
PAL8 = {"K": "#010101", "W": WHITE, "G": "#e98db8", "P": "#b4b4b4", "R": "#e177af",
        "Y": ACCENT, "y": ACCENT_D, "O": VEST, "o": VEST_D, "S": "#b8c4cc"}


def kun8():
    g = [list(r) for r in KUN8.splitlines()]
    g.insert(0, list("." * 32))   # the file starts one row down, like the upstream grid
    def put(x, y, c):
        g[y][x] = c
    # hard hat: dome between the ears on rows 1..4, brim across the top of the head on row 5
    for y, (a, b) in zip(range(1, 5), [(14, 17), (13, 18), (13, 18), (13, 18)]):
        put(a - 1, y, "K"); put(b + 1, y, "K")
        for x in range(a, b + 1):
            put(x, y, "Y")
    for x in range(13, 19):
        put(x, 0, "K")
    put(15, 2, "y"); put(16, 2, "y")
    put(7, 5, "K"); put(24, 5, "K")
    for x in range(8, 24):
        put(x, 5, "y")
    for x in range(8, 24):
        put(x, 6, "K")
    # hi-vis vest over rows 23..30, open down the middle, one reflective band
    for y in range(23, 31):
        for x in range(32):
            if g[y][x] == "W" and not (13 <= x <= 18):
                put(x, y, "S" if y == 26 else ("o" if x < 6 or x > 25 else "O"))
    rects = "".join(f'<rect x="{x}" y="{y}" width="1" height="1" fill="{PAL8[c]}"/>'
                    for y, row in enumerate(g) for x, c in enumerate(row) if c != ".")
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32" shape-rendering="crispEdges">{rects}</svg>'


def main8():
    p = write("root-kun-8bit-32x32", kun8())
    png(p, 32)
    print(png(p, 512, "root-kun-8bit"))


if __name__ == "__main__":
    main()
    main8()
