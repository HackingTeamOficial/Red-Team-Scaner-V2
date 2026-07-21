🛡 RedTeam Scanner v4 NUEVA ACTUALIZACION – Herramienta oficial de Hacking Team Para Equipos Red Team
<img width="1920" height="1080" alt="Screenshot_2026-07-21_15_30_40" src="https://github.com/user-attachments/assets/777ec444-fa8d-49c5-9710-d08f03b68fe8" />
<img width="1920" height="1080" alt="Screenshot_2026-07-21_15_30_44" src="https://github.com/user-attachments/assets/eb12ed58-8a97-46ce-9f60-169e42ebb8ec" />



RedTeam Scanner v2 es una herramienta avanzada de reconocimiento y análisis automatizado diseñada por la comunidad Hacking Team, Orientada a pentesters, bug bounty hunters y equipos de Red Team.

Combina en un solo script Bash las principales utilidades de enumeración ofensiva (subdominios, puertos, web scanning, fuzzing, extracción de URLs, XSS, escaneo de templates y más), gestionando errores, tiempos de ejecución y generando resultados organizados por dominio.

🔥 Características principales

Automatiza un flujo completo de reconocimiento y escaneo, desde subdominios hasta fuzzing avanzado.

Incluye herramientas clave como:

subfinder, assetfinder, dnsx, naabu, httpx, gau, waybackurls, dalfox, nuclei, ffuf, metasploit, nmap, ghauri.

Además de extracción desde crt.sh.

Sistema de timeout seguro, control de errores y registros detallados.

Análisis avanzado con IA incorporado (Ollama / Transformers):

Resume hallazgos.

Clasifica por impacto.

Da pasos de explotación y recomendaciones de mitigación.

Genera un archivo agregado por dominio + salidas individuales organizadas por herramienta.

Banner personalizado estilo red team.

🎯 Pensado para:

Red Team / Blue Team / Purple Team

Bug bounty hunters

Pentesters que buscan automatización del reconocimiento

Profesionales que quieren IA integrada en su flujo de análisis

🚀 Por qué usarlo

Todo tu reconocimiento web full stack en un solo comando: ./redteam-scanner.sh <dominio> 

Escanea, organiza, analiza, prioriza y entrega hallazgos — todo totalmente automatizado 

(ACTUALIZACION) representa un gran salto frente a la versión original, haciendo que la auditoría sea mucho más integral, automática y ofensiva.

Principales avances respecto al primer código

Menú interactivo: puedes elegir qué módulos ejecutar (reconocimiento, escaneo de inyecciones, IA, Metasploit, o todos juntos).
​
Reconocimiento avanzado: lanza tools como subfinder, assetfinder, nmap, naabu, nuclei y más, guardando todos los resultados en directorios organizados.

Automatización de explotación: analiza los puertos y servicios encontrados y genera comandos para Metasploit que lanzan exploits y módulos de ataque relevantes (por ejemplo, para SMB, HTTP, FTP, SSH, RDP, MySQL, etc.), todo sin intervención manual.

IA offline: usa modelos locales (Ollama, GPT4All, Llama.cpp) para analizar los hallazgos y crear un informe técnico.

JSON final: produce un reporte estructurado en formato JSON con los resultados de escaneo, explotación y análisis IA, ideal para crear dashboards o informes automáticos.

Escaneo Ghauri: detecta automáticamente URLs interesantes y las somete a pruebas automáticas de SQLi usando Ghauri.
​

Ahora el RedTeam Scanner es una suite automática capaz de:

    Detectar y mapear los activos.

    Atacar los servicios con exploits habituales.

    Probar inyección SQL en URLs relevantes.

    Generar informes y resúmenes profesionales usando IA local.

    Exportar todo centralmente en un archivo JSON listo para reportes o dashboards.

Novedades en esta versión

1. Módulo CVE / Searchsploit ([6])

    Extrae automáticamente todos los CVE-ID de Nuclei, Nmap y Nikto.
    Consulta la API pública cve.circl.lu para obtener CVSS y descripción de cada CVE.
    Ejecuta searchsploit --cve <ID> para encontrar exploits concretos.
    Separa los CVEs críticos (CVSS ≥ 7) en un archivo aparte.
    Si no hay CVEs directos, busca por nombres de tecnología/versión desde httpx y Nmap.
    Genera un archivo con los módulos de Metasploit aplicables para cada CVE.

2. Notificaciones Telegram

    Al inicio del escaneo (tg_notify_start): target, módulos, directorio de salida.
    Al finalizar (tg_notify_summary): resumen con números, top 5 CVEs críticos, top 3 nuclei, y envía los archivos de hallazgos (CVE summary, nuclei, IA report).
    Se activa configurando:

bash

export TG_BOT_TOKEN="tu_token_bot"
export TG_CHAT_ID="tu_chat_id"

O puedes ponerlas directamente al inicio del script en las variables TG_BOT_TOKEN y TG_CHAT_ID.

3. Otras mejoras

    El menú ahora incluye la opción [6] CVE/Searchsploit y el Full Pipeline [9] la incluye.
    El reporte HTML tiene una sección dedicada a CVEs/Exploits con tarjeta de conteo.
    El JSON incluye cve.summary y cve.critical.
    El autoinstalador (opción [0]) ahora también instala searchsploit (clona exploitdb en /opt/exploitdb).

Configurar Telegram rápido
bash

# Crea un bot con @BotFather en Telegram, obtén el token
# Obtén tu chat_id (escribe a @userinfobot)

export TG_BOT_TOKEN="123456:ABC-DEF1234..."
export TG_CHAT_ID="987654321"

# Ejecutar
./redteam_scanner.sh ejemplo.com --full

Si prefieres ponerlas fijas, edita las líneas al inicio del script donde pone TG_BOT_TOKEN="${TG_BOT_TOKEN:-}" y pon el valor entre las comillas.
    

Nuestras Redes Sociales

Telegram

https://t.me/PlantillasNucleiHackingTeam

https://t.me/HackingTeamGrupoOfficial

https://t.me/+0hHSaKO7eI9mNWY8 Hacking Team Difusion

https://t.me/+llcmNGzz6JIyMmI0 Biblioteca

https://t.me/TermuxHackingTeam

X

@HackingTeam77

Bluesky

https://bsky.app/profile/hackingteam.bsky.social

Discord

https://discord.gg/V4nPFbQX

Facebook 

https://www.facebook.com/groups/hackingteam2022/?ref=share
https://www.facebook.com/groups/HackingTeamCyber/?ref=share

Youtube 

https://www.youtube.com/@HackingTeamOfficial

Canal de tiktok 

https://www.tiktok.com/@hacking.kdea?_t=ZS-8vTtlaQrDTL&_r=1

#hackingteam #cibersecurity #infosec #eticalhacking #pentesting #dns #script #cracking #hack #security #bugbounty #payload #tools #exploit #cors #sqli #ssrf #python #c2 #poc #web #ramsomware #phishing #linux #osint #linux #windows #redteam #blueteam #spyware #digitalforensics #reverseengineeringtools #rat #malwareforensics #exploitdevelopment #sandboxing #apt #zerodayexploit #xss #github #cve #java #tools #termux #troyano    #dev #sqlmap #waybackurls #copilot #ai #ia #kalilinux #parrot #dracos #susse #nessus #oswazap #burpsuite #wireguar
