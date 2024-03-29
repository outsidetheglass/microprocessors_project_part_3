.text
.global _start
.global INT_DIRECTOR
_start:
@ stack logic
 	LDR R13, =STACK1		@ point to base of stack1
	ADD R13, R13, #0x1000
	CPS #0x12
	LDR R13, =STACK2		@ point to base of stack2
	ADD R13, R13, #0x1000
	CPS #0x13
@ turn on GPIO1 clock
	LDR R0, =#0x02
	LDR R1, =0x44E000AC
	STR R0, [R1]
@ GPIO registers and their logic
	LDR R11, =0x4804C000 	@ base address for GPIO1
	MOV R9, #0x01E00000		@ all USR LEDS high value 
	STR R9, [R11, #0x190]	@ store LEDs high value into base address + CLEARDATAOUT offset
	STR R9, [R11, #0x194]	@ store LEDs high value into base address + SETDATAOUT offset 
@ GPIO1_OE logic for USR LEDS 0 through 3
	LDR R6, =0xFE1FFFFF
	STR R6, [R11, #0x134]
@ initialize INTC
	LDR R1, =0x48200000		@ new base address, for INTC_CONFIG
	MOV R2, #0x2			@ reset INTC_CONFIG register
	STR R2, [R1, #0x10]		@ write the value in to EA = base address
	MOV R2, #0x80000000		@ unmask timer 7 at value intc int 95
	STR R2, [R1, #0xC8]		@ write unmasking value in 
	MOV R2, #0x04			@ unmasking value
	STR R2, [R1, #0xE8]		@ write unmasking value in
	
@ inititalize timer
	MOV R0, #0x02
	LDR R9, =0x44E0007C		@ address for CM_PER_timer 7_CLKCTRL
	STR R0, [R9]			@ R0 contains #0x02
	LDR R9, =0x44E00504		@ address for PRCMCLKSEL_TIMER7
	STR R0, [R9] 			@ store R0 into PRCMCLKSEL_TIMER7
	
	LDR R8, =0x4804A000		@ base address for timer 7 registers
	MOV R2, #0x1			@ value to reset timer 7
	STR R2, [R8, #0x10]		@ write to CFG register
	MOV R2, #0x2			@ Value to enable overflow interrupt
	STR R2, [R8, #0x2C]		@ write to IRQ ENABLE SET
	LDR R2, =0xFFFFC000		@ count value to 1/2 second
	STR R2, [R8, #0x40]		@ TLDR load register for reload value
	STR R2, [R8, #0x3C]		@ write to timer 7 TCRR count register
	
@ CPSR enable for IRQ
	MRS R3, CPSR			@ copy CPSR to R3
	BIC R3, #0x80			@ clear bit 7
	MSR CPSR_c, R3			@ write to CPSR	
	
@ flag bits
	MOV R10, #0x01			@  for if LEDs blinking are on or not, 1 is on, 0 is off
	MOV R7, #0x01200000		@ this value will hold whatever LEDs are on right now
	@ if LEDs are on the second time the button has been pressed then I need to turn them off instead
	
@ start timer
	MOV R2, #0x03			@ Load value to auto reload timer and start
	STR R2, [R8, #0x38]

@ From here, loop blinking LEDs 1 and 2 and then LEDS 3 and 0, and so on

@ this first tests if the flag bit is set

@ if flag is set, then go into BLINK_30 and blink LEDs 3 and 0
@ then delay 2 seconds with DELAY1
@ then go to BLINK_21 and blink LEDs 2 and 1
@ then use DELAY2 to delay another 2 seconds, then go back to BLINK_30
@ repeat this until interrupted

@ if flag is not set, then go to LEDS_OFF
@ run a delay in DELAY3 to keep them off while waiting for an interrupt

LOOP:
	NOP
	B LOOP	

@ IRQ for the button
INT_DIRECTOR:
	STMFD SP!, {R0-R3, LR}	@ push registers on stack
CHECK_INTC:
	LDR R0,=0x48200000		@ base address for the INTC
	LDR R2, [R0, #0xF8]		@ read into R2 from the EA of base address + INTC PENDING IRQ3 register offset	
	TST R2, #0x4			@ test R2 against unmask
	BEQ	CHECK_TIMER			@ else go to check timer
	B PASS_ON				@ go to pass on
CHECK_TIMER:
	LDR R1, =0x482000D8		@ Address of INTC PENDING_IRQ2 register
	LDR R0, [R1]			@ read value
	TST R0, #0x80000000			@ check if interrupt from timer
	BEQ PASS_ON				@ no means return
	BNE OVERFLOW_CHECK		@ yes means check for overflow
OVERFLOW_CHECK:
	ADD R1, R8, #0x28		@ address of timer2 irqstatus register
	LDR R0, [R1]			@ read timer 7 TCRR count register, EA = base address of DMtimer7 + IRQ status offset
	TST R0, #0x2			@ check bit 1
	BNE TOGGLE_LEDS			@ if overflowed, go toggle LEDs
	B PASS_ON
PASS_ON:
	LDR R0, = 0x48200048	@ address of INTC_CONTROL register
	MOV R1, #0x01			@ value to clear bit 0
	STR R1, [R0]			@ write to INTC_CONTROL register
	LDMFD SP!, {R0-R3, LR}	@ restore registers
	SUBS PC, LR, #4			@ Pass execution to blinking loop	
TOGGLE_LEDS:
	MOV R2, #0x2			@ value to reset overflow request
	STR R2, [R1]			@ store value into address of timer irqstatus register
	TST R10, #0x01			@ test if LEDs blinking is set right now
	BNE TURN_OFF			@ if so, turn blinking LEDs off
	BEQ TURN_ON				@ and go to pass on
TURN_OFF:
	MOV R10, #0x00			@ set flag bit to show LEDs are off
	MOV R9, #0x01E00000		@ all USR LEDS high value 
	STR R9, [R11, #0x190]	@ store LEDs high value into EA = base address + CLEARDATAOUT offset 
	B PASS_ON
TURN_ON:
	MOV R10, #0x01			@ set flag bit to show LEDs are on
	MOV R9, #0x01E00000		@ all USR LEDS high value 
	STR R9, [R11, #0x194]	@ store LEDs high value into base address + SETDATAOUT offset 
	B PASS_ON 




@BUTTON_SVC:
@turn off IRQ request for GPIO1
	@LDR R1,=0x4804C02C		@GPIO1_IRQSTATUS_0 address
	@MOV R2,#0x40000000		@turn off GPIO1_IRQSTATUS at pin 30 by writing there 1
	@STR R2,[R1]				@Writing value to Turn IRQ off GPIO1_IRQ_RAW_0
@check if GPIO1_DATAOUT has LEDs is lit
	@LDR R1,=0x4804C13C		@GPIO1 0x4804C000 with offset 13C dataout
	@@@@LDR R2,[R1]			@Load value from GPIO_DATAOUT to check
	@@@@TST R2,#0x01E00000		@ test pin 21-24 on GPIO1
@TESTING TIMER RIGHT HERE
	@LDR R0,=0x48042038		@Address for Timer3 TCLR
	@LDR R2,[R0]				@0x3 start and reload timer
	@TST R2,#0x03			@check if timer is running and auto reload 
	@BEQ LED_ON				@if z flag is clear (no led is lit) go LED_ON
	@B LED_OFF				@if z flag is set (at least 1 led is lit) go LED_OFF








.data
.align 2
STACK1:	.rept 1024
	.word 0x0000
	.endr
STACK2:	.rept 1024
	.word 0x0000
	.endr
.END