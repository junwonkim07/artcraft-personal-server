#!/usr/bin/env bash
# Creates Elasticsearch indexes from upstream _database/elasticsearch/index_definitions/*.json.
# Index names are the file basenames (e.g. media_files_v1, see
# crates/schema/database/elasticsearch_schema/src/documents/media_file_document.rs).
# Upstream definitions use number_of_replicas=2; on a single node we set replicas to 0 afterwards.
set -euo pipefail
ES="${ELASTICSEARCH_URL:?ELASTICSEARCH_URL is required}"
for f in /app/_database/elasticsearch/index_definitions/*.json; do
  idx="$(basename "$f" .json)"
  if curl -fsS -o /dev/null "${ES}/${idx}"; then
    echo "index ${idx} exists"
  else
    curl -fsS -X PUT "${ES}/${idx}" -H 'Content-Type: application/json' --data-binary "@${f}" >/dev/null
    echo "created index ${idx}"
  fi
  curl -fsS -X PUT "${ES}/${idx}/_settings" -H 'Content-Type: application/json' \
    -d '{"index":{"number_of_replicas":0}}' >/dev/null
done
