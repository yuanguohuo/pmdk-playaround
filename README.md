# btree

## Test With PMem Module

### 配置Pmem (假设是Intel Optane)

- 发现

```
# dmesg | egrep -i 'nfit|pmem|nvdimm'
[    0.031524] ACPI: NFIT 0x0000000067082000 0000D8 (v01 ALASKA A M I    00000002 INTL 20091013)

# ipmctl show -dimm
 DimmID | Capacity    | LockState | HealthState | FWVersion
===============================================================
 0x0011 | 126.742 GiB | Disabled  | Healthy     | 02.02.00.1553

# ndctl list -D
[
  {
    "dev":"nmem0",
    "id":"8089-a2-2116-00003917",
    "handle":17,
    "phys_id":25,
    "flag_failed_map":true
  }
]

# ndctl list -R
# 没有region
```

- 配置AppDirect模式，系统自动创建Interleave Set和Region

```
# ipmctl create -goal PersistentMemoryType=AppDirect

The following configuration will be applied:
 SocketID | DimmID | MemorySize | AppDirect1Size | AppDirect2Size
==================================================================
 0x0000   | 0x0011 | 0.000 GiB  | 126.000 GiB    | 0.000 GiB

Do you want to continue? [y/n] y
Created following region configuration goal

 SocketID | DimmID | MemorySize | AppDirect1Size | AppDirect2Size
==================================================================
 0x0000   | 0x0011 | 0.000 GiB  | 126.000 GiB    | 0.000 GiB

A reboot is required to process new memory allocation goals.
```

- 重启之后，可以看到Region

```
# ndctl list -R
[
  {
    "dev":"region0",
    "size":135291469824,
    "available_size":135291469824,
    "max_available_extent":135291469824,
    "type":"pmem",
    "iset_id":-5807432881699911134,
    "persistence_domain":"memory_controller"
  }
]

# dctl list -N
# 没有namespace
```

# 创建devdax类型的Namespace

首先，要测试通过PMDK直接访问PMem，绕过内核态Filesystem，需要devdax类型的namespace，它是一个chardev，一般是`/dev/dax0.0`。

其次，默认对齐是2MiB。为了测试方便，这里设置为4KiB；这样`mmap`不容易失败：虽然btree.c没有显示`mmap`，但PMDK底层会调用；若传入的内存地址不对齐（2MiB或4KiB的整数倍），则失败。问题：会影响性能吗？

```
# ndctl create-namespace --region=region0 --mode=devdax --align=4096
{
  "dev":"namespace0.0",
  "mode":"devdax",
  "map":"dev",
  "size":"124.03 GiB (133.18 GB)",
  "uuid":"8a490caf-63c2-47c6-aee1-8cfbc66697a3",
  "daxregion":{
    "id":0,
    "size":"124.03 GiB (133.18 GB)",
    "align":4096,
    "devices":[
      {
        "chardev":"dax0.0",
        "size":"124.03 GiB (133.18 GB)"
      }
    ]
  },
  "align":4096
}

# ls -l /dev/dax*
crw------- 1 root root 250, 21 Jun  9 10:36 /dev/dax0.0
```

- 运行程序

注意：因为当前模块不支持Saft Shutdown State (SDS)特性，所以Makefile中通过PMEMOBJ_CONF="sds.at_create=0"告知PMDK；

```
# make clean
rm -f pmdk_btree

# make build
gcc -I/usr/local/pmdk-2.1.0/include -L/usr/local/pmdk-2.1.0/lib/pmdk_debug btree.c -o pmdk_btree -lpmemobj

#make test_btree
```

- 重新测试

第一次运行pmdk_btree程序，会在PMmem上创建pool；由于PMem是持久化的，pool只会被创建一次，即使`ndctl destroy-namespace namespace0.0`然后重建namespace。

暂时通过这种办法：把devdax namespace删掉，创建一个fsdax amespace，然后使用`dd`强行覆盖掉header。然后再删除fsdax namesapce，重建devdax namespace。

```
# ndctl disable-namespace namespace0.0 
# ndctl destroy-namespace namespace0.0
# 
# ndctl create-namespace --region=region0 --mode=fsdax --align=4096
# dd if=/dev/zero of=/dev/pmem0 bs=4096 count=1024
# 
# ndctl disable-namespace namespace0.0 
# ndctl destroy-namespace namespace0.0

# ndctl create-namespace --region=region0 --mode=devdax --align=4096
```

## Test Without PMem Module

程序会创建一个名为`/dev/dax0.0`的普通文件（可以修改Makefile指定其它路径）；
