// ****************************
// BaDCaT related functions
//
// Author: Andres Ortiz, 2023 
// ****************************

#include "fcb.h"

char fbuffer[512];


char check_badcat(void)
{
    char av=0;
    if (check_BC()==1)
    {
        Print("BaDCaT: found\n");
        av=1;
    }
    else
    {
        Print("BaDCaT: NOT found\n");
    }
    if (uart_checkAFE()==1)
    {
        Print("Version: AFE \n");
        av=2;
    }
    else
    {
        Print("Version: No AFE\n");
    }
    return av;
}


int badcat_upload_protocol(void)
{

    // Start file upload protocol to BaDCaT flash
    // Protocol is as follows:
    // Send 0xfe command (FWUPDATE command)
    // BaDCaT replies ">" waiting for file size
    // Since firmware filesize is 256KB, we send "261472<" (ASCII string with terminator character)
    // Start sending the binary file byte by byte
    unsigned char rb=0;
    unsigned char filesize_str[]="261472>";
    unsigned int i;

    //nifi_init();                      // Reset the Firmware
    uart_write(OP_FILEUPLOAD);          // send 0xfd command
    rb=uart_readB();       // Receive character
    
    if (rb==0x3E)           // We expect ">" character
    {
        Print("Current firmware: NiFi\n");
        /*uart_write(OP_VERSION_STR);
        char* rxbuf = receive_buffer_NULL2();
        Print(rxbuf);
        Print("\n");*/
    }
    else
    {
        Print("Firmware Error. Exiting.\n");
        return 1;
    }

    // Send the filesize as a string terminated with ">"

    for (i=0;i<sizeof(filesize_str); i++) 
    {
        //PrintChar(filesize_str[i]);
        uart_write(filesize_str[i]);
        delay(1);
    }

    // Wait for ">" to start sending file
    rb=0;
    while(rb!=0x3e)
    {
        rb=uart_readTimeout(retries);
    }
    return 0;  
}

void badcat_fwupdate(char *file_name)
{
    int res=0;
    // Upload firmware from disk
    res=FT_LoadbinFile(file_name);
}

void badcat_savefw(void)
{
    int res=0;
    // Upload firmware from disk
    res=FT_SavebinFile("f.bin");
}

void formatflash(void)
{
  char rc;
  Print("Formatting Flash... ");
  uart_write(OP_FORMATFLASH);
  rc=uart_readB();
  if (rc==0x00)
  {
    Print("OK\n");
    rc=0xff;
    while(rc!=0x00)
    {
        rc=uart_readTimeout(retries);
        PrintChar(rc);
    }
  }
  else 
  { 
    Print("ERROR");
    flush_FIFO();
  }
}

