#/bin/bash
#==========================================================
# port_monitor - discovers all interfaces and listening ports
#               spawns tcpdumps to monitor connections for 31 minutes
#               on each of these.
#
# 02/09/18 - mgcdrd
#==========================================================

#==========================================================
# Global variables
#==========================================================
INTERFACE_FILE=/tmp/interface_file.$$
PORTS_FILE=/tmp/ports_file.$$
#PUPPET_DIR=/etc/puppet/scripts
PUPPET_DIR=/etc/puppetlabs/puppet/scripts
LOG_FILE=/var/log/if_monitor.log


#==========================================================
# Gather all the active interfaces
#==========================================================
capture_interfaces() {
   echo "$(date +'%b %d %X') - gathering interfaces" >> ${LOG_FILE}
   ifconfig -a | egrep "^[0-9a-z]{3,7}" | grep -v "lo"| awk '{print $1}' | awk -F: "{print $1}" > ${INTERFACE_FILE} 2> /dev/null
   if [ `grep -c ":" ${INTERFACE_FILE}` ]; then
      sed -i "s/:/ /g" ${INTERFACE_FILE}
   fi
}


#==========================================================
# Gather the open ports, regardless of interface
#==========================================================
capture_ports() {
   echo "$(date +'%b %d %X') - gathering ports" >> ${LOG_FILE}
   netstat -ltuna | egrep "([0-9]{1,3}.){3}[0-9]{1,3}" | egrep -v "[ ]{2,}127.0.0.1" | awk '{print $4}' | awk -F: '{print $2}' | sort | uniq > ${PORTS_FILE} 2> /dev/null
}


#==========================================================
# Launch tcpdump for each interface looks at the open ports
#==========================================================
spawn_tcpdumps() {
   while read inter; do
      while read prts; do
             echo "$(date +'%b %d %X') - starting tcpdump for $inter:$prts" >> ${LOG_FILE}
             # timeout spawns tcpdump with a time limit.  tcpdump only has -c for packet count...if none are
                         #     collected, the tcpdump doesn't close
                         timeout 31m tcpdump -s 0 -i $inter port $prts 1> /tmp/$inter_$prts_$(date +%F) 2> /dev/null &
          done < ${PORTS_FILE}
   done < ${INTERFACE_FILE}
}


#==========================================================
# Verify if there are any existing export files and consolidate them into one
#==========================================================
check_previous(){
   while read inter; do
      while read prts; do
         #Look for the previous captures and start parsing out the sources
             if [ -f /tmp/$inter_$prts_$(date +%F) ]; then
                    echo "$(date +'%b %d %X') - file /tmp/$inter_$prts_$(date +%F) found.  Starting parser" >> ${LOG_FILE}
                        awk "{print $3}" /tmp/$inter_$prts_$(date +%F) | sort | uniq >> /tmp/tcp_parsed.$$
                        rm -f /tmp/$inter_$prts_$(date +%F)

                 fi
                 #Look for any captures from previous day and start parsing out the source
                 if [ -f /tmp/$inter_$prts_$(date +%F -d "yesterday") ]; then
                        echo "$(date +'%b %d %X') - file /tmp/$inter_$prts_$(date +%F -d "yesterday") found.  Starting parser"  >> ${LOG_FILE}
                        awk "{print $3}" /tmp/$inter_$prts_$(date +%F -d "yesterday") | sort | uniq >> /tmp/tcp_parsed.$$
                        rm -f /tmp/$inter_$prts_$(date +%F -d "yesterday")
                 fi
                 #if the if statements ran, remove localhost IPs and save to a puppet file
                 if [ -f /tmp/tcp_parsed.$$ ]; then
                    echo  "$(date +'%b %d %X') - consolidating capture details to ${PUPPET_DIR}/net_services_ready"  >> ${LOG_FILE}
                    ifconfig -a | egrep "inet" | egrep -v "inet6" | awk '{print $2}' > /tmp/ip_addr
                        while read lines; do
                            sed '/$lines/d' /tmp/ip_addr >> /tmp/tcp_host_removed
                                cat /tmp/tcp_host_removed | sort | uniq >> ${PUPPET_DIR}/net_services
                        done < /tmp/ip_addr
                 fi
                 rm -f /tmp/ip_addr 2> /dev/null
          done < ${PORTS_FILE}
   done < ${INTERFACE_FILE}
   #remove any old files
   rm -f /tmp/tcp_parsed.$$ 2> /dev/null
}


#==========================================================
# Gather all the IPs connecting to this host, and create a file
#   with a pretty list of them.  End product is ${PUPPET_DIR}/interfaces_ready
#   while loop removes the local IP addresses of this host
#==========================================================
final_doc_cleanup() {
   if [ -f ${PUPPET_DIR}/net_services ]; then
      cat ${PUPPET_DIR}/net_services | sort | uniq > ${PUPPET_DIR}/interfaces_ready
      rm -rf ${PUPPET_DIR}/net_services
         OIFS=$IFS
         IFS=' '
         for inter in `hostname -I`; do
             sed -i "/$inter/d" ${PUPPET_DIR}/interfaces_ready
         done
         sed -i '/127.0.0.1/d' ${PUPPET_DIR}/interfaces_ready
         IFS=$OIFS
   fi
   rm -rf ${INTERFACE_FILE}
   rm -rf ${PORTS_FILE}
}

capture_interfaces
capture_ports
check_previous
spawn_tcpdumps
final_doc_cleanup
