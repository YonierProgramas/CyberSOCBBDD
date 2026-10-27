#!/usr/bin/env bash
set -Eeo pipefail
source /usr/local/bin/docker-entrypoint.sh

# La imagen oficial conserva su secuencia de inicio. Solo se detiene la creación
# de la BD con dos puertas controladas por el test; nunca mediante una demora fija.
eval "$(declare -f docker_setup_db | sed '1s/docker_setup_db/original_docker_setup_db/')"
wait_for_gate() {
  local gate="$1"
  for ((attempt=0; attempt<1200; attempt++)); do
    if [ -f "$gate" ]; then return 0; fi
    sleep 0.05
  done
  echo "Timeout de puerta de prueba: $gate" >&2
  return 1
}
docker_setup_db() {
  touch /tmp/cybersoc-before-db
  wait_for_gate /tmp/cybersoc-allow-db
  original_docker_setup_db
  touch /tmp/cybersoc-after-db
  wait_for_gate /tmp/cybersoc-allow-final
}
_main postgres
