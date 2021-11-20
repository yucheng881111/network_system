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
int tunnel_cnt = 0;

char *dev;
pcap_t *descr;
char errbuf[PCAP_ERRBUF_SIZE];

struct bpf_program fp;   /* The compiled filter expression */
bpf_u_int32 mask;    /* The netmask of our sniffing device */
bpf_u_int32 net;
string update_filter = "ip proto gre and not src host 140.113.0.1 and not src 140.113.0.2"; /* The filter expression */

void packetHandler(u_char * arg, const struct pcap_pkthdr * pkthdr, const u_char * packet){
    cout<<endl<<endl;
    printf("Packet length: %d\n", pkthdr->len);
    printf("Number of bytes: %d\n", pkthdr->caplen);
    printf("Recieved time: %s\n", ctime((const time_t *)&pkthdr->ts.tv_sec));
    //print packet
    int i;
    for(i=0; i<pkthdr->len; ++i) {
        printf(" %02x", packet[i]);
        if( (i + 1) % 16 == 0 )
            printf("\n");
    }
    printf("\n\n");

    
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
    
    u_char *gre_type = (u_char*)(packet + sizeof(struct ether_header) + sizeof(struct ip));
    cout<<"\nGRE type: ";
    string type;
    type+=to_string((int)gre_type[2]);
    type+=to_string((int)gre_type[3]);
    if (type == "10188"){
      cout<<"Transparent Ethernet Bridging"<<endl;
    } else {
      for(int i=0;i<4;++i){
        printf(" %02x", gre_type[i]);
      }
      cout<<endl;
    }
    cout<<endl;
    /*
    Reserved                            0000
    SNA                                 0004
    OSI network layer                   00FE
    PUP                                 0200
    XNS                                 0600
    IP                                  0800
    Chaos                               0804
    RFC 826 ARP                         0806
    Frame Relay ARP                     0808
    VINES                               0BAD
    VINES Echo                          0BAE
    VINES Loopback                      0BAF
    DECnet (Phase IV)                   6003
    Transparent Ethernet Bridging       6558
    Raw Frame Relay                     6559
    Apollo Domain                       8019
    Ethertalk (Appletalk)               809B
    Novell IPX                          8137
    RFC 1144 TCP/IP compression         876B
    IP Autonomous Systems               876C
    Secure Data                         876D
    Reserved                            FFFF
    */

    const struct ether_header* Inner_ethernetHeader;
    const struct ip* Inner_ipHeader;
    char Inner_sourceIp[INET_ADDRSTRLEN];
    char Inner_destIp[INET_ADDRSTRLEN];

    Inner_ethernetHeader = (struct ether_header*)(packet + sizeof(struct ether_header) + sizeof(struct ip) + 4);
    cout << "Inner Source MAC: " << ether_ntoa((struct ether_addr*)Inner_ethernetHeader->ether_shost) << endl;
    cout << "Inner Destination MAC: " << ether_ntoa((struct ether_addr*)Inner_ethernetHeader->ether_dhost) << endl;

    if (ntohs(Inner_ethernetHeader->ether_type) == 2048) {
      cout << "Inner Ethernet type: IPv4" << endl;
    } else if (ntohs(Inner_ethernetHeader->ether_type) == 2054) {
      cout << "Inner Ethernet type: ARP" << endl;
    } else if (ntohs(Inner_ethernetHeader->ether_type) == 34525) {
      cout << "Inner Ethernet type: IPv6" << endl;
    } else {
      cout << "Inner Ethernet type: " << ntohs(Inner_ethernetHeader->ether_type) << endl;
    }

    if (ntohs(Inner_ethernetHeader->ether_type) == 2048) {
      Inner_ipHeader = (struct ip*)(packet + sizeof(struct ether_header) + sizeof(struct ip) + 4 + sizeof(struct ether_header));
      inet_ntop(AF_INET, &(Inner_ipHeader->ip_src), Inner_sourceIp, INET_ADDRSTRLEN);
      inet_ntop(AF_INET, &(Inner_ipHeader->ip_dst), Inner_destIp, INET_ADDRSTRLEN);
      
      cout << "Inner Src IP " <<Inner_sourceIp << endl;
      cout << "Inner Dst IP " <<Inner_destIp << endl;
    }
    
    // create tunnel
    if (ntohs(ethernetHeader->ether_type) == 2048) {
      string s = "ip link add GRE" + to_string(tunnel_cnt) + " type gretap remote " + string(sourceIp) + " local 140.113.0.1";
      system(s.c_str());

      s = "ip link set GRE" + to_string(tunnel_cnt) + " up";
      system(s.c_str());
      
      if ( tunnel_cnt < 1 ){
        system("ip link add br0 type bridge");

        system("brctl addif br0 BRGr-eth0");
      }

      s = "brctl addif br0 GRE" + to_string(tunnel_cnt);
      system(s.c_str());

      system("ip link set br0 up");

      cout<<"Tunnel " + string(sourceIp) + " to BRGr created." << endl;
      tunnel_cnt++;

      // update filter
      update_filter += (" and not src " + string(sourceIp));
      
      const char* filter_exp = update_filter.c_str();
      if (pcap_compile(descr, &fp, filter_exp, 0, net) == -1) {
        fprintf(stderr, "Couldn't parse filter %s: %s\n", filter_exp, pcap_geterr(descr));
        return;
      }
      
      if (pcap_setfilter(descr, &fp) == -1) {
        fprintf(stderr, "Couldn't install filter %s: %s\n", filter_exp, pcap_geterr(descr));
        return;
      }
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
  string filter;
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




