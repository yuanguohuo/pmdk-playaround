.PHONY: build clean test_btree 

all: clean build

build:
	gcc -I/home/zhuhai/local/pmdk-2.1.0/include -L/home/zhuhai/local/pmdk-2.1.0/lib/pmdk_debug btree.c -o pmdk_btree -lpmemobj

test_btree:
	LD_LIBRARY_PATH=/home/zhuhai/local/pmdk-2.1.0/lib/pmdk_debug PMEMOBJ_LOG_LEVEL=0 PMEMOBJ_CONF="sds.at_create=0" ./pmdk_btree /dev/dax0.0 i 123 hello
	LD_LIBRARY_PATH=/home/zhuhai/local/pmdk-2.1.0/lib/pmdk_debug PMEMOBJ_LOG_LEVEL=0 PMEMOBJ_CONF="sds.at_create=0" ./pmdk_btree /dev/dax0.0 p

clean:
	rm -f pmdk_btree
