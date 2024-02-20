// ************************************************
// Menus for the BadCat / NiFi Configuration tool
//
// Author: Andres Ortiz, 2023 
// Based on the work of Alexander Nihirash, 2021
// ************************************************

void welcome_msg(void)
{
    Print("BaDCaT/NiFi UNAPI configuration and update utility\n");
    Print("2023 - Andres Ortiz & Alexander Nihirash\n\n");
}

void show_menu(void)
{
    Print("1. Wifi AP setup\n");
    Print("2. Download file from http repo\n");
    Print("3. Firmware Update\n");
    Print("4. Exit\n");

    Print("\n");
    Print("Select option:");
}


void show_IPs(void)
{    
    Print("Local IP: ");
    GetIP(IP_LOCAL);
    Print("\n");
    Print("Gateway IP: ");
    GetIP(IP_GATEWAY);
    Print("\n");
    Print("DNS IP: ");
    GetIP(IP_DNS1);
    Print("\n");
}