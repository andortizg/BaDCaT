// *******************************************************
// Nifi related functions
//
// Author: Andres Ortiz, 2023 
// Based on the previous work of Alexander Nihirash, 2021
// *******************************************************
int con_sta=0;


void nifi_init(void)
{
    const char init_str[] = {"N", "i", "F", "i",0x00};
    char rb=0xff;
    int success=0;
    unsigned long timer=0;
    Print("Initializing your modem...");
    while (success==0)
    {
        uart_write(OP_Reset);        // send reset command
        rb = uart_readTimeout(retries);
        while(rb!=0)
        {
            uart_write(OP_Reset);
            rb = uart_readTimeout(retries);
            delay(20);
            timer++;
            if (timer>100)
            {
                Print("[TIMEOUT ERROR]\n");
                break;
            }
        }

        char* rxbuf = receive_buffer_NULL();
        if (StrCompare(init_str,rxbuf)==0)
            {
                Print("[DONE]\n");
                success=1;
                break;
            }
    }
}

void get_AP_LIST(void)
{   
    static char buf[50];
    char rb;
    unsigned char i;

    uart_write(0x30);
    Print("getting AP LIST...\n");
    while(!uart_isavailable())
    {
        __asm  
        nop  
        __endasm;
    }

    while(uart_isavailable())
    {
        rb=uart_readTimeout(retries);
        i=0;
        while((rb!=0x00)&&(rb!=0xFF))
        {
            buf[i]=rb;
            rb=uart_readTimeout(retries);
            i++;        
        }
        buf[i]=0x00;
        Print(buf);
        Print("\n");
    }
}

void setAP(void)
{
    char buf[51];
    char rc;
    unsigned char i;
    uart_write(OP_SET_AP);
    Print("SSID:");
    InputString(buf,50);
    i=0;
    while(buf[i]!=0x00)
    {
        uart_write(buf[i]);
        i++;
    }
    uart_write(0x00);
    Print("\n");
    Print("Password:");
    InputString(buf,50);
    i=0;
    while(buf[i]!=0x00)
    {
        uart_write(buf[i]);
        i++;
    }
    uart_write(0x00);
    Print("\n");
    rc=uart_readB();
    if (rc==0x00)
    {
        Print("Connected!\n");
        con_sta=1;
    }
    else{
        Print("ERROR\n");
    }
}

int GetAP(void)
{
    static char buf[64];  // Asignar memoria para el string
    unsigned char i=0;
    char rc;
    Print("Current AP: ");
    uart_write(OP_GET_AP);
    rc=uart_readB();
    if (rc==0x00)
    {
        rc=uart_readB();
        while(rc!=0)
        {
            buf[i]=rc;
            i++;
            rc=uart_readB();
        }
        buf[i]=0x00;
        Print(buf);
        Print("\n");
        return 0;
    }
    else
    {
        Print("Not Connected\n");
        return -1;
    }
}

void GetIP(char tip)
{
    int i=0;
    char rc;
    uart_write(OP_GET_IP);
    uart_write(tip);
    rc=uart_readB();
    if (rc==0x00)
    {
        for (i=0; i<4;i++)
        {
                rc=uart_readB();
                if (i>0) Print(".");
                PrintDec(rc);
        }
    }
    else
    {
    Print("No IP");
    }
}

void GetVERSION(void)
{
    char rc=0xff;
    Print("Firmware version: ");
    uart_write(OP_VERSION_STR);
    rc=uart_readB();
    if (rc==0x00)
    {
        rc=uart_readTimeout(retries);
        while (rc!=00)
        {
            PrintChar(rc);
            rc=uart_readTimeout(200);
        } 
        Print("\n");
    }
    else
    {
        Print("ERROR\n");
        flush_FIFO();
    }
}