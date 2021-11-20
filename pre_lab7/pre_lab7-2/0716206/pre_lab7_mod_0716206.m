%% BPSK transmission over AWGN channel
close all;clear all;clc;           % BPSK
dist=100:100:400;        % distance in meters
PtdBm=10;                % transmit power in dBm
PndBm=-85;              % noise power in dBm
Pt=10^(PtdBm/10)/1000;  % transmit power in watt
Pn=10^(PndBm/10)/1000;  % noise power in watt
Bit_Length=1e3;         % number of bits transmitted

%% Friss Path Loss Model
Gt=1;
Gr=1;
freq=2.4e9;
c=3e8;
% TODO: Calculate Pr(d)
Pr=ones(length(dist),1);    % TODO: replace this with Friis' model
for d=1:length(dist)
    Pr(d)=Gt*Gr*((c/(4*pi*freq*dist(d)))^2)*Pt;
end
%% BPSK Transmission over AWGN channel
tx_data = randi(2, 1, Bit_Length) - 1;                  % random between 0 and 1
%% TODO-2
%% BPSK: {1,0} -> {1+0i, -1+0i}
%% QPSK: {11,10,01,00} -> {1+i, -1+i, -1-i, 1-i} * scaling factor
%% 16QAM: {1111, 1110, 1101, 1100, 1011, 1010, 1001, 1000, 0111, 0110, 0101, 0100, 0011, 0010, 0001, 0000}
%% -> {3a+3ai, 3a+ai, a+3ai, a+ai, -a+3ai, -3a+3ai, -3a+ai, -a+ai, 3a-ai, 3a-3ai, a-ai, a-3i, -a-ai, -a-3ai, -3a-ai, -3a-3ai}

n=(randn(1,Bit_Length)+randn(1,Bit_Length)*1i)/sqrt(2);  % AWGN noises
n=n*sqrt(Pn);

for mod_order=[1,2,4]
    if mod_order == 1
        x(mod_order,:)=(tx_data.*2-1)+0i;                                    % TODO-2: change it to three different modulated symbols
    end
    if mod_order == 2
        for i=1:2:Bit_Length
            x(mod_order,(i+1)/2) = ((tx_data(i).*2-1) + (tx_data(i+1).*2-1)*1i)*(1/sqrt(2));
        end
    end
    if mod_order == 4
        for i=1:4:Bit_Length
            x(mod_order,(i+3)/4) = ((tx_data(i).*2-1)*(tx_data(i+1).*2+1) + (tx_data(i+2).*2-1)*(tx_data(i+3).*2+1)*1i);
        end
        a =(sqrt(2)+sqrt(10)+sqrt(10)+sqrt(18)) / 4;
        
        for i=1:4:Bit_Length
            x(mod_order,(i+3)/4) =  x(mod_order,(i+3)/4) / a;           
        end
    end
    
    for d=1:length(dist)
        y(mod_order,d,:)=sqrt(Pr(d))*x(mod_order,:)+n;
    end
    
    for i=501:1000
        y(2,:,i)=0;
    end
    
    for i=251:1000
        y(4,:,i)=0;
    end
    
end

%% Equalization
% Detection Scheme:(Soft Detection)
% +1 if o/p >=0
% -1 if o/p<0
% Error if input and output are of different signs

for mod_order=[1,2,4]
    figure('units','normalized','outerposition',[0 0 1 1])
	sgtitle(sprintf('Modulation order: %d', mod_order)); 
    for d=1:length(dist)
        % TODO: s = y/Pr
        % TODO: x_est = 1 if real(s) >= 0; otherwise, x_est = -1
        for i=1:Bit_Length
            s(i)=y(mod_order,d,i)/sqrt(Pr(d)); % h^2=Pr
        end
        
        SNR(d,mod_order)=Pr(d)/Pn;
        SNRdB(d,mod_order)=10*log10(SNR(d,mod_order));
        BER_simulated(d,mod_order)=0;
        SNRdB_simulated(d,mod_order)=0;
        % TODO-2: demodulate x_est to x' for various modulation schemes and calculate BER_simulated(d)
        % TODO: noise = s - x, and, then, calculate SNR_simulated(d)
        sum_N=0;
        bit_e=0;
        
        if mod_order == 1
            for i=1:Bit_Length
                if real(s(i))*x(mod_order,i) < 0
                    bit_e=bit_e+1;
                end
                n=s(i)-x(mod_order,i);
                N=real(n)^2+imag(n)^2; %N=n^2
                sum_N=sum_N+N;
            end
            SNR_simulated(d,mod_order)=Bit_Length/sum_N;
        end
        if mod_order == 2
            for i=1:(Bit_Length/2)
                if ~(real(s(i))*real(x(mod_order,i)) > 0 && imag(s(i))*imag(x(mod_order,i)) > 0)
                    bit_e=bit_e+2;
                end
                n=s(i)-x(mod_order,i);
                N=real(n)^2+imag(n)^2; %N=n^2
                sum_N=sum_N+N;
            end
            SNR_simulated(d,mod_order) = 500/sum_N;
        end
        if mod_order == 4
            a1 = (sqrt(2)+sqrt(10)+sqrt(10)+sqrt(18)) / 4;
            for i=1:(Bit_Length/4)
                s(i) = s(i) * a1; %restore
                x(mod_order,i) = x(mod_order,i) * a1; 
                if ~(real(s(i))*real(x(mod_order,i)) > 0 && imag(s(i))*imag(x(mod_order,i)) > 0 && (abs(real(s(i)))-2)*(abs(real(x(mod_order,i)))-2) > 0 && (abs(imag(s(i)))-2)*(abs(imag(x(mod_order,i)))-2) > 0) 
                    bit_e = bit_e + 4;
                end
                s(i) = s(i) / a1;
                x(mod_order,i) = x(mod_order,i)/a1;
                n = s(i) - x(mod_order,i);
                N = real(n)^2+imag(n)^2; %N=n^2
                sum_N = sum_N + N;
            end
            SNR_simulated(d,mod_order) = 250/sum_N;
        end
        
        SNRdB_simulated(d,mod_order)=10*log10(SNR_simulated(d,mod_order));
        BER_simulated(d,mod_order)=bit_e/Bit_Length;
        
        subplot(2, 2, d)
        hold on;
        plot(s,'bx');       % TODO: replace y with s
        plot(x,'ro');
        hold off;
        xlim([-2,2]);
        ylim([-2,2]);
        title(sprintf('Constellation points d=%d', dist(d)));
        legend('decoded samples', 'transmitted samples');
        grid
    end
    filename = sprintf('IQ_%d.jpg', mod_order);
    saveas(gcf,filename,'jpg');
end

%% TODO-2: modify the figures to compare three modulation schemes
figure('units','normalized','outerposition',[0 0 1 1])
hold on;
semilogy(dist,SNRdB_simulated(:,1),'bo-','linewidth',2.0);
semilogy(dist,SNRdB_simulated(:,2),'rv--','linewidth',2.0);
semilogy(dist,SNRdB_simulated(:,4),'mx-.','linewidth',2.0);
hold off;
title('SNR');
xlabel('Distance [m]');
ylabel('SNR [dB]');
legend('BPSK','QPSK','16QAM');
axis tight 
grid
%saveas(gcf,'SNR.jpg','jpg')

figure('units','normalized','outerposition',[0 0 1 1])
hold on;
semilogy(dist,BER_simulated(:,1),'bo-','linewidth',2.0);
semilogy(dist,BER_simulated(:,2),'rv--','linewidth',2.0);
semilogy(dist,BER_simulated(:,4),'mx-.','linewidth',2.0);
hold off;
title('BER');
xlabel('Distance [m]');
ylabel('BER');
legend('BPSK','QPSK','16QAM');
axis tight 
grid
%saveas(gcf,'BER.jpg','jpg')
return;
