#!/bin/bash

# Set the domain to be enumerated
domains="roots.txt"
domain=$(cat roots.txt)

# Set the directories and tools used in the process
SUBDOMAINS_DIR="subdomains"
CHAOS_API_KEY="YOUR_ONE"
AMASS_CONFIG="/root/.config/amass/datasources.yaml"
BRUTEFORCE_WORDLIST="/root/wordlists/wordlists/inventory/subdomains.txt"
PERM_WORDLIST="/root/Tools/permutations_list.txt"
RESOLVERS="/root/wordlists/resolvers/resolvers.txt"
RESOLVERS_TRUSTED="/root/wordlists/resolvers/resolvers-trusted.txt"
VHOST_WORDLIST="/root/wordlists/subdomains-top1million-5000.txt"

# Create the subdomains directory if it does not exist
if [ ! -d "$SUBDOMAINS_DIR" ]; then
  mkdir -p "$SUBDOMAINS_DIR"
fi

#Enumerate subdomains using Chaos
echo "🔍 Enumerating subdomains using Chaos..."
chaos -dL "$domains" -key "$CHAOS_API_KEY" -silent -o "$SUBDOMAINS_DIR/chaos.txt"
echo "✅ Done with Chaos enumeration."
echo -e "\e[31m======================================\e[0m"

#Enumerate subdomains using Amass
echo "🔍 Enumerating subdomains using Amass..."
amass enum -df "$domains" -passive -active -o "$SUBDOMAINS_DIR/amass_subs.txt"
echo "✅ Done with Amass enumeration."
echo -e "\e[31m======================================\e[0m"

# Enumerate subdomains using Subfinder
echo "🔍 Enumerating subdomains using Subfinder..."
subfinder -dL "$domains" -all -o "$SUBDOMAINS_DIR/subfinder-subs.txt"
echo "✅ Done with Subfinder enumeration."
echo -e "\e[31m======================================\e[0m"

# Enumerate subdomains using Bruteforce Mode
echo "🔍 Enumerating subdomains using PureDNS bruteforce..."
puredns bruteforce "$BRUTEFORCE_WORDLIST" $domain --resolvers "$RESOLVERS" --resolvers-trusted "$RESOLVERS_TRUSTED" -t 250 -w "$SUBDOMAINS_DIR/pure-bruteforce.txt"
echo "✅ Done with PureDNS bruteforce enumeration."
echo -e "\e[31m======================================\e[0m"

# Enumerate subdomains using HOST Bruteforce
echo "🔍 Enumerating subdomains using VHOST BruteForce..."
ffuf -H "Host: FUZZ.$domain" -u "https://$domain" -w "$VHOST_WORDLIST" -t 50 -maxtime 900 -ac -o "$SUBDOMAINS_DIR/.vhosts.txt"; cat "$SUBDOMAINS_DIR/.vhosts.txt" | jq -r '.results[].host' > "$SUBDOMAINS_DIR/vhosts.txt"
echo "✅ Done with VHOST PruteForce enumeration."
echo -e "\e[31m======================================\e[0m"

# Enumerate subdomains using Perms
echo "🔍 Enumerating subdomains Gotator..."
gotator -sub $domains -perm "$PERM_WORDLIST" -depth 1 -prefixes -mindup -t 200 | puredns resolve --resolvers "$RESOLVERS" --resolvers-trusted "$RESOLVERS_TRUSTED" -t 250  -w "$SUBDOMAINS_DIR/gotator-perms.txt"
echo "✅ Done with Gotator Perms enumeration."
echo -e "\e[31m======================================\e[0m"

# Filtering
echo "🧹 Filtering duplicate subdomains..."
cat "$SUBDOMAINS_DIR/"*.txt | anew | sort -u | tee "$SUBDOMAINS_DIR/first-unique-subdomains.txt"
echo "✅ Done with filtering."
echo -e "\e[31m======================================\e[0m"


# last Filtering
echo "🧹 Filtering duplicate subdomains..."
cat "$SUBDOMAINS_DIR/"*.txt | anew | sort -u | tee "$SUBDOMAINS_DIR/unique-subdomains.txt"
echo "✅ Done with last filtering."
echo -e "\e[31m======================================\e[0m"


# Enumerate subdomains using Resolve Mode
echo "🔍 Resolving Subs using PureDNS..."
puredns resolve "$SUBDOMAINS_DIR/unique-subdomains.txt" --resolvers "$RESOLVERS" --resolvers-trusted "$RESOLVERS_TRUSTED" -t 250 -w "$SUBDOMAINS_DIR/all-subdomains.txt"
echo "✅ Done with PureDNS Resolvation."
echo -e "\e[31m======================================\e[0m"

# Probing Subdomains
echo "🔍 Probing Webservers using HTTProbe..."
cat "$SUBDOMAINS_DIR/all-subdomains.txt" "$SUBDOMAINS_DIR/unique-subdomains.txt" | sort -u | httprobe -c 150 | tee "$SUBDOMAINS_DIR/all-probed.txt"
echo "✅ Done with probing."
echo -e "\e[31m======================================\e[0m"

# Check the CNAME records for the subdomains to find out if they are aliased to another domain
echo "🔍 Checking CNAME records for the subdomains..."
while read subdomain; do
    cname=$(dig +short $subdomain CNAME)
    if [ -n "$cname" ]; then
        echo "$subdomain  ==>  $cname" >> cname_records.txt
    fi
done < "$SUBDOMAINS_DIR/all-probed.txt"

# Checking for Subdomain Takeover using Nuclei
echo "🔎 Checking for subdomain takeover using Nuclei..."
nuclei -l "$SUBDOMAINS_DIR/all-probed.txt" -tags takeover -o "$SUBDOMAINS_DIR/nuclei_results.txt" -c 150 | notify -silent
echo "✅ Done with subdomain takeover check."
echo -e "\e[31m======================================\e[0m"

# Tech Detect
echo "🛠️ Detecting technologies used on \"web servers\" using httpx..."
cat "$SUBDOMAINS_DIR/all-subdomains.txt" | httpx -follow-redirects -location -content-length -title -status-code -web-server -tech-detect -retries 2 -random-agent -t 100 -timeout 10 -o "$SUBDOMAINS_DIR/httpx_tech.txt"
echo "✅ Done with detecting technologies."
echo -e "\e[31m======================================\e[0m"
