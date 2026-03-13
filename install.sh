#!/bin/sh

# Resolve the absolute path to the directives file in the same directory as
# this script. Do not assume that it's in the current working directory.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P)
directives_md="${script_dir}/directives/common.md"

# Verify that the directives file exists where expected.
if [ ! -f "$directives_md" ]; then
    echo "Error: Could not find directives/common.md next to install.sh." 1>&2
    echo "Expected at: $directives_md" 1>&2
    exit 1
fi

# install_link src dst label
#
# Creates a symlink at dst pointing to src. The behavior depends on what is
# already at dst:
#
#   - If dst is already a symlink pointing to src, skip silently.
#   - If dst is a real (non-symlink) directory, print a warning and skip.
#     Removing a directory tree is too destructive to do without explicit user
#     action.
#   - If dst exists in any other form (a file, a broken symlink, or a symlink
#     pointing elsewhere), prompt the user before replacing it. Without this
#     guard, passing an already-installed symlink-to-directory to ln would
#     cause it to treat the destination as a directory and place a new link
#     inside it — for a skill foo this would produce a self-referential chain:
#     ~/.claude/skills/foo -> .../skills/claude/foo, then on the next run,
#     .../skills/claude/foo/foo -> .../skills/claude/foo, and so on.
#   - If dst does not exist, create the symlink.
install_link() {
    src="$1"
    dst="$2"
    label="$3"

    # Already correct — nothing to do.
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        echo "  Already installed: ${label}"
        return 0
    fi

    # Refuse to silently remove a real directory.
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        echo "  Warning: ${dst} is a real directory; skipping ${label}." >&2
        return 1
    fi

    # Target exists but is wrong — prompt before replacing.
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        printf "  %s already exists at %s. Replace? [y/N] " "$label" "$dst"
        read -r _answer
        case "$_answer" in
            [yY]*) ;;
            *) echo "  Skipping: ${label}"; return 0 ;;
        esac
        rm -f "$dst" || return 1
    fi

    ln -s "$src" "$dst" && echo "  Installed: ${label}"
}

# Register with Claude Code, if configured.
if [ -d "${HOME}/.claude" ]; then
    echo "Registering for Claude Code."

    # Register directives.
    install_link "$directives_md" "${HOME}/.claude/CLAUDE.md" "CLAUDE.md"

    # Register Claude-specific skills.
    claude_skills_src="${script_dir}/skills/claude"
    if [ -d "$claude_skills_src" ]; then
        mkdir -p "${HOME}/.claude/skills"
        for skill_dir in "${claude_skills_src}"/*/; do
            [ -d "$skill_dir" ] || continue
            skill_name=$(basename "$skill_dir")
            install_link \
                "${claude_skills_src}/${skill_name}" \
                "${HOME}/.claude/skills/${skill_name}" \
                "skill: ${skill_name}"
        done
    fi

    # Register common skills.
    common_skills_src="${script_dir}/skills/common"
    if [ -d "$common_skills_src" ]; then
        mkdir -p "${HOME}/.claude/skills"
        for skill_dir in "${common_skills_src}"/*/; do
            [ -d "$skill_dir" ] || continue
            skill_name=$(basename "$skill_dir")
            install_link \
                "${common_skills_src}/${skill_name}" \
                "${HOME}/.claude/skills/${skill_name}" \
                "skill: ${skill_name}"
        done
    fi
else
    echo "Claude Code not configured."
fi

# Register with OpenAI Codex, if configured.
if [ -d "${HOME}/.codex" ]; then
    echo "Registering for OpenAI Codex."

    # Register directives.
    install_link "$directives_md" "${HOME}/.codex/AGENTS.md" "AGENTS.md"

    # Register Codex-specific skills. Codex reads user-level skills from
    # ~/.agents/skills, not ~/.codex/skills. Claude Code reads from
    # ~/.claude/skills, so these two directories are fully separate and
    # Codex skills installed here will not be visible to Claude Code.
    codex_skills_src="${script_dir}/skills/codex"
    if [ -d "$codex_skills_src" ]; then
        mkdir -p "${HOME}/.agents/skills"
        for skill_dir in "${codex_skills_src}"/*/; do
            [ -d "$skill_dir" ] || continue
            skill_name=$(basename "$skill_dir")
            install_link \
                "${codex_skills_src}/${skill_name}" \
                "${HOME}/.agents/skills/${skill_name}" \
                "skill: ${skill_name}"
        done
    fi

    # Register common skills. See the comment above about why these are
    # installed to ~/.agents/skills, not ~/.codex/skills.
    common_skills_src="${script_dir}/skills/common"
    if [ -d "$common_skills_src" ]; then
        mkdir -p "${HOME}/.agents/skills"
        for skill_dir in "${common_skills_src}"/*/; do
            [ -d "$skill_dir" ] || continue
            skill_name=$(basename "$skill_dir")
            install_link \
                "${common_skills_src}/${skill_name}" \
                "${HOME}/.agents/skills/${skill_name}" \
                "skill: ${skill_name}"
        done
    fi
else
    echo "OpenAI Codex not configured."
fi
