#!/bin/env bash

###############################################
#本脚本可用于centos/ubuntu系统安装或卸载filebeat
#安装filebeat前会检测是否安装audit审计服务，如果
#未安装则会安装audit审计服务，并加载审计规则
###############################################

PATH=/sbin:/bin:/usr/sbin:/usr/bin

#check os 
os_type=$(cat /etc/os-release |head -1|awk -F "=" '{print $2}'|sed 's/"//g'|awk -F" " '{print $1}')
cpu_type=$(uname -m)

#centos安装auditd服务
centos_inst_audit() {
    auditctl -s
    if [[ $? -ne 0 ]];then
        yum install -y audit
        systemctl enable --now auditd
    else    
        echo "auditd服务已安装......"
    fi
} 

#ubuntu安装auditd服务
ubuntu_inst_audit() {
    auditctl -s
    if [[ $? -ne 0 ]];then
        apt install auditd audispd-plugins -y
        systemctl enable --now auditd
    else    
        echo "auditd服务已安装......"
    fi
}

#清除剩余的垃圾文件(centos/ubunt)
clean_junk_files() {
    rm -rf /etc/filebeat
    rm -rf /var/lib/filebeat
    rm -rf /var/log/filebeat
    rm -rf /usr/lib/systemd/system/filebeat.service
    rm -rf /etc/audit/rules.d/99-custom.rules
}

#centos安装filebeat服务
centos_inst_filebeat() {
    rpm -aq | grep filebeat
    if [[ $? -eq 0 ]];then
        yum remove -y filebeat
        clean_junk_files
    fi
    cd /tmp && wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.19.6-x86_64.rpm
    rpm -ivh filebeat-8.19.6-x86_64.rpm
    systemctl enable filebeat && systemctl start filebeat
}

#ubuntu安装filebeat服务
ubuntu_inst_filebeat() {
    dpkg -s filebeat
    if [[ $? -eq 0 ]];then
        apt purge -y filebeat
        clean_junk_files
    fi
    cd /tmp && wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.19.6-amd64.deb
    dpkg -i filebeat-8.19.6-amd64.deb
    systemctl enable filebeat && systemctl start filebeat
}

#centos 使用Unix的时间格式，并实时追加执行的命令到历史记录中,捕获清除命令history -c
centos_capture_current_history_command() {
cat >> /etc/bashrc << 'EOF'

[[ $- != *i* ]] && return

history() {
    if [[ "$1" == "-c" ]]; then
        logger -t bash_history_clear \
            "User:$USER executed 'history -c' TTY:$(tty) IP:$(who am i 2>/dev/null | awk '{print $NF}')"
    fi

    if [[ $# -eq 0 ]]; then
        builtin history
    else
        builtin history "$@"
    fi
}

export HISTTIMEFORMAT="%F %T "
export PROMPT_COMMAND='history -a'
shopt -s histappend
EOF

source /etc/bashrc
}

#ubuntu 使用Unix的时间格式，并实时追加执行的命令到历史记录中,捕获清除命令history -c
ubuntu_capture_current_history_command() {
cat >> /etc/bash.bashrc << 'EOF'

[[ $- != *i* ]] && return

history() {
    if [[ "$1" == "-c" ]]; then
        logger -t bash_history_clear \
            "User:$USER executed 'history -c' TTY:$(tty) IP:$(who am i 2>/dev/null | awk '{print $NF}')"
    fi

    if [[ $# -eq 0 ]]; then
        builtin history
    else
        builtin history "$@"
    fi
}

export HISTTIMEFORMAT="%F %T "
export PROMPT_COMMAND='history -a'
shopt -s histappend
EOF

source /etc/bash.bashrc
}

#确认filebeat.tar.gz部署包是否存在
file_exist() {
    [[ `pwd` != "/tmp" ]] && echo "请将Shell脚本放到/tmp目录下执行 !!!" && exit 2
    cd /tmp
    echo "开始下载Audit规则文件和filebeat.tar.gz部署包......"
    sleep 2
    wget https://raw.githubusercontent.com/gagaga2468/filebeat/refs/heads/main/98-custom.rules
    wget https://raw.githubusercontent.com/gagaga2468/filebeat/refs/heads/main/filebeat.tar.gz
    [[ ! -f filebeat.tar.gz ]] && echo "找不到filebeat.tar.gz部署包，请将部署包和安装脚本放在/tmp目录下 !!!" && exit 1
    [[ ! -f 98-custom.rules ]] && echo "找不到audit规则文件98-custom.rules，请将audit规则文件和安装脚本放在/tmp目录下 !!!" && exit 1
}

#初始化filebeat
init_filebeat() {
    tar -zxf filebeat.tar.gz
    cp /tmp/filebeat/filebeat.yml /etc/filebeat/
    cp -r /tmp/filebeat/scripts /etc/filebeat/
    systemctl restart filebeat
    cp /tmp/99-custom.rules /etc/audit/rules.d/
    augenrules --load > /dev/null 2>&1
    echo "查看audit系统审计加载的规则"
    sleep 2
    auditctl -l
    echo "查看filebeat服务状态"
    sleep 2
    systemctl status filebeat
}

#执行filebeat的安装
main_install() {
    if [[ ${cpu_type} == "x86_64" && ${os_type} == "CentOS" ]];then
        echo "操作系统版本：${os_type}"
        echo "CPU架构：${cpu_type}"
        echo "现在开始安装......"
        file_exist
        echo "安装audit系统审计服务"
        sleep 3
        centos_inst_audit
        echo "下载并安装filebeat的rpm包"
        sleep 3
        centos_inst_filebeat
        echo "添加实时捕获history指令的命令"
        sleep 2
        centos_capture_current_history_command
        echo "将配置好的filebeat.yaml文件添加到线上"
        sleep 2
        init_filebeat
    elif [[ ${cpu_type} == "x86_64" && ${os_type} == "Ubuntu" ]];then
        echo "操作系统版本：${os_type}"
        echo "CPU架构：${cpu_type}"
        echo "现在开始安装......"
        file_exist
        echo "安装audit系统审计服务"
        sleep 3
        ubuntu_inst_audit
        echo "下载并安装filebeat的deb包"
        sleep 3
        ubuntu_inst_filebeat
        echo "添加实时捕获history指令的命令"
        sleep 2
        ubuntu_capture_current_history_command
        echo "将配置好的filebeat.yaml文件添加到线上"
        sleep 2
        init_filebeat
    else
        echo "不匹配的操作系统类型或者CPU架构，请检测后再试......"
        exit 1
    fi
}

#执行filebeat的卸载
main_uninstall() {
    if [[ ${os_type} == "CentOS" ]];then
        rpm -aq | grep filebeat
        if [[ $? -eq 0 ]];then
            systemctl stop filebeat
            auditctl -D
            systemctl daemon-reload
            yum remove -y filebeat
            clean_junk_files
        else
            echo "尚未安装filebeat服务"
            exit 0
        fi
    elif [[ ${os_type} == "Ubuntu" ]];then
        dpkg -s filebeat
        if [[ $? -eq 0 ]];then
            systemctl stop filebeat
            auditctl -D
            systemctl daemon-reload
            apt purge -y filebeat
            clean_junk_files
        else
            echo "尚未安装filebeat服务"
            exit 0         
        fi
    else
        echo "不匹配的操作系统类型，请检测后再试......"
        exit 1
    fi
}

#程序的主入口
main() {
    while true; do
        echo "请选择操作："
        echo "1) 安装filebeat"
        echo "2) 卸载filebeat"
        echo "q) 退出"

        read -p "请输入你的选择 [1/2/q]: " choice

        case "$choice" in
            1)
                echo "安装filebeat..."
                main_install
                break
                ;;
            2)
                echo "卸载filebeat..."
                main_uninstall
                break
                ;;
            q|Q)
                echo "已退出"
                exit 0
                ;;
            *)
                echo "输入错误，请重新选择"
                ;;
        esac
    done
}

main

