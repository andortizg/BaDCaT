// 16C550C register addresses
#define RBR_THR 0x80
#define IER     0x81
#define IIR_FCR 0x82
#define LCR     0x83
#define MCR     0x84
#define LSR     0x85
#define MSR     0x86
#define SR      0x87

// Define Nifi commands
#define OP_Reset        0x00
#define OP_GET_IP       0x02
#define OP_GET_AP_LIST  0x30 
#define OP_SET_AP       0x31 
#define OP_GET_AP       0x32 
#define OP_DLOADHTTP    0xF8
#define OP_OTAUPDATE    0xF9
#define OP_READFILE     0xFA
#define OP_SHOWFILES    0xFB
#define OP_FORMATFLASH  0xFC
#define OP_FILEUPLOAD   0xFD
#define OP_FWUPDATE     0xFE
#define OP_VERSION_STR  0xFF

// define NIFI ESP IP constants
#define IP_LOCAL         1
#define IP_REMOTE        2
#define IP_MASK          3
#define IP_GATEWAY       4
#define IP_DNS1          5

// UART constants
#define retries         50

// DEBUG definitions
#define debug           1