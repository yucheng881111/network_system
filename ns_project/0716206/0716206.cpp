#include <bits/stdc++.h>
#include <pcap.h>
#include <net/ethernet.h>
#include <netinet/ip.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netinet/ether.h>
#include <arpa/inet.h>

using namespace std;

int packetCount = 0;
int tunnel_cnt = 1;

char *dev;
pcap_t *descr;
char errbuf[PCAP_ERRBUF_SIZE];

struct bpf_program fp;   /* The compiled filter expression */
bpf_u_int32 mask;    /* The netmask of our sniffing device */
bpf_u_int32 net;
string filter; /* The filter expression */
int power(int t, int p){
  int k=1;
  for(int i=0;i<p;i++){
    k*=t;
  }
  return k;
}

string b_to_int(string s){
  int tmp = 2;
  int p = 0;
  int ans = 0;
  for(int i=s.size()-1 ; i>=0 ; i--){
    ans += ((int)s[i]-48) * power(tmp,p);
    p++;
  }
  return to_string(ans);
}

void packetHandler(u_char * arg, const struct pcap_pkthdr * pkthdr, const u_char * packet){
    cout<<endl<<endl;
    printf("Packet length: %d\n", pkthdr->len);
    printf("Number of bytes: %d\n", pkthdr->caplen);
    printf("Recieved time: %s\n", ctime((const time_t *)&pkthdr->ts.tv_sec));
    //print packet
    int i;
    string dst_port="";
    string src_port="";
    for(i=0; i<pkthdr->len; ++i) {
        printf(" %02x", packet[i]);
        if (i >= 36 && i <= 37){
          bitset<8> b(packet[i]);
          dst_port += b.to_string();
        }
        

        if ( i>=42 ){
          int t = (int)packet[i];
          char tmp = t;
          src_port += tmp;
        }

        if( (i + 1) % 16 == 0 )
            printf("\n");
    }
    printf("\n\n");
    dst_port = b_to_int(dst_port);
    
    const struct ether_header* ethernetHeader;
    const struct ip* ipHeader;
    char sourceIp[INET_ADDRSTRLEN];
    char destIp[INET_ADDRSTRLEN];

    ethernetHeader = (struct ether_header*)packet;
    cout << "Source MAC: " << ether_ntoa((struct ether_addr*)ethernetHeader->ether_shost)  << endl;
    cout << "Destination MAC: " << ether_ntoa((struct ether_addr*)ethernetHeader->ether_dhost) << endl;

    if (ntohs(ethernetHeader->ether_type) == 2048) {
      cout << "Ethernet type: IPv4" << endl;
    } else {
      cout << "Ethernet type: " << ntohs(ethernetHeader->ether_type) << endl;
    }

    if (ntohs(ethernetHeader->ether_type) == 2048) {
      ipHeader = (struct ip*)(packet + sizeof(struct ether_header));
      inet_ntop(AF_INET, &(ipHeader->ip_src), sourceIp, INET_ADDRSTRLEN);
      inet_ntop(AF_INET, &(ipHeader->ip_dst), destIp, INET_ADDRSTRLEN);

      // print the results
      cout << "Src IP " << sourceIp << endl;
      cout << "Dst IP " << destIp << endl;
    }
    cout<<"tunnel dst port: "<<src_port<<endl;
    cout<<"tunnel src port: "<<dst_port<<endl;
    
    // create tunnel

    string cmd = "ip fou add port "+ dst_port +" ipproto 47";
    system(cmd.c_str());
    cmd = "ip link add GRE" + to_string(tunnel_cnt) + " type gretap remote " + string(sourceIp) + " local 140.113.0.2 key "+ to_string(tunnel_cnt) +" encap fou encap-sport "+ dst_port +" encap-dport "+ src_port; 
    system(cmd.c_str());
    cmd = "ip link set GRE" + to_string(tunnel_cnt) + " up";
    system(cmd.c_str());
    if(tunnel_cnt == 1){
        system("ip link add br1 type bridge");
        system("brctl addif br1 BRGr-eth0");
    }
    cmd = "brctl addif br1 GRE" + to_string(tunnel_cnt);
    system(cmd.c_str());
    if(tunnel_cnt == 1){
        system("ip link set br1 up");
    }
    cout<<"\nCreate tunnel " << string(sourceIp) << ":" << src_port << " to " << "140.113.0.2:" << dst_port << endl;
    tunnel_cnt++;

    //update filter
    string temp = filter;
    filter = temp + " and not port " + dst_port;
    const char* filter_exp = filter.c_str();
    if (pcap_compile(descr, &fp, filter_exp, 0, net) == -1) {
      fprintf(stderr, "Couldn't parse filter %s: %s\n", filter_exp, pcap_geterr(descr));
      return;
    }
      
    if (pcap_setfilter(descr, &fp) == -1) {
      fprintf(stderr, "Couldn't install filter %s: %s\n", filter_exp, pcap_geterr(descr));
      return;
    }
    
}

int main(int argc, char **argv) {

  pcap_if_t *iface, *devs;
  if (pcap_findalldevs(&devs, errbuf) == -1 || !devs) {
    fprintf(stderr, "No network devices are currently connected.\n");
    return 1;
  }

  cout<<"Interfaces:\n";
  char *devices[100];
  int i;
  for (i = 1, iface = devs; iface; iface = iface->next){
    printf("%2d : %s\n", i++, iface->name);
    devices[i]=(char *)iface->name;
  }

  cout<<"Select an interface: ";
  int s;
  cin>>s;
  s++;
  dev=devices[s];

  cout<<"\nUsing interface: "<<dev<<endl;

  descr = pcap_open_live(dev, BUFSIZ, 0, -1, errbuf);
  if (descr == NULL) {
      cout << "pcap_open_live() failed: " << errbuf << endl;
      return 1;
  }

  cout<<"BPF filtering expression: ";
  
  cin.ignore();
  getline(cin,filter);
  
  const char* filter_exp=filter.c_str();
  if (pcap_compile(descr, &fp, filter_exp, 0, net) == -1) {
     fprintf(stderr, "Couldn't parse filter %s: %s\n", filter_exp, pcap_geterr(descr));
     return 1;
  }
  
  if (pcap_setfilter(descr, &fp) == -1) {
     fprintf(stderr, "Couldn't install filter %s: %s\n", filter_exp, pcap_geterr(descr));
     return 1;
  }

  if (pcap_loop(descr, -1, packetHandler, NULL) < 0) {
      cout << "pcap_loop() failed: " << pcap_geterr(descr);
      return 1;
  }

  cout << "capture finished" << endl;

  return 0;
}




