# OpenWRT in Docker

Inspired by other projects that run `hostapd` in a Docker container. This goes one step further and boots a full network OS intended for embedded devices called [OpenWRT](https://openwrt.org/), so you can manage all aspects of your network from a user-friendly web UI.

I only tested this on x86_64, but it might work on ARM too with some minor tweaking.


## Dependencies

* docker
* iw
* iproute2
* envsubst (part of `gettext` or `gettext-base` package)
* dhcpcd

## Build
```
$ make build
```
If you want additional OpenWRT packages to be present in the base image, add them to the Dockerfile. Otherwise you can install them with `opkg` after bringing up the container.

A searchable package list is available on [openwrt.org](https://openwrt.org/packages/table/start).

## Configure

Initial configuration is performed using a config file, `openwrt.conf`. Values read from this file at runtime are used to generate OpenWRT format config files.

To add or change the base configuration, modify the config templates in `etc/config/<section>.tpl`.

You can of course make persistent changes in the UI and download a backup of your full router configuration by navigating to System > Backup / Flash Firmware and clicking Backup.

## Run
```
$ make run
```

If you arrive at `* Ready`, point your browser to http://openwrt.home (or whatever you set in `LAN_DOMAIN`) and you should be presented with the login page. The default login is `root` with the password set as `ROOT_PW`.

To shut down the router, press `Ctrl+C`. Any settings you configured or additional packages you installed will persist until you run `make clean`, which will delete the container.

## Install / Uninstall
```
$ make install
```
Install and uninstall targets for `systemd` have been included in the Makefile.

Installing will create and enable a service pointing to wherever you cloned this directory and execute `run.sh` on boot.

## Cleanup
```
$ make clean
```
This will delete the container and all associated Docker networks so you can start fresh if you screw something up.

---

## Notes

### Hairpinning

This took a couple of tries to get working. The most challenging issue was getting traffic from WLAN clients to reach each other.

In order for this to work, OpenWRT bridges all interfaces in the LAN zone and sets hairpin mode (aka [reflective relay](https://lwn.net/Articles/347344/)) on the WLAN interface, meaning packets arriving on that interface can be 'reflected' back out through the same interface.
OpenWRT is not able to set this mode from inside the container even with `NET_ADMIN` capabilities, so this must be done from the host. 

`run.sh` tries to handle this, and prints a warning if it fails.

### Network namespace

For `hostapd` running inside the container to have access to the physical wireless device, we need to set the device's network namespace to the PID of the running container. This causes the interface to 'disappear' from the primary network namespace for the duration of the container's parent process. `run.sh` checks if the host is using NetworkManager to manage the wifi interface, and tries to steal it away if so.

### Troubleshooting

Logs are redirected to `stdout` so the Docker daemon can process them. They are accessible with:
```
$ docker logs ${CONTAINER} [-f]
```

As an alternative to installing debug packages inside your router, it's possible to execute commands available to the host inside the network namespace. A symlink is created in `/var/run/netns/<container_name>` for convenience:

```
$ sudo ip netns exec ${CONTAINER} tcpdump -vvi any 
```
---
## [OpenVPN Howto](./vpn.md)

## [Bandwidth Monitoring Howto](./monitoring.md)

## [Monitoring with InfluxDB + Grafana](./monitoring/README.md)

## [IPv6 Notes](./ipv6.md)