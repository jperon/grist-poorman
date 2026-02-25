#!/usr/bin/env sh

cd /srv/grist || exit 1

rm -f persist/docs/*-backup.grist

ls persist/docs/*.grist | while read f ; do docker compose exec grist /grist/cli history prune /"${f}" 10 ; done

docker compose pull grist

docker build --network=host -t grist-nginx openresty

docker compose down ; docker compose up -d

docker image prune -f
