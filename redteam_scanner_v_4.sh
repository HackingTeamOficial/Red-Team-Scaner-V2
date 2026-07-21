#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# RedTeam Scanner v4 - Automate · Exploit · IA Report · 2026
# Uso autorizado únicamente en targets con permiso explícito
# ─────────────────────────────────────────────────────────────
set -o errexit
set -o pipefail
set -o nounset

# ═════════════════════════════════════════════════════════════
# CONFIG
# ═════════════════════════════════════════════════════════════
VERSION="7.0"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
OUT_BASE="${OUT_BASE:-outputs}"
THREADS="${THREADS:-40}"
WORDLIST_DIRS="${WORDLIST_DIRS:-/usr/share/wordlists/dirb/common.txt}"
WORDLIST_DIRB="${WORDLIST_DIRB:-/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt}"
NUCLEI_SEVERITY="${NUCLEI_SEVERITY:-critical,high,medium}"
GHAURI_URL_LIMIT="${GHAURI_URL_LIMIT:-15}"

OLLAMA_BIN="${OLLAMA_BIN:-$(command -v ollama 2>/dev/null || true)}"
GPT4ALL_BIN="${GPT4ALL_BIN:-$(command -v gpt4all 2>/dev/null || true)}"
LLAMACPP_BIN="${LLAMACPP_BIN:-$(command -v llama-cli 2>/dev/null || true)}"
OLLAMA_MODEL="${OLLAMA_MODEL:-}"

# Herramientas core (apt/go)
TOOLS_CORE=(
  subfinder assetfinder amass dnsx naabu nmap httpx
  gau waybackurls katana gospider dalfox nuclei ffuf
  ghauri whatweb wafw00f nikto curl jq dig whois
)

# ═════════════════════════════════════════════════════════════
# COLORES
# ═════════════════════════════════════════════════════════════
reset='\e[0m'
bold='\e[1m'
dim='\e[2m'
red='\e[91m'
green='\e[92m'
yellow='\e[93m'
blue='\e[94m'
magenta='\e[95m'
cyan='\e[96m'
white='\e[97m'
orange='\e[38;5;208m'
pink='\e[38;5;198m'
lime='\e[38;5;118m'
purple='\e[38;5;141m'

COLORS=("$red" "$green" "$yellow" "$blue" "$magenta" "$cyan" "$orange" "$pink" "$lime" "$purple")
BANNER_COLOR="${COLORS[$((RANDOM % ${#COLORS[@]}))]}"
ACCENT="${COLORS[$((RANDOM % ${#COLORS[@]}))]}"

# ═════════════════════════════════════════════════════════════
# UTILS
# ═════════════════════════════════════════════════════════════
cprint(){ echo -e "${1}${2}${reset}"; }
hr(){ echo -e "${dim}──────────────────────────────────────────────────────────────${reset}"; }

log(){
  local level="${1:-INFO}"
  shift
  local msg="$*"
  local ts color
  ts="$(date +%H:%M:%S)"
  case "$level" in
    OK)   color="$green"  ;;
    WARN) color="$yellow" ;;
    ERR)  color="$red"    ;;
    RUN)  color="$cyan"   ;;
    AI)   color="$magenta";;
    *)    color="$blue"   ;;
  esac
  echo -e "${dim}[$ts]${reset} ${color}${bold}[$level]${reset} $msg" | tee -a "$aggregate"
}

die(){ log ERR "$*"; exit 1; }

spinner(){
  local pid=$1 msg="${2:-Procesando...}"
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r ${ACCENT}%s${reset} %s" "${spin:i++%${#spin}:1}" "$msg"
    sleep 0.08
  done
  printf "\r\033[K"
}

have(){ command -v "$1" >/dev/null 2>&1; }

_timeout_cmd(){
  if timeout --help 2>&1 | grep -q -- '--foreground'; then
    timeout --foreground "$@"
  else
    timeout "$@"
  fi
}

require_root_apt(){
  if [[ $EUID -ne 0 ]] && ! have sudo; then
    log WARN "Sin root/sudo: no se puede usar apt automáticamente"
    return 1
  fi
  return 0
}

apt_install(){
  local pkgs=("$@")
  require_root_apt || return 1
  if [[ $EUID -eq 0 ]]; then
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}"
  else
    sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}"
  fi
}

go_install(){
  local pkg="$1"
  if ! have go; then
    log WARN "Go no instalado; omitiendo $pkg"
    return 1
  fi
  # GOBIN preferente
  export GOPATH="${GOPATH:-$HOME/go}"
  export GOBIN="${GOBIN:-$GOPATH/bin}"
  mkdir -p "$GOBIN"
  export PATH="$PATH:$GOBIN:$(go env GOPATH 2>/dev/null)/bin"
  go install -v "$pkg@latest" >/dev/null 2>&1
}

# ═════════════════════════════════════════════════════════════
# BANNER (color aleatorio cada ejecución)
# ═════════════════════════════════════════════════════════════
banner(){
  clear 2>/dev/null || true
  local c="$BANNER_COLOR"
  echo -e "${c}${bold}"
  cat << 'EOF'
    ██████╗ ███████╗██████╗ ████████╗███████╗ █████╗ ███╗   ███╗
    ██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
    ██████╔╝█████╗  ██║  ██║   ██║   █████╗  ███████║██╔████╔██║
    ██╔══██╗██╔══╝  ██║  ██║   ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║
    ██║  ██║███████╗██████╔╝   ██║   ███████╗██║  ██║██║ ╚═╝ ██║
    ╚═╝  ╚═╝╚══════╝╚═════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
EOF
  echo -e "${reset}"
  echo -e "  ${ACCENT}${bold}» RedTeam Scanner v${VERSION}${reset}  ${dim}· Automate · Exploit · IA · Report${reset}"
  echo -e "  ${dim}Telegram:${reset} ${cyan}https://t.me/+0hHSaKO7eI9mNWY8${reset}"
  echo -e "  ${dim}Team:${reset} ${white}@makina50 @HombreM @P4b10hdr @Vixt0r24 @kdeahack @HackingTeamProHackers${reset}"
  hr
  if [[ -n "${domain:-}" ]]; then
    echo -e "  ${bold}Objetivo:${reset}  ${green}${domain}${reset}"
    echo -e "  ${bold}Salida:${reset}    ${cyan}${outdir}${reset}"
    echo -e "  ${bold}Timeout:${reset}   ${yellow}${TIMEOUT_SECONDS}s${reset}   ${bold}Threads:${reset} ${yellow}${THREADS}${reset}"
    hr
  fi
}

# ═════════════════════════════════════════════════════════════
# AUTOINSTALADOR
# ═════════════════════════════════════════════════════════════
install_deps_base(){
  log RUN "Instalando dependencias base del sistema..."
  apt_install curl wget git jq dig whois nmap nikto whatweb python3 python3-pip golang-go chromium 2>/dev/null \
    || apt_install curl wget git jq dnsutils whois nmap nikto whatweb python3 python3-pip golang-go 2>/dev/null \
    || log WARN "Algunas deps base fallaron (continúa)"
  # PATH go
  export GOPATH="${GOPATH:-$HOME/go}"
  export PATH="$PATH:$GOPATH/bin:$(go env GOPATH 2>/dev/null)/bin:${HOME}/.local/bin"
}

install_go_tools(){
  log RUN "Instalando herramientas Go (puede tardar)..."
  local -A pkgs=(
    [subfinder]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    [dnsx]="github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    [naabu]="github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    [httpx]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
    [nuclei]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    [katana]="github.com/projectdiscovery/katana/cmd/katana@latest"
    [notify]="github.com/projectdiscovery/notify/cmd/notify@latest"
    [assetfinder]="github.com/tomnomnom/assetfinder@latest"
    [waybackurls]="github.com/tomnomnom/waybackurls@latest"
    [gau]="github.com/lc/gau/v2/cmd/gau@latest"
    [ffuf]="github.com/ffuf/ffuf/v2@latest"
    [dalfox]="github.com/hahwul/dalfox/v2@latest"
    [gospider]="github.com/jaeles-project/gospider@latest"
    [amass]="github.com/owasp-amass/amass/v4/...@master"
    [anew]="github.com/tomnomnom/anew@latest"
    [qsreplace]="github.com/tomnomnom/qsreplace@latest"
    [unfurl]="github.com/tomnomnom/unfurl@latest"
    [gf]="github.com/tomnomnom/gf@latest"
  )
  for bin in "${!pkgs[@]}"; do
    if have "$bin"; then
      log OK "$bin ya instalado"
    else
      log RUN "go install → $bin"
      if go install -v "${pkgs[$bin]}" >/dev/null 2>&1; then
        log OK "$bin instalado"
      else
        log WARN "No se pudo instalar $bin"
      fi
    fi
  done
}

install_pip_tools(){
  log RUN "Instalando herramientas Python..."
  python3 -m pip install --user -U pip setuptools wheel >/dev/null 2>&1 || true
  # ghauri
  if ! have ghauri; then
    python3 -m pip install --user -U ghauri >/dev/null 2>&1 \
      || pip3 install --user ghauri >/dev/null 2>&1 \
      || log WARN "ghauri no instalado (pip)"
  else
    log OK "ghauri ya instalado"
  fi
  # arjun / uro (útiles extra)
  python3 -m pip install --user -U arjun uro >/dev/null 2>&1 || true
}

install_wordlists(){
  if [[ ! -f "$WORDLIST_DIRS" ]]; then
    log RUN "Buscando wordlists alternativas..."
    for wl in \
      /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt \
      /usr/share/seclists/Discovery/Web-Content/common.txt \
      /usr/share/wordlists/dirb/big.txt
    do
      [[ -f "$wl" ]] && WORDLIST_DIRS="$wl" && break
    done
  fi
  if [[ ! -f "$WORDLIST_DIRS" ]]; then
    mkdir -p "$HOME/.wordlists"
    WORDLIST_DIRS="$HOME/.wordlists/common.txt"
    if [[ ! -f "$WORDLIST_DIRS" ]]; then
      cat > "$WORDLIST_DIRS" << 'WL'
admin
login
api
assets
backup
config
dashboard
debug
dev
docs
download
files
images
includes
js
media
old
panel
private
robots.txt
sitemap.xml
tmp
upload
uploads
wp-admin
wp-content
wp-login.php
.xml
.json
.env
.git
.svn
server-status
WL
      log WARN "Wordlist mínima creada en $WORDLIST_DIRS"
    fi
  fi
  log OK "Wordlist: $WORDLIST_DIRS"
}

install_nuclei_templates(){
  if have nuclei; then
    log RUN "Actualizando templates de nuclei..."
    nuclei -update-templates -silent >/dev/null 2>&1 || true
    log OK "Templates nuclei listos"
  fi
}

auto_install_all(){
  banner
  cprint "$yellow$bold" "  ⚙  MODO AUTOINSTALADOR"
  hr
  install_deps_base
  install_go_tools
  install_pip_tools
  install_wordlists
  install_nuclei_templates
  # Asegurar PATH en sesión actual
  export PATH="$PATH:${HOME}/go/bin:$(go env GOPATH 2>/dev/null)/bin:${HOME}/.local/bin"
  log OK "Autoinstalación finalizada"
  echo
  check_tools_pretty
  echo
  read -rp " Pulsa ENTER para continuar al menú..." _
}

check_tools_pretty(){
  cprint "$cyan$bold" "  Estado de herramientas"
  hr
  local ok=0 miss=0
  local check_list=(
    subfinder assetfinder amass dnsx naabu nmap httpx gau waybackurls
    katana gospider dalfox nuclei ffuf ghauri whatweb wafw00f nikto
    jq curl msfconsole ollama
  )
  for t in "${check_list[@]}"; do
    if have "$t"; then
      printf "  ${green}✔${reset} %-14s ${dim}ok${reset}\n" "$t"
      ((ok++)) || true
    else
      printf "  ${red}✖${reset} %-14s ${yellow}faltante${reset}\n" "$t"
      ((miss++)) || true
    fi
  done
  hr
  echo -e "  ${green}OK:${reset} $ok   ${red}Faltan:${reset} $miss"
}

# ═════════════════════════════════════════════════════════════
# SETUP TARGET
# ═════════════════════════════════════════════════════════════
normalize_target(){
  local t="$1"
  t="$(echo "$t" | sed -E 's#https?://##; s#/.*##; s#:\*##; s#"##g; s# ##g')"
  echo "$t" | tr '[:upper:]' '[:lower:]'
}

setup_paths(){
  domain="$(normalize_target "$target")"
  [[ -z "$domain" ]] && die "Debes indicar un dominio/IP. Uso: $0 <target>"
  # Validación simple
  if ! [[ "$domain" =~ ^[a-zA-Z0-9._-]+$ || "$domain" =~ ^[0-9.]+$ ]]; then
    die "Target inválido: $domain"
  fi
  outdir="${OUT_BASE}/${domain//\//_}"
  aggregate="${outdir}/${domain}_aggregate.log"
  json_out="${outdir}/${domain}_summary.json"
  html_out="${outdir}/${domain}_report.html"
  mkdir -p "$outdir"/{recon,web,vuln,exploit,ai,raw}
  : > "$aggregate"
}

# ═════════════════════════════════════════════════════════════
# RUNNER GENÉRICO
# ═════════════════════════════════════════════════════════════
run_tool(){
  local name="$1"
  local bin="$2"
  local cmd="$3"
  local outfile="$4"

  if ! have "$bin"; then
    log WARN "$name omitido ($bin no está en PATH)"
    return 0
  fi

  log RUN "$name..."
  if _timeout_cmd "$TIMEOUT_SECONDS" bash -c "$cmd" >"$outfile" 2>>"$aggregate"; then
    local lines
    lines=$(wc -l < "$outfile" 2>/dev/null | tr -d ' ' || echo 0)
    log OK "$name → $outfile (${lines} líneas)"
  else
    log WARN "$name falló o timeout (${TIMEOUT_SECONDS}s)"
    touch "$outfile"
  fi
}

# ═════════════════════════════════════════════════════════════
# MÓDULOS
# ═════════════════════════════════════════════════════════════
mod_recon(){
  log INFO "═══ RECON PASIVO / ACTIVO ═══"
  local r="$outdir/recon"

  run_tool "WHOIS" "whois" "whois $domain" "$r/whois.txt"
  run_tool "DIG" "dig" "dig ANY $domain +noall +answer; dig NS $domain +short; dig MX $domain +short; dig TXT $domain +short" "$r/dns.txt"
  run_tool "subfinder" "subfinder" "subfinder -d $domain -silent -all" "$r/subfinder.txt"
  run_tool "assetfinder" "assetfinder" "assetfinder --subs-only $domain" "$r/assetfinder.txt"
  run_tool "amass" "amass" "amass enum -passive -d $domain -silent" "$r/amass.txt"

  # Unificar subdominios
  cat "$r"/subfinder.txt "$r"/assetfinder.txt "$r"/amass.txt 2>/dev/null \
    | sed '/^$/d' | sort -u > "$r/subs_all.txt"
  log OK "Subdominios únicos: $(wc -l < "$r/subs_all.txt" | tr -d ' ')"

  if have dnsx && [[ -s "$r/subs_all.txt" ]]; then
    run_tool "dnsx-resolve" "dnsx" "dnsx -l $r/subs_all.txt -silent -a -aaaa -cname -resp -o $r/dnsx_resolved.txt" "$r/dnsx_resolved.txt"
  else
    run_tool "dnsx" "dnsx" "echo $domain | dnsx -silent -a -aaaa -cname -resp" "$r/dnsx.txt"
  fi

  # Hosts vivos + puertos
  if [[ -s "$r/subs_all.txt" ]]; then
    run_tool "httpx-alive" "httpx" "httpx -l $r/subs_all.txt -silent -status-code -title -tech-detect -follow-redirects -threads $THREADS" "$r/httpx_alive.txt"
    run_tool "naabu-live" "naabu" "naabu -list $r/subs_all.txt -rate 200 -silent -top-ports 1000" "$r/naabu.txt"
  else
    run_tool "httpx" "httpx" "echo https://$domain | httpx -silent -status-code -title -tech-detect -content-length" "$r/httpx.txt"
    run_tool "naabu" "naabu" "naabu -host $domain -rate 200 -silent -top-ports 1000" "$r/naabu.txt"
  fi

  run_tool "nmap" "nmap" "nmap -Pn -sS --open -sV --top-ports 1000 -oA $r/nmap $domain" "$r/nmap.nmap"
  run_tool "whatweb" "whatweb" "whatweb -a 3 https://$domain" "$r/whatweb.txt"
  run_tool "wafw00f" "wafw00f" "wafw00f https://$domain" "$r/wafw00f.txt"
}

mod_urls(){
  log INFO "═══ URL MINING ═══"
  local w="$outdir/web"
  run_tool "gau" "gau" "gau --subs $domain" "$w/gau.txt"
  run_tool "waybackurls" "waybackurls" "echo $domain | waybackurls" "$w/waybackurls.txt"
  run_tool "katana" "katana" "katana -u https://$domain -d 3 -silent -jc" "$w/katana.txt"
  run_tool "gospider" "gospider" "gospider -s https://$domain -d 2 -c 10 --other-source --sitemap -q" "$w/gospider.txt"

  cat "$w"/gau.txt "$w"/waybackurls.txt "$w"/katana.txt "$w"/gospider.txt 2>/dev/null \
    | grep -Eoi 'https?://[^ ]+' | sed 's/[),;]$//' | sort -u > "$w/urls_all.txt"
  log OK "URLs únicas: $(wc -l < "$w/urls_all.txt" | tr -d ' ')"

  # Parámetros interesantes
  if have gf; then
    gf xss < "$w/urls_all.txt" 2>/dev/null | sort -u > "$w/gf_xss.txt" || true
    gf sqli < "$w/urls_all.txt" 2>/dev/null | sort -u > "$w/gf_sqli.txt" || true
    gf ssrf < "$w/urls_all.txt" 2>/dev/null | sort -u > "$w/gf_ssrf.txt" || true
    gf redirect < "$w/urls_all.txt" 2>/dev/null | sort -u > "$w/gf_redirect.txt" || true
  else
    grep -E '[?&](id|page|url|q|search|redirect|next|file|path|data)=' "$w/urls_all.txt" \
      | sort -u > "$w/params_urls.txt" || true
  fi

  # JS endpoints
  grep -E '\.js($|\?)' "$w/urls_all.txt" | sort -u > "$w/js_urls.txt" || true
  if [[ -s "$w/js_urls.txt" ]] && have httpx; then
    head -n 50 "$w/js_urls.txt" | while read -r js; do
      curl -sk --max-time 10 "$js" 2>/dev/null
    done | grep -Eoi '(api[_/][^\"'\'' ]+|Bearer [A-Za-z0-9._-]+|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35})' \
      | sort -u > "$w/js_secrets_hints.txt" || true
    log OK "Pistas secretos JS → $w/js_secrets_hints.txt"
  fi
}

mod_dirs(){
  log INFO "═══ DIRECTORY / CONTENT DISCOVERY ═══"
  local w="$outdir/web"
  install_wordlists
  run_tool "ffuf" "ffuf" \
    "ffuf -u https://$domain/FUZZ -w $WORDLIST_DIRS -t $THREADS -mc 200,201,202,204,301,302,307,401,403 -fc 404 -of json -o $w/ffuf.json -s" \
    "$w/ffuf.txt"
  # También con httpx + wordlist simple si ffuf falla vacío
  if [[ ! -s "$w/ffuf.txt" ]] && have curl; then
    log RUN "Brute light con curl..."
    while read -r p; do
      code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://$domain/$p" || echo 000)
      [[ "$code" =~ ^(200|204|301|302|401|403)$ ]] && echo "[$code] /$p"
    done < "$WORDLIST_DIRS" | tee "$w/dirs_light.txt" >/dev/null
  fi
}

mod_vuln(){
  log INFO "═══ VULN SCAN (nuclei / dalfox / nikto) ═══"
  local v="$outdir/vuln"
  local targets_file="$outdir/recon/httpx_alive.txt"
  [[ ! -s "$targets_file" ]] && targets_file="$outdir/recon/httpx.txt"

  if [[ -s "$targets_file" ]]; then
    # extraer solo URLs
    awk '{print $1}' "$targets_file" | sed 's#]]*##' | grep -E '^https?://' | sort -u > "$v/alive_urls.txt"
  else
    echo "https://$domain" > "$v/alive_urls.txt"
  fi

  run_tool "nuclei" "nuclei" \
    "nuclei -l $v/alive_urls.txt -severity $NUCLEI_SEVERITY -silent -stats -o $v/nuclei.txt" \
    "$v/nuclei.txt"

  run_tool "dalfox" "dalfox" \
    "dalfox url https://$domain --silence --skip-bav -o $v/dalfox.txt" \
    "$v/dalfox.txt"

  if [[ -s "$outdir/web/gf_xss.txt" ]] && have dalfox; then
    run_tool "dalfox-pipe" "dalfox" \
      "dalfox file $outdir/web/gf_xss.txt --silence --skip-bav -o $v/dalfox_mass.txt" \
      "$v/dalfox_mass.txt"
  fi

  run_tool "nikto" "nikto" "nikto -h https://$domain -output $v/nikto.txt -Format txt" "$v/nikto.txt"
}

mod_ghauri(){
  log INFO "═══ GHAURI SQLi ═══"
  local v="$outdir/vuln"
  local ghauri_out="$v/ghauri.txt"
  : > "$ghauri_out"

  if ! have ghauri; then
    log WARN "ghauri no instalado. Ejecuta autoinstalador (opción 0)."
    return 0
  fi

  local list="$outdir/web/gf_sqli.txt"
  [[ ! -s "$list" ]] && list="$outdir/web/params_urls.txt"
  [[ ! -s "$list" ]] && list="$outdir/web/urls_all.txt"

  if [[ -s "$list" ]]; then
    log RUN "Ghauri sobre hasta $GHAURI_URL_LIMIT URLs con params..."
    local n=0
    while read -r url && (( n < GHAURI_URL_LIMIT )); do
      [[ "$url" != *"?"* ]] && continue
      log RUN "SQLi → $url"
      ghauri -u "$url" --dbs --random-agent --batch --time-sec 8 --ignore-code 404 \
        --force-ssl -p 100 >>"$ghauri_out" 2>>"$aggregate" || true
      ((n++)) || true
    done < "$list"
  else
    log RUN "Ghauri directo sobre https://$domain"
    ghauri -u "https://$domain" --dbs --random-agent --batch --time-sec 8 \
      --ignore-code 404 --force-ssl -p 100 >"$ghauri_out" 2>>"$aggregate" || true
  fi
  log OK "Ghauri → $ghauri_out"
}

mod_ai(){
  log INFO "═══ IA LOCAL REPORT ═══"
  local a="$outdir/ai"
  local outfile="$a/ai_report.txt"
  local nuc="$outdir/vuln/nuclei.txt"
  local gh="$outdir/vuln/ghauri.txt"
  local nmapf="$outdir/recon/nmap.nmap"
  local httpxf="$outdir/recon/httpx_alive.txt"
  [[ ! -s "$httpxf" ]] && httpxf="$outdir/recon/httpx.txt"

  local prompt
  prompt="$(cat << EOF
Eres un Red Teamer senior. Analiza los hallazgos del pentest sobre ${domain}.
1) Resume hallazgos críticos/altos
2) Prioriza por criticidad (CVSS mental)
3) Indica impacto de negocio
4) Propón explotación siguiente paso (sin fluff)
5) Mitigaciones concretas

--- NMAP ---
$(head -n 200 "$nmapf" 2>/dev/null || echo N/A)

--- HTTPX ---
$(head -n 80 "$httpxf" 2>/dev/null || echo N/A)

--- NUCLEI ---
$(head -n 200 "$nuc" 2>/dev/null || echo N/A)

--- GHAURI ---
$(head -n 120 "$gh" 2>/dev/null || echo N/A)
EOF
)"

  if [[ -n "$OLLAMA_BIN" ]] && have ollama; then
    if [[ -z "$OLLAMA_MODEL" ]]; then
      OLLAMA_MODEL="$(ollama list 2>/dev/null | awk 'NR==2{print $1}')"
    fi
    if [[ -z "$OLLAMA_MODEL" ]]; then
      log WARN "Ollama sin modelos. Ejemplo: ollama pull llama3.2"
      echo "$prompt" > "$a/prompt.txt"
      return 0
    fi
    log AI "Ollama model=$OLLAMA_MODEL"
    printf "%s" "$prompt" | ollama run "$OLLAMA_MODEL" >"$outfile" 2>>"$aggregate" || true
  elif [[ -n "$GPT4ALL_BIN" ]]; then
    log AI "GPT4All"
    echo "$prompt" | "$GPT4ALL_BIN" >"$outfile" 2>>"$aggregate" || true
  elif [[ -n "$LLAMACPP_BIN" ]]; then
    log AI "llama.cpp"
    "$LLAMACPP_BIN" -p "$prompt" >"$outfile" 2>>"$aggregate" || true
  else
    log WARN "Sin IA local (ollama/gpt4all/llama). Guardando prompt."
    echo "$prompt" > "$a/prompt.txt"
    return 0
  fi
  log OK "IA Report → $outfile"
}

generate_msf_resource(){
  local nmap_grep="$outdir/recon/nmap.gnmap"
  [[ ! -f "$nmap_grep" ]] && nmap_grep="$outdir/recon/nmap.grep"
  # fallback: generar desde .nmap basico
  local msfrc="$outdir/exploit/msf_auto.rc"
  : > "$msfrc"
  {
    echo "setg RHOSTS $domain"
    echo "setg VERBOSE true"
    echo "spool $outdir/exploit/msf_spool.log"
  } >> "$msfrc"

  log RUN "Generando resource script Metasploit..."

  # Parse puertos abiertos de salida nmap normal
  local ports_file="$outdir/recon/naabu.txt"
  if [[ -s "$ports_file" ]]; then
    while read -r line; do
      # naabu: host:port
      local port
      port="$(echo "$line" | awk -F: '{print $NF}')"
      [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]] && continue
      case "$port" in
        21)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/ftp/ftp_version
set RPORT 21
run
use exploit/unix/ftp/vsftpd_234_backdoor
set RPORT 21
check
EOF
          ;;
        22)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/ssh/ssh_version
set RPORT 22
run
use auxiliary/scanner/ssh/ssh_login
set RPORT 22
set USER_FILE /usr/share/wordlists/metasploit/unix_users.txt
set PASS_FILE /usr/share/wordlists/metasploit/unix_passwords.txt
set STOP_ON_SUCCESS true
set THREADS 4
run
EOF
          ;;
        23)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/telnet/telnet_version
set RPORT 23
run
EOF
          ;;
        25|587)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/smtp/smtp_version
set RPORT $port
run
use auxiliary/scanner/smtp/smtp_enum
set RPORT $port
run
EOF
          ;;
        80|8080|8000|8888)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/http/http_version
set RPORT $port
run
use auxiliary/scanner/http/dir_scanner
set RPORT $port
run
use auxiliary/scanner/http/http_header
set RPORT $port
run
EOF
          ;;
        443|8443)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/http/http_version
set RPORT $port
set SSL true
run
use auxiliary/scanner/http/ssl/openssl_heartbleed
set RPORT $port
run
EOF
          ;;
        445)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/smb/smb_version
set RPORT 445
run
use auxiliary/scanner/smb/smb_ms17_010
set RPORT 445
run
use exploit/windows/smb/ms17_010_eternalblue
set RPORT 445
check
EOF
          ;;
        3306)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/mysql/mysql_version
set RPORT 3306
run
use auxiliary/scanner/mysql/mysql_login
set RPORT 3306
run
EOF
          ;;
        1433)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/mssql/mssql_ping
run
use auxiliary/scanner/mssql/mssql_login
set RPORT 1433
run
EOF
          ;;
        6379)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/redis/redis_server
set RPORT 6379
run
EOF
          ;;
        3389)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/rdp/rdp_scanner
set RPORT 3389
run
EOF
          ;;
        5900)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/vnc/vnc_none_auth
set RPORT 5900
run
EOF
          ;;
        27017)
          cat >>"$msfrc" <<EOF
use auxiliary/scanner/mongodb/mongodb_login
set RPORT 27017
run
EOF
          ;;
      esac
    done < "$ports_file"
  else
    # fallback mínimo
    cat >>"$msfrc" <<EOF
use auxiliary/scanner/portscan/tcp
set PORTS 1-1000
run
use auxiliary/scanner/http/http_version
set RPORT 80
run
use auxiliary/scanner/http/http_version
set RPORT 443
set SSL true
run
EOF
  fi

  echo "spool off" >> "$msfrc"
  echo "exit -y" >> "$msfrc"
  log OK "MSF RC → $msfrc"
}

mod_msf(){
  log INFO "═══ METASPLOIT AUTO ═══"
  if ! have msfconsole; then
    log WARN "msfconsole no encontrado. Instala Metasploit Framework."
    generate_msf_resource
    return 0
  fi
  generate_msf_resource
  log RUN "Lanzando msfconsole -q -r ..."
  msfconsole -q -r "$outdir/exploit/msf_auto.rc" | tee "$outdir/exploit/msf_auto.log" || true
  log OK "Metasploit finalizado → $outdir/exploit/msf_auto.log"
}

# ═════════════════════════════════════════════════════════════
# REPORTES
# ═════════════════════════════════════════════════════════════
generate_json(){
  log RUN "Generando JSON..."
  local jq_str file_to_json
  file_to_json(){
    local f="$1"
    if [[ -s "$f" ]] && have jq; then
      jq -Rs '.' "$f" 2>/dev/null || echo '""'
    else
      echo '""'
    fi
  }

  if have jq; then
    jq -n \
      --arg target "$domain" \
      --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" \
      --arg version "$VERSION" \
      --argjson subs "$(file_to_json "$outdir/recon/subs_all.txt")" \
      --argjson httpx "$(file_to_json "$outdir/recon/httpx_alive.txt")" \
      --argjson nuclei "$(file_to_json "$outdir/vuln/nuclei.txt")" \
      --argjson ghauri "$(file_to_json "$outdir/vuln/ghauri.txt")" \
      --argjson ai "$(file_to_json "$outdir/ai/ai_report.txt")" \
      --argjson msf "$(file_to_json "$outdir/exploit/msf_auto.log")" \
      '{
        target:$target,
        timestamp:$ts,
        scanner_version:$version,
        recon:{subdomains:$subs, httpx:$httpx},
        vuln:{nuclei:$nuclei, ghauri:$ghauri},
        ai_summary:$ai,
        metasploit:$msf
      }' > "$json_out"
  else
    cat > "$json_out" <<EOF
{
  "target": "$domain",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "scanner_version": "$VERSION",
  "note": "Instala jq para JSON completo"
}
EOF
  fi
  log OK "JSON → $json_out"
}

generate_html(){
  log RUN "Generando HTML report..."
  local subs_n nuclei_n urls_n
  subs_n=$(wc -l < "$outdir/recon/subs_all.txt" 2>/dev/null | tr -d ' ' || echo 0)
  nuclei_n=$(wc -l < "$outdir/vuln/nuclei.txt" 2>/dev/null | tr -d ' ' || echo 0)
  urls_n=$(wc -l < "$outdir/web/urls_all.txt" 2>/dev/null | tr -d ' ' || echo 0)

  cat > "$html_out" <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8"/>
<title>RedTeam Report · ${domain}</title>
<style>
  :root { --bg:#0b0f14; --card:#121821; --fg:#e6edf3; --acc:#00e5a8; --warn:#ffb454; --bad:#ff6b6b; --dim:#8b949e; }
  *{box-sizing:border-box} body{margin:0;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;background:var(--bg);color:var(--fg)}
  header{padding:28px 32px;background:linear-gradient(135deg,#0f172a,#123,#0b0f14);border-bottom:1px solid #1f2a37}
  h1{margin:0;font-size:1.4rem;letter-spacing:.04em} h1 span{color:var(--acc)}
  .meta{color:var(--dim);margin-top:8px;font-size:.85rem}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px;padding:22px 32px}
  .card{background:var(--card);border:1px solid #1f2a37;border-radius:12px;padding:16px}
  .card b{display:block;font-size:1.6rem;color:var(--acc)}
  .card small{color:var(--dim)}
  section{padding:8px 32px 28px}
  pre{background:#0d1117;border:1px solid #1f2a37;border-radius:10px;padding:14px;overflow:auto;max-height:380px;white-space:pre-wrap;font-size:.78rem;line-height:1.35}
  h2{font-size:1rem;color:var(--warn);margin:18px 0 8px}
  footer{padding:16px 32px 32px;color:var(--dim);font-size:.75rem}
</style>
</head>
<body>
<header>
  <h1>⚔ RedTeam Scanner <span>v${VERSION}</span></h1>
  <div class="meta">Target: <b style="color:#fff">${domain}</b> · $(date '+%Y-%m-%d %H:%M:%S') · Uso autorizado</div>
</header>
<div class="grid">
  <div class="card"><b>${subs_n}</b><small>Subdominios</small></div>
  <div class="card"><b>${urls_n}</b><small>URLs</small></div>
  <div class="card"><b>${nuclei_n}</b><small>Nuclei hits</small></div>
  <div class="card"><b>$( [[ -s $outdir/ai/ai_report.txt ]] && echo SI || echo NO )</b><small>IA Report</small></div>
</div>
<section>
  <h2>// nuclei</h2>
  <pre>$(sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g' "$outdir/vuln/nuclei.txt" 2>/dev/null | head -n 250 || echo "Sin datos")</pre>
  <h2>// httpx vivos</h2>
  <pre>$(sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g' "$outdir/recon/httpx_alive.txt" 2>/dev/null | head -n 120 || echo "Sin datos")</pre>
  <h2>// ghauri</h2>
  <pre>$(sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g' "$outdir/vuln/ghauri.txt" 2>/dev/null | head -n 120 || echo "Sin datos")</pre>
  <h2>// ia summary</h2>
  <pre>$(sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g' "$outdir/ai/ai_report.txt" 2>/dev/null | head -n 200 || echo "Sin datos")</pre>
</section>
<footer>RedTeam Scanner v${VERSION} · outputs/${domain}/ · No compartas este reporte fuera del equipo autorizado.</footer>
</body>
</html>
EOF
  log OK "HTML → $html_out"
}

summary_box(){
  hr
  cprint "$green$bold" "  ✔ ESCaneo finalizado"
  echo -e "  ${bold}Target:${reset}  $domain"
  echo -e "  ${bold}Dir:${reset}     $outdir"
  echo -e "  ${bold}Log:${reset}     $aggregate"
  echo -e "  ${bold}JSON:${reset}    $json_out"
  echo -e "  ${bold}HTML:${reset}    $html_out"
  hr
  echo -e "  ${dim}Subdominios:${reset} $(wc -l < "$outdir/recon/subs_all.txt" 2>/dev/null | tr -d ' ' || echo 0)"
  echo -e "  ${dim}URLs:${reset}        $(wc -l < "$outdir/web/urls_all.txt" 2>/dev/null | tr -d ' ' || echo 0)"
  echo -e "  ${dim}Nuclei:${reset}      $(wc -l < "$outdir/vuln/nuclei.txt" 2>/dev/null | tr -d ' ' || echo 0)"
  hr
}

# ═════════════════════════════════════════════════════════════
# MENÚ
# ═════════════════════════════════════════════════════════════
menu(){
  banner
  echo -e "  ${bold}${ACCENT}Selecciona módulos${reset}"
  echo
  echo -e "  ${cyan}[0]${reset} Autoinstalador de herramientas"
  echo -e "  ${cyan}[1]${reset} Recon (subs, DNS, ports, tech, WAF)"
  echo -e "  ${cyan}[2]${reset} URL Mining (gau/wayback/katana/JS)"
  echo -e "  ${cyan}[3]${reset} Dirs / FFUF"
  echo -e "  ${cyan}[4]${reset} Vuln scan (nuclei + dalfox + nikto)"
  echo -e "  ${cyan}[5]${reset} Ghauri SQLi"
  echo -e "  ${cyan}[6]${reset} IA Local Report"
  echo -e "  ${cyan}[7]${reset} Metasploit auto"
  echo -e "  ${green}[8]${reset} ${bold}FULL PIPELINE${reset} (1→7)"
  echo -e "  ${yellow}[9]${reset} Solo chequear herramientas"
  echo -e "  ${red}[q]${reset} Salir"
  echo
  read -rp "  » Opción: " mod_choice
}

run_selected(){
  case "${mod_choice}" in
    0) auto_install_all; menu; run_selected ;;
    1) mod_recon ;;
    2) mod_urls ;;
    3) mod_dirs ;;
    4) mod_vuln ;;
    5) mod_ghauri ;;
    6) mod_ai ;;
    7) mod_msf ;;
    8)
      mod_recon
      mod_urls
      mod_dirs
      mod_vuln
      mod_ghauri
      mod_ai
      mod_msf
      ;;
    9) check_tools_pretty; exit 0 ;;
    q|Q) cprint "$yellow" "Bye."; exit 0 ;;
    *) die "Opción inválida" ;;
  esac
}

usage(){
  cat <<EOF
Uso:
  $0 <dominio|IP>              # menú interactivo
  $0 <dominio|IP> --full       # pipeline completo sin menú
  $0 <dominio|IP> --install    # solo autoinstalador
  $0 --check                   # estado de herramientas

Variables útiles:
  TIMEOUT_SECONDS=300 THREADS=50 OLLAMA_MODEL=llama3.2 $0 target.com
EOF
}

# ═════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════
main(){
  # PATH útil
  export PATH="$PATH:${HOME}/go/bin:${HOME}/.local/bin:/usr/local/go/bin"
  [[ -n "${GOPATH:-}" ]] && export PATH="$PATH:$GOPATH/bin"
  if have go; then
    export PATH="$PATH:$(go env GOPATH 2>/dev/null)/bin"
  fi

  local arg1="${1:-}"
  local arg2="${2:-}"

  if [[ "$arg1" == "-h" || "$arg1" == "--help" ]]; then
    usage; exit 0
  fi

  if [[ "$arg1" == "--check" ]]; then
    banner
    check_tools_pretty
    exit 0
  fi

  if [[ "$arg1" == "--install" ]]; then
    target="install.local"
    domain="install"
    outdir="${OUT_BASE}/_install"
    aggregate="${outdir}/install.log"
    mkdir -p "$outdir"
    : > "$aggregate"
    auto_install_all
    exit 0
  fi

  target="${arg1:-}"
  if [[ -z "$target" ]]; then
    banner
    read -rp "  » Target (dominio/IP): " target
  fi

  setup_paths

  if [[ "$arg2" == "--install" || "$arg1" == *"--install"* ]]; then
    auto_install_all
  fi

  if [[ "$arg2" == "--full" ]]; then
    banner
    check_tools_pretty
    mod_choice=8
    run_selected
  else
    menu
    run_selected
  fi

  generate_json
  generate_html
  summary_box
  log OK "Job done."
}

main "$@"
