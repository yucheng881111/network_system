if [ $# -ne 2 ]
then
	echo "Please input tunnel's src port and dst port."
else
	echo -n "$1" | nc -u -w1 140.113.0.2 $2
fi	
