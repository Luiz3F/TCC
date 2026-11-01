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
# 4.5. SSH no atacante para coletar pcap (?)
# 4.6. Desconectar do atacante
# 4.7. Para cada modelo de LLM:
# 4.7.1. Rodar o script em python usando o pcap, tipo de ataque, firewall e modelo de LLM como parâmetros
# 4.7.2. Aplicar a regra gerada
# 4.7.3. SSH na VM cliente legítima e coletar tempo com ataque e com regras N vezes
# 4.7.4. Desconectar do cliente legítimo
# 4.7.5. Resetar VMs a um estado antes da modificação do firewall
# 5. Voltar ao passo 1 mudando o firewall

#python ./teste.py

collect_download_times() {
    local N=$1
    for ((i = 0; i  < N; i++)); do
        whoami
    done
}

# 0.
readonly NUM_ITER=5
firewall="iptables"
# TODO: Definir ip de cliente, atacante e servidor como variáveis

# 1.
    # TODO

# 2.
ssh tcc-client-vm "$(declare -f collect_download_times); collect_download_times $NUM_ITER"