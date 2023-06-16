#UNAPI driver for BaDCaT wifi modem.
-------------------------------------
Based on the work of Alexander Nihirash ( @nihirash ) and his Nifi firmware

- badcat_config : Configuration and firmware utility
- bcunapi : UNAPI driver. Once loaded, you can use BaDCaT wifi modem as standard UNAPI network interface

#Limitations

- Passive TCP not yet implemented. FTP based on passive connections is not working.
- ICMP not yet implemented. PING command is not working.
