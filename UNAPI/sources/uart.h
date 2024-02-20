// ****************************
// 16C550C UART functions
//
// Author: Andres Ortiz, 2023 
// ****************************


void uart_init(void) 
{
  Print("Initializing UART...\n");	
  OutPort(MCR,0x0D);            // Assert RTS
  OutPort(IIR_FCR, 0x87);       // Enable fifo 8 level, and clear it
  OutPort(LCR,0x83);          // 8n1, DLAB=1
  OutPort(RBR_THR,0x01);      // 115200 (divider 1)
  OutPort(IER,0x00);            // (divider 0). Divider is 16 bit, so we get (#0002 divider)
  OutPort(LCR,0x03);       // 8n1, DLAB=0
  OutPort(IER,0x00);       // Disable int
  OutPort(MCR,0x2F);       // Enable AFE (AFE + RTS bits)
}




char uart_checkAFE(void)
{
    // Check if AFE is present
    unsigned char ub=0;
    OutPort(SR,0x22);
    if (InPort(SR)==0x22)
    {
        ub=1;
    }
    return ub;
}

unsigned char uart_isavailable(void)
{
    // Check if Data is available in UART FIFO (LSR0 bit is set)
    return (InPort(LSR)&0x01);
}

char uart_read(void)
{
    char readbyte=0;
    // Non-blocking read
    if (uart_isavailable()) {
        readbyte=InPort(RBR_THR);    
        }
    return readbyte;
}

char uart_readTimeout(unsigned char nret)
{
    char rb=0;
    unsigned int i;
    // Tries read byte with timeout
    for (i = 0; i < nret; ++i)
    {
        if (uart_isavailable())
        {
            rb=uart_read();
            break;
        }
        __asm 
        halt 
        __endasm;
    }
    return rb;
}

char uart_readB(void)
{
    // Blocking read
    unsigned char rb;
    unsigned long i=0;
    while(uart_isavailable()==0)
    {
        __asm 
        halt
        __endasm;
    }
    rb=InPort(RBR_THR);
    return rb;
}

void uart_write(char wb)
{
    while ((InPort(LSR)&0x20)==0)
    {
        __asm 
        nop 
        __endasm;
    }
    OutPort(RBR_THR,wb);
}



char check_BC(void)
{
    // Check if badcat is present
    unsigned char ub=0;
    OutPort(SR,0x55);
    if (InPort(SR)==0x55)
    {
        ub=1;
    }
    return ub;
}

// Helper Functions

void read_sep_NULL( char *output) {
    char i = 0; 
    char rb;
    uart_readTimeout(retries);
    while (uart_readTimeout(retries)!= 0x00) {
        rb=uart_readTimeout(retries);
        output[i] = rb;
        i++;
    }
    output[i]=0x00;
}

char* receive_buffer_NULL()
{
        char buf[64];  // Asignar memoria para el string
        unsigned char i=0;
        char rc;
        while(uart_isavailable())
        {
            rc=uart_readTimeout(retries);
            if (rc!=0x00)
            {
              buf[i]=rc;
              i++;  
            }
            else
            {
              buf[i]=0x00;
            }
        }
        return buf;
}

char* receive_buffer_NULLB()
{
        char buf[200];  // Asignar memoria para el string
        char rc;
        int i=0;
        rc=uart_readB();
        if (rc==0x00)
        {
            rc=0xff;
            while(rc!=0x00)
            {
                rc=uart_readB();
                if (rc!=0x00) 
                {
                    buf[i]=rc;
                    i++;
                }

            }
        }
        return buf;
}

void flush_FIFO(void)
{
    volatile int i;
    unsigned char r;
    for (i=0;i<20;i++)
    {
        r=InPort(RBR_THR);
    }
}

void delay(unsigned int n)
{
    // Implements a n/50 seg delay
    unsigned int i;
    for (i=0;i<n; i++)
    {
        __asm 
        halt 
        __endasm;
    }
}

