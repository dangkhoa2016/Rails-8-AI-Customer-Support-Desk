#!/usr/bin/env bash
# Shared runtime discovery for ephemeral Colab and persistent dev hosts.
# SOURCE this helper after setting repo to the repository's absolute path.
if [[ -z "${repo:-}" || ! -f "$repo/Gemfile.lock" ]]; then
  echo "RAILS8_RUNTIME_ERROR: repository root was not resolved" >&2
  return 1
fi
if [[ "$(id -u)" == "0" && -d /root/.local/share/mise/installs/ruby ]]; then
  export HOME=/root
fi
if ! command -v ruby >/dev/null 2>&1 || ! command -v bundle >/dev/null 2>&1; then
  ruby_install_base="$HOME/.local/share/mise/installs/ruby"
  if [[ -d "$ruby_install_base" ]]; then
    # Use an installed Bundler runtime; no network downloads or fixed Ruby patch.
    mapfile -t ruby_bundle_bins < <(find "$ruby_install_base" -mindepth 3 -maxdepth 3 \
      -type f -path '*/bin/bundle' | sort -V)
    if (( ${#ruby_bundle_bins[@]} )); then
      export PATH="$(dirname "${ruby_bundle_bins[-1]}"):$PATH"
    fi
  fi
fi
if ! command -v ruby >/dev/null 2>&1 || ! command -v bundle >/dev/null 2>&1; then
  echo "RAILS8_RUNTIME_ERROR: Ruby and Bundler are not installed" >&2
  return 1
fi
# Dedicated local gem directory survives moves between Colab workspaces.
export BUNDLE_PATH="${BUNDLE_PATH:-$(dirname "$repo")/.rails8-gems}"
