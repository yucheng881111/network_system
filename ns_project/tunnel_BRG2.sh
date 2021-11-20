server_ip=$(ifconfig | sed -n '9p' | awk '{print $2;}')
ip fou add port 20000 ipproto 47
ip link add GRE2 type gretap remote 140.113.0.2 local $server_ip key 2 encap fou encap-sport 20000 encap-dport 40000
ip link set GRE2 up
ip link add br1 type bridge
brctl addif br1 BRG2-eth0
brctl addif br1 GRE2
ip link set br1 up
echo "GRE2 src port 20000, dst port 40000."
