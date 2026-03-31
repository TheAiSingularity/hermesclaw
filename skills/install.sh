#!/usr/bin/env bash
# HermesClaw skills installer.
#
# Copies skills from this repo into ~/.hermes/skills/ where Hermes can find them.
#
# Usage:
#   ./skills/install.sh                          # interactive menu
#   ./skills/install.sh research-digest          # install one skill
#   ./skills/install.sh research-digest code-review  # install multiple
#   ./skills/install.sh --all                    # install all skills
#   ./skills/install.sh --list                   # list available skills

set -uo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
SKILLS_DEST="${HERMES_HOME:-$HOME/.hermes}/skills"

# ── Helpers ───────────────────────────────────────────────────────────────────

available_skills() {
    find "$SKILLS_SRC" -mindepth 1 -maxdepth 1 -type d \
        ! -name "scripts" \
        -exec basename {} \; | sort
}

install_skill() {
    local skill="$1"
    local src="$SKILLS_SRC/$skill"
    local dest="$SKILLS_DEST/$skill"

    if [ ! -d "$src" ]; then
        echo -e "${YELLOW}SKIP${RESET}  $skill — not found in skills/"
        return 1
    fi

    mkdir -p "$SKILLS_DEST"
    cp -r "$src" "$SKILLS_DEST/"
    echo -e "${GREEN}OK${RESET}    $skill → $dest"
}

print_list() {
    echo ""
    echo -e "${BOLD}Available HermesClaw skills:${RESET}"
    echo ""
    while IFS= read -r skill; do
        desc=""
        skill_file="$SKILLS_SRC/$skill/SKILL.md"
        if [ -f "$skill_file" ]; then
            # Extract description from YAML frontmatter
            desc=$(awk '/^---/{p++} p==1 && /^description:/{gsub(/^description: */, ""); print; exit}' "$skill_file")
        fi
        printf "  %-25s  %s\n" "$skill" "$desc"
    done < <(available_skills)
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

if [ $# -eq 0 ]; then
    print_list
    echo "Usage: ./skills/install.sh <skill-name> [skill-name ...]"
    echo "       ./skills/install.sh --all"
    exit 0
fi

if [ "${1:-}" = "--list" ]; then
    print_list
    exit 0
fi

if [ "${1:-}" = "--all" ]; then
    echo ""
    echo -e "${BOLD}Installing all HermesClaw skills...${RESET}"
    echo ""
    while IFS= read -r skill; do
        install_skill "$skill"
    done < <(available_skills)
    echo ""
    echo -e "${GREEN}Done.${RESET} Skills installed to: $SKILLS_DEST"
    echo ""
    echo "To use a skill, tell Hermes:"
    echo "  hermes chat -q \"run research-digest\""
    echo "  or in any gateway: \"run the anomaly-detection skill\""
    exit 0
fi

echo ""
echo -e "${BOLD}Installing skills...${RESET}"
echo ""

INSTALLED=0
for skill in "$@"; do
    if install_skill "$skill"; then
        INSTALLED=$((INSTALLED + 1))
    fi
done

echo ""
if [ "$INSTALLED" -gt 0 ]; then
    echo -e "${GREEN}$INSTALLED skill(s) installed to: $SKILLS_DEST${RESET}"
    echo ""
    echo "If running in Docker mode, restart to pick up new skills:"
    echo "  docker compose restart hermesclaw"
    echo ""
    echo "If running in OpenShell mode, the skill is available immediately"
    echo "(~/.hermes/skills is mounted into the sandbox)."
fi
