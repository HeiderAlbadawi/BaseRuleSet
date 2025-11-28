#!/bin/bash

# kql_json_converter.sh
# Usage:
#   ./kql_json_converter.sh json2kql input.json       # Convert JSON to KQL
#   ./kql_json_converter.sh kql2json input.kql       # Convert KQL to JSON

MODE=$1
INPUT_FILE=$2

if [[ -z "$MODE" || -z "$INPUT_FILE" ]]; then
    echo "Usage:"
    echo "  $0 json2kql input.json"
    echo "  $0 kql2json input.kql"
    exit 1
fi

if [[ "$MODE" == "json2kql" ]]; then
    # Extract JSON field and unescape newlines/tabs
    jq -r '.query' "$INPUT_FILE"

elif [[ "$MODE" == "kql2json" ]]; then
    # Convert KQL file into valid JSON safely
    jq -Rn --arg kql "$(cat "$INPUT_FILE")" '{query: $kql}'

else
    echo "Invalid mode: $MODE"
    echo "Use 'json2kql' or 'kql2json'"
    exit 1
fi
