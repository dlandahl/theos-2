gcc source_code/source/*.c -Isource_code/include -c -mno-red-zone -mcmodel=kernel -fno-pie -mno-tls-direct-seg-refs -O1 -fno-stack-protector -g -gdwarf-4 -gstrict-dwarf -fno-omit-frame-pointer
ar rcs uacpi.a *.o
rm *.o
