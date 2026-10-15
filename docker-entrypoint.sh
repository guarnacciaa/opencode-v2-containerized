#!/bin/sh
# Entrypoint: forwards everything to `opencode`, with smart defaults for `serve`.
#
#   No args (default)      -> serve --hostname $OPENCODE_HOSTNAME --port $OPENCODE_PORT
#   serve [flags]           -> missing --hostname/--port are filled from env (explicit flags win)
#   anything else           -> passed through untouched (e.g. --version, run, attach)
#
# Configurable environment:
#   OPENCODE_HOSTNAME          default 0.0.0.0 (upstream binds 127.0.0.1: unreachable from host)
#   OPENCODE_PORT              default 4096
#   OPENCODE_SERVER_PASSWORD   no default: without it (or OPENCODE_PASSWORD) a random
#                              password is generated on every start (see container logs)
set -e

if [ "$#" -eq 0 ]; then
  set -- serve
fi

if [ "$1" = "serve" ]; then
  shift
  has_hostname=false
  has_port=false
  for arg in "$@"; do
    case "$arg" in
      --hostname | --hostname=*) has_hostname=true ;;
      --port | --port=*) has_port=true ;;
    esac
  done
  if [ "$has_hostname" = "false" ]; then
    set -- --hostname "${OPENCODE_HOSTNAME:-0.0.0.0}" "$@"
  fi
  if [ "$has_port" = "false" ]; then
    set -- --port "${OPENCODE_PORT:-4096}" "$@"
  fi
  set -- serve "$@"

  if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ] && [ -z "${OPENCODE_PASSWORD:-}" ]; then
    echo "WARNING: no OPENCODE_SERVER_PASSWORD (or OPENCODE_PASSWORD) set;" >&2
    echo "WARNING: the server will generate a random password on every start (see logs)." >&2
  fi
fi

exec opencode "$@"
