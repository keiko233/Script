#!/bin/bash

CLOUDFALRE_USER_MAIL=""
CLOUDFALRE_GLOBAL_API=""
CLOUDFALRE_ZONES_ID=""
CLOUDFALRE_DOMAIN=""
CLOUDFALRE_DNS_RECORD_ID=""

INTERFACE_NAME=""
GET_NTH_ADDRESS=""

OPENWRT_FIREWALL_RULE_ID=""

LogOut() {
  echo -e "$(date "+%H:%M:%S") [$1] $2"
}

GetInterfaceIPv6Address() {
  LogOut "INFO" "获取IPv6地址"
  IPV6ADDRESS=$(ip -6 addr show dev ${INTERFACE_NAME} | grep global | awk '{print $2}' | awk -F "/" '{print $1}' | sed -n ${GET_NTH_ADDRESS}p)
  LogOut "INFO" "当前IPv6地址为: ${IPV6ADDRESS}"
}

GetAddressFormCloudflare() {
  LogOut "INFO" "获取当前DNS记录的地址"
  CLOUDFLARE_IP_CONTENT=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFALRE_ZONES_ID}/dns_records?type=AAAA&name=${CLOUDFALRE_DOMAIN}&content=127.0.0.1&page=1&per_page=100&order=type&direction=desc&match=any" \
    -H "X-Auth-Email: ${CLOUDFALRE_USER_MAIL}" \
    -H "X-Auth-Key: ${CLOUDFALRE_GLOBAL_API}" \
    -H "Content-Type: application/json" | \
    jq --raw-output '.result[0].content')
  LogOut "INFO" "获取当前DNS记录地址为: ${CLOUDFLARE_IP_CONTENT}"
}

PutAddress2Cloudflare() {
  LogOut "INFO" "更新Cloudflare上的IPv6地址为: ${IPV6ADDRESS}"
  CLOUDFLARE_RETURN_STATUS=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CLOUDFALRE_ZONES_ID}/dns_records/${CLOUDFALRE_DNS_RECORD_ID}" \
    -H "X-Auth-Email: ${CLOUDFALRE_USER_MAIL}" \
    -H "X-Auth-Key: ${CLOUDFALRE_GLOBAL_API}" \
    -H "Content-Type: application/json" --data '{"type":"AAAA","name":"'"${CLOUDFALRE_DOMAIN}"'","content":"'"${IPV6ADDRESS}"'","ttl":1,"proxied":false}' | \
    jq --raw-output '.success')
  if [ "$CLOUDFLARE_RETURN_STATUS" = "true" ]; then
    LogOut "INFO" "更新IPV6地址成功"
  else
    LogOut "ERROR" "更新IPV6地址失败"
  fi
}

CheckJqInstalled() {
  local JQPATCH="/usr/bin/jq"

  if [ -f "$JQPATCH" ]; then
    LogOut "INFO" "在${JQPATCH}检测到jq的安装"
  else 
    LogOut "ERROR" "在没有检测到jq的安装，即将安装jq依赖"
    apt update -y && apt install -y jq
  fi
}

PutOpenwrtFirewall() {
  LogOut "INFO" "在Openwrt中放行${IPV6ADDRESS}地址"
  ssh root@10.0.0.1 "uci del firewall.@rule[${OPENWRT_FIREWALL_RULE_ID}].dest_ip; \
    uci add_list firewall.@rule[${OPENWRT_FIREWALL_RULE_ID}].dest_ip='${IPV6ADDRESS}'; \
    uci commit; \
    uci changes; "
  OPENWRT_FIREWALL_DEST_IP=$(ssh root@10.0.0.1 "uci show firewall.@rule[${OPENWRT_FIREWALL_RULE_ID}].dest_ip" | awk -F \' '{print $2}')
  LogOut "INFO" "防火墙放行地址已修改为: ${OPENWRT_FIREWALL_DEST_IP}"
}

ShellRun() {
  CheckJqInstalled
  GetInterfaceIPv6Address
  GetAddressFormCloudflare
  if [ "$IPV6ADDRESS" != "$CLOUDFLARE_IP_CONTENT" ]; then
    PutAddress2Cloudflare
    PutOpenwrtFirewall
  else 
    LogOut "INFO" "无需更新地址"
  fi
}

ShellRun

exit