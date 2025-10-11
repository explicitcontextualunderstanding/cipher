#!/usr/bin/env bash
set -euo pipefail

# Universal entrypoint: export any *_API_KEY_FILE into *_API_KEY
# Uses bash's compgen builtin when available, and falls back to parsing env
if command -v compgen >/dev/null 2>&1; then
  file_vars=$(compgen -e | grep '_API_KEY_FILE$' || true)
else
  file_vars=$(env | awk -F= '/_API_KEY_FILE$/{print $1}' || true)
fi

for file_var in $file_vars; do
  key_var="${file_var%_FILE}"
  # Indirect expansion to get the file path value
  file_path="${!file_var:-}"
  if [[ -n "$file_path" && -f "$file_path" ]]; then
    export "$key_var"="$(cat "$file_path")"
  else
    echo "Warning: secret file for $key_var not found at ${file_path:-'<unset>'}" >&2
  fi
done

# Execute the original command
exec "$@"
