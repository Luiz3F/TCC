#!/bin/bash

readonly NUM_ITER=10
client_ip="192.168.165.5"
server_ip="192.168.244.4"

client_vm="iptables"
server_vm="nftables"
pfSense_vm="pfSense"
attacker_vm="kali-linux-2025.4-virtualbox-amd64"

declare -A slowloris=(["name"]="slowloris" ["path"]="auxiliary/dos/http/slowloris")
declare -A synflood=(["name"]="synflood" ["path"]="auxiliary/dos/tcp/synflood")

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

# Will be run in client vm
client_collect_times() {
    local N=$1
    TIMEFORMAT=%R
    for ((i = 0; i < N; i++)); do
        time wget --timeout=120 --tries=1 -qO teste.html http://192.168.244.4:8080
    done
}

collect_download_times() {
    local filename=$1

    # Run client_collect_times inside client vm
    ssh tcc-client-vm "$(declare -f client_collect_times); client_collect_times $NUM_ITER" > $filename 2>&1
    [ -s $filename ]
    error "Falha na coleta de tempos"

    echo "" >> $filename
    
    # Calculate average 
    local avg=$(awk '{sum+=$1} END {print sum/NR}' "$filename")
    echo $avg >> $filename

    # Calculate std deviation
    local dev=$(awk '{sum+=$1; sumsq+=$1*$1} END {print sqrt(sumsq/NR - (sum/NR)**2)}' "$filename")

    echo $dev >> $filename
}

# Will be run inside attacker vm
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
    echo "Parando ataques que estejam acontecendo"
    { printf "kali\n"; } | ssh tcc-attacker-vm "sudo -S bash -c '$(declare -f attacker_stop_attack); attacker_stop_attack' 2>/dev/null"
    error "Falha na conexão com vm atacante" 
}

# Will be run inside attacker vm
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
    echo "Começando ataque $attack"
    { printf "kali\n"; } | ssh tcc-attacker-vm "sudo -S bash -c '$(declare -f attacker_start_attack); attacker_start_attack $attack $server_ip' 2>/dev/null"
    error "Falha na conexão com vm atacante"

    # It may take some seconds for the attack to affect the server
    sleep 25
}

start_vms

echo Coletando tempos controle
collect_download_times controle.txt

for i in "slowloris" "synflood"; do

    declare -n attack=$i
    pcap_path="${attack["name"]}.pcap"

    echo Coletando tempos com ${attack["name"]}
    start_attack ${attack["path"]}
    collect_download_times ${attack["name"]}.txt
    stop_attack

    echo Colectando .pcap do ataque
    ssh tcc-pfsense-vm "nohup timeout 15 tcpdump -ni em2 -w /tmp/$pcap_path host $server_ip > /tmp/${attack["name"]}.log 2>&1 &" # .pcap is stored inside pfSense vm
    error "Falha ao coletar .pcap do ataque"
    
    # Sleeps are for giving time to the vms to do what they got to do before continuing
    sleep 2
    start_attack ${attack["path"]}
    sleep 10
    stop_attack
    sleep 5
    scp tcc-pfsense-vm:/tmp/$pcap_path .    # Gets .pcap from pfSense vm
    error "Falha ao coletar .pcap do ataque"
    [ -s $pcap_path ]                       # Check if empty file
    error "Falha ao coletar .pcap do ataque"

    for firewall in "iptables" "nftables" "pfSense"; do 
        model="openai"
        script_path="./${model}/${attack["name"]}_${firewall}_rules_${model}.sh"

        echo "Gerando regras para ${firewall}/${attack["name"]}"
        touch $script_path
        python rules_gen.py $pcap_path $firewall $model -a $attack["name"] > $script_path
        error "Falha na geração de regras"
        sed -i 's/\r$//' $script_path # Windows moment

        
        echo "Reiniciando e restaurando VM"
        
        # If firewall is pfSense, firewall mode has to be enabled
        if [ $firewall = "pfSense" ]; then 
            VBoxManage controlvm $pfSense_vm poweroff
            sleep 3
            VBoxManage snapshot $pfSense_vm restore "Firewall State"
            sleep 3
            VBoxManage startvm $pfSense_vm --type headless
            sleep 10
            echo "Aplicando regras para ${firewall}/${attack["name"]}"
            ssh tcc-pfsense-vm 'sh -s' < $script_path
        else
            VBoxManage controlvm $server_vm poweroff
            sleep 3
            VBoxManage snapshot $server_vm restore "Default State"
            sleep 3
            VBoxManage startvm $server_vm --type headless
            sleep 20
            echo "Aplicando regras para ${firewall}/${attack["name"]}"
            { printf "senha\n"; cat $script_path; } | ssh tcc-server-vm -T "sudo -S sh -s 2>/dev/null"
        fi
        sleep 10

        start_attack ${attack["path"]}
        echo "Coletando tempos com regras aplicadas em ${firewall}/${attack["name"]}"
        collect_download_times "./${model}/${attack["name"]}_${firewall}_${model}.txt"
        stop_attack

    done
    unset attack
done
stop_attack
shutdown_vms