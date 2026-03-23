#!/usr/bin/env bash
# Provides project ID sanitization and validation for a google cloud project.
# When run directly, it prompts for a project ID and prints the normalized result.

sanitize_project_id() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g' \
    | sed -E 's/^-+//; s/-+$//; s/-+/-/g'
}

validate_project_id_format() {
  [[ "$1" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
}

validation_main() {
  local raw_id sanitized
  read -r -p "Project ID to validate: " raw_id
  sanitized="$(sanitize_project_id "$raw_id")"
  printf "Sanitized: %s\n" "$sanitized"
  if validate_project_id_format "$sanitized"; then
    printf "Valid: yes\n"
  else
    printf "Valid: no\n"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  validation_main "$@"
fi
