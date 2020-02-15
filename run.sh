#!/bin/bash

source .env
IFACE=$WIFI_IFACE

function _usage {
  echo "$0 [interface_name]"
  exit 1
}

function _get_phy_from_dev {
  if [[ -f /sys/class/net/$IFACE/phy80211/name ]] ; then
    PHY=$(cat /sys/class/net/$IFACE/phy80211/name 2>/dev/null)
    echo "* got '$PHY' for device '$IFACE'"
  else
    echo "$IFACE is not a valid phy80211 device"
    exit 1
  fi
}

# we need this because openwrt renames the interface
function _get_dev_from_phy {
  for dev in /sys/class/net/*; do
    test -f $dev/phy80211/name && phy=$(cat $dev/phy80211/name 2>/dev/null)
    if [[ "$phy" = "$1" ]]; then
      IFACE_NEW=$(basename $dev)
      break
    else
      IFACE_NEW=''
    fi
  done
}

function _cleanup {
  echo -e "\n* cleaning up..."
  echo "* stopping container"
  docker stop openwrt_1 >/dev/null
  # echo "* deleting network"
  # docker network rm $NET_NAME >/dev/null
  echo -n "* restoring network interface name.."
  retries=15
  while [[ retries -ge 0 && -z $IFACE_NEW ]]; do
    _get_dev_from_phy $PHY
    sleep 1
    let "retries--"
    echo -n '.'
  done
  if [[ $retries -lt 0 ]]; then
    echo -e "\nERROR: problem restoring interface name, you may need to restore it manually."
    exit 1
  fi
  sudo ip link set dev $IFACE_NEW down
  sudo ip link set dev $IFACE_NEW name $IFACE
  echo " ok"
  echo -ne "* finished"
}

function _create_or_start_container {
  echo "* setting up docker network"
  docker network create --driver macvlan \
    -o parent=$NET_PARENT \
    --gateway $NET_GW \
    --subnet $NET_SUBNET \
      $NET_NAME 2>/dev/null

  sudo ip link add macvlan0 link $NET_PARENT type macvlan mode bridge
  sudo ip addr add $NET_HOST/24 dev macvlan0
  sudo ip link set macvlan0 up
  sudo ip route add $NET_ADDR/32 dev macvlan0

  docker inspect $CONTAINER >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "* starting container '$CONTAINER'"
    docker start $CONTAINER
  else
    echo "* creating container $CONTAINER"
    docker run -d \
      --network $NET_NAME \
      -p2222:22 \
      -p8080:80 \
      --env-file .env \
      -e WIFI_PHY=$PHY \
      --cap-add NET_ADMIN \
      --cap-add NET_RAW \
      --hostname openwrt\
      --name $CONTAINER openwrt >/dev/null
  fi
}

function main {
  test -z $IFACE && _usage

  _get_phy_from_dev

  echo "* setting interface '$IFACE' to unmanaged"
  nmcli dev set $IFACE managed no

  _create_or_start_container

  echo "* moving device $PHY to docker network namespace"
  pid=$(docker inspect -f '{{.State.Pid}}' $CONTAINER)
  sudo iw phy "$PHY" set netns $pid
  docker exec $CONTAINER /etc/init.d/network restart

  echo "* ready"
}

main
trap "_cleanup" EXIT
tail --pid=$pid -f /dev/null