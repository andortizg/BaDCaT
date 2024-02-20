// ************************************************
// FCB Management
//
// Author: Andres Ortiz, 2023 
//
// ************************************************


#include "../fusion-c/header/msx_fusion.h"
#include "../fusion-c/header/io.h"
#include <string.h>
#include <stdio.h>
#include "utils.h"

static FCB file; 

void FT_errorHandler(char n, char *name)            
{
  switch (n)
  {
      case 1:
          Print("\n\rERROR opening file ");
          Print(name);
      break;
 
      case 2:
          Print("\n\rERROR closing file ");
          Print(name);
      break;  
 
      case 3:
          Print("\n\rStop Kidding, run me on MSX2 !");
      break; 

      case 4:
        Print("\n\rError writing file ");
        Print(name);
      break;
  }
Exit(0);
}

void FT_SetName( FCB *p_fcb, const char *p_name ) 
{
  char i, j;
  memset( p_fcb, 0, sizeof(FCB) );
  for( i = 0; i < 11; i++ ) {
    p_fcb->name[i] = ' ';
  }
  for( i = 0; (i < 8) && (p_name[i] != 0) && (p_name[i] != '.'); i++ ) {
    p_fcb->name[i] =  p_name[i];
  }
  if( p_name[i] == '.' ) {
    i++;
    for( j = 0; (j < 3) && (p_name[i + j] != 0) && (p_name[i + j] != '.'); j++ ) {
      p_fcb->ext[j] =  p_name[i + j] ;
    }
  }
}

/* ---------------------------------
          FT_LoadbinFile

    Load a binary file and send data 
            to the UART
-----------------------------------*/ 
int FT_LoadbinFile(char *file_name)
    {
        int rd=16;
        unsigned int i;
        unsigned long j=0;
        char buffer[512];

        FT_SetName( &file, file_name );
        if(fcb_open( &file ) != FCB_SUCCESS) 
        {
          FT_errorHandler(1, file_name);
          return (0);
        }
        Print("Uploading firmware *");
        //while (uart_isavailable()) PrintChar(uart_readTimeout(retries));
        //delay(100);
        //while (uart_isavailable()) PrintChar(uart_readTimeout(retries));

        while(rd!=0)
        {
            rd = fcb_read(&file, buffer, 512);
                if (rd!=0)
                {
                  for (i=0;i<rd;i++)
                    {
                      uart_write(buffer[i]);
                      //while (uart_isavailable()) (rb=uart_readTimeout(retries));
                      //printf("%x ", (unsigned char)buffer[i]);
                      //delay(10);
                    }
                  j++;
                  if ((j%4096)==0)
                  {
                    j=0;
                    Print("*");
                  }
                }
                //while (uart_isavailable()) PrintChar(uart_readTimeout(retries));
        }

      if( fcb_close( &file ) != FCB_SUCCESS ) 
      {
         FT_errorHandler(2, file_name);
          return (0);
      }
      while (uart_isavailable()) PrintChar(uart_readTimeout(retries));
      Print("\n");      
return(1);
}



int FT_SavebinFile(char *file_name)
    {
        unsigned long i;
        unsigned long bw=0;
        unsigned char rb=0;
        unsigned int MaxToWrite;
        unsigned int finish=0;
        char buffer[512];
        
        FT_SetName( &file, file_name );
        // Create & Writing a file with FCB MSXDOS 1 & 2
        printf("Creating File %s \n\r",file_name);
        if(fcb_create( &file ) != FCB_SUCCESS) 
        {
            FT_errorHandler(4, file_name);
            return (0);
        }   
        Print("Writing file");
        while (rb!=0x3e)
        {
          uart_write(0xfa);
          rb=uart_readTimeout(retries);
          PrintChar(rb);
        }

        while (finish==0)   
        {
          if ((261472-bw)>512)
          { 
            MaxToWrite=512;
            bw=bw+512;
          }
          else
          {
            MaxToWrite=261472-bw;
            finish=1;
          }
          for (i=0; i<MaxToWrite; i++)
          {
            buffer[i]=uart_readTimeout(retries);
          }
            fcb_write( &file, buffer, MaxToWrite ); 
            //Locate(1,20); printf("%u  %d",bw, finish);
        }
        Print("EOF");
        if( fcb_close( &file ) != FCB_SUCCESS ) 
        {
          FT_errorHandler(2, file_name);
          return (0);
        }      
return(1);
}

// Get File size

/*unsigned long get_filesize(char *file_name)
{
  int fH;
  unsigned long fsize;
  FCBs();
  fH = Open(file_name, O_RDONLY);
  // Read registers
  if (fH < 0) {
      printf("Can't open input file\r\n");
      return (0);
  }
  Lseek(fH, 0L, SEEK_END);
  fsize = Ltell(fH,fsize);
  Close(fH);
  return fsize;
}*/

void download_http(void)
{
    uart_write(OP_DLOADHTTP);
    // Wait for URL and filename keyboard input
    send_string("Repository URL: ");                
    send_string("File name: ");  
    // Prints out Nifi output
    while(uart_isavailable()) PrintChar(uart_readTimeout(retries));
}

