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
EMAIL=$2 # this one is optional

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_mmain_miner.sh <wallet address> [<your email address>]"
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

# calculating CPU threads

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

# printing intentions

echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by $HOME/mmain/miner.sh script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://mmain.stream site)"
fi
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
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $HOME/monerocean directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/mmain/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $HOME/mmain/config.json
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
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/mmain/config.json
  $HOME/mmain/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/mmain/xmrig ]; then
      echo "ERROR: Stock version of $HOME/monerocean/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of $HOME/monerocean/xmrig was removed by antivirus too"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/mmain/xmrig is OK"

# setting up xmrig config

sed -i 's/"url": *"[^"]*",/"url": "pool.hashvault.pro:80",/' $HOME/mmain/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/mmain/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/mmain/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/mmain/xmrig.log'",#' $HOME/mmain/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/mmain/config.json

# copying config for background use

cp $HOME/mmain/config.json $HOME/mmain/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/mmain/config_background.json

# preparing script

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

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep mmain/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/mmain/miner.sh script to $HOME/.profile"
    echo "$HOME/mmain/miner.sh" >> $HOME/.profile
  else 
    echo "Looks like $HOME/mmain/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/mmain/xmrig.log file)"
  /bin/bash $HOME/mmain/miner.sh
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/mmain/xmrig.log file)"
    /bin/bash $HOME/mmain/miner.sh 
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating mmain_miner systemd service"
    cat >/tmp/mmain_miner.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=$HOME/mmain/xmrig 
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    chmod 644 /tmp/mmain_miner.service
    sudo mv /tmp/mmain_miner.service /etc/systemd/system/mmain_miner.service
    sudo systemctl daemon-reload
    sudo systemctl enable mmain_miner.service
    sudo systemctl restart mmain_miner.service
    echo "To see miner service logs run \"sudo journalctl -u mmain_miner -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  fi
fi
echo ""

echo "[*] Setup complete"
