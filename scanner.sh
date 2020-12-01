#!/bin/bash

# IP público máquina secundária: 18.232.184.50
# IP privado máquina secundária: 10.0.0.118
#
# Ambas máquinas usam a mesma chave para conectar via ssh

SCRIPTS_DIRECTORY="vulnScripts"

PRESSED_CANCEL=1
FAILURE=1
SUCCESS=0

MainMenu() {
    while true; do
        idx_menu=$(dialog                                                        \
            --stdout                                                             \
            --title 'Menu principal'                                             \
            --menu 'Marque abaixo qual operação deseja realizar:' 0 0 0          \
            1 'Utilizar o nmap'                                                  \
            2 'Utilizar o rustscan')

        if [ $? -eq $PRESSED_CANCEL ]; then
            dialog --title "Aviso" --msgbox "Programa encerrado!" 0 0
            clear && exit $FAILURE
        fi

        idx_menu="$(($idx_menu - 1))" 
        menu=('NmapOptions' 'RustScanOptions')

        VerifySudo && VerifyInstall
        
       ${menu[$idx_menu]}
    done
}

VerifyInstall() {    
    if [ ! -x /usr/bin/nmap ]; then
        nmapInstall=$(dialog --stdout --title 'Erro' --yesno 'Nmap não está instalado, deseja instalar?' 0 0)
        if [ $nmapInstall -eq 0 ]; then
            InstallNmap
        else
            dialog --title 'Erro' --msgbox 'Não é possivel continuar sem instalar o NMAP' 0 0
            clear && exit $FAILURE
        fi 
    fi

    if [ ! -x /usr/bin/rustscan ]; then
        rustScanInstall=$(dialog --stdout --title 'Erro' --yesno 'RustScan não está instalado, deseja instalar?' 0 0)
        if [ $rustScanInstall -eq 0 ]; then 
            InstallRustScan
        else
            dialog --title 'Erro' --msgbox 'Não é possivel continuar sem instalar o RustScan' 0 0
            clear && exit $FAILURE
        fi 
    fi
}

VerifySudo() {
    if [[ $EUID -ne 0 ]]; then
        dialog --title 'Erro' --msgbox 'É necessario executar este script com permissão de super usuário' 10 40
        clear && exit $FAILURE
    fi
}

InstallVulnScripts() {
    vulnScriptUrl="https://svn.nmap.org/nmap/scripts/vulners.nse"

    mkdir $SCRIPTS_DIRECTORY
    wget $vulnScriptUrl
    mv vulners.nse $SCRIPTS_DIRECTORY 
}

InstallNmap() {
    apt-get install nmap
    InstallVulnScripts
}

InstallRustScan() {  
    rustScanURL="https://github.com/RustScan/RustScan/releases/download/2.0.1/rustscan_2.0.1_amd64.deb"
    rustScanFile="rustscan_2.0.1_amd64.deb"

    wget $rustScanURL
    dpkg -i $rustScanFile
    rm $rustScanFile
}

ExecCMD() {
    dialog --title 'Tela de espera' --infobox '\nExecutando comando, aguarde...' 0 0
    $($1 >> temp)
    dialog --tailbox temp 0 0     
    rm temp
}

NmapOptions() {

    idx_option=$(dialog                                                      \
        --stdout                                                             \
        --menu 'Marque abaixo qual operação deseja realizar:' 0 0 0          \
        1 'Verificar portas abertas'                                         \
        2 'Verificar vulnerabilidades'                                       \
        3 'Verificar Sistema Operacional e serviços de rede'                 \
        4 'Identificar os computadores da rede fornecendo uma lista'         \
        5 'Inserir comando customizado') 
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE

    if [ $idx_option -eq 5 ]; then
        command=$(dialog --stdout --inputbox 'Digite o commando a ser executado' 0 0)
        [ $? -eq $PRESSED_CANCEL ] && return $FAILURE

        ExecCMD "$command"

        return $SUCCESS
    fi

    idx_mode=$(dialog                                           \
        --stdout                                                \
        --title 'Modo de escaneamento'                          \
        --menu 'Escolha que opção de verificação deseja usar:'  \
        0 0 0                                                   \
        1       'Stealth'                                       \
        2       'Normal'                                        \
        3       'Agressivo')     
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE

    idx_output=$(dialog                                                          \
        --stdout                                                                 \
        --title 'Modo de Visualização '                                          \
        --menu 'Deseja visualizar resultado na tela ou salvar como scan.txt?'    \
        0 0 0                                                                    \
        1     'Visualizar'                                                       \
        2     'Salvar')
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE

    mode=('-T1' '-T3' '-T4') 
    output=('' '-oN nmap.log')                            
    option=('-F' "-sV --script ./$SCRIPTS_DIRECTORY/vulners" '-A' '-sn')   
    
    idx_mode="$(($idx_mode - 1))"
    idx_output="$(($idx_output - 1))"
    idx_option="$(($idx_option - 1))"

    if [ $idx_option -eq 3 ]; then
        ip=$(ip r | grep kernel | awk '/kernel/ {print $1}')
    else
        ip=$(dialog --stdout --inputbox 'Digite o ip em que deseja aplicar a operação:' 0 0)
        [ $? -eq $PRESSED_CANCEL ] && return $FAILURE
    fi
    
    ExecCMD "nmap ${option[$idx_option]} ${mode[$idx_mode]} ${output[$idx_output]} $ip"

    return $SUCCESS
}

SetBatchSize() {
    batch_size=$(dialog --stdout --inputbox 'Digite a quantidade de portas a serem scaneadas em paralelo (Padrão: 4500, Máximo: 65535)' 0 0)
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE

    [ $batch_size -gt 65535 ] && dialog --stdout --title 'Erro' --msgbox 'A quantidade de portas em paralelo não pode ser superior à 65535' 0 0 && return $FAILURE
    echo -b $batch_size
}

SetScanOrder() {
    scan_order=$(dialog                                                      \
        --stdout                                                                 \
        --title "Ordem de escaneamento"                                          \
        --menu 'Selecione a ordem de escaneamento de portas (Padrão: Serial)'    \
        0 0 0                                                                    \
        Serial     "Serial"                                                      \
        Random     'Aleatório')
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE
    echo --scan-order $scan_order
}

SetTimeout() {
    timeout=$(dialog --stdout --inputbox "Digite o tempo em milisegundos para considerar uma porta como fechada (Padrão: 1500)" 0 0)
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE
    echo -t $timeout
}

SetTries() {
    tries=$(dialog --stdout --inputbox 'Digite o número de tentativas a serem realizadas antes de considerar a porta como fechada (Padrão: 1)' 0 0)
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE
    echo --tries $tries
}

RustScanOptions() {
    
    rust_option=$(dialog                                                     \
        --stdout                                                             \
        --menu 'Marque abaixo qual operação deseja realizar:' 0 0 0          \
        1 'Verificar portas abertas'                                         \
        2 'Inserir comando customizado') 
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE

    if [ $rust_option -eq 2 ]; then
        command=$(dialog --stdout --inputbox 'Digite o commando a ser executado' 0 0)
        [ $? -eq $PRESSED_CANCEL ] && return $FAILURE

        ExecCMD "$command"

        return $SUCCESS
    fi
    
    #                         NOME : FUNÇÃO
    optional_params=('o batch size : SetBatchSize'
                    'a Ordem de escaneamento : SetScanOrder'
                    'o timeout correspondente à porta fechada : SetTimeout' 
                    'o número de tentativas antes de considerar a porta fechada : SetTries')

    array_optional_params=()

    for opt_param in "${optional_params[@]}"
    do
        NAME="${opt_param% :*}"
        DIALOG_FUNCTION="${opt_param#* :}"
        
        dialog                                                                          \
            --title 'Parâmetros Opcionais'                                              \
            --yesno "Deseja configurar $NAME do comando em questão (opcional)?"         \
            0 0
            if [ $? -eq 0 ]; then 
                array_optional_params+=("$($DIALOG_FUNCTION)")
                [ $? -eq $FAILURE ] && return $FAILURE
            fi
    done

    target=$(dialog --stdout --inputbox "Digite o ip em que deseja aplicar a operação:" 0 0)
    [ $? -eq $PRESSED_CANCEL ] && return $FAILURE

    cmd="rustscan --accessible ${array_optional_params[@]} -a $target"

    ExecCMD "$cmd"
}

MainMenu