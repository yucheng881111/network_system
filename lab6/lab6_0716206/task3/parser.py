import dpkt
import datetime
import socket
import sys
import math

def get_formatted_mac_addr(original_mac_addr):
    return ':'.join('%02x' % dpkt.compat.compat_ord(x) for x in original_mac_addr)

def print_packets(pcap):
    '''
    [TODO]: 
    1. Use MGMT_TYPE packets to calculate AP's mac addr / connection time / handoff times, and to collect beacon SNR
    2. Use DATA_TYPE packets to calculate total transmitted bytes / CDF of packets' SNR 
    3. Please do not print the SNR information in your submitted code, dump it to a file instead
    Note: As for SNR information, you only need to count downlink packets (but for all APs)
    '''
    
    # For each packet in the pcap process the contents
    for timestamp, buf in pcap:
        # radiotap -> ieee80211
        wlan_pkt = dpkt.radiotap.Radiotap(buf).data
        
        if(wlan_pkt.type == dpkt.ieee80211.MGMT_TYPE): 
            dst_mac_addr = get_formatted_mac_addr(wlan_pkt.mgmt.dst)
            src_mac_addr = get_formatted_mac_addr(wlan_pkt.mgmt.src)
            print('%8.6f WLAN-Pack-Mgmt: %s -> %s' % (timestamp, src_mac_addr, dst_mac_addr))
        
        elif(wlan_pkt.type == dpkt.ieee80211.DATA_TYPE):
            dst_mac_addr = get_formatted_mac_addr(wlan_pkt.data_frame.dst)
            src_mac_addr = get_formatted_mac_addr(wlan_pkt.data_frame.src)
            print('%8.6f WLAN-Pack-Data: %s -> %s' % (timestamp, src_mac_addr, dst_mac_addr))

            # ieee80211 -> llc
            llc_pkt = dpkt.llc.LLC(wlan_pkt.data_frame.data)
            if llc_pkt.type == dpkt.ethernet.ETH_TYPE_ARP:
                # llc -> arp
                arp_pkt = llc_pkt.data
                src_ip_addr = socket.inet_ntop(socket.AF_INET, arp_pkt.spa)
                dst_ip_addr = socket.inet_ntop(socket.AF_INET, arp_pkt.tpa)
                print('[ARP packet]: %s -> %s' % (src_ip_addr, dst_ip_addr))
            elif llc_pkt.type == dpkt.ethernet.ETH_TYPE_IP:
                # llc -> ip
                ip_pkt = llc_pkt.data
                src_ip_addr = socket.inet_ntop(socket.AF_INET, ip_pkt.src)
                dst_ip_addr = socket.inet_ntop(socket.AF_INET, ip_pkt.dst)
                src_port = ip_pkt.data.sport
                dst_port = ip_pkt.data.dport
                print('[IP packet] : %s:%s -> %s:%s' % (src_ip_addr, str(src_port), dst_ip_addr, str(dst_port)))
        
        elif(wlan_pkt.type == dpkt.ieee80211.CTL_TYPE):
            if wlan_pkt.subtype == dpkt.ieee80211.C_ACK:
                dst_mac_addr = get_formatted_mac_addr(wlan_pkt.ack.dst)
                src_mac_addr = ' '*17
            elif wlan_pkt.subtype == dpkt.ieee80211.C_CTS:
                dst_mac_addr = get_formatted_mac_addr(wlan_pkt.cts.dst)
                src_mac_addr = ' '*17
            elif wlan_pkt.subtype == dpkt.ieee80211.C_RTS:
                dst_mac_addr = get_formatted_mac_addr(wlan_pkt.rts.dst)
                src_mac_addr = get_formatted_mac_addr(wlan_pkt.rts.src)
            print('%8.6f WLAN-Pack-Ctrl: %s -> %s' % (timestamp, src_mac_addr, dst_mac_addr))

def MyParser(pcap):
    f = open('SNR.txt','w')

    total_trans1 = 0
    total_trans2 = 0
    AP = ''
    AP1 = ''
    AP2 = ''
    handoff = 0
    sum_rate = 0
    connect = False
    ts = []
    if pcap.datalink() == 127:         # RadioTap
        for timestamp, rawdata in pcap:
            tap = dpkt.radiotap.Radiotap(rawdata)

            t_len = str(rawdata[2:3]).replace('\'','').replace('b\\','0')
            t_len = int(t_len, 16)     # ratiotap length
            wlan = dpkt.ieee80211.IEEE80211(rawdata[t_len:])

            try:
                AP_now = get_formatted_mac_addr(wlan.mgmt.src)

                if AP1 == '' and wlan.subtype == 5: # Probe Response AP1
                    AP1 = AP_now
                    continue
                if AP2 == '' and wlan.subtype == 5: # Probe Response AP2
                    AP2 = AP_now
                    continue

                if wlan.subtype == 1:   # Association Response
                    if AP == '':
                        AP = AP_now
                    else:
                        if AP != AP_now:
                            handoff += 1
                            AP = AP_now
                    ts.append((AP_now, 'ass', timestamp))
                    connect = True
                elif wlan.subtype == 10: # Disassociate
                    AP_dst = get_formatted_mac_addr(wlan.mgmt.dst)
                    ts.append((AP_dst, 'dis', timestamp))
                    connect = False
                
            except:  # Data
                pass

            if wlan.type == dpkt.ieee80211.MGMT_TYPE:
                if wlan.subtype == 8:  # Beacon
                    snr = tap.ant_sig.db - tap.ant_noise.db
                    #print('SNR: ' + str(snr))
                    if get_formatted_mac_addr(wlan.mgmt.src) == AP and connect:
                        sum_rate += 0.1024 * 20 * math.log2(1 + (10 ** (snr/10)))

            elif wlan.type == dpkt.ieee80211.DATA_TYPE:
                llc_pkt = dpkt.llc.LLC(wlan.data_frame.data)
                if llc_pkt.type == dpkt.ethernet.ETH_TYPE_IP:                        # downlink udp
                    try:
                        f.write(str(tap.ant_sig.db - tap.ant_noise.db) + '\n')
                    except:                                                          # no snr: pass
                        pass

                    if AP == AP1:
                        total_trans1 += (len(llc_pkt.data)-20)
                    elif AP == AP2:
                        total_trans2 += (len(llc_pkt.data)-20)
                
            elif wlan.type == dpkt.ieee80211.CTL_TYPE:
                pass

    dur1 = 0
    dur2 = 0

    if ts[-1][1] == 'ass':
        ts.append((0,'dis',60))
    
    # if no disassociate
    ts_new = []
    for t in range(len(ts)):
        ts_new.append(ts[t])
        if t+1 < len(ts) and ts[t+1][1] == 'ass' and ts[t][1] == 'ass':
            temp = (ts[t][0], 'dis', ts[t+1][2])
            ts_new.append(temp)

    
    #for t in ts_new:
    #    print(t)
            


    for t in range(len(ts_new)-1):
        if t % 2 == 0:
            dur = ts_new[t+1][2] - ts_new[t][2]
            if ts_new[t][0] == AP1:
                dur1 += dur
            else:
                dur2 += dur

    
    if handoff == 0:
        print('[Connection statistics]')
        print('- AP1')
        print('  - MAC addr: %s' % AP1)
        print('  - Total connection duration: %.4fs' % dur1)
        print('  - Total transmitted bytes: %d bytes' % total_trans1)
        print('\n[Other statistics]')
        print('  - Number of handoff events: %d' % handoff)
        print('  - Theoretical sum-rate: %d mbps' % int(math.floor(sum_rate/60)))
    else:
        print('[Connection statistics]')
        print('- AP1')
        print('  - MAC addr: %s' % AP1)
        print('  - Total connection duration: %.4fs' % dur1)
        print('  - Total transmitted bytes: %d bytes' % total_trans1)
        print('- AP2')
        print('  - MAC addr: %s' % AP2)
        print('  - Total connection duration: %.4fs' % dur2)
        print('  - Total transmitted bytes: %d bytes' % total_trans2)
        print('\n[Other statistics]')
        print('  - Number of handoff events: %d' % handoff)
        print('  - Theoretical sum-rate: %d mbps' % int(math.floor(sum_rate/60)))



if __name__ == '__main__':
    with open(sys.argv[1], 'rb') as f:
        pcap = dpkt.pcap.Reader(f)
        #print_packets(pcap)
        MyParser(pcap)
    #print('\n[Connection statistics]')
    #print('- AP1')
    #print('  - Mac addr: 00:00:00:00:00:01')
    #print('  - Total connection duration: %.4fs' % 12.3654)
    #print('  - Total transmitted bytes: %d bytes' % 1234)
    #print('\n[Other statistics]')
    #print('  - Number of handoff events: %d' % 2)
    #print('  - Theoretical sum-rate: %d mbps' % int(math.floor(125.25)))
