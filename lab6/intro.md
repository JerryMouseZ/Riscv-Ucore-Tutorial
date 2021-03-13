# lab6 进程调度

在前两章中，我们已经分别实现了内核进程和用户进程，并且让他们正确运行了起来。我们同时也实现了一个简单的调度算法，FIFO调度算法，来对我们的进程进行调度。但是，单单如此就够了吗？显然，我们可以让ucore支持更加丰富的调度算法，从而满足各方面的调度需求。在本章里，我们要实现一个调度框架，从而方便我们实现各种各样的调度算法。

在本次实验中，我们在`init/init.c`中加入了对`sched_init`函数的调用。这个函数主要完成调度器和特定调度算法的绑定。初始化后，我们在调度函数中就可以使用相应的接口了。这也是在C语言环境下对于面向对象编程模式的一种模仿。这样之后，我们只需要关注于实现调度类的接口即可，操作系统也同样不关心调度类具体的实现，方便了新调度算法的开发。

在ucore中，进程有如下几个状态：

- `PROC_UNINIT`：这个状态表示进程刚刚被分配相应的进程控制块，但还没有初始化，需要进一步的初始化才能进入`PROC_RUNNABLE`的状态。
- `PROC_SLEEPING`：这个状态表示进程正在等待某个事件的发生，通常由于等待锁的释放，或者主动交出CPU资源（`do_sleep`）。这个状态下的进程是不会被调度的。
- `PROC_RUNNABLE`：这个状态表示进程已经准备好要执行了，只需要操作系统给他分配相应的CPU资源就可以运行。
- `PROC_ZOMBIE`：这个状态表示进程已经退出，相应的资源被回收（大部分），`almost dead`。

一个进程的生命周期一般由如下过程组成：

  **1.** 刚刚开始初始化，进程处在`PROC_UNINIT`的状态
  **2.** 进程已经完成初始化，时刻准备执行，进入`PROC_RUNNABLE`状态
  **3.** 在调度的时候，调度器选中该进程进行执行，进程处在`running`的状态
  **4.(1)** 正在运行的进程由于`wait`等系统调用被阻塞，进入`PROC_SLEEPING`，等待相应的资源或者信号。
  **4.(2)** 另一种可能是正在运行的进程被外部中断打断，此时进程变为`PROC_RUNNABLE`状态，等待下次被调用
  **5.** 等待的事件发生，进程又变成`PROC_RUNNABLE`状态
  **6.** 重复3~6，直到进程执行完毕，通过`exit`进入`PROC_ZOMBIE`状态，由父进程对他的资源进行回收，释放进程控制块。至此，这个进程的生命周期彻底结束

下面我们来看一看如何实现内核对于进程的调度。

## 项目组成

```
lab6
├── Makefile
├── kern
│   ├── debug
│   │   ├── assert.h
│   │   ├── kdebug.c
│   │   ├── kdebug.h
│   │   ├── kmonitor.c
│   │   ├── kmonitor.h
│   │   ├── panic.c
│   │   └── stab.h
│   ├── driver
│   │   ├── clock.c
│   │   ├── clock.h
│   │   ├── console.c
│   │   ├── console.h
│   │   ├── ide.c
│   │   ├── ide.h
│   │   ├── intr.c
│   │   ├── intr.h
│   │   ├── kbdreg.h
│   │   ├── picirq.c
│   │   └── picirq.h
│   ├── fs
│   │   ├── fs.h
│   │   ├── swapfs.c
│   │   └── swapfs.h
│   ├── init
│   │   ├── entry.S
│   │   └── init.c
│   ├── libs
│   │   ├── readline.c
│   │   └── stdio.c
│   ├── mm
│   │   ├── default_pmm.c
│   │   ├── default_pmm.h
│   │   ├── kmalloc.c
│   │   ├── kmalloc.h
│   │   ├── memlayout.h
│   │   ├── mmu.h
│   │   ├── pmm.c
│   │   ├── pmm.h
│   │   ├── swap.c
│   │   ├── swap.h
│   │   ├── swap_fifo.c
│   │   ├── swap_fifo.h
│   │   ├── vmm.c
│   │   └── vmm.h
│   ├── process
│   │   ├── entry.S
│   │   ├── proc.c
│   │   ├── proc.h
│   │   └── switch.S
│   ├── schedule
│   │   ├── default_sched.h
│   │   ├── default_sched_c
│   │   ├── default_sched_stride.c
│   │   ├── sched.c
│   │   └── sched.h
│   ├── sync
│   │   └── sync.h
│   ├── syscall
│   │   ├── syscall.c
│   │   └── syscall.h
│   └── trap
│       ├── trap.c
│       ├── trap.h
│       └── trapentry.S
├── libs
│   ├── atomic.h
│   ├── defs.h
│   ├── elf.h
│   ├── error.h
│   ├── hash.c
│   ├── list.h
│   ├── printfmt.c
│   ├── rand.c
│   ├── riscv.h
│   ├── sbi.h
│   ├── skew_heap.h
│   ├── stdarg.h
│   ├── stdio.h
│   ├── stdlib.h
│   ├── string.c
│   ├── string.h
│   └── unistd.h
├── tools
│   ├── boot.ld
│   ├── function.mk
│   ├── gdbinit
│   ├── grade.sh
│   ├── kernel.ld
│   ├── sign.c
│   ├── user.ld
│   └── vector.c
└── user
    ├── badarg.c
    ├── badsegment.c
    ├── divzero.c
    ├── exit.c
    ├── faultread.c
    ├── faultreadkernel.c
    ├── forktest.c
    ├── forktree.c
    ├── hello.c
    ├── libs
    │   ├── initcode.S
    │   ├── panic.c
    │   ├── stdio.c
    │   ├── syscall.c
    │   ├── syscall.h
    │   ├── ulib.c
    │   ├── ulib.h
    │   └── umain.c
    ├── matrix.c
    ├── pgdir.c
    ├── priority.c
    ├── softint.c
    ├── spin.c
    ├── testbss.c
    ├── waitkill.c
    └── yield.c

16 directories, 105 files
```

