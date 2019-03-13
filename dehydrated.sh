#!/bin/sh
#
# dehydrated for plesk 12 above by cross
#
# Ref
#   https://github.com/lukas2511/dehydrated
#
# HotTo
#   mkdir /etc/dehydrated
#   wget https://raw.githubusercontent.com/lukas2511/dehydrated/master/dehydrated -O /etc/dehydrated/dehydrated
#   ln -s /etc/dehydrated/dehydrated.sh  /usr/local/bin/dehydrated.sh
#   chmod +x /usr/local/bin/dehydrated.sh
#   dehydrated.sh
#
home_path="/etc/dehydrated"
dehydrated_bin="${home_path}/dehydrated"
wellknown="${home_path}/wellknown"
dehydrated_httpd_conf="/etc/httpd/conf.d/dehydrated.conf"
dehydrated_config="${home_path}/config"
keysize="2048"
api_url_production="https://acme-v02.api.letsencrypt.org/directory"
api_url_staging="https://acme-staging-v02.api.letsencrypt.org/directory"
production=0
defaultconfig=0
domains_txt="${home_path}/domains.txt"

main() {

    if [ -z ${domain_name} ]; then
        echo 'needs domain.tld'
        exit 1
    fi
    
    if [ ! -d  ${domain_path} ]; then
        echo "no such path ${domain_path}"
        exit 1
    fi

    a=$(dig +short +time=2 ${domain_name} @8.8.8.8)
    if [ -z $a ]; then
        echo "${domain_name} needs DNS A record"
        exit 1
    fi
    
    if [ ${production} == 1 ]; then
        api_url=${api_url_production}
    else
        api_url=${api_url_staging}
    fi

    echo "wellknown=${wellknown}"
    echo "dehydrated_httpd_conf=${dehydrated_httpd_conf}"
    echo "dehydrated_config=${dehydrated_config}"
    echo "keysize=${keysize}"
    echo "domain_name=${domain_name}"
    echo "api_url=${api_url}"
    echo "defaultconfig=${defaultconfig}"
    echo "sans=${sans}"

    # 每個網站使用同一個 well-known
    # 所以建立一個 alias 給 apache
    [ -d "${wellknown}" ] || mkdir "${wellknown}"
    if [ ! -f "${dehydrated_httpd_conf}" ]; then
        echo "Alias /.well-known/acme-challenge ${wellknown}" > ${dehydrated_httpd_conf}
        service httpd graceful
        echo 123 > "${wellknown}/123.html" # 確認可被瀏覽
    fi

    # if [ ! -f "${dehydrated_config}" ] || [ ${defaultconfig} == 1 ]; then
        echo "WELLKNOWN=\"${wellknown}\"" >  ${dehydrated_config}
        echo "KEYSIZE=\"${keysize}\"" >> ${dehydrated_config}
        echo "CA=\"${api_url}\""      >> ${dehydrated_config}
    # fi

    # 第一次需要先同意 Let's Encrypt 的條款
    # config 有變動都要再執行一次
    sh ${dehydrated_bin} --register --accept-terms

    is_success=1
    
    if [ ! -z "${sans}" ]; then
        sans=$(echo "${sans}" | sed 's/,/ /g')
        echo "${domain_name} ${sans}" > "${domains_txt}"
    else
        # www 有 A record 才加入
        www_domain_name=''
        a=$(dig +short +time=2 www.${domain_name} @8.8.8.8)
        if [ ! -z $a ]; then
            www_domain_name="www.${domain_name}"
        fi
        
        echo "${domain_name} ${www_domain_name}" > "${domains_txt}"
    fi

    sh ${dehydrated_bin} -c | tee ${home_path}/access_log
    is_success=$?

    grep 'Skipping renew' ${home_path}/access_log
    is_fail=$?
    grep 'Challenge validation has failed' ${home_path}/access_log
    is_fail2=$?

    echo is_success=${is_success}
    echo is_fail=${is_fail}
    echo is_fail2=${is_fail2}

    private_key="${home_path}/certs/${domain_name}/privkey.pem"
    public_key="${home_path}/certs/${domain_name}/cert.pem"
    ca_key="${home_path}/certs/${domain_name}/chain.pem"

    echo private_key=${private_key}
    echo public_key=${public_key}
    echo ca_key=${ca_key}

    # 匯入 plesk
    if [ ${is_success} == 0 ] && [ ${is_fail} == 1 ] && [ ${is_fail2} == 1 ]; then
        if [ -f "${private_key}" ] && [ -f "${public_key}" ] && [ -f "${ca_key}" ]; then
            plesk bin certificate -l -domain ${domain_name} | grep " ${domain_name} "
            if [ $? == 0 ]; then
                aaa="plesk bin certificate -u ${domain_name} -domain ${domain_name} -key-file ${private_key} -cert-file ${public_key} -cacert-file ${ca_key}"
                echo ${aaa}
                eval ${aaa}
            else
                aaa="plesk bin certificate -c ${domain_name} -domain ${domain_name} -key-file ${private_key} -cert-file ${public_key} -cacert-file ${ca_key}"
                bbb="plesk bin domain -u ${domain_name} -ssl true -certificate-name ${domain_name}"
                echo ${aaa}
                eval ${aaa}
                echo ${bbb}
                eval ${bbb}
            fi
        fi
    fi

    aaa="openssl x509 -text -noout -in ${public_key} | egrep '(Issuer: |Subject: |DNS:)'"
    bbb="openssl s_client -connect ${domain_name}:443 < /dev/null 2>&1 | openssl x509 -noout -enddate -issuer 2>/dev/null"
    echo ${aaa}
    eval ${aaa}
    echo ${bbb}
    eval ${bbb}
}
# wildcard 要用 DNS TXT 驗證
# sh /etc/dehydrated/dehydrated -c -d '*.webca.org' --alias wildcard.webca.org
# # INFO: Using main config file /etc/dehydrated/config
# Processing *.webca.org
#  + Creating new directory /etc/dehydrated/certs/wildcard.webca.org ...
#  + Signing domains...
#  + Generating private key...
#  + Generating signing request...
#  + Requesting new certificate order from CA...
#  + Received 1 authorizations URLs from the CA
#  + Handling authorization for webca.org
# ERROR: Validating this certificate is not possible using http-01. Possible validation methods are: dns-01

# Usage: --help (-h)
# Description: Show help text
command_help() {
    printf "\n"
    printf "Usage: %s [-h] [command [argument]] [parameter [argument]] [parameter [argument]] ...\n\n" "${0}"
    printf "Default command: help\n\n"
    echo "Commands:"
    grep -e '^[[:space:]]*# Usage:' -e '^[[:space:]]*# Description:' -e '^command_.*()[[:space:]]*{' "${0}" | while read -r usage; read -r description; read -r command; do
        if [[ ! "${usage}" =~ Usage ]] || [[ ! "${description}" =~ Description ]] || [[ ! "${command}" =~ ^command_ ]]; then
        _exiterr "Error generating help text."
        fi
        printf "    %-32s %s\n" "${usage##"# Usage: "}" "${description##"# Description: "}"
    done
    printf -- "\nParameters:\n"
    grep -E -e '^[[:space:]]*# PARAM_Usage:' -e '^[[:space:]]*# PARAM_Description:' "${0}" | while read -r usage; read -r description; do
        if [[ ! "${usage}" =~ Usage ]] || [[ ! "${description}" =~ Description ]]; then
        _exiterr "Error generating help text."
        fi
        printf "    %-32s %s\n" "${usage##"# PARAM_Usage: "}" "${description##"# PARAM_Description: "}"
    done

    printf -- "\nOn production:\n"
    printf "    %-32s %s\n" "" "sh ${0} -d domain.tld -pn"
    # printf "    %-32s %s\n" "" "sh ${0} -d domain.tld -pn -dc"

    printf -- "\nOn development:\n"
    printf "    %-32s %s\n" "" "sh ${0} -d domain.tld"
    
    printf "\n"
}

[[ -z "${@}" ]] && eval set -- "--help"

while (( ${#} )); do
    case "${1}" in
        --help|-h)
            command_help
            exit 0
            ;;

        # PARAM_Usage: --domain|-d domain.tld
        # PARAM_Description: Use specified domain name
        --domain|-d)
            shift 1
            domain_name="${1}"
            domain_path="/var/www/vhosts/${domain_name}/httpdocs"
            ;;
        
        # PARAM_Usage: --production|-pn
        # PARAM_Description: use the production environment (default staging)
        --production|-pn)
            shift 1
            # 因為有次數限制，所以測試時最好用 staging 環境
            production=1
            ;;

        # PARAM_Usage: --domainpath|-dp [ /var/www/vhosts/domain.tld/subdomain ]
        # PARAM_Description: if subdomain or others
        --domainpath|-dp)
            shift 1
            domain_path="${1}"
            ;;

        # PARAM_Usage: --keysize|-ks [ 2048 | 4096 ]
        # PARAM_Description: 加密長度 (default 2048)
        --keysize|-ks)
            shift 1
            keysize="${1}"
            ;;
            
        # # PARAM_Usage: --defaultconfig|-dc
        # # PARAM_Description: 回復預設 config 檔
        # --defaultconfig|-dc)
        #     shift 1
        #     defaultconfig=1
        #     ;;

        # PARAM_Usage: --sans|-s
        # PARAM_Description: SANs, domain2.tld,sub.domain.tld,.... (default www.domain.tld)
        --sans|-s)
            shift 1
            sans="${1}"
            ;;

        *)
            echo "Unknown parameter detected: ${1}" >&2
            echo >&2
            command_help >&2
            exit 1
            ;;
    esac

    shift 1
done

if [[ ! "${DEHYDRATED_NOOP:-}" = "NOOP" ]]; then
    # Run script
    main "${@:-}"
fi
