#!/bin/bash

APPS_DIR="/Applications"
EXCLUDE_FILE="exclude_apps.txt"
LOG_FILE="brew_actions.log"
DRY_RUN=false

INSTALLED_VIA_BREW=()
ALREADY_INSTALLED_VIA_BREW=()
UNABLE_TO_INSTALL=()
CASK_PACKAGES=()
CASK_APPS=()
FORMULA_PACKAGES=()
FORMULA_APPS=()

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

print_help() {
  echo -e "Usage: $0 [--list] [--reinstall \"App Name\"] [--dry-run] [--help]"
  echo "--list          List applications and categorize them into sections, saving to list.txt"
  echo "--reinstall     Uninstall and reinstall a specific app via Homebrew"
  echo "--dry-run       Show actions without making changes"
  echo "--help          Show this help message"
}

# Check for Homebrew
if ! command -v brew &> /dev/null; then
  echo -e "${RED}Homebrew is not installed. Please install it first.${NC}"
  exit 1
fi

# Load exclusions
EXCLUDES=()
if [ -f "$EXCLUDE_FILE" ]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    EXCLUDES+=("$line")
  done < "$EXCLUDE_FILE"
fi

normalize_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g'
}

is_excluded() {
  local app="$1"
  if printf '%s\n' "${EXCLUDES[@]}" | grep -Fxq "$app"; then
    return 0
  else
    return 1
  fi
}

if [[ "$1" == "--help" ]]; then
  print_help
  exit 0
fi

if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo -e "${YELLOW}Running in dry-run mode. No changes will be made.${NC}"
  shift
fi

if [[ "$1" == "--list" ]]; then
  installed_casks=$(brew list --cask --versions | awk '{print $1}')
  installed_formulas=$(brew list --versions | awk '{print $1}')

  app_list=()
  while IFS= read -r -d '' app; do
    app_name=$(basename "$app" .app)
    if is_excluded "$app_name"; then
      continue
    fi
    app_list+=("$app_name")
  done < <(find "$APPS_DIR" -maxdepth 1 -type d -name "*.app" -print0)

  total=${#app_list[@]}
  count=0

  > list.txt
  echo "Already installed with brew:" >> list.txt

  for app in "${app_list[@]}"; do
    count=$((count + 1))
    echo -e "Checking $count of $total applications: $app"
    brew_name=$(normalize_name "$app")
    if echo "$installed_casks" | grep -Fxq "$brew_name" || echo "$installed_formulas" | grep -Fxq "$brew_name"; then
      echo "$app" >> list.txt
      ALREADY_INSTALLED_VIA_BREW+=("$app")
    fi
  done

  echo -e "\nNot available via brew:" >> list.txt
  for app in "${app_list[@]}"; do
    brew_name=$(normalize_name "$app")
    if ! brew info --cask "$brew_name" &> /dev/null && ! brew info "$brew_name" &> /dev/null; then
      echo "$app" >> list.txt
      UNABLE_TO_INSTALL+=("$app")
    fi
  done

  echo -e "\nCan be reinstalled with brew:" >> list.txt
  for app in "${app_list[@]}"; do
    brew_name=$(normalize_name "$app")
    if (brew info --cask "$brew_name" &> /dev/null || brew info "$brew_name" &> /dev/null) && \
       ! echo "$installed_casks" | grep -Fxq "$brew_name" && \
       ! echo "$installed_formulas" | grep -Fxq "$brew_name"; then
      echo "$app" >> list.txt
    fi
  done

  echo -e "${GREEN}List saved to list.txt${NC}"
  exit 0
fi

if [[ "$1" == "--reinstall" ]]; then
  shift
  target_app="$1"
  if [ -z "$target_app" ]; then
    echo -e "${RED}Error: Please provide the application name.${NC}"
    exit 1
  fi

  brew_name=$(normalize_name "$target_app")

  app_path="$APPS_DIR/$target_app.app"
  if [ ! -d "$app_path" ]; then
    echo -e "${RED}Error: $target_app.app not found in /Applications.${NC}"
    exit 1
  fi

  backup_path="$APPS_DIR/${target_app}.app.backup_$(date +%Y%m%d%H%M%S)"
  echo -e "${BLUE}Backing up $app_path to $backup_path...${NC}"
  if [ "$DRY_RUN" = false ]; then
    cp -R "$app_path" "$backup_path"
    sudo rm -rf "$app_path"
  fi
  echo "Backup created at $backup_path" | tee -a "$LOG_FILE"

  if brew info --cask "$brew_name" &> /dev/null; then
    echo -e "${GREEN}Installing $brew_name via cask...${NC}"
    if [ "$DRY_RUN" = false ]; then
      brew install --cask "$brew_name" | tee -a "$LOG_FILE"
    fi
  elif brew info "$brew_name" &> /dev/null; then
    echo -e "${GREEN}Installing $brew_name via formula...${NC}"
    if [ "$DRY_RUN" = false ]; then
      brew install "$brew_name" | tee -a "$LOG_FILE"
    fi
  else
    echo -e "${RED}Error: $brew_name not found in Brew.${NC}"
    exit 1
  fi

  echo -e "${GREEN}Reinstallation complete.${NC}"
  exit 0
fi

print_help

