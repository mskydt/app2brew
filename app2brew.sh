#!/bin/bash

APPS_DIR="/Applications"
EXCLUDE_FILE="exclude_apps.txt"
ALIAS_FILE="aliases.txt"
LIST_OUTPUT="brew_app_list.txt"
LOG_FILE="app2brew.log"

alias_app_names=()
alias_brew_names=()
exclude_apps=()

# Load exclude_apps.txt
if [ -f "$EXCLUDE_FILE" ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        exclude_apps+=("$line")
    done < "$EXCLUDE_FILE"
fi

# Load aliases.txt
if [ -f "$ALIAS_FILE" ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        app_name="${line%%::*}"
        brew_name="${line##*::}"
        alias_app_names+=("$app_name")
        alias_brew_names+=("$brew_name")
    done < "$ALIAS_FILE"
fi

# Function to look up alias
get_alias_brew_name() {
    local search_name="$1"
    for i in "${!alias_app_names[@]}"; do
        if [ "$search_name" == "${alias_app_names[$i]}" ]; then
            echo "${alias_brew_names[$i]}"
            return
        fi
    done
    echo ""
}

# Function to check if app is in exclude list
is_excluded() {
    local check_name="$1"
    for excl in "${exclude_apps[@]}"; do
        if [ "$check_name" == "$excl" ]; then
            return 0
        fi
    done
    return 1
}

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Please install it before continuing."
    exit 1
fi

# Precompute installed casks/formulas
installed_casks=$(brew list --cask --versions | awk '{print $1}')
installed_formulas=$(brew list --versions | awk '{print $1}')

INSTALLED_VIA_BREW=()
ALREADY_INSTALLED_VIA_BREW=()
UNABLE_TO_INSTALL=()
CAN_BE_REINSTALLED=()

app_list=()
while IFS= read -r -d '' app; do
    app_name="$(basename "$app" .app)"
    app_list+=("$app_name")
done < <(find "$APPS_DIR" -maxdepth 1 -type d -name "*.app" -print0)

total=${#app_list[@]}
count=1

> "$LIST_OUTPUT"

echo "Starting --list check..."

for app in "${app_list[@]}"; do
    echo "Checking $count of $total applications: $app"
    count=$((count + 1))

    is_excluded "$app" && continue

    alias_brew_name=$(get_alias_brew_name "$app")
    brew_name=""
    
    if [ -n "$alias_brew_name" ]; then
        brew_name="$alias_brew_name"
    else
        brew_name=$(echo "$app" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
    fi

    if echo "$installed_casks" | grep -Fxq "$brew_name" || echo "$installed_formulas" | grep -Fxq "$brew_name"; then
        ALREADY_INSTALLED_VIA_BREW+=("$app")
    else
        if brew info --cask "$brew_name" &> /dev/null || brew info "$brew_name" &> /dev/null; then
            CAN_BE_REINSTALLED+=("$app")
        else
            UNABLE_TO_INSTALL+=("$app")
        fi
    fi
done

echo "Generating $LIST_OUTPUT..."
echo "=== Already Installed with Brew ===" > "$LIST_OUTPUT"
printf "%s\n" "${ALREADY_INSTALLED_VIA_BREW[@]}" >> "$LIST_OUTPUT"

echo "\n=== Not Available via Brew ===" >> "$LIST_OUTPUT"
printf "%s\n" "${UNABLE_TO_INSTALL[@]}" >> "$LIST_OUTPUT"

echo "\n=== Can Be Reinstalled with Brew ===" >> "$LIST_OUTPUT"
printf "%s\n" "${CAN_BE_REINSTALLED[@]}" >> "$LIST_OUTPUT"

echo "List saved to $LIST_OUTPUT"

