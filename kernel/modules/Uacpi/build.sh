gcc source_code/source/*.c -Isource_code/include -c -mno-red-zone -mcmodel=kernel -fno-pie -O1
ar rcs uacpi.a *.o
rm *.o
