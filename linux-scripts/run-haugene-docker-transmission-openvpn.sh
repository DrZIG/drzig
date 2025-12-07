#!/bin/bash

docker run --cap-add=NET_ADMIN -d \
              -v /data/:/data \
              -v /data/vpn-transmission/:/config \
              -e TRANSMISSION_DOWNLOAD_DIR=/data/yandex.disk/bluevps \
              -e TRANSMISSION_INCOMPLETE_DIR=/data/transmission/incomplete \
              -e OPENVPN_PROVIDER=NORDVPN \
              -e NORDVPN_COUNTRY=NL \
              -e NORDVPN_PROTOCOL=tcp \
              -e NORDVPN_CATEGORY=legacy_p2p \
              -e OPENVPN_USERNAME=$OPENVPN_USERNAME \
              -e OPENVPN_PASSWORD=$OPENVPN_PASSWORD \
              -e TRANSMISSION_RPC_USERNAME=$TRANSMISSION_USERNAME \
              -e TRANSMISSION_RPC_PASSWORD=$TRANSMISSION_PASSWORD \
              -e LOCAL_NETWORK=192.168.0.0/16 \
              --log-driver json-file \
              --log-opt max-size=10m \
              -p 127.0.0.1:9091:9091 \
              haugene/transmission-openvpn
