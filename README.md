# verilog-65C2402-fsm
A verilog model of the mythical 65C24T8 CPU, a 24-bit address version of the WDC 65C02 with 8 threads

## Design goals
The 6502 wasn't commonly used for multi-tasking operating systems, but in the alternative history of 24-bit addresses, a possible next iteration would be to add a few threads, useful for either speeding up interrupt handling or for running multiple processes at once.

The key change is replicating the registers, and not just A/B/X but also S (the stack register), PC (the program counter), and P (the processor flags).  One of each takes up less than 10% of the die space of the CPU.  Adding seven copies of each adds a lot of transitors between the register and the muxes plus the extra logic for a few more opcodes.
This implemention adds eight and a half new opcodes.

$03: THR, switch to another thread, where the thread number is stored in Y
$13: THW, similar to WAI, except it just halts the thread by switching to thread #0, which is presumed to be the interrupt handler and scheduler
$23: THY, copy the current thread's index value into Y
$33: THI #89ABCD, set the PC of thread Y to the immediate (24-bit) address 
$43: TTA, copy register A[Y] to A (where A is the A register of the current thread)
$53: TAT, copy A to register A[Y]
$63: TTS, copy the stack register from thread Y to X
$73: TST, copy X to the stack register of thread Y
$F3: _T_, NOP, which techically isn't needed, but makes it easier to see when a thread changes in the debug log

The Y index register was used to specify the thread being run or modified so that code need not be hardwired with immidiates if there were different versions of the CPU with different numbers of threads.  The CPU instruction from the 65C2402 has been modified to return (in the A register) the number of threads in the least significant nibble.  That thus supports up to 15 threads.

The threads each have their own stack.  Thread 0's is at the traditional range of $0100-$01FF.  Each thread is $0100 higher in memory.  Thus thread 7 uses $0800-$08FF.

The TTS and TST instructions let one thread push items onto other thread's stacks, but only through STA operations and quite a bit of instructions.  There could be push and pull opcodes added that use Y to specify which stack to push and pull from.  That might be useful for single threaded implementations of Forth and C, which generally use multiple stacks.

As Arlet's 65C02 does not include interrupts, I've not modified that logic.  There are a few ways interrupts can be improved with this design.  The best way is to assume thread 0 is the interrupt handler.  Upon an IRQ or NMI, the CPU could set a flag in thread 0's processor flags and after the current opcode finishes, switch to thread 0.  This can be fast as thread switching can be done concurrently with looking up the IRQ/NMI vector.  Plus the A, X, and Y registers are all set with whatever values the interrupt handler last left them with, and the stack has no entries from any of the other threads.

To make it even faster, the CPU could lookup those vectors upon RST, and if they they are all zeros, don't lookup the vectors again until another RST and instead just switch to thread 0 upon an IRQ or NMI (or BRK).  For backwards compatibility, the standard IRQ/NMI behavior of pushing the RTI address and processor flags can continue, without switching the current thread.

For multi-tasking operating systems, these new opcodes are sufficient with no extra hardware for cooperative multitasking.  The scheduler runs in thread 0.  The other threads use THW to yield to the scheduler.  The original Macintosh OS was like this, with a yield() system call.  For Unix-like preemptive multitasking, an external clock generates an interrupt, and the interrupt handler and scheduler work together to pick the next thread to run.

## Cycle counts
Most of the instructions are one cycle, as most use the Y register to specify the thread, and as such, those opcodes have no parameters to load

| Opcode | Cycles |
| :----: | :----: |
| THR    |   3    | This can likely be dropped to 2 with some optimization
| THW    |   3    | (same comment as above)
| THY    |   1    |
| THI    |   4    | 3 cycles are from loading the 24-bit address
| TTA    |   1    |
| TAT    |   1    |
| TTS    |   1    |
| TST    |   1    |
| _T_    |   1    |

## Complexity
The actual verilog code used in this 6502 variation is far from optimized.  The goal was to see if it could be done, and if so, how hard would it be.

Total lines of verilog grew by 100 between the 65C2402 adn 65C24T8.  That is 10% more lines of code.  If optimized, this can probably drop to around 80 lines.

Lines of code doesn't correspond directly to number of gates or transistors, as it takes the same single line to specify one 8-bit A register as eight 8-bit registers.  The netlist is a better judge of that complexity.  The 65C24T8's netlist is 2155 lines long vs. 1773 for the 65C2402.  That is 21% larger.  That seems a reasonable estimate for the additional transistors that would be needed to store the extra 452 bits of registers for eight threads, plus the added decode logic to manage those extra registers. 

## Not hyperthreading

In case you are wondering, this design isn't much at all like hyperthreading on modern processors.  On the ARM and Intel, the CPU has two sets of registers, but to the OS it simply looks like there are two whole CPUs intead of one CPU running two threads.  Hyperthreading was added to keep the CPU busy during cache misses and when I/O would be far slower than CPU speeds.  The two threads on a hyperthreaded CPU can't talk to each other, and can't even tell that there is another thread.

This 6502 threading is instead designed for fast switching between user-controlled threads.  The use case for a 1970s-1980s computer would be to have keyboard input on thread 1, graphics drawing on thread 2, application logic on thread 3, and some other background tasks on other threads.  That way the code for processing input and output and logic could all be cleanly separated, with either a preemptive timer keepign all the threads running or judicious use of THW to drop down to a cooperative scheduler.



# Based on my verilog-65C2402-fsm
## (the README for that follows)
A verilog model of the mythical 65C2402 CPU, a 24-bit address version of the WDC 65C02

## Design goals
The main design goal is to show the possibility of a backwards-compatible 65C02 with a 24-bit
address bus, with no modes, no new flags, just two new op-codes: CPU and A24

$0F: CPU isn't necessary, but fills the A register with #$10, matching the prefix code
$1F: A24 does nothing by itself.  Like in the Z80, it's a prefix code that modifies the
subsequent opcode.

When prefixed all ABS / ABS,X / ABS,Y / IND, and IND,X opcodes take a three byte address in the
subsequent three bytes.  E.g. $1F $AD $EF $78 $56 = LDA $5678EF.

Opcode A24 before a JMP or JSR changes those opcodes to use three bytes to specify the address,
with this 24-bit version of JSR pushing three bytes onto the stack: low, high, 3rd.  The matching
24-bit RTS ($1F $60) pops three bytes off the stack low, high, and 3rd.

RTI always pops four bytes: low, high, and 3rd for the IR, then 1 byte for the flags
(But Arlet's code doesn't support IRQ or NMI, so this CPU never pushes those bytes)

The IRQ, RST, and NMI vectors are $FFFFF7/8/9, $FFFFFA/B/C, and $FFFFFD/E/F.

Without the prefix code, all opcodes are identical to the 65C02.  Zero page is unchanged.
ABS and IND addressing are all two bytes.  Historic code using JSR/RTS will use 2-byte/16-bit
addresses.

The only non-backward-compatible behaviors are the new interrupt vectors. A new RST handler
could simply JMP ($FFFC), presuming a copy of the historic ROM was addressable at in page $FF.
A new IRQ handler similarly JMP ($FFFE).  The only issue would be legacy interrupt handlers
that assumed the return address was the top two bytes on the stack, rather than three.

## Changes from the original

PC (the program counter) is extended from 16-bits to 24-bits 
AB (the address bus) is extended from 16-bits to 24-bits
D3 (a new data register) is added to allow loading three-byte addresses

One new decode line is added for pushing the third byte for the long JSR

A handful of new states were added to the finite state machine that process the opcodes, in general
just one new state for handling ABS addresses, three-byte JMP/JSR, and three-byte RTS/RTI

## The hypothetical roadmap

A potential next step design is to further extend the address bus to 32-bits and 48-bits. 
In keeping with this core design, new prefix codes $2F and $3F would be used.

Along similar lines, the data bus and A, X, Y, and S registers could be extended to 16-bits,
24-bits, and 32-bits, using prefix codes $4F, $8F, and $BF to specify the width for each
instruction.

The CPU (0F) opcode would fill the A register with #$10, #$20, or #$30 depending on the
widest address bus supported, logically or'd with #$40, #$80, or #$B0 to specify the widest
data bus supported.  E.g., #50 = 16-bit data bus/registers and 24-bit address bus.

## Building with and without the testbed

main.v, ram.v, ram.hex, and vec.hex are the testbed, using the SIM macro to enable simulations.
E.g. iverilog -D SIM -o test *.v; vvp test

ram.hex is 128K, loaded from $000000-$01ffff.  Accessing RAM above $020000 returns x's.
vec.hex are the NMI, RST, and IRQ vectors, loaded at $FFFFF0-$FFFFFF (each is three bytes)

Use macro ONEXIT to dump the contents of RAM 16-bytes prior to the RST vector and 16-bites starting
at the RST vector before and after running the simulation.  16-bytes so that you can use those
bytes as storage in your test to check the results.

The opcode HLT (#$db) will end the simulation.


# Based on Arlet Ottens's verilog-65C02-fsm
## (Arlet's notes follow)
A verilog model of the 65C02 CPU. The code is rewritten from scratch.

* Assumes synchronous memory
* Uses finite state machine rather than microcode for control
* Designed for simplicity, size and speed
* Reduced cycle count eliminates all unnecessary cycles

## Design goals
The main design goal is to provide an easy understand implementation that has good performance

## Code
Code is far from complete.  Right now it's in a 'proof of concept' stage where the address
generation and ALU are done in a quick and dirty fashion to test some new ideas. Once I'm happy
with the overall design, I can do some optimizations. 

* cpu.v module is the top level. 

Code has been tested with Verilator. 

## Status

* All CMOS/NMOS 6502 instructions added (except for NOPs as undefined, Rockwell/WDC extensions)
* Model passes Klaus Dormann's test suite for 6502 (with BCD *disabled*)
* BCD not yet supported
* SYNC, RST supported
* IRQ, RDY, NMI not yet supported

### Cycle counts
For purpose of minimizing design and performance improvement, I did not keep the original cycle
count. All of the so-called dead cycles have been removed.
(65C2402 has more cycles for prefixed opcodes, and counts below *include* A24 prefix)

| Instruction type | Cycles | 24-bit |
| :--------------: | :----: | :----: |
| Implied PHx/PLx  |   2    |        |
| RTS              |   4    |   6    |
| RTI              |   5    |   7    |
| BRK              |   7    |        |
| Other implied    |   1    |        |
| JMP Absolute     |   3    |   5    |
| JMP (Indirect)   |   5    |   8    |
| JSR Absolute     |   5    |   7    |
| branch           |   2    |        |
| Immediate        |   2    |        |
| Zero page        |   3    |        |
| Zero page, X     |   3    |        |
| Zero page, Y     |   3    |        |
| Absolute         |   4    |   6    |
| Absolute, X      |   4    |   6    |
| Absolute, Y      |   4    |   6    |
| (Zero page)      |   5    |        |
| (Zero page), Y   |   5    |        |
| (Zero page, X)   |   5    |        |

Add 1 cycle for any read-modify-write. There is no extra cycle for taken branches, page overflows, or for X/Y offset calculations.

Have fun. 
