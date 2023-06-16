# UNAPI driver for BaDCaT wifi modem (Only for AFE version and MSX2 computers!)
Based on the work of Alexander Nihirash ( @nihirash ) and his Nifi firmware

- badcat_config : Configuration and firmware utility
- bcunapi : UNAPI driver. Once loaded, you can use BaDCaT wifi modem as standard UNAPI network interface

# Limitations

- Passive TCP not yet implemented. FTP based on passive connections is not working.
- ICMP not yet implemented. PING command is not working.
- ROM loading from BaDCaT does not work with the UNAPI firmware


# Update procedure

## From non-unapi version: 

1. In AT+CONFIG menu, use the the repository <badcatrepo.duckdns.org>  -> [REPO] option
2. In command mode: at&u=2.0
3. Wait for BaDCaT reboot

## From unapi version:
- Use badcat_config tool with the repository: <badcatrepo.duckdns.org>



