#!/bin/bash

# Constants
TECH_DIR="technologies"
DOMAIN=$(cat "roots.txt")
SUBDOMAINS_DIR="subdomains"
HTTPX_PATH="$SUBDOMAINS_DIR/httpx_tech.txt"
ORWA_WORDLIST_URL="https://raw.githubusercontent.com/orwagodfather/WordList/main/iis.txt"
ORWA_WORDLIST="/root/wordlists/iis.txt"
FFUF_OPTIONS="-w $ORWA_WORDLIST -mc all -ac -o $TECH_DIR/ffuf_iis.txt"
SHORTSCAN_OPTIONS="-c 40 -p 1 -w $ORWA_WORDLIST"
IIS_NUCLEI_TEMPLATE_URL="https://raw.githubusercontent.com/projectdiscovery/nuclei-templates/master/iis-shortname.yaml"
IIS_SHORTNAME_TEMPLATE="$TECH_DIR/iis-shortname.yaml"
IIS_WEBSITES_FILE="$TECH_DIR/iis_websites.txt"
NUCLEI_OUTPUT_FILE="$TECH_DIR/nuclei_iis_shortname.txt"

# Check if the 'technologies' directory exists, and create it if not
if [ ! -d "$TECH_DIR" ]; then
    mkdir -p "$TECH_DIR"
fi

download_file() {
    url="$1"
    target="$2"
    description="$3"

    if [ ! -f "$target" ]; then
        echo "🔍 Downloading $description..."
        if wget "$url" -O "$target"; then
            echo "✅ $description downloaded successfully."
        else
            echo "❌ $description download failed."
        fi
    fi
}

# Download necessary files
download_file "$IIS_NUCLEI_TEMPLATE_URL" "$IIS_SHORTNAME_TEMPLATE" "IIS Nuclei Template"
download_file "$ORWA_WORDLIST_URL" "$ORWA_WORDLIST" "ORWA Wordlist"

# Extract IIS Server Websites
echo "🔍 Getting the IIS Server Websites from httpx_tech.txt..."
awk -F' ' '/[Ii][Ii][Ss]|[Mm]icrosoft[\-\s]*IIS[\/ ]*([0-9]*)|[Mm]icrosoft[\-\s]*[Aa]zure[\-\s]*[Aa]pp[\-\s]*[Ss]ervice|[Mm]icrosoft[\-\s]*[Ii][Ii][Ss][\-\s]*[Hh][Tt][Tt][Pp][Dd]|[Ii][Ii][Ss][\-\s]*[Ww]indows[\-\s]*[Ss]erver|[Ii][Ii][Ss][\/\-\s]*[0-9]*|[Ii][Ii][Ss][\-\s]*[Ww]indows/ {print $1}' "$HTTPX_PATH" | sort -u > "$IIS_WEBSITES_FILE"

echo "🔍 Getting the IIS Server Websites from Shodan ..."
{
    shodan search hostname:"$DOMAIN" http.title:"IIS" --fields ip_str,port
    shodan search ssl.cert.subject.cn:"$DOMAIN" http.title:"IIS" --fields ip_str,port
    shodan search org:"$(echo "$DOMAIN" | awk -F'.' '{print $1}')" http.title:"IIS" --fields ip_str,port
} | awk '{print $1 ":" $2}' | sort -u | httpx -c 100 -silent | tee -a "$IIS_WEBSITES_FILE"

# Scanning Section
if [ -s "$IIS_WEBSITES_FILE" ]; then
    echo "🔍 Scanning with Nuclei..."
    nuclei -c 100 -retries 2 -stats -tags iis -o "$NUCLEI_OUTPUT_FILE" < "$IIS_WEBSITES_FILE"
else
    echo "No IIS websites found for scanning."
fi

# Fuzzing Section
if [ -s "$IIS_WEBSITES_FILE" ]; then
    echo "🔍 Fuzzing with ffuf and Shortscan..."
    while read -r website; do
        ffuf $FFUF_OPTIONS -u "$website/FUZZ" >> /dev/null
        shortscan "$website" $SHORTSCAN_OPTIONS | tee "$TECH_DIR/shortscan_iis.txt"
    done < "$IIS_WEBSITES_FILE"
    echo "✅ Fuzzing with ffuf completed."
else
    echo "No IIS websites found for fuzzing."
fi
