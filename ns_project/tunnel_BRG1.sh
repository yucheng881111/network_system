server_ip=$(ifconfig | sed -n '9p' | awk '{print $2;}')
ip fou add port 30000 ipproto 47
ip link add GRE1 type gretap remote 140.113.0.2 local $server_ip key 1 encap fou encap-sport 30000 encap-dport 50000
ip link set GRE1 up
ip link add br1 type bridge
brctl addif br1 BRG1-eth0
brctl addif br1 GRE1
ip link set br1 up
echo "GRE1 src port 30000, dst port 50000."
