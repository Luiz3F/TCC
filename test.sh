#!/bin/bash

# 0. Definir constantes (N, firewall)
# 1. Resetar VMs a um estado antes da modificação do firewall
# 2. SSH na VM cliente legítima e coletar tempo controle sem ataque N vezes
# 3. Desconectar do cliente legítimo
# 4. Para cada tipo de ataque:
# 4.1. SSH na VM atacante e iniciar ataque do tipo attack
# 4.2. Desconectar do atacante
# 4.3. SSH na VM cliente legítima e coletar tempo controle com ataque N vezes
# 4.4. Desconectar do cliente legítimo
# 4.5. SSH no gateway para coletar pcap
# 4.6. Desconectar do gateway
# 4.7. Para cada modelo de LLM:
# 4.7.1. Rodar o script em python usando o pcap, tipo de ataque, firewall e modelo de LLM como parâmetros
# 4.7.2. Aplicar a regra gerada
# 4.7.3. SSH na VM cliente legítima e coletar tempo com ataque e com regras N vezes
# 4.7.4. Desconectar do cliente legítimo
# 4.7.5. Resetar VMs a um estado antes da modificação do firewall
# 5. Voltar ao passo 1 mudando o firewall

#python ./teste.py

# 0.
readonly NUM_ITER=10
client_ip="192.168.165.5"
server_ip="192.168.244.4"

client_vm="iptables"
server_vm="nftables"
pfSense_vm="pfSense"
attacker_vm="kali-linux-2025.4-virtualbox-amd64"
# tcc-client-vm, tcc-server-vm, tcc-attacker-vm, tcc-pfsense-vm

error() {
    local error_code=$?
    if [[ $error_code -ne 0 ]] ; then
        echo $1 >&2
        exit $error_code
    fi
}

shutdown_vms() {
    VBoxManage list runningvms | awk -F'"' '{print $2}' | while read -r vm; do
        [ -z "$vm" ] && continue
        VBoxManage controlvm "$vm" poweroff
        error "Falha no desligamento de $vm"
    done
}

start_vms() {
    local vms=($pfSense_vm $server_vm $client_vm $attacker_vm)

    # Shutdown vms if there are still some running
    shutdown_vms

    # In case program stops before vms are properly turned off
    trap 'shutdown_vms' EXIT

    # Restore them to default state
    sleep 3
    for vm in "${vms[@]}"; do
        VBoxManage snapshot $vm restore "Default State"
        error "Falha na restauração de $vm ao estado default"

        VBoxManage startvm $vm --type headless
        error "Falha no startup de $vm"
    done

    sleep 15
}

client_collect_times() {
    local N=$1
    TIMEFORMAT=%R
    for ((i = 0; i < N; i++)); do
        time wget -qO teste.html http://192.168.244.4:8080
        test $? -eq 0 || exit 1
    done
}

collect_download_times() {
    local filename=$1
    ssh tcc-client-vm "$(declare -f client_collect_times); client_collect_times $NUM_ITER" > $filename 2>&1
    error "Falha na coleta de tempos"

    echo "" >> $filename
    
    # Calculate average 
    local avg=$(awk '{sum+=$1} END {print sum/NR}' "$filename")
    echo $avg >> $filename

    # Calculate std deviation
    local dev=$(awk '{sum+=$1; sumsq+=$1*$1} END {print sqrt(sumsq/NR - (sum/NR)**2)}' "$filename")

    echo $dev >> $filename
}

attacker_stop_attack() {
    local script_path="/tmp/start_exploit.rc"
    local pid_path="/tmp/exploit.pid"

    if [ -f $pid_path ]; then
        local pid=$(cat $pid_path)
        if ps -p $pid > /dev/null; then
            kill -9 $pid
        fi
        rm -f $script_path
        rm -f $pid_path
    fi
}

stop_attack() {
    ssh tcc-attacker-vm "$(declare -f attacker_stop_attack); attacker_stop_attack"
    error "Falha na conexão com vm atacante" 
}

attacker_start_attack() {
    local attack=$1
    local server_ip=$2
    local script_path="/tmp/start_exploit.rc"
    local pid_path="/tmp/exploit.pid"

    cat << EOF > "$script_path"
    use $attack
    set rhost $server_ip
    set rport 8080
    set sockets 2000
    exploit -q
EOF
    msfconsole -q -r $script_path > /dev/null 2>&1 &

    echo $! > $pid_path
    cat $pid_path
}

start_attack() {
    # In case last attack was not properly ended
    stop_attack

    local attack=$1
    ssh tcc-attacker-vm "$(declare -f attacker_start_attack); attacker_start_attack $attack $server_ip"
    error "Falha na conexão com vm atacante"

    # It may take some seconds for the attack to affect the server
    sleep 25
}

# 1.
start_vms

# 2/3.
#echo Coletando tempos controle
#collect_download_times controle.txt

# 4.

    # TODO
    attack="auxiliary/dos/http/slowloris" #tcp/synflood
    pcap_path="./slowloris.pcap"

# 4.1/2
echo Começando ataque
#start_attack $attack


# 4.3/4
echo Coletando tempos com slowloris
#collect_download_times slowloris.txt


# 4.5/6
echo Colectando .pcap do ataque
#timeout --preserve-status 5 ssh tcc-pfsense-vm "tcpdump -ni em2 -w -" > $pcap_path
#test $? -eq 255 || error "Falha ao coletar .pcap do ataque"
#[ -s $pcap_path ]
#error "Falha ao coletar .pcap do ataque"
#stop_attack


# 4.7
for firewall in "pfSense"; do # "iptables" "nftables" ; do
    model="openai"

    # 4.7.1
    echo Gerando regras
    #python teste.py $pcap_path $firewall $model -a slowloris > tmp.sh # TODO: FAZER SER UM ARQUIVO TMP REAL! (mktemp)
    sed -i 's/\r$//' tmp.sh # Windows moment

    # 4.7.2
    echo "Aplicando regras"
    if [ $firewall = "pfSense" ]; then # Caso o firewall atual seja o pfSense
        VBoxManage controlvm $pfSense_vm poweroff
        sleep 3
        VBoxManage snapshot $pfSense_vm restore "Firewall State"
        sleep 3
        VBoxManage startvm $pfSense_vm --type headless
        sleep 10
        #start_attack $attack
        #echo Coletando tempos antes da aplicação das regras pra ter certeza que essa joça funcioa
        #collect_download_times slowloris.txt
        #stop_attack
        ssh tcc-pfsense-vm 'sh -s' < tmp.sh
    else
        VBoxManage controlvm $server_vm poweroff
        sleep 3
        VBoxManage snapshot $server_vm restore "Default State"
        sleep 3
        VBoxManage startvm $server_vm --type headless
        sleep 20
        
        { printf "senha\n"; cat tmp.sh; } | ssh tcc-server-vm -T 'sudo -S sh -s 2>/dev/null'
    fi
    sleep 10
    #rm -f tmp.sh

    # 4.7.3
    start_attack $attack
    echo Coletando tempos com regras aplicadas
    collect_download_times slowloris_ai.txt
    stop_attack

done
stop_attack
shutdown_vms