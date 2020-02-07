#!/usr/bin/env bash

# Setup BCC tools
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4052245BD4284CDD
echo "deb https://repo.iovisor.org/apt/$(lsb_release -cs) $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/iovisor.list
sudo apt-get update
sudo apt-get install -y bcc-tools libbcc-examples linux-headers-$(uname -r) lnav
sudo apt-get install -y python-pip
sudo pip install --upgrade pip
sudo pip install magic-wormhole

echo "export PATH=$PATH:/usr/share/bcc/tools"

cat <<EOF | > /usr/bin/node-mon.sh
#!/usr/bin/env bash

trap "exit" INT TERM ERR
trap "kill 0" EXIT


/usr/share/bcc/tools/tcptop -C 1 >/var/log/io-tcptop.log 2>&1 &
/usr/share/bcc/tools/ext4slower -j 1 >/var/log/io-ext4slower-machine.log 2>&1 &
/usr/share/bcc/tools/ext4dist 1 >/var/log/io-ext4dist.log 2>&1 &
/usr/share/bcc/tools/biotop -C 1 >/var/log/io-biosnoop.log 2>&1 &
iotop -botqk >/var/log/io-iotop.log 2>&1 &
top -ba >/var/log/io-topbymem.log 2>&1 &


wait
EOF
chmod a+x /usr/bin/node-mon.sh
