;**********************************************************************
;                                                                     *
;    Filename: VFD Main.asm                                           *
;    Date:     17/09/1991 to 21/12/2017                                            *
;    File Version:      0.01                                          *
;                                                                     *
;    Author:             W.K.Todd                                     *
;    Company:                                                         *
;                                                                     * 
;                                                                     *
;**********************************************************************
;                                                                     *
;    Files Required: P16F1572.INC                                      *
;                                                                     *
;**********************************************************************

;**********************************************************************
; The display is multiplexed one frame at a time, by taking a grid
; (or pair of grids) high (output 1) and the anodes low for off or high for on
;
; In order to ensure even brightness at the ends of  the grids, the 
; top and bottom anode segments are illuminated separately with
; the two adjacent grids on.
; 
; A complete scan is made every 19 frames.
; 
;--------------------------------------------------------------------

; Many possible display modes are possible:
; i) for a conventional bar - 0 at the bottom 100 at the top set 'bar on value' (bonvl & bonvr)
;     and 'dot value' (DotVl & DotVr) to zero. Then change the Bar off values (BoffVl & BoffVr)
;	
; ii) for an inverted bar  - 0 at the top 100 at the bottom. Set 'bar off value' (boffvl & boffvr) to 100
;     and 'dot value' (DotVl & DotVr) to zero. Then change the Bar on values (BoffVl & BoffVr)
;
; iii) for trend meter with zero in the middle - For  values < 50 should set Bar on value 
;      (with Boff fixed at 50) For values > 50  Bar off value should be set to 50 + value

; iv) for dot display simply set dot values (dotvl & dotvr)

; v) a centre line for the dot display can be set using Bar on and bar off set to 50

; vi) bar and dot modes can be combined to show level bar with peak dot

;  Plus many more :)
;--------------------------------------------------------------------------------------------------



; PIC12F1572 Configuration Bit Settings

; ASM source line config statements

#include "p12F1572.inc"

; CONFIG1
; __config 0xF9A4
 __CONFIG _CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _BOREN_OFF & _CLKOUTEN_OFF
; CONFIG2
; __config 0xFFFF
 __CONFIG _CONFIG2, _WRT_OFF & _PLLEN_ON & _STVREN_ON & _BORV_LO & _LPBOREN_OFF & _LVP_OFF


;***** VARIABLE DEFINITIONS

DisPort		EQU		PortA
;Bit values for Display control outputs 
SDATA		EQU		RA5	;use alt pin APFCON		
SCLK		EQU		RA4
Latch		EQU		RA2
;Analogue inputs 
Lin		EQU		RA0	;Left analogue input
Rin		EQU		RA1	;Right analogue input	
Switch		EQU		RA3	;switch input

;BANK 0 RAM (80 bytes 0x20 - 0x6F)
;five bytes are required to hold the 40 display bits 
PB29		EQU		0x20		;PB 9-2 
PAB01		EQU		0x21		;PA1b,PA1a,PB1b,Pb1a,PA0b,PA0b,PB0b,Pb0a
PA29		EQU		0x22		;PA 9-2
GRD17		EQU		0x23		;Grid 7 - 0 ,PAB00
GRD810		EQU		0x24		;LED 6-10, Grid 10 - 8
;bytes used by display routine to keep place
FrmNo		EQU		0x25		;Bits 0-5 Current frame number [0=bottom 19=top], bit6-7
AnVal		EQU		0x26		;Current anode value [1-100]

;bit value for the display bytes
IND1		EQU		7			;Aux LED1 (GRD810.7)
IND2		EQU		6			;Aux LED2 (GRD810.6)
IND3		EQU		5			;Aux LED3 (GRD810.5)
IND4		EQU		4			;Aux LED4 (GRD810.4)
IND5		EQU		3			;Aux LED5 (GRD810.3)
PAB00		EQU		0			;Bottom pair of segments (Grd17.0)

ABBAfg		EQU		0			;flag to determine if this pair is ab or ba

PA1b		EQU		7			;anode bits
PA1a		EQU		6
PB1b		EQU		5
PB1a		EQU		4
PA0b		EQU		3
PA0a		EQU		2
PB0b		EQU		1
Pb0a		EQU		0

;values for bar and dot display 0-100 [0=off, 1= bottom, 100= top]
;set these bytes from your code to light display
BonVl		EQU		0x27		;Bar on value left
BoffVl		EQU		0x28		;Bar off value left
BonVr		EQU		0x29		;Bar on value right
BoffVr		EQU		0x2A		;Bar off value right
DotVl		EQU		0x2B		;Dot on value left
DotVr		EQU		0x2C		;Dot on value right	
AuxInd		EQU		0x2D		;Aux indicators and PAB00
RefVl		EQU		0X2E		;Ref Dot left (dimmed)	
RefVr		EQU		0x2F		;Ref Dot Right (dimmed)

;demo control variables
TestVal		EQU		0x30		;value is ramped up to 100 then down to 0 in a loop
Mode		EQU		0x31		;display mode changes after each ramp		
RefCnt		EQU		0x32		;Dimmer control count
Randlo		EQU		0x33		;random shift reg
RandHI		EQU		0x34		
		
;PPM prefs
DecRate		EQU		0x35		;Decay rate
PkHldTm		EQU		0x36		;Peak Hold Time (counter 0=off FF=hold)
		
;BANK 1 RAM (80 bytes - FSR 0xA0H - 0xEF)	
;ADC input values  (2'sComp) etc. 	
ALinH		EQU		0x20	;analogue left in high byte
ALinL		EQU		0x21	;low byte
ARinH		EQU		0x22	;analogue Right in low byte
ARinL		EQU		0x23	;low byte
		
PLinH		EQU		0x24	;Peak left in high byte bits 8-1 (no sign bit)
PLinL		EQU		0x25	;low byte (bit 0)
PRinH		EQU		0x26	;Peak Right in low byte
PRinL		EQU		0x27	;low byte
		
Ptemp		EQU		0x2F	;temp store for peak	
		
;Common RAM (16 bytes   0x70 - 0x7F)		
Temp0		EQU		0x70		;temp bytes for normal routines
Temp1 		EQU		0x71
Intemp0		EQU		0x72		;temp bytes for interrupt routines
Intemp1		EQU		0x73

Control		Equ		0x7F		;control bits
;Control bits
RampDwn		equ		0		;count up/dwn flag
SwtDBB		equ		1		;mode switch debounce bit
SwtUP		equ		2		;up switch
SwtDwn		equ		3		;down switch
		
ADCch		equ		6		;analogue input 0=right 1=left
RefEn		equ		7		;display flag for ref marker dimmer


;**********************************************************************
	    ORG     0x000             ; processor reset vector

	    goto    main              ; go to beginning of program


	    ORG     0x004             ; interrupt vector location
; isr code can go here or be located as a call subroutine elsewhere
	    banksel	PIR1	
	    btfss	PIR1,ADIF 	; test ADC interupt
	    bra		intT0
	    bcf		PIR1,ADIF	;clear interrupt
	    
	    banksel	ADCON0		;bank1
	    movlw	B'00000101'	    
	    btfss	Control,ADCch	;0=right 1=left
	    movlw	B'00000001'
	    movwf	ADCON0		;select other channel (start Tacq)

	    movlw	0x80		;save channel value as twos compliment
	    xorwf	ADRESH,w	;get high byte and compliment	
	    ;movf	ADRESH,w	;get high byte 	
	    
	    btfsc	Control,ADCch	;test channel and toggle
	    bra		saveLch
	    bsf		Control,ADCch	;toggle input to left ch
;save  Right channel and test peak
	    movwf	ARinH		;save left channel
	    movf	ADRESL,w
	    movwf	ARinL
	    lslf	ARinL,w		;get bit 1 into carry
	    rlf		ARinH,w		;get sign bit (9) into carry and 8-1 into w
	    btfsc	status,c	;test sign bit
	    xorlw	0xff		;rectify
	    addlw	0x01
	    movwf	Ptemp		;save for later
	    subwf	PRinH,w		;compare with Peak value
	    btfsc	status,c	
	    bra		xitPR		;Input < Peak we're done
	    ;btfss	status,z	
	    ;bra		newPR		;input > Peak save new peak
	    ;btfss	ARinL,6		;test input bit 0
	    ;bra		xitPR		;if low then bit is not greater than peak so exit
	    
newPR	    movf	Ptemp,w
	    movwf	PRinH		;save new peak   	    
	    ;bsf		PRinL,7
	    ;btfss	ARinL,6		;test bit 0
	    ;bcf		PRinL,7
	    
	    bra		xitPR
	    
	    
saveLch	    bcf		Control,ADCch	;toggle channel to right ch
	    movwf	ALinH		;save left channel
	    movf	ADRESL,w
	    movwf	ALinL
	    
	    lslf	ALinL,w		;get bit 1 into carry
	    rlf		ALinH,w		;get sign bit (9) into carry and 8-1 into w
	    btfsc	status,c	;test sign bit
	    xorlw	0xff		;rectify
	    addlw	0x01
	    movwf	Ptemp
	    subwf	PLinH,w		;compare with Peak value
	    btfsc	status,c	
	    bra		xitPL		;Input < Peak we're done
	    ;btfss	status,z	
	    ;bra		newPL		;input > Peak save new peak
	    ;btfss	ALinL,6		;test input bit 0
	    ;bra		xitPL		;if low then bit is not greater than peak so exit
	    
newPL	    movf	Ptemp,w
	    movwf	PLinH		;save new peak 
	    ;bsf		PLinL,7
	    ;btfss	ALinL,6		;test bit 0
	    ;bcf		PLinL,7
xitPL
xitPR	    ;
	    
intT0	    btfss	INTCON,T0IF	    ;test timer 0 interrupt	
	    bra		intxit
	    bcf		INTCON,T0IF	    ;clear the interrupt flag
	    ;call	DoFrm
	    call	setTimer
	    movlb	0x01
	    bsf		ADCON0,ADGO	;start new ADC process
intxit	    retfie                    ; return from interrupt

;==========================================< Tables >=======================================
;------Anode value table
;This holds the initial value for the anodes in the current frame (faster than multiplying on the fly) 
AnVTab	    brw
	    retlw 	.1		;G1		1-9
	    retlw 	.10		;G2-1	10,11
	    retlw 	.12		;G2		12-19
	    retlw 	.20		;G3-2	20,21
	    retlw	.22		;G3		22-29
	    retlw	.30		;G4-3	30,31
	    retlw	.32		;G4
	    retlw	.40		;G4-5
	    retlw	.42		;G5
	    retlw 	.50		;G5-6
	    retlw 	.52		;G6
	    retlw 	.60		;G6-7
	    retlw 	.62		;G7
	    retlw 	.70		;G7-8
	    retlw 	.72		;G8
	    retlw 	.80		;G8-9
	    retlw 	.82		;G9
	    retlw 	.90		;G9-10
	    retlw 	.92		;G10

;------Grid tables------
; These hold the grid setup value for each frame (high and low bytes).
;GrdTabL bit 0 indicates an ab or ba frame pair
 
GrdTabL	    brw
	    retlw 	0x02	;G1
	    retlw 	0x07	;G2-1 AB
	    retlw 	0x04	;G2
	    retlw 	0x0c	;G3-2 BA
	    retlw	0x08	;G3
	    retlw	0x19	;G4-3 AB
	    retlw	0x10	;G4
	    retlw	0x30	;G4-5 BA
	    retlw	0x20	;G5
	    retlw 	0x61	;G5-6 AB
	    retlw 	0x40	;G6
	    retlw 	0xc0	;G6-7 BA
	    retlw 	0x80	;G7
	    retlw 	0x81	;G7-8 AB
	    retlw 	0x00	;G8
	    retlw 	0x00	;G8-9 BA
	    retlw 	0x00	;G9
	    retlw 	0x01	;G9-10 AB
	    retlw 	0x00	;G10
	
GrdTabH	    brw
	    retlw 	0x00	;G1
	    retlw 	0x00	;G2-1
	    retlw 	0x00	;G2
	    retlw 	0x00	;G3-2
	    retlw 	0x00	;G3
	    retlw 	0x00	;G4-3
	    retlw 	0x00	;G4
	    retlw 	0x00	;G4-5
	    retlw 	0x00	;G5
	    retlw 	0x00	;G5-6
	    retlw 	0x00	;G6
	    retlw 	0x00	;G6-7
	    retlw 	0x00	;G7
	    retlw 	0x01	;G7-8
	    retlw 	0x01	;G8
	    retlw 	0x03	;G8-9
	    retlw 	0x02	;G9
	    retlw 	0x06	;G9-10
	    retlw 	0x04	;G10

;-----------------------------------------< end of tables >-----------------------------------


;=======================================< Start of main code >===============================
main:
;start
	    ;initialise clock
	    banksel	OSCCON		;BANK 1
	    movlw	B'11110000' ;32Mhz clock
	    ;movlw	B'01111010' ;16Mhz clock
	    ;movlw	B'01110010' ;8Mhz clock
	    ;movlw	B'01101010' ;4Mhz clock
	    movwf	OSCCON
	    
	    ;initialise analogue ports
	    banksel	FVRCON		;BANK 2
	    movlw	B'10000010'	;FVR for ADC ref set to 2.048v
	    ;movlw	B'10000001'	;FVR for ADC ref set to 1.024v
	    movwf	FVRCON
	    
	    banksel	ANSELA		;select bank 3
	    movlw	B'00000011' 
	    movwf	ANSELA		;RA0 & RA1 analogue input	    
	    
	    banksel	ADCON0		;BANK 1
	    movlw	B'00000001'	;enable ADC
	    movwf	ADCON0
	    
	    ;banksel	ADCON1		;BANK 1
	    movlw	B'01010011'	;left justify, Fosc/32, Vrpos = FVR
	    movwf	ADCON1
	    
	    ;banksel	ADCON2		;BANK 1
	    movlw	B'00000000'	;No auto triggers
	    movwf	ADCON2
	    
	    ;initialise O/P pins
	    ;banksel	TrisA		;BANK 1
	    movlw	B'00000011'	;RA0 & RA1 & RA3 inputs
	    movwf	TrisA		;port A i/o set
	    
	    ;initislise EUSART
	    call	InitUART 

	    ;initialise timer
	    banksel	Option_Reg
	    movlw	B'00001000'	;Timer0 no prescale osc/4
	    movwf	Option_Reg
	    call	setTimer		
	    

	    ;initialise interrupts
	    movlw	B'11100000'	;enable TOIE - disable interrupt if calling dofrm from mainloop
	    ;movlw	B'11000000'	;enable peripheral interrupts (ADC)
	    movwf	INTCON
	    
	    banksel	PIE1		;bank 1
	    movlw	B'01000000'	;enable ADC interupt
	    movwf	PIE1
	    
	    clrf	PLinH
	    clrf	PLinL  
	    clrf	PRinH
	    clrf	PRinL
	    
	    bsf		ADCON0,ADGO	;start converter
	    
	    Banksel	0

	    ;seed random gen
	    movlw	0x30
	    movwf	Randhi
	    movlw	0x45
	    movwf	Randlo
	    ;clear variables
	    call	clrall
	    clrf	mode
	    clrf	control
	    clrf	testval
;==================================< main loop >===================================
;
mainlp:
	    decfsz	temp0,f
	    goto	mainlp		;delay to slow main loop
	    movlw	0x80		
	    movwf	temp0
	    
	    movlb	0
	    
	    call 	dofrm		;doframe can be called here instead of interrupt
	    decfsz	temp1,f
	    goto	mainlp
	    movlw	.76		;
	    movwf	temp1

	    call	Ramp		;Ramp testval up and down
	    call	Random16	;randomise 
	    call	doMode		;do demo display mode
	    
	    btfsc	Disport,Switch	;test switch
	    goto	clrDBB
	    btfss	Control,SwtDBB
	    goto	NextM
	    goto	mainlp
clrDBB	    bcf		Control,SwtDBB
	    goto	mainlp
	    
NextM	    bsf		Control,SwtDBB
	    incf	mode,f
	    goto	mainlp
;--------------------------------------------------------------------------------
Random16:	;psuedo random routine
	     rlf 	RandHi,W
	     xorwf 	RandHi,W
	     ;rlf 	WREG, F ; carry bit = xorwf(Q15,14)
	     swapf 	RandHi, F
	     swapf 	RandLo,W
	     ;rlf 	WREG, F
	     xorwf 	RandHi,W ; LSB = xorwf(Q12,Q3)
	     swapf 	RandHi, F
	     andlw 	0x01
	     rlf 	RandLo, F
	     xorwf 	RandLo, F
	     rlf 	RandHi, F
	     return

Ramp:		;ramp test value up to 100 then ramp down to 0 in a loop
	    btfsc	control,rampdwn
	    goto	rampdn
	    incf	TestVal,f
	    movf	TestVal,w
	    xorlw	.100
	    btfss	status,z
	    return
	    bsf		control,rampdwn
	    return

rampdn	    decfsz	TestVal,f
	    return
	    bcf		control,rampdwn
	    ;incf	mode,f
	    
	    return

;---------------< demo display modes >-----------------------------------------------
DoMode:	    movf	mode,w
	    andlw	0x07		
	    addwf	PCL,f
	    goto	peakbar		;bar with peak dot
	    goto	CentreDot	;dot display with centre line
	    goto	ConvBar		;do conventional bar display
	    goto	Indbar
	    goto	InvBar		;do inverted bar
	    goto	TrendBar	;do trend bar
	    goto	SimpleDot	;do dot display
	    goto	peakbar		;bar with peak dot			

	    clrf	mode
	    return

;Conventional bar
ConvBar:
	    clrf	bonvl	;clear value
	    clrf	bonvr
	    clrf	dotvl
	    clrf	dotvr
	    bsf		AuxInd,PAB00		; light the bottom pair
	    movf	testval,w
	    movwf	boffvl
	    movwf	boffvr
	    return

;Indpendant left right
IndBar:
	    clrf	bonvl	;clear value
	    clrf	bonvr
	    clrf	dotvl
	    clrf	dotvr
	    bsf		AuxInd,PAB00		; light the bottom pair
	    movf	testval,w
	    movwf	boffvl
	    sublw	.100		
	    movwf	boffvr
	    return

;inverted bar 
InvBar:	    movlw	.100
	    movwf	boffvl
	    movwf	boffvr			;bar should be on at the top			
	    bcf		AuxInd,PAB00	;switch off the bottom pair
	    clrf	dotvl
	    clrf	dotvr
	    movf	testval,w		
	    sublw	.100		;to make bar start at the right end for demo
	    movwf	bonvl			
	    movwf	bonvr
	    return

;trend bar - centred on zero
TrendBar:
	    call	clrall   
	    movf	testval,w	
	    sublw	.50
	    btfss	status,c
	    goto	Trdpos
	    movf	testval,w
	    movwf	bonvl			
	    movwf	bonvr
	    movlw	.50
	    movwf	boffvl
	    movwf	boffvr
	    return		

Trdpos	    movf	testval,w	;for values < 50 
	    movwf	boffvl
	    movwf	boffvr			
	    movlw	.50	
	    movwf	bonvl			
	    movwf	bonvr
	    return

;dot displays 
clrall:	    
	    movlb	0
	    clrf	Refvl
	    clrf	Refvr
	    clrf	Auxind
clrdabs	    bcf		AuxInd,IND1		;clear dots and bars
	    bcf		AuxInd,IND2
	    clrf	dotvl	    
	    clrf	dotvr
clrbars	    clrf	bonvl
	    clrf	bonvr
	    clrf	boffvl
	    clrf	boffvr
	    return
	    
SimpleDot:
	    call	clrall 
	    bcf		AuxInd,PAB00	;bottom segments off
	    movf	testval,w	
	    movwf	dotvl
	    sublw	.100
	    movwf	dotvr		
	    return
	    
CentreDot:  
	    call	clrall
	    bcf		AuxInd,PAB00	;bottom segments off
	    movlw	.50
	    movwf	RefVl
	    movwf	RefVr	    

	    movlb	1	    
	    movf	ALinH,w
	    movlb	0
	    addlw	.50
	    movwf	dotvl
	    
	    movlb	1
	    movf	ARinH,w	    
	    movlb	0
	    addlw	.50
	    movwf	dotvr	

	    return

	    ;analogue peak linear bar
	    
PeakBar:    clrf	bonvl
	    clrf	bonvr
	    movlw	.75	    ;0dB marker for current scale
	    movwf	RefVl
	    movwf	RefVr
	    bsf		AuxInd,PAB00	;bottom segments on
	    call	DoDecay
	    movf	testval,w
	    btfss	status,z	;clear peak on second run
	    goto	pkleft
	    call	ClrPeak

pkleft	    
	    movlb	1		;bank 1
	    movf	PLinH,w		;get current peak
	    clrf	PLinH		;and clear
	    movlb	0
	    call	DoScale		;scale in w and Temp1
	    ;btfss	status,c	;test if over level
	    ;bra		OverL
	    subwf	BoffVl,w	;compare with current peak
	    btfsc	status,c
	    bra		pkright
	    movf	Temp1,w		;get scale value
	    movwf	Boffvl		;set new peak
	    subwf	dotVl,w		;compare with current peak
	    btfsc	status,c
	    bra		pkright
	    movf	BoffVl,w	
	    movwf	DotVl		;set peak dot
	    bra		pkright

OverL	    bsf		AuxInd,IND1
	    movlw	.100
	    movwf	BoffVl
	    movwf	DotVl
	    
pkright	    
	    movlb	1		;bank 1
	    movf	PRinH,w		;get current peak
	    clrf	PRinH		;and clear
	    movlb	0
	    call	DoScale		;scale in w and Temp1
	    ;btfss	status,c	;test if over level c=0
	    ;bra		OverR
	    subwf	BoffVr,w	;compare with current peak
	    btfsc	status,c
	    return
	    movf	Temp1,w		;get scale value
	    movwf	Boffvr		;set new peak

	    subwf	dotVr,w		;compare with current peak
	    btfsc	status,c
	    return
	    movf	BoffVr,w	
	    movwf	dotvr		;set new peak			
	    return
	    
OverR	    bsf		AuxInd,IND2
	    movlw	.100
	    movwf	BoffVr
	    movwf	DotVr
	    return

DoScale:    ;convert adc value to scale 1-100
	    movwf	Temp0	    ; save adc value (left or right)
   	    movlw	.101
	    movwf	Temp1	    ;scale pointer
scloop	    movf	Temp1,w
	    call	ScaleTab    ;get scale value into w
	    subwf	Temp0,w
	    btfsc	status,c    ;c=1 adc >= scale
	    bra		pkfnd	    ;level found 
	    decfsz	Temp1,f
	    bra		scloop
	    
pkfnd	    movf	Temp1,w
	    return		    ;w= scale carry clear if over
	    
	    
DoDecay:    ;decrement bar on each call
	    movf	BoffVl,w
	    btfss	status,z
	    decf	BoffVl,f	;do decay if >0
	    movf	BoffVr,w
	    btfss	status,z	    
	    decf	BoffVr,f
	    return
	    
ClrPeak:
	    clrf	dotvl
	    clrf	dotvr
	    bcf		AuxInd,IND1	
	    bcf		AuxInd,IND2
	    return
;----------------------------------------------------------------------------------


; remaining code goes here

;VFD display routines called from timer interrupt or main loop

setTimer: 	;usedto trigger adc go at regular intervals
	    banksel	TMR0
	    movlw	.255 - (.8*.17) 	;osc/4 17us 
	    movwf	TMR0	;set timer	
	    return	

DoFrm:	    
	    banksel	0
	    incf	FrmNo,f		;next frame (19 frames numbered 0-18)
	    movf	FrmNo,w		;get frame number and test if >18
	    sublw	.18
	    btfss	status,c
	    clrf	FrmNo		;reset frame number

	    clrf	PB29		;switch off anodes
	    clrf	PAB01
	    clrf	PA29
	    call	setGrid		;set up grids
	    call	setAval		;set initial anode value

	    movf	FrmNo,w		;test if frame 0/grid1
	    btfss	status,z
	    goto	tstODD		;goto test Odd frame. Odd frames have two grids & set PAB10

	    bcf		Control,RefEn
	    decfsz	RefCnt,f
	    goto	noRef
	    bsf		Control,RefEn	;do ref on this loop
	    ;reset ref frame counter
	    movlw	0x07		;increase this to dim ref
	    movwf	RefCnt

noRef	    
;do frame 0 - this is a special even frame because it has to test 
;PAB00, PA1a & PB1a as well as PA2-9 & PB2-9 (PAB29)
					
	    call	setPAB1a		;do anodes PA1a & PB1a
	    incf	Anval,f			;increment anode value and...
	    btfsc	AuxInd,PAB00	;test if bottom segment should be on
	    bsf		GRD17,PAB00

evnFrm	    call	setPAB29	;do anodes PA2-9 & PB2-9

	    incf	Anval,f
	    movf	frmno,w		;frame 19 also has to set PA0b & PB0b
	    xorlw	.18
	    btfsc	status,z
	    call	setPAB0b

	    movf	AuxInd,w		;get LED indicator switches
	    andlw	0xF8
	    iorwf	GRD810,w		;set output bits	
	    movwf	GRD810

shft	    Call	Shftout		;shift output bytes to display
	    return


tstODD	    movf	FrmNo,w
	    andlw	0x01
	    btfsc	status,z
	    goto	evnFrm		;do even frame output

;brightness correcting delay
	    movlw	0x4f		;adjust until all segments look the same brightness
	    movwf	intemp0
BClp	    decfsz	intemp0,f	;loop here to correct brightness between odd and even frames
	    goto	BClp

	    movf	FrmNo,w		;this is an odd frame so now test if ab or ba	
	    call	GrdTabl		;get low byte
	    andlw	0x01		;test  abba flag
	    btfss	status,z	;w=1=AB  w=0=BA
	    goto	setab
;setba
	    call	setPAB0b	;do anodes PA0b & PB0b
	    incf	Anval,f		;increment anode value then...
	    call	setPAB1a	;do anodes PA1a & PB1a
	    goto	shft

setab	    call	setPAB0a	;do anodes PA0a & PB0a
	    incf	Anval,f		;increment anode value then...
	    call	setPAB1b	;do anodes PA1b & PB1b	
	    goto	shft


;anode setting routines
;
SetPAB29:
	    movlw	0x08
	    movwf	intemp0		;bit counter
	    goto	iniPAB29

PAB29lp	    incf	Anval,f		;increment anode value
	    bcf		status,c
	    rrf		PA29,f		;shift bits down
	    bcf		status,c
	    rrf		PB29,f

iniPAB29    movf	Anval,w		;test Bar on left values
	    subwf	BonVl,w
	    btfss	status,c	;if Anval > Bar on left value...
	    bsf		PB29,7		;switch on bit7 (will be shifted down)
	    movf	Anval,w
	    subwf	BonVr,w
	    btfss	status,c
	    bsf		PA29,7

	    movf	Anval,w		;test bar off values
	    subwf	BoffVl,w
	    btfss	status,c	;if anval > Bar off value
	    bcf		PB29,7		;switch anode off
	    movf	Anval,w
	    subwf	BoffVr,w
	    btfss	status,c
	    bcf		PA29,7

	    movf	Anval,w		;test Dot values
	    subwf	DotVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PB29,7		;switch anode on
	    movf	Anval,w
	    subwf	DotVr,w
	    btfsc	status,z
	    bsf		PA29,7
	    
	    btfss	Control,RefEn	;do ref on this loop
	    goto	noRef1
	    ;do ref dot
	    movf	Anval,w		;test Dot values
	    subwf	RefVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PB29,7		;switch anode on
	    movf	Anval,w
	    subwf	RefVr,w
	    btfsc	status,z
	    bsf		PA29,7
	    
noRef1	    decfsz	intemp0,f
	    goto	PAB29lp

	    return


SetPAB1a:
	    movf	Anval,w		;test Bar on values
	    subwf	BonVl,w
	    btfss	status,c	;if Anval > Bar on value...
	    bsf		PAB01,PB1a	;switch anode on
	    movf	Anval,w
	    subwf	BonVr,w
	    btfss	status,c
	    bsf		PAB01,PA1a

	    movf	Anval,w		;test bar off values
	    subwf	BoffVl,w
	    btfss	status,c	;if anval > Bar off value
	    bcf		PAB01,PB1a	;switch anode off
	    movf	Anval,w
	    subwf	BoffVr,w
	    btfss	status,c
	    bcf		PAB01,PA1a

	    movf	Anval,w		;test Dot values
	    subwf	DotVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PAB01,PB1a	;switch anode on
	    movf	Anval,w
	    subwf	DotVr,w
	    btfsc	status,z
	    bsf		PAB01,PA1a

	    btfss	Control,RefEn	;do ref on this loop
	    return
	    ;do ref dots
	    movf	Anval,w		;test Dot values
	    subwf	RefVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PAB01,PB1a	;switch anode on
	    movf	Anval,w
	    subwf	RefVr,w
	    btfsc	status,z
	    bsf		PAB01,PA1a
	    
	    return

SetPAB0a:
	    movf	Anval,w		;test Bar on values
	    subwf	BonVl,w
	    btfss	status,c	;if Anval > Bar on value...
	    bsf		PAB01,PB0a	;switch anode on
	    movf	Anval,w
	    subwf	BonVr,w
	    btfss	status,c
	    bsf		PAB01,PA0a

	    movf	Anval,w		;test Bar off values
	    subwf	BoffVl,w
	    btfss	status,c	;if anval > Bar off value
	    bcf		PAB01,PB0a	;switch anode off
	    movf	Anval,w
	    subwf	BoffVr,w
	    btfss	status,c
	    bcf		PAB01,PA0a

	    movf	Anval,w		;test Dot values
	    subwf	DotVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PAB01,PB0a	;switch anode on
	    movf	Anval,w
	    subwf	DotVr,w
	    btfsc	status,z
	    bsf		PAB01,PA0a

	    btfss	Control,RefEn	;do ref on this loop
	    return	    
	    ;do ref dots
	    movf	Anval,w		;test Dot values
	    subwf	RefVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PAB01,PB0a	;switch anode on
	    movf	Anval,w
	    subwf	RefVr,w
	    btfsc	status,z
	    bsf		PAB01,PA0a
	    return
	    
	    

SetPAB1b:
	    movf	Anval,w		;test Bar on values
	    subwf	BonVl,w
	    btfss	status,c	;if Anval > Bar on value...
	    bsf		PAB01,PB1b	;switch anode on
	    movf	Anval,w
	    subwf	BonVr,w
	    btfss	status,c
	    bsf		PAB01,PA1b

	    movf	Anval,w		;test bar off values
	    subwf	BoffVl,w
	    btfss	status,c	;if anval > Bar off value
	    bcf		PAB01,PB1b	;switch anode off
	    movf	Anval,w
	    subwf	BoffVr,w
	    btfss	status,c
	    bcf		PAB01,PA1b

	    movf	Anval,w		;test Dot values
	    subwf	DotVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PAB01,PB1b	;switch anode on
	    movf	Anval,w
	    subwf	DotVr,w
	    btfsc	status,z
	    bsf		PAB01,PA1b
	    
	    btfss	Control,RefEn	;do ref on this loop
	    return
	    ;do ref dots
	    movf	Anval,w		;test Dot values
	    subwf	RefVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PAB01,PB1b	;switch anode on
	    movf	Anval,w
	    subwf	RefVr,w
	    btfsc	status,z
	    bsf		PAB01,PA1b
	    return

SetPAB0b:
	    movf	Anval,w		;test Bar on values
	    subwf	BonVl,w
	    btfss	status,c	;if Anval > Bar on value...
	    bsf		PAB01,PB0b	;switch anode on
	    movf	Anval,w
	    subwf	BonVr,w
	    btfss	status,c
	    bsf		PAB01,PA0b

	    movf	Anval,w		;test Bar off values
	    subwf	BoffVl,w
	    btfss	status,c	;if anval > Bar off value
	    bcf		PAB01,PB0b	;switch anode off
	    movf	Anval,w
	    subwf	BoffVr,w
	    btfss	status,c
	    bcf		PAB01,PA0b

	    movf	Anval,w		;test Dot values
	    subwf	DotVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PAB01,PB0b	;switch anode on
	    movf	Anval,w
	    subwf	DotVr,w
	    btfsc	status,z
	    bsf		PAB01,PA0b

	    btfss	Control,RefEn	;do ref on this loop
	    return	    
	    ;do ref dots
	    movf	Anval,w		;test Dot values
	    subwf	RefVl,w
	    btfsc	status,z	;if anval = dot value
	    bsf		PAB01,PB0b	;switch anode on
	    movf	Anval,w
	    subwf	RefVr,w
	    btfsc	status,z
	    bsf		PAB01,PA0b	    
	    return

;This routine sets the grid bytes for the current frame
SetGrid:
	    movf	FrmNo,w		;get frame number
	    call	GrdTabl		;get low byte
	    andlw	0xFE		;ignore and clear bit0 (ABBA flag)
	    movwf	Grd17		;save grid setting 1-7
	    movf	FrmNo,w		;get frame number
	    call	GrdTabh		;get Hi byte
	    movwf	Grd810		;save grid setting 8-10
	    return	

SetAval:
	    movf	FrmNo,w		;get frame number
	    call	AnVTab		;get value
	    movwf	Anval		;save grid setting
	    return				



;shift bits out to display

InitUART:
	    Banksel	APFCON	    ;set alt pins
	    movlw	B'10000100'
	    movwf	APFCON
	    	       
	    Banksel	SPBRGH	    ;BANK 3
	    clrf	SPBRGH
	    movlw	0x10	    ;use 4 for 16MHz
	    movwf	SPBRGL

	    ;Banksel	BAUDCON	    ;BANK 3
	    movlw	B'00011000'
	    movwf	BAUDCON
	    
	    ;Banksel	TXSTA	    ;set tx control BANK 3
	    movlw	B'10110000'
	    movwf	TXSTA
   
	    ;Banksel	RCSTA	    ;BANK 3
	    movlw	B'10000000' ;enable USART
	    movwf	RCSTA

	    return
	    
Shftout:    movlw	PB29
	    movwf	FSR0L	    ;set indirection pointer
	    clrf	FSR0H
	    movlw	0x05	    ;set byte counter
	    movwf	intemp0
	    Banksel	PortA	    ;BANK 0
	    bcf		disport,latch  	    
 
	    Banksel	TXREG	    ;BANK 3
waitTXF:    moviw	INDF0++	    ;get byte at pointer and increment FSR
	    movwf	TXREG	    ;output to shifter

	    ;Banksel	TXSTA	    ;BANK 3
waitlst     btfss	TXSTA,TRMT	    
	    goto	waitlst	    ;wait for last buffer clear	    
	    decfsz	intemp0,f   ;decrement counter
	    goto	waitTXF	    ;loop 5 bytes out	    
	    Banksel	PortA	    ;BANK 0
	    bsf		disport,latch  

	    return
	    
	    
	    ORG	    0x300	    ;align table with page
	    
;VU scale +5 at top, -5 middle, -30 bottom	    
ScaleTab:   BRW	   
	    RETLW   .0	    ;0
	    RETLW  .4	    ;1 -30dBv
	    RETLW  .6
	    RETLW  .8	    ;-25dB
	    RETLW  .10
	    RETLW  .13	    ;-20dB
	    RETLW  .14
	    RETLW  .15
	    RETLW  .15
	    RETLW  .16
	    RETLW  .17
	    RETLW  .18
	    RETLW  .19
	    RETLW  .20
	    RETLW  .21
	    RETLW  .23	    ;-15dB
	    RETLW  .24
	    RETLW  .25
	    RETLW  .27
	    RETLW  .28
	    RETLW  .30
	    RETLW  .32
	    RETLW  .34
	    RETLW  .36
	    RETLW  .38
	    RETLW  .40	    ;-10dB
	    RETLW  .41
	    RETLW  .42
	    RETLW  .43
	    RETLW  .44
	    RETLW  .45
	    RETLW  .46
	    RETLW  .47
	    RETLW  .48
	    RETLW  .49
	    RETLW  .50
	    RETLW  .51
	    RETLW  .53
	    RETLW  .54
	    RETLW  .55
	    RETLW  .56
	    RETLW  .58
	    RETLW  .59
	    RETLW  .60
	    RETLW  .62
	    RETLW  .63
	    RETLW  .65
	    RETLW  .66
	    RETLW  .68
	    RETLW  .69
	    RETLW  .71	    ;-5dB
	    RETLW  .72
	    RETLW  .74
	    RETLW  .76
	    RETLW  .78
	    RETLW  .79
	    RETLW  .81
	    RETLW  .83
	    RETLW  .85
	    RETLW  .87
	    RETLW  .89
	    RETLW  .91
	    RETLW  .93
	    RETLW  .95
	    RETLW  .98
	    RETLW  .100
	    RETLW  .102
	    RETLW  .104
	    RETLW  .107
	    RETLW  .109
	    RETLW  .112
	    RETLW  .115
	    RETLW  .117
	    RETLW  .120
	    RETLW  .123
	    RETLW  .125	    ;0dB
	    RETLW  .128
	    RETLW  .131
	    RETLW  .134
	    RETLW  .138
	    RETLW  .141
	    RETLW  .144
	    RETLW  .147
	    RETLW  .151
	    RETLW  .154
	    RETLW  .158
	    RETLW  .162
	    RETLW  .165
	    RETLW  .169
	    RETLW  .173
	    RETLW  .177
	    RETLW  .181
	    RETLW  .185
	    RETLW  .190
	    RETLW  .194
	    RETLW  .199
	    RETLW  .203
	    RETLW  .208
	    RETLW  .213
	    RETLW  .218
	    RETLW  .223	    ;fsd 100  +5dB
	    RETLW  .228	    ;over level 101
	    END                       ; directive 'end of program'


