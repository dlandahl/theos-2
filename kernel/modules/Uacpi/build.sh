gcc source_code/source/*.c -Isource_code/include -c -mno-red-zone -mcmodel=kernel -fno-pie
ar rcs uacpi.a *.o
rm *.o
