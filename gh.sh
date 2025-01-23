#!/bin/bash

# Read input securely
read -p "Enter the organization name: " org_name

# Configuration
TOKENS=(
    "TOKEN"
    "TOKEN"
    "TOKEN"
)
github_scan_dir="github"
GITDORKS_PATH="./gitdorks_go"
DORKS_FILE="gitdorks/Dorks/smalldorks.txt"  # Updated path

# Validate at least one token exists
if [ ${#TOKENS[@]} -eq 0 ]; then
    echo "ERROR: No GitHub tokens provided"
    exit 1
fi

# Create scan directory
if ! mkdir -p "$github_scan_dir"; then
    echo "ERROR: Failed to create directory $github_scan_dir"
    exit 1
fi

# Create token file
echo "Creating token file..."
printf "%s\n" "${TOKENS[@]}" > "$github_scan_dir/tokens.txt"

# Install gitdorks_go if missing
if [ ! -f "$GITDORKS_PATH" ]; then
    echo "Downloading gitdorks_go..."
    if ! wget -q https://github.com/damit5/gitdorks_go/releases/download/v0.1/gitdorks_go_amd_linux -O "$GITDORKS_PATH"; then
        echo "ERROR: Failed to download gitdorks_go"
        exit 1
    fi
    chmod +x "$GITDORKS_PATH"
fi

# Clone dorks repository if missing
if [ ! -f "$DORKS_FILE" ]; then
    echo "Cloning gitdorks_go repository..."
    if ! git clone -q https://github.com/damit5/gitdorks_go.git gitdorks; then
        echo "ERROR: Failed to clone gitdorks repository"
        exit 1
    fi
fi

# Validate dorks file exists
if [ ! -f "$DORKS_FILE" ]; then
    echo "ERROR: Dorks file still missing after clone attempt"
    exit 1
fi

# Run TruffleHog scan (using first token)
echo "[1/3] Running TruffleHog..."
if ! trufflehog github --org "$org_name" \
    --token="${TOKENS[0]}" \
    --include-members \
    --concurrency=20 \
    --issue-comments \
    --pr-comments \
    --gist-comments \
    --results=verified,unknown \
    --json > "$github_scan_dir/trufflehog_secrets.json"; then
    echo "ERROR: TruffleHog scan failed"
    exit 1
fi

# Run gitdorks_go scan (using all tokens)
echo "[2/3] Running gitdorks_go..."
if ! "$GITDORKS_PATH" \
    -target "$org_name" \
    -tf "$github_scan_dir/tokens.txt" \
    -gd "$DORKS_FILE" \
    -ew 5 \
    -nws 30 \
    -nw true \
    > "$github_scan_dir/gitdorks_raw.txt"; then
    echo "ERROR: gitdorks_go scan failed"
    exit 1
fi

# Process results
echo "[3/3] Processing results..."
if ! awk '!seen[$0]++' "$github_scan_dir/gitdorks_raw.txt" | \
    grep -E 'https://github.com' > "$github_scan_dir/gitdorks_clean.txt"; then
    echo "ERROR: Failed to process gitdorks results"
    exit 1
fi

# Generate combined report
{
    echo "=== Verified Secrets (TruffleHog) ==="
    jq -r 'select(.Verified == true) | "\(.DetectorName): \(.Redacted)"' "$github_scan_dir/trufflehog_secrets.json"
    
    echo -e "\n=== Sensitive Findings (gitdorks_go) ==="
    awk -F'/' '{print "Repo: " $4 "/" $5 "\nFile: " $NF "\nURL: " $0 "\n"}' "$github_scan_dir/gitdorks_clean.txt"
} > "$github_scan_dir/final_report.txt"

echo "Scan complete! Results saved to: $github_scan_dir/"
