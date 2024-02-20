//***********************************************
// ******* Some Helper Functions ****************
//***********************************************

// Get a string from keyboard and finish sending NULL
void send_string(char *printstring)
{
    char strin[100];
    int res=0;
    int i=0;
    Print(printstring);
    res=InputString(strin,90);
    while (strin[i]!=0x00)
    {
        uart_write(strin[i]);
        i++;
    }
    uart_write(0x00);
    Print("\n");
}

