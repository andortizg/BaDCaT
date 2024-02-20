// ************************************************
// BaDCaT Configuration tool for NiFi firmware
// For Fusion-C v1.3
// Author: Andres Ortiz, 2023 
// Based on the work of Alexander Nihirash, 2021
// ************************************************


#include <stdio.h>
#include "../fusion-c/header/msx_fusion.h"
#include "../fusion-c/header/io.h"

#include "definitions.h"
#include "uart.h"
#include "nifi.h"
#include "badcat.h"
#include "display.h"



void main(void)
{   
    char option;
    int i=0;
    char rb=0;
    int r;
    char strs[50];
    

    Width(80);
    Cls();
    welcome_msg();
    uart_init();
    check_badcat();
    GetVERSION();
    nifi_init();
    con_sta=GetAP();
    show_IPs();
    
    
   
    while(1)
    {
        Print("\n\n");
        show_menu();
        option=Getche();
        Print("\n");

        switch (option) {
            case '1':
                get_AP_LIST();
                Print("\n");
                setAP();
                break;
                
            /*case '2':
                formatflash();
                break;*/

            case '2':
                if (con_sta==0)
                {
                    uart_write(OP_DLOADHTTP);
                    send_string("Rpository URL: ");
                    send_string("File name: ");
                    // Prints out Nifi output
                    rb=uart_readB();
                    while(rb!=0x00)
                    {
                        PrintChar(rb);
                        rb=uart_readB();
                    } 
                }
                else
                {
                    Print("Not Connected!\n");
                }
                break;

            case '3':
                if (con_sta==0)
                {
                    uart_write(OP_FWUPDATE);
                    send_string("File name: ");
                    send_string("Are you sure? (Y/n): ");
                    // Prints out Nifi output
                    rb=uart_readB();
                    while(rb!=0x00)
                    {
                        PrintChar(rb);
                        rb=uart_readB();
                    } 
                }
                else 
                {
                    Print("Not Connected!\n");
                }
                break;

            case '4':
                Print("Exiting...\n");
                Exit(0);
                break;
        }
    }
    
}
