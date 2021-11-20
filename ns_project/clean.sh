docker stop $(docker ps -a -q)
docker rm $(docker ps -a -q)
sudo ip link del br0
sudo iptables -t nat -F
sudo kill -9 `ps aux | grep dhcpd | awk '{print $2}'`
