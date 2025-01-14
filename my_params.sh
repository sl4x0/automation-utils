#!/bin/bash

# List of input URLs
input_urls=(
    "https://raw.githubusercontent.com/s0md3v/Arjun/master/arjun/db/large.txt"
    "https://raw.githubusercontent.com/PortSwigger/param-miner/master/resources/params"
    "https://wordlists-cdn.assetnote.io/data/automated/httparchive_parameters_top_1m_2023_07_28.txt"
    "https://gist.githubusercontent.com/nullenc0de/9cb36260207924f8e1787279a05eb773/raw/0197d33c073a04933c5c1e2c41f447d74d2e435b/params.txt"
)

# Download and combine parameters
output_file=/roots/wordlists/my_parameters.txt
> "$output_file" # Clear contents of the file

for url in "${input_urls[@]}"; do
    wget -q -O - "$url" >> "$output_file"
done

# Filter unique parameters
sort -u -o "$output_file" "$output_file"

echo "Unique parameters saved to $output_file"

# Remove the script
rm -- "$0"
