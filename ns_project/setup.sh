sudo docker build -t test .
docker create -it --cap-add=NET_ADMIN --name BRGr --net=none --privileged test
docker create -it --cap-add=NET_ADMIN --name Router --net=none --privileged test
docker create -it --cap-add=NET_ADMIN --name EdgeRouter --net=none --privileged test
docker create -it --cap-add=NET_ADMIN --name BRG2 --net=none --privileged test
docker create -it --cap-add=NET_ADMIN --name BRG1 --net=none --privileged test
docker create -it --cap-add=NET_ADMIN --name H1 --net=none --privileged test
docker create -it --cap-add=NET_ADMIN --name H2 --net=none --privileged test
docker start H1 H2 BRG1 BRG2 EdgeRouter Router BRGr

sudo modprobe fou
sudo iptables -P FORWARD ACCEPT

sudo ip link add br0 type bridge
sudo ip link add veth1 type veth peer name BRG1-eth1
sudo ip link add veth0 type veth peer name ERouter-eth1
sudo ip link add veth2 type veth peer name BRG2-eth1
sudo ip link add BRGr-eth0 type veth peer name Veth

sudo ip link add BRG1-eth0 type veth peer name H1-eth0
sudo ip link add BRG2-eth0 type veth peer name H2-eth0
sudo ip link add ERouter-eth0 type veth peer name Router-eth0
sudo ip link add Router-eth1 type veth peer name BRGr-eth1

sudo ip link set ERouter-eth1 netns $(sudo docker inspect -f '{{.State.Pid}} ' EdgeRouter)
sudo ip link set ERouter-eth0 netns $(sudo docker inspect -f '{{.State.Pid}} ' EdgeRouter)
sudo ip link set BRG1-eth1 netns $(sudo docker inspect -f '{{.State.Pid}} ' BRG1)
sudo ip link set BRG1-eth0 netns $(sudo docker inspect -f '{{.State.Pid}} ' BRG1)
sudo ip link set BRG2-eth1 netns $(sudo docker inspect -f '{{.State.Pid}} ' BRG2)
sudo ip link set BRG2-eth0 netns $(sudo docker inspect -f '{{.State.Pid}} ' BRG2)
sudo ip link set H1-eth0 netns $(sudo docker inspect -f '{{.State.Pid}} ' H1)
sudo ip link set H2-eth0 netns $(sudo docker inspect -f '{{.State.Pid}} ' H2)
sudo ip link set Router-eth0 netns $(sudo docker inspect -f '{{.State.Pid}} ' Router)
sudo ip link set Router-eth1 netns $(sudo docker inspect -f '{{.State.Pid}} ' Router)
sudo ip link set BRGr-eth1 netns $(sudo docker inspect -f '{{.State.Pid}} ' BRGr)
sudo ip link set BRGr-eth0 netns $(sudo docker inspect -f '{{.State.Pid}} ' BRGr)

sudo docker exec -it H1 ip link set H1-eth0 up
sudo docker exec -it H2 ip link set H2-eth0 up
sudo docker exec -it BRG1 ip link set BRG1-eth0 up
sudo docker exec -it BRG1 ip link set BRG1-eth1 up
sudo docker exec -it BRG2 ip link set BRG2-eth0 up
sudo docker exec -it BRG2 ip link set BRG2-eth1 up
sudo docker exec -it EdgeRouter ip link set ERouter-eth1 up
sudo docker exec -it EdgeRouter ip link set ERouter-eth0 up
sudo docker exec -it Router ip link set Router-eth1 up
sudo docker exec -it Router ip link set Router-eth0 up
sudo docker exec -it BRGr ip link set BRGr-eth1 up
sudo docker exec -it BRGr ip link set BRGr-eth0 up

sudo docker exec -it EdgeRouter ip addr add 172.27.0.1/24 dev ERouter-eth1
sudo docker exec -it EdgeRouter ip addr add 140.114.0.1/24 dev ERouter-eth0
sudo docker exec -it Router ip addr add 140.114.0.2/24 dev Router-eth0
sudo docker exec -it Router ip addr add 140.113.0.1/24 dev Router-eth1
sudo docker exec -it BRGr ip addr add 140.113.0.2/24 dev BRGr-eth1
sudo docker exec -it EdgeRouter route add -net 140.113.0.0/24 gw 140.114.0.2
sudo docker exec -it BRGr route add -net 140.114.0.0/24 gw 140.113.0.1
sudo docker exec -it BRGr route add default dev BRGr-eth0

sudo ip link set dev veth0 master br0
sudo ip link set dev veth1 master br0
sudo ip link set dev veth2 master br0
sudo ip link set dev veth0 up
sudo ip link set dev veth1 up
sudo ip link set dev veth2 up
sudo ip link set dev Veth up
sudo ip link set br0 up

sudo docker exec -it EdgeRouter iptables -t nat -A POSTROUTING -o ERouter-eth0 -j MASQUERADE

sudo ip addr add 20.0.0.1/24 dev Veth
sudo docker exec -it BRGr route add -net 0.0.0.0/0 gw 20.0.0.1
sudo iptables -t nat -A POSTROUTING -s 20.0.0.0/8 -j MASQUERADE

sudo docker cp dhcpd_edge.conf EdgeRouter:/dhcpd.conf
sudo docker exec -it EdgeRouter touch /var/lib/dhcp/dhcpd.leases
sudo docker exec -it EdgeRouter /usr/sbin/dhcpd 4 -pf /run/dhcp-server-dhcpd.pid -cf ./dhcpd.conf ERouter-eth1
sudo /usr/sbin/dhcpd 4 -pf /run/dhcp-server-dhcpd.pid -cf ./dhcpd.conf Veth

#sudo docker exec -it BRG1 dhclient BRG1-eth1 -v
#sudo docker exec -it BRG2 dhclient BRG2-eth1 -v
#static route for BRG1,2
sudo docker exec -it BRG1 ip addr add 172.27.0.2/24 dev BRG1-eth1
sudo docker exec -it BRG2 ip addr add 172.27.0.3/24 dev BRG2-eth1
sudo docker exec -it BRG1 route add -net 140.0.0.0/8 gw 172.27.0.1
sudo docker exec -it BRG2 route add -net 140.0.0.0/8 gw 172.27.0.1

sudo docker cp send_udp.sh BRG1:/send_udp_GRE1.sh
sudo docker cp send_udp.sh BRG2:/send_udp_GRE2.sh
sudo docker cp packet_capture BRGr:/packet_capture
#flush iptable: sudo iptables -t nat -F
#check iptable: sudo iptables -t nat -nvL
sudo docker cp tunnel_BRG1.sh BRG1:/tunnel_BRG1.sh
sudo docker cp tunnel_BRG2.sh BRG2:/tunnel_BRG2.sh
sudo docker exec -it BRG1 bash tunnel_BRG1.sh
sudo docker exec -it BRG2 bash tunnel_BRG2.sh

#sudo docker exec -it BRGr ip fou add port 50000 ipproto 47
#sudo docker exec -it BRGr ip link add GRE1 type gretap remote 140.114.0.1 local 140.113.0.2 key 1 encap fou encap-sport 50000 encap-dport 30000
#sudo docker exec -it BRGr ip link set GRE1 up
#sudo docker exec -it BRGr ip link add br1 type bridge
#sudo docker exec -it BRGr brctl addif br1 BRGr-eth0
#sudo docker exec -it BRGr brctl addif br1 GRE1
#sudo docker exec -it BRGr ip link set br1 up

#sudo docker exec -it BRGr ip fou add port 40000 ipproto 47
#sudo docker exec -it BRGr ip link add GRE2 type gretap remote 140.114.0.1 local 140.113.0.2 key 2 encap fou encap-sport 40000 encap-dport 20000
#sudo docker exec -it BRGr ip link set GRE2 up
#sudo docker exec -it BRGr brctl addif br1 GRE2i

#sudo docker exec -it H1 dhclient H1-eth0 -v
#sudo docker exec -it H2 dhclient H2-eth0 -v
